Set-StrictMode -Version Latest

$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$script:RuntimeDirectory = Join-Path $env:TEMP 'codex-project-rts-host-p2p'
$script:TrackedProcessFile = Join-Path $script:RuntimeDirectory 'processes.json'

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

function Get-TrustedGodotPath {
    param([string]$RequestedPath)

    $allowedRoots = @(
        'D:\mysoftware\godot',
        'D:\application\Godot_v4.7.2'
    )
    $candidates = if ($RequestedPath) {
        @($RequestedPath)
    } else {
        @(
            'D:\mysoftware\godot\Godot_v4.7.2-stable_win64_console.exe',
            'D:\mysoftware\godot\Godot_v4.7.2-stable_win64.exe',
            'D:\application\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe'
        )
    }

    foreach ($candidate in $candidates) {
        $fullPath = [IO.Path]::GetFullPath($candidate)
        $allowed = $allowedRoots | Where-Object { Test-PathWithin -Candidate $fullPath -Root $_ }
        if ($allowed -and (Test-Path -LiteralPath $fullPath -PathType Leaf) -and
            [IO.Path]::GetFileName($fullPath) -match '^Godot.*\.exe$') {
            return $fullPath
        }
    }
    throw 'No trusted Godot executable was found in the configured installation roots.'
}

function Get-TrustedBlenderPath {
    $candidates = @(
        'D:\mysoftware\blender-5.2.2\blender.exe',
        'D:\mysoftware\blender-5.2.2\blender-launcher.exe'
    )
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            [IO.Path]::GetFileName($candidate) -eq 'blender.exe') {
            return $candidate
        }
    }
    throw 'No trusted Blender executable was found in the configured installation roots.'
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
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [switch]$Wait
    )

    $processArguments = ConvertTo-ProcessArguments -ArgumentList $ArgumentList
    $process = Start-Process -FilePath $FilePath -ArgumentList $processArguments -WorkingDirectory $script:ProjectRoot -WindowStyle Hidden -PassThru
    Add-TrackedProcess -ProcessId $process.Id -Label $Label -Executable $FilePath
    Write-Host "Started $Label (PID $($process.Id))"

    if ($Wait) {
        try {
            $process.WaitForExit()
            return $process.ExitCode
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
