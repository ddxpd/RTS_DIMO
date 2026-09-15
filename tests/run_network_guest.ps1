param([string]$GodotPath = 'D:\application\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$resultDir = Join-Path $projectDir 'build\verification'
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$started = @()
try {
    $hostProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',$projectDir,'--log-file','build/verification/host.log','--script','res://tests/network_guest.gd','--','--role=host') -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
    $started += $hostProcess
    Start-Sleep -Milliseconds 600
    foreach ($testRole in @('mismatch','guest','guest')) {
        if ($testRole -eq 'mismatch') { $roundIndex = 0 } elseif ($roundIndex -eq 0) { $roundIndex = 1 } else { $roundIndex = 2 }
        $log = "build/verification/guest_$roundIndex.log"
        $guestProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',$projectDir,'--log-file',$log,'--script','res://tests/network_guest.gd','--',"--role=$testRole","--round=$roundIndex") -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
        $started += $guestProcess
        if ($roundIndex -eq 1) {
            Start-Sleep -Milliseconds 1000
            $spectatorProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',$projectDir,'--log-file','build/verification/spectator.log','--script','res://tests/network_guest.gd','--','--role=spectator') -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
            $started += $spectatorProcess
            if (-not $spectatorProcess.WaitForExit(6000)) { throw 'Spectator timed out' }
            $spectatorLog = Get-Content -Raw -LiteralPath (Join-Path $resultDir 'spectator.log')
            if ($spectatorLog -match 'SCRIPT ERROR|ERROR:' -or $spectatorLog -notmatch 'NETWORK_TEST PASS') { throw $spectatorLog }
            Write-Output $spectatorLog
        }
        if (-not $guestProcess.WaitForExit(50000)) { throw "Guest $roundIndex timed out" }
        $text = Get-Content -Raw -LiteralPath (Join-Path $projectDir $log)
        if ($text -match 'SCRIPT ERROR|NETWORK_TEST.*Timeout|ERROR:' -or $text -notmatch 'NETWORK_TEST PASS') { throw "Guest $roundIndex failed: $text" }
        Write-Output $text
        Start-Sleep -Milliseconds 500
    }
    if (-not $hostProcess.WaitForExit(5000)) { throw 'Host timed out' }
    $text = Get-Content -Raw -LiteralPath (Join-Path $resultDir 'host.log')
    if ($text -match 'SCRIPT ERROR|ERROR:' -or $text -notmatch 'PASS round 2') { throw "Host failed: $text" }
    Write-Output $text
} finally {
    foreach ($testProcess in $started) {
        $testProcess.Refresh()
        if (-not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id -Force }
    }
}
