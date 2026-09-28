[CmdletBinding()]
param(
    [string]$GodotPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$networkScript = Join-Path $script:ProjectRoot 'tests\run_network_guest.ps1'
if (-not (Test-Path -LiteralPath $networkScript -PathType Leaf)) {
    throw "Network test runner was not found: $networkScript"
}

& $networkScript -GodotPath $godot
