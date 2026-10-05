Set-StrictMode -Version Latest

$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$projectHasher = [Security.Cryptography.SHA256]::Create()
try {
    $projectKey = [BitConverter]::ToString($projectHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:ProjectRoot.ToLowerInvariant()))).Replace('-', '').Substring(0, 16)
} finally {
    $projectHasher.Dispose()
}
$script:RuntimeDirectory = Join-Path $env:TEMP ('codex-project-rts-' + $projectKey)
$script:TrackedProcessFile = Join-Path $script:RuntimeDirectory 'processes.json'

function Get-ProcessPathState {
    param([Parameter(Mandatory = $true)][Collections.IDictionary]$Variables)

    # Windows names are case-insensitive, but inherited environment blocks can
    # contain both Path and PATH. Never merge different values or remove the
    # sandbox's injected directories while repairing that representation.
    $names = @($Variables.Keys | Where-Object { [string]$_ -ieq 'Path' })
    $value = if ($names.Count -gt 0) { [string]$Variables[$names[0]] } else { $null }
    foreach ($name in $names) {
        if (-not [string]::Equals($value, [string]$Variables[$name], [StringComparison]::Ordinal)) {
            throw 'Conflicting Path/PATH values; process environment left unchanged.'
        }
    }
    return [pscustomobject]@{ Count = $names.Count; Value = $value }
}

function Repair-ProcessPathCasing {
    $before = Get-ProcessPathState -Variables ([Environment]::GetEnvironmentVariables())
    if ($before.Count -le 1) { return }
    if ([string]::IsNullOrEmpty($before.Value)) {
        throw 'Duplicate empty Path entries cannot be safely normalized.'
    }

    # Process scope only: keep the exact effective value, including sandbox
    # entries. Win32 can delete one matching entry at a time from a duplicate
    # block, so remove at most the number observed and restore in finally.
    try {
        for ($index = 0; $index -lt $before.Count; $index++) {
            [Environment]::SetEnvironmentVariable('Path', $null, 'Process')
        }
    } finally {
        [Environment]::SetEnvironmentVariable('Path', $before.Value, 'Process')
    }
    $after = Get-ProcessPathState -Variables ([Environment]::GetEnvironmentVariables())
    if ($after.Count -ne 1 -or
        -not [string]::Equals($before.Value, $after.Value, [StringComparison]::Ordinal)) {
        throw 'Process Path normalization failed; refusing to launch a child process.'
    }
    Write-Host "PROCESS_PATH_NORMALIZED $($before.Count) -> 1 (value preserved)"
}

# Every fixed entry point imports this file, including network and CLI checks
# that start children without Start-TrackedProcess.
Repair-ProcessPathCasing

function ConvertTo-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AllowMissing
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path $script:ProjectRoot $Path
    }

    $fullPath = [IO.Path]::GetFullPath($candidate)
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $fullPath)) {
        throw "Path does not exist: $fullPath"
    }
    return $fullPath
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $candidatePath = [IO.Path]::GetFullPath($Candidate).TrimEnd('\')
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $candidatePath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
        $candidatePath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ProjectPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AllowMissing
    )

    $fullPath = ConvertTo-FullPath -Path $Path -AllowMissing:$AllowMissing
    if (-not (Test-PathWithin -Candidate $fullPath -Root $script:ProjectRoot)) {
        throw "Path must remain inside the project: $Path"
    }
    return $fullPath
}

function Resolve-ProjectScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script
    )

    if ($Script -notmatch '^res://') {
        throw "Scripts must use a project-relative res:// path."
    }
    $relativePath = $Script.Substring(6).Replace('/', '\')
    $fullPath = Resolve-ProjectPath -Path $relativePath
    if ([IO.Path]::GetExtension($fullPath) -notin @('.gd', '.py')) {
        throw "Only project GDScript or Python files may be executed: $Script"
    }
    return $fullPath
}

