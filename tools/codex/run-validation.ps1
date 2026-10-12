[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Light', 'Full')]
    [string]$Level,
    [string]$Area = '',
    [string]$GodotPath,
    [ValidatePattern('^(\d+(,\d+)*)?$')]
    [string]$PreserveProcessId = ''
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
$registry = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'validation-suites.json') | ConvertFrom-Json
$requestedSuites = @($registry.suites | Where-Object {
    $_.full -and ($Level -eq 'Full' -or @($_.areas | Where-Object { $_ -in $selectedAreas }).Count -gt 0)
})
$runEnet = $Level -eq 'Full' -or $selectedAreas -contains 'Network'
$runTooling = $selectedAreas -contains 'Tooling'

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
    Invoke-ValidationStage -Name 'structure' -Action {
        & (Join-Path $PSScriptRoot 'run-structure.ps1')
    }
    if ($runTooling) {
        # Tooling includes a Godot startup regression with duplicate Path keys.
        $cleanupNeeded = $true
        Invoke-ValidationStage -Name 'tooling' -Action {
            & $verifyPermissions
        }
    }

    foreach ($suite in $requestedSuites) {
        $suiteName = $suite.name
        $cleanupNeeded = $true
        $scriptPath = $suite.script
        Invoke-ValidationStage -Name $suiteName -Action {
            $stageLog = Join-Path $script:ProjectRoot ".godot\validation\$runId\$suiteName.log"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stageLog) | Out-Null
            & $runGodot -Action script -Script $scriptPath -GodotPath $GodotPath -TimeoutSeconds $suite.timeout -LogFile $stageLog -Rendered:($suite.mode -eq 'rendered')
            $stageText = (Get-Content -Raw -LiteralPath $stageLog) + (Get-Content -Raw -LiteralPath ($stageLog + '.err'))
            Write-Output $stageText
            if ($suite.marker -and $stageText -notmatch [regex]::Escape($suite.marker)) { throw "Missing completion marker in $suiteName. See $stageLog" }
            if ($stageText -match '"?failures"?\s*[:=]\s*[1-9][0-9]*') { throw "Godot reported failed assertions in $suiteName. See $stageLog" }
            if ($stageText -match 'SCRIPT ERROR|(?m)^ERROR:') { throw "Godot logged an error in $suiteName. See $stageLog" }
            if ($stageText -match '"?failures"?\s*[:=]\s*\[\s*[^\s\]]') { throw "Godot reported failed assertions in $suiteName. See $stageLog" }
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
            & $cleanup -StopTracked -StopUntracked -PreserveProcessId $PreserveProcessId
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
