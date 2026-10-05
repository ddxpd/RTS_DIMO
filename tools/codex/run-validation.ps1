[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Light', 'Full')]
    [string]$Level,
    [string]$Area = '',
    [string]$GodotPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$allowedAreas = @('Simulation', 'Presentation', 'Features', 'Camera', 'ActionBar', 'Visual', 'Performance', 'Network', 'Tooling')
$selectedAreas = @(if ([string]::IsNullOrWhiteSpace($Area)) {
    @()
} else {
    @($Area.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
})
$invalidAreas = @($selectedAreas | Where-Object { $_ -notin $allowedAreas })
if ($invalidAreas.Count -gt 0) {
    throw "Unknown validation Area: $($invalidAreas -join ', ')."
}
if ($Level -eq 'Light' -and $selectedAreas.Count -eq 0) {
    throw 'Light validation requires at least one -Area.'
}
if ($Level -eq 'Full' -and $selectedAreas.Count -gt 0) {
    throw 'Full validation uses the fixed complete source suite and does not accept -Area.'
}

$runGodot = Join-Path $PSScriptRoot 'run-godot.ps1'
$runNetwork = Join-Path $PSScriptRoot 'run-network.ps1'
$verifyPermissions = Join-Path $PSScriptRoot 'verify-permissions.ps1'
$cleanup = Join-Path $PSScriptRoot 'cleanup-project-processes.ps1'
$suiteOrder = @('gameplay', 'arrival_formation', 'presentation', 'features', 'camera', 'action_bar', 'visual_models', 'soldier_locomotion', 'visual_performance', 'terrain_maps', 'terrain_presentation', 'terrain_sample', 'terrain_sample_view')
$suiteScripts = @{
    arrival_formation = 'res://tests/arrival_formation.gd'
    soldier_locomotion = 'res://tests/soldier_locomotion.gd'
    terrain_sample     = 'res://tests/terrain_sample.gd'
    terrain_sample_view = 'res://tests/terrain_sample_view.gd'
    terrain_maps       = 'res://tests/terrain_maps.gd'
    terrain_presentation = 'res://tests/terrain_presentation.gd'
    gameplay           = 'res://tests/gameplay.gd'
    presentation       = 'res://tests/presentation.gd'
    features           = 'res://tests/features.gd'
    camera             = 'res://tests/camera.gd'
    action_bar         = 'res://tests/action_bar.gd'
    visual_models      = 'res://tests/visual_models.gd'
    visual_performance = 'res://tests/visual_performance.gd'
}
$areaSuites = @{
    Simulation   = @('gameplay', 'arrival_formation', 'terrain_maps', 'terrain_sample')
    Presentation = @('presentation')
    Features     = @('features', 'terrain_presentation', 'terrain_sample_view')
    Camera       = @('camera')
    ActionBar    = @('action_bar')
    Visual       = @('visual_models', 'soldier_locomotion', 'terrain_presentation', 'terrain_sample_view')
    Performance  = @('visual_performance')
    Network      = @('gameplay', 'terrain_maps')
    Tooling      = @()
}

$requestedSuites = @()
$runEnet = $Level -eq 'Full' -or $selectedAreas -contains 'Network'
$runTooling = $Level -eq 'Light' -and $selectedAreas -contains 'Tooling'

if ($Level -eq 'Full') {
    $requestedSuites = @($suiteOrder)
} else {
    foreach ($selectedArea in $selectedAreas) {
        $requestedSuites += @($areaSuites[$selectedArea])
    }
    $requestedSuites = @($suiteOrder | Where-Object { $requestedSuites -contains $_ })
}

$results = [Collections.Generic.List[object]]::new()
$hasFailure = $false
$cleanupNeeded = $false
$totalWatch = [Diagnostics.Stopwatch]::StartNew()
$runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
$networkResultDirectory = Join-Path $script:ProjectRoot ".godot\validation\$runId\network"

function Add-ValidationResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][long]$DurationMs,
        [string]$Detail = ''
    )
    [void]$script:results.Add([ordered]@{
        name        = $Name
        status      = $Status
        duration_ms = $DurationMs
        detail      = $Detail
    })
}

function Invoke-ValidationStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        Add-ValidationResult -Name $Name -Status 'passed' -DurationMs $watch.ElapsedMilliseconds
    } catch {
        $script:hasFailure = $true
        Add-ValidationResult -Name $Name -Status 'failed' -DurationMs $watch.ElapsedMilliseconds -Detail $_.Exception.Message
        Write-Warning "Validation stage failed: ${Name}: $($_.Exception.Message)"
    }
}

try {
    if ($runTooling) {
        # Tooling includes a Godot startup regression with duplicate Path keys.
        $cleanupNeeded = $true
        Invoke-ValidationStage -Name 'tooling' -Action {
            & $verifyPermissions
        }
    }

    foreach ($suiteName in $requestedSuites) {
        $cleanupNeeded = $true
        $scriptPath = $suiteScripts[$suiteName]
        Invoke-ValidationStage -Name $suiteName -Action {
            $stageLog = Join-Path $script:ProjectRoot ".godot\validation\$runId\$suiteName.log"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stageLog) | Out-Null
            & $runGodot -Action script -Script $scriptPath -GodotPath $GodotPath -TimeoutSeconds 180 -LogFile $stageLog
            $stageText = (Get-Content -Raw -LiteralPath $stageLog) + (Get-Content -Raw -LiteralPath ($stageLog + '.err'))
            Write-Output $stageText
            if ($stageText -match 'SCRIPT ERROR|(?m)^ERROR:') { throw "Godot logged an error in $suiteName. See $stageLog" }
            if ($suiteName -eq 'visual_performance') {
                $desertLog = Join-Path $script:ProjectRoot ".godot\validation\$runId\desert_performance.log"
                & $runGodot -Action script -Script $scriptPath -GodotPath $GodotPath -Arguments @('--desert') -TimeoutSeconds 180 -LogFile $desertLog
                $desertText = (Get-Content -Raw -LiteralPath $desertLog) + (Get-Content -Raw -LiteralPath ($desertLog + '.err'))
                Write-Output $desertText
                if ($desertText -match 'SCRIPT ERROR|(?m)^ERROR:' -or $desertText -notmatch 'failures=\[\]') { throw "Desert performance failed. See $desertLog" }
            }
        }
    }

    if ($runEnet) {
        if ($hasFailure) {
            Add-ValidationResult -Name 'enet' -Status 'skipped' -DurationMs 0 -Detail 'An earlier validation stage failed.'
        } else {
            $cleanupNeeded = $true
            Invoke-ValidationStage -Name 'enet' -Action {
                & $runNetwork -GodotPath $GodotPath -ResultDirectory $networkResultDirectory
            }
        }
    }
} finally {
    if ($cleanupNeeded) {
        Invoke-ValidationStage -Name 'cleanup' -Action {
            & $cleanup -StopTracked -StopUntracked
        }
    }
}

$totalWatch.Stop()
$summary = [ordered]@{
    level       = $Level
    areas       = @($selectedAreas)
    status      = if ($hasFailure) { 'failed' } else { 'passed' }
    duration_ms = $totalWatch.ElapsedMilliseconds
    results     = @($results)
}
Write-Output ('VALIDATION_SUMMARY ' + ($summary | ConvertTo-Json -Depth 5 -Compress))

if ($hasFailure) {
    throw "$Level validation failed."
}