. (Join-Path $PSScriptRoot 'toolchain.ps1')

function Get-TrustedGodotPath {
    param([string]$RequestedPath)
    Get-RegisteredToolPath -Tool Godot -RequestedPath $RequestedPath
}

function Get-TrustedBlenderPath {
    param([string]$RequestedPath)
    Get-RegisteredToolPath -Tool Blender -RequestedPath $RequestedPath
}

function Ensure-RuntimeDirectory {
    if (-not (Test-Path -LiteralPath $script:RuntimeDirectory)) {
        New-Item -ItemType Directory -Path $script:RuntimeDirectory -Force | Out-Null
    }
}

function Read-TrackedProcesses {
    if (-not (Test-Path -LiteralPath $script:TrackedProcessFile)) {
        return @()
    }
    try {
        $value = Get-Content -Raw -LiteralPath $script:TrackedProcessFile | ConvertFrom-Json
        if ($null -eq $value) { return @() }
        return @($value)
    } catch {
        Write-Warning "Ignoring unreadable process ledger: $script:TrackedProcessFile"
        return @()
    }
}

function Write-TrackedProcesses {
    param([object[]]$Processes)
    Ensure-RuntimeDirectory
    $json = ConvertTo-Json -InputObject @($Processes) -Depth 5
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $json | Set-Content -LiteralPath $script:TrackedProcessFile -Encoding UTF8
            return
        } catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Milliseconds 150
        }
    }
}

function ConvertTo-ProcessArguments {
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    return @($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    })
}

function Add-TrackedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$Executable
    )

    $entries = @(Read-TrackedProcesses | Where-Object { [int]$_.ProcessId -ne $ProcessId })
    $entries += [pscustomobject]@{
        ProcessId = $ProcessId
        Label     = $Label
        Executable = $Executable
        StartedAt = (Get-Date).ToString('o')
    }
    Write-TrackedProcesses -Processes $entries
}

function Remove-TrackedProcess {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    $entries = @(Read-TrackedProcesses | Where-Object { [int]$_.ProcessId -ne $ProcessId })
    Write-TrackedProcesses -Processes $entries
}

function Start-TrackedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [AllowEmptyCollection()]
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [string]$OutputLog,
        [string]$ErrorLog,
        [ValidateRange(0, 3600)]
        [int]$TimeoutSeconds = 0,
        [switch]$Wait
    )

    $processArguments = ConvertTo-ProcessArguments -ArgumentList $ArgumentList
    $startParameters = @{
        FilePath         = $FilePath
        ArgumentList     = $processArguments
        WorkingDirectory = $script:ProjectRoot
        WindowStyle      = 'Hidden'
        PassThru          = $true
    }
    if ($OutputLog) {
        $startParameters.RedirectStandardOutput = $OutputLog
        $startParameters.RedirectStandardError = if ($ErrorLog) { $ErrorLog } else { $OutputLog + '.err' }
    }
    $process = Start-Process @startParameters
    Add-TrackedProcess -ProcessId $process.Id -Label $Label -Executable $FilePath
    Write-Host "Started $Label (PID $($process.Id))"

    if ($Wait) {
        try {
            if ($TimeoutSeconds -gt 0) {
                if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    throw "$Label timed out after $TimeoutSeconds seconds."
                }
            } else {
                $process.WaitForExit()
            }
            $process.Refresh()
            return [int]$process.ExitCode
        } finally {
            Remove-TrackedProcess -ProcessId $process.Id
        }
    }
    return $process.Id
}

function Stop-TrackedProcess {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        if (-not $process.HasExited) {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        }
        Write-Output "Stopped tracked process PID $ProcessId"
    } catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Write-Output "Tracked process PID $ProcessId is already stopped"
    } catch {
        Write-Warning "Could not stop tracked process PID ${ProcessId}: $($_.Exception.Message)"
    } finally {
        Remove-TrackedProcess -ProcessId $ProcessId
    }
}
