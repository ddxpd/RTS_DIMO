[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$requiredFiles = @(
    (Join-Path $script:ProjectRoot '.codex\config.toml'),
    (Join-Path $script:ProjectRoot '.codex\rules\default.rules'),
    (Join-Path $PSScriptRoot 'run-godot.ps1'),
    (Join-Path $PSScriptRoot 'run-blender.ps1'),
    (Join-Path $PSScriptRoot 'run-mcp.ps1'),
    (Join-Path $PSScriptRoot 'cleanup-project-processes.ps1')
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required permission file is missing: $file"
    }
}

$parseErrors = @()
foreach ($scriptPath in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath.FullName, [ref]$null, [ref]$parseErrors) | Out-Null
}
if ($parseErrors.Count -gt 0) {
    throw (($parseErrors | ForEach-Object { $_.Message }) -join [Environment]::NewLine)
}

Write-Output 'WRAPPER_SYNTAX PASS'
& (Join-Path $PSScriptRoot 'run-godot.ps1') -Action version
& (Join-Path $PSScriptRoot 'run-blender.ps1') -Action version
& (Join-Path $PSScriptRoot 'cleanup-project-processes.ps1') -ReportOnly

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) {
    Write-Warning 'codex executable is not on PATH; skipped execpolicy check.'
} else {
    $rulesPath = Join-Path $script:ProjectRoot '.codex\rules\default.rules'
    $windowsRulesPath = Join-Path $script:ProjectRoot '.codex\rules\windows-execution-policy.rules'
    & $codex.Source execpolicy check --pretty --rules $rulesPath --rules $windowsRulesPath -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-godot.ps1') -Action version
    & $codex.Source execpolicy check --pretty --rules $rulesPath --rules $windowsRulesPath -- powershell.exe -NoProfile -Command 'Get-Process'
}
