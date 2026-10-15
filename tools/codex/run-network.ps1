[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$ResultDirectory,
    [ValidateSet('Regression', 'Weak')]
    [string]$Mode = 'Regression',
    [ValidateSet('all', 'baseline', 'rtt50', 'rtt100', 'rtt200', 'normal', 'poor', 'limited', 'outage')]
    [string]$Profile = 'all',
    [ValidateRange(0, 10000)]
    [int]$Seed = 0,
    [ValidateRange(15, 600)]
    [int]$DurationSeconds = 180
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$networkScript = Join-Path $script:ProjectRoot 'tests\network\run_network_guest.ps1'
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

if ($Mode -eq 'Weak') {
    & (Join-Path $script:ProjectRoot 'tests\network\run_weak_network.ps1') -GodotPath $godot -ResultDirectory $resultPath -Profile $Profile -Seed $Seed -DurationSeconds $DurationSeconds
    return
}
foreach ($mapId in @("desert_quarry")) {
    & $networkScript -GodotPath $godot -ResultDirectory (Join-Path $resultPath $mapId) -MapId $mapId
}
