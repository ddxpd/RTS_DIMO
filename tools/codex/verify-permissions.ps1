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

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) {
    Write-Warning 'codex executable is not on PATH; skipped execpolicy check.'
} else {
    $rulesPath = Join-Path $script:ProjectRoot '.codex\rules\default.rules'
    $wrapperNames = @(
        'run-godot.ps1',
        'run-network.ps1',
        'run-exported.ps1',
        'run-blender.ps1',
        'run-mcp.ps1',
        'run-validation.ps1',
        'cleanup-project-processes.ps1',
        'verify-permissions.ps1'
    )
    foreach ($wrapperName in $wrapperNames) {
        $wrapperPath = Join-Path $PSScriptRoot $wrapperName
        $policyText = & $codex.Source execpolicy check --rules $rulesPath -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Execpolicy check failed for $wrapperName."
        }
        $policy = ($policyText -join [Environment]::NewLine) | ConvertFrom-Json
        if ($policy.PSObject.Properties.Name -notcontains 'decision' -or $policy.decision -ne 'allow') {
            throw "The trusted wrapper is not allowed by execpolicy: $wrapperName"
        }
    }

    $rawPolicyText = & $codex.Source execpolicy check --rules $rulesPath -- powershell.exe -NoProfile -Command 'Get-Process' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Execpolicy check failed for the raw PowerShell control case.'
    }
    $rawPolicy = ($rawPolicyText -join [Environment]::NewLine) | ConvertFrom-Json
    if ($rawPolicy.PSObject.Properties.Name -contains 'decision' -and $rawPolicy.decision -eq 'allow') {
        throw 'Raw PowerShell unexpectedly matched an allow rule.'
    }
    Write-Output 'EXECPOLICY PASS'
}

if ($ToolchainSmoke) {
    & (Join-Path $PSScriptRoot 'run-godot.ps1') -Action version
    & (Join-Path $PSScriptRoot 'run-blender.ps1') -Action version
    & (Join-Path $PSScriptRoot 'cleanup-project-processes.ps1') -ReportOnly
    Write-Output 'TOOLCHAIN_SMOKE PASS'
} else {
    Write-Output 'TOOLCHAIN_SMOKE SKIP (use -ToolchainSmoke to enable)'
}
