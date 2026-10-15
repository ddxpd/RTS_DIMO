[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ResultDirectory,
    [ValidateRange(15, 600)][int]$DurationSeconds = 180
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$directory = Resolve-ProjectPath -Path $ResultDirectory
if (-not (Test-PathWithin -Candidate $directory -Root (Join-Path $script:ProjectRoot '.godot\validation'))) {
    throw 'Network results must remain under .godot/validation.'
}
function Get-Percentile {
    param([object[]]$Values, [double]$Fraction = 0.95)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    return $sorted[[Math]::Min($sorted.Count - 1, [Math]::Floor($sorted.Count * $Fraction))]
}
$runs = Get-Content -Raw -LiteralPath (Join-Path $directory 'summary.json') | ConvertFrom-Json
$report = @()
$phaseMs = $DurationSeconds * 1000 / 3
foreach ($run in $runs) {
    $guest = $run.result
    $hostFile = Join-Path $run.directory 'host.json'
    $proxyFile = Join-Path $run.directory 'proxy.json'
    $hostResult = if (Test-Path -LiteralPath $hostFile) { Get-Content -Raw -LiteralPath $hostFile | ConvertFrom-Json } else { $null }
    $proxy = if (Test-Path -LiteralPath $proxyFile) { Get-Content -Raw -LiteralPath $proxyFile | ConvertFrom-Json } else { $null }
    $phases = @()
    if ($guest) {
        foreach ($phase in 0..2) {
            $values = @($guest.ack_samples | Where-Object {
                $issued = $_.elapsed_ms - $_.ms
                $issued -ge ($phase * $phaseMs) -and $issued -lt (($phase + 1) * $phaseMs)
            } | ForEach-Object ms)
            $phases += [ordered]@{ units=@(50,100,200)[$phase]; acknowledgements=$values.Count; ack_p95_ms=Get-Percentile -Values $values }
        }
    }
    $entry = [ordered]@{
        profile=$run.profile
        seed=$run.seed
        correctness=$run.correctness
        responsive=$run.responsive
        acknowledgement_ms=if ($guest) { $guest.ack_ms } else { $null }
        application_ping_ms=if ($guest) { $guest.rtt_ms } else { $null }
        snapshot_interval_ms=if ($guest) { $guest.snapshot_interval_ms } else { $null }
        host_tick_interval_ms=if ($hostResult) { $hostResult.host_tick_interval_ms } else { $null }
        snapshot_frame_lag_p95=if ($guest) { Get-Percentile -Values @($guest.snapshot_frame_lag | ForEach-Object frames) } else { $null }
        snapshot_frame_lag_max=if ($guest) { Get-Percentile -Values @($guest.snapshot_frame_lag | ForEach-Object frames) -Fraction 1 } else { $null }
        phases=$phases
        first_snapshot_after_restore_ms=$run.recovery_ms
        failures=@(if ($guest) { $guest.failures } else { 'Missing guest result' })
        host_failures=@(if ($hostResult) { $hostResult.failures } else { 'Missing host result' })
        transport=$proxy
    }
    $report += $entry
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $directory 'report.json')
$report | ForEach-Object {
    [pscustomobject]@{
        Profile=$_.profile; Seed=$_.seed; Correct=$_.correctness; Responsive=$_.responsive
        AckP95=if ($_.acknowledgement_ms -and $_.acknowledgement_ms.count -gt 0) { $_.acknowledgement_ms.p95 } else { $null }
        PingP95=if ($_.application_ping_ms -and $_.application_ping_ms.count -gt 0) { $_.application_ping_ms.p95 } else { $null }
        FrameLagP95=$_.snapshot_frame_lag_p95
    }
} | Format-Table -AutoSize | Out-String -Width 180
