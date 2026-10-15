param(
    [string]$GodotPath,
    [string]$ResultDirectory,
    [ValidateSet("desert_quarry")]
    [string]$MapId = "desert_quarry"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\codex\project-common.ps1')
$GodotPath = Get-TrustedGodotPath -RequestedPath $GodotPath
$projectDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$validationRoot = [IO.Path]::GetFullPath((Join-Path $projectDir '.godot\validation')).TrimEnd('\')
$resultDir = if ($ResultDirectory) {
    [IO.Path]::GetFullPath($ResultDirectory).TrimEnd('\')
} else {
    Join-Path $validationRoot ('network-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
}
if (-not ($resultDir.Equals($validationRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $resultDir.StartsWith($validationRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Network validation output must remain under .godot\validation.'
}
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$started = @()
function Wait-NetworkMarker {
    param([string]$Path, [string]$Marker)
    $until = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $until) {
        $content = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($content -match 'SCRIPT ERROR|NETWORK_TEST.*Timeout') { throw "Network startup failed: $content" }
        if ($content -match [regex]::Escape($Marker)) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "Network startup marker missing: $Marker in $Path"
}
try {
    $hostLog = Join-Path $resultDir 'host.log'
    $hostProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',$projectDir,'--log-file',$hostLog,'--script','res://tests/network/network_guest.gd','--','--role=host',"--map=$MapId") -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
    $started += $hostProcess
    Wait-NetworkMarker -Path $hostLog -Marker 'NETWORK_BOOTSTRAP_READY'
    foreach ($testRole in @('mismatch','guest','guest')) {
        if ($testRole -eq 'mismatch') { $roundIndex = 0 } elseif ($roundIndex -eq 0) { $roundIndex = 1 } else { $roundIndex = 2 }
        $log = Join-Path $resultDir "guest_$roundIndex.log"
        $guestProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',$projectDir,'--log-file',$log,'--script','res://tests/network/network_guest.gd','--',"--role=$testRole","--round=$roundIndex", "--map=$MapId") -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
        $started += $guestProcess
        if ($roundIndex -eq 1) {
            Wait-NetworkMarker -Path $log -Marker 'NETWORK_STAGE joined round 1'
            $spectatorLogPath = Join-Path $resultDir 'spectator.log'
            $spectatorProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',$projectDir,'--log-file',$spectatorLogPath,'--script','res://tests/network/network_guest.gd','--','--role=spectator',"--map=$MapId") -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
            $started += $spectatorProcess
            # Asset loading is separate from the six-second connection budget.
            Wait-NetworkMarker -Path $spectatorLogPath -Marker 'NETWORK_BOOTSTRAP_READY'
            if (-not $spectatorProcess.WaitForExit(6000)) { throw 'Spectator timed out' }
            $spectatorLog = Get-Content -Raw -LiteralPath $spectatorLogPath
            $spectatorLog = $spectatorLog -replace 'ERROR: Failed to read the root certificate store\.', ''
            if ($spectatorLog -match 'SCRIPT ERROR|ERROR:' -or $spectatorLog -notmatch 'NETWORK_TEST PASS') { throw $spectatorLog }
            Write-Output $spectatorLog
        }
        # Match network_probe.gd's 180-second watchdog. Directional relocation
        # now includes stationary turns before travel and before landing.
        if (-not $guestProcess.WaitForExit(185000)) { throw "Guest $roundIndex timed out" }
        $text = Get-Content -Raw -LiteralPath $log
        $text = $text -replace 'ERROR: Failed to read the root certificate store\.', ''
        if ($text -match 'SCRIPT ERROR|NETWORK_TEST.*Timeout|ERROR:' -or $text -notmatch 'NETWORK_TEST PASS') { throw "Guest $roundIndex failed: $text" }
        Write-Output $text
        Start-Sleep -Milliseconds 500
    }
    if (-not $hostProcess.WaitForExit(5000)) { throw 'Host timed out' }
    $text = Get-Content -Raw -LiteralPath (Join-Path $resultDir 'host.log')
    $text = $text -replace 'ERROR: Failed to read the root certificate store\.', ''
    if ($text -match 'SCRIPT ERROR|ERROR:' -or $text -notmatch 'PASS round 2') { throw "Host failed: $text" }
    Write-Output $text
} finally {
    foreach ($testProcess in $started) {
        $testProcess.Refresh()
        if (-not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id -Force }
    }
}
Write-Output "NETWORK_LOG_DIR $resultDir"
