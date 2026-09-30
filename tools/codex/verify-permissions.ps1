[CmdletBinding()]
param(
    [switch]$ToolchainSmoke
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$requiredFiles = @(
    (Join-Path $script:ProjectRoot '.codex\config.toml'),
    (Join-Path $script:ProjectRoot '.codex\rules\default.rules'),
    (Join-Path $PSScriptRoot 'run-godot.ps1'),
    (Join-Path $PSScriptRoot 'run-blender.ps1'),
    (Join-Path $PSScriptRoot 'run-network.ps1'),
    (Join-Path $PSScriptRoot 'run-exported.ps1'),
    (Join-Path $PSScriptRoot 'run-mcp.ps1'),
    (Join-Path $PSScriptRoot 'run-validation.ps1'),
    (Join-Path $PSScriptRoot 'inspect-cursor.ps1'),
    (Join-Path $PSScriptRoot 'cleanup-project-processes.ps1')
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required permission file is missing: $file"
    }
}

$parseErrors = @()
foreach ($scriptPath in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    $fileErrors = @()
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath.FullName, [ref]$null, [ref]$fileErrors) | Out-Null
    $parseErrors += @($fileErrors)
}
if ($parseErrors.Count -gt 0) {
    throw (($parseErrors | ForEach-Object { $_.Message }) -join [Environment]::NewLine)
}

Write-Output 'WRAPPER_SYNTAX PASS'

$pathFixture = [Collections.Hashtable]::new([StringComparer]::Ordinal)
$pathFixture.Add('Path', 'C:\sandbox-tools;C:\Windows;C:\tools with spaces')
$pathFixture.Add('PATH', $pathFixture['Path'])
$pathFixture.Add('OTHER', 'untouched')
$pathState = Get-ProcessPathState -Variables $pathFixture
if ($pathState.Count -ne 2 -or $pathState.Value -cne $pathFixture['Path'] -or $pathFixture.Count -ne 3) {
    throw 'Duplicate Path detection must preserve the complete value and input.'
}
$pathFixture['PATH'] = 'C:\different-tools'
$conflictRejected = $false
try {
    $null = Get-ProcessPathState -Variables $pathFixture
} catch {
    if ($_.Exception.Message -notlike 'Conflicting Path/PATH values*') { throw }
    $conflictRejected = $true
}
if (-not $conflictRejected) { throw 'Conflicting Path values were not rejected.' }
$pathFixture.Remove('PATH')
if ((Get-ProcessPathState -Variables $pathFixture).Count -ne 1) { throw 'Single Path detection failed.' }
$pathFixture.Remove('Path')
if ((Get-ProcessPathState -Variables $pathFixture).Count -ne 0) { throw 'Missing Path detection failed.' }
$actualPathBefore = Get-ProcessPathState -Variables ([Environment]::GetEnvironmentVariables())
Repair-ProcessPathCasing
$actualPathAfter = Get-ProcessPathState -Variables ([Environment]::GetEnvironmentVariables())
if ($actualPathAfter.Count -gt 1 -or $actualPathAfter.Value -cne $actualPathBefore.Value) {
    throw 'Process Path normalization is not idempotent or changed the effective value.'
}
Write-Output 'PROCESS_PATH_CHECK PASS (duplicate/single/missing/conflict fixtures; live value preserved)'
& (Join-Path $script:ProjectRoot 'tests\process_environment.ps1')

$codex = Get-Command codex -ErrorAction SilentlyContinue
$codexPath = if ($null -ne $codex) { $codex.Source } else { $null }
if (-not $codexPath -and $env:LOCALAPPDATA) {
    $bundledCodex = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
    if (Test-Path -LiteralPath $bundledCodex -PathType Leaf) {
        $codexPath = $bundledCodex
    }
}
if (-not $codexPath) {
    throw 'Codex CLI was not found on PATH or in the desktop installation. Execpolicy is NOT verified; install/configure the CLI before retrying Tooling validation.'
} else {
    $rulesPath = Join-Path $script:ProjectRoot '.codex\rules\default.rules'
    $wrapperNames = @(
        'run-godot.ps1',
        'run-network.ps1',
        'run-exported.ps1',
        'run-blender.ps1',
        'run-mcp.ps1',
        'run-validation.ps1',
        'inspect-cursor.ps1',
        'cleanup-project-processes.ps1',
        'verify-permissions.ps1'
    )
    function Get-CommandPolicy {
        param([string[]]$CommandArguments)
        $policyText = & $codexPath execpolicy check --rules $rulesPath -- @CommandArguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Execpolicy check failed: $($CommandArguments -join ' ')"
        }
        return (($policyText -join [Environment]::NewLine) | ConvertFrom-Json)
    }

    $shellNames = @('powershell.exe', 'powershell', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')
    foreach ($shellName in $shellNames) {
        foreach ($wrapperName in $wrapperNames) {
            $wrapperPath = Join-Path $PSScriptRoot $wrapperName
            $policy = Get-CommandPolicy -CommandArguments @($shellName, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath)
            if ($policy.PSObject.Properties.Name -notcontains 'decision' -or $policy.decision -ne 'allow') {
                throw "The trusted wrapper is not allowed by execpolicy: $shellName $wrapperName"
            }
        }
    }

    $godotPrefix = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-godot.ps1'))
    foreach ($logName in @('.godot\path-check-a.log', '.godot\path-check-b.log')) {
        $policy = Get-CommandPolicy -CommandArguments ($godotPrefix + @('-Action', 'script', '-Script', 'res://tests/terrain_sample_view.gd', '-Rendered', '-LogFile', $logName, '-TimeoutSeconds', '150'))
        if ($policy.PSObject.Properties.Name -notcontains 'decision' -or $policy.decision -ne 'allow') {
            throw "Godot command with variable log parameters is not allowed: $logName"
        }
    }
    Write-Output 'GODOT_ARGUMENT_RULES PASS (two different log names; project rules only)'

    # These commands are evaluated only, never executed. A file extension is not
    # permission to run arbitrary shell code or another project's script.
    $controlCases = @(
        @{ Name = 'raw PowerShell'; Command = @('powershell.exe', '-NoProfile', '-Command', 'Get-Process') },
        @{ Name = 'raw cmd'; Command = @('cmd.exe', '/c', 'echo control') },
        @{ Name = 'unlisted script'; Command = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'not-authorized.ps1')) },
        @{ Name = 'external script'; Command = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'D:\unrelated-project\inspect-cursor.ps1') },
        @{ Name = 'lookalike path'; Command = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'inspect-cursor.ps1.extra')) }
    )
    foreach ($controlCase in $controlCases) {
        $policy = Get-CommandPolicy -CommandArguments $controlCase.Command
        if ($policy.PSObject.Properties.Name -contains 'decision' -and $policy.decision -eq 'allow') {
            throw "Unexpected allow rule match: $($controlCase.Name)"
        }
    }
    Write-Output "EXECPOLICY PASS (project rules only; $($shellNames.Count * $wrapperNames.Count) allowed cases, $($controlCases.Count) negative cases)"
}

if ($ToolchainSmoke) {
    & (Join-Path $PSScriptRoot 'run-godot.ps1') -Action version
    & (Join-Path $PSScriptRoot 'run-blender.ps1') -Action version
    & (Join-Path $PSScriptRoot 'cleanup-project-processes.ps1') -ReportOnly
    Write-Output 'TOOLCHAIN_SMOKE PASS'
} else {
    Write-Output 'TOOLCHAIN_SMOKE SKIP (use -ToolchainSmoke to enable)'
}
