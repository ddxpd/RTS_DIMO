[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$ResultDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$networkScript = Join-Path $script:ProjectRoot 'tests\run_network_guest.ps1'
if (-not (Test-Path -LiteralPath $networkScript -PathType Leaf)) {
    throw "Network test runner was not found: $networkScript"
}

$validationRoot = Join-Path $script:ProjectRoot '.godot\validation'
$resultPath = if ($ResultDirectory) {
    Resolve-ProjectPath -Path $ResultDirectory -AllowMissing
} else {
    Join-Path $validationRoot ('network-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
}
if (-not (Test-PathWithin -Candidate $resultPath -Root $validationRoot)) {
    throw 'Network validation output must remain under .godot\validation.'
}

& $networkScript -GodotPath $godot -ResultDirectory $resultPath
