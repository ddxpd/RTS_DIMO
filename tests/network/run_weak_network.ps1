param([string]$GodotPath, [string]$ResultDirectory, [string]$Profile = 'all', [int]$Seed = 0, [int]$DurationSeconds = 180)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\codex\project-common.ps1')
$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$resultRoot = Resolve-ProjectPath -Path $ResultDirectory -AllowMissing
if (-not (Test-PathWithin -Candidate $resultRoot -Root (Join-Path $script:ProjectRoot '.godot\validation'))) { throw 'Invalid weak-network result directory.' }
$profiles = if ($Profile -eq 'all') { @('baseline', 'rtt50', 'rtt100', 'rtt200', 'normal', 'poor', 'limited', 'outage') } else { @($Profile) }
$seeds = @(if ($Seed -eq 0) { 101; 202; 303 } else { $Seed })
$summary = @()
foreach ($profileName in $profiles) {
    $runs = @()
    try {
        # Fixed disjoint ports allow the three seeds to run concurrently. Record
        # host timing too: concurrent CPU pressure must not be called network lag.
        foreach ($seedValue in $seeds) {
            $index = $runs.Count
            $port = 24600 + $index * 10
            $directory = Join-Path $resultRoot "$profileName-$seedValue"
            New-Item -ItemType Directory -Force -Path $directory | Out-Null
            if (Test-Path -LiteralPath (Join-Path $directory 'guest.json')) { throw "Refusing to overwrite test evidence: $directory" }
            $hostArgs = @('--headless', '--path', $script:ProjectRoot, '--script', 'res://tests/network/network_guest.gd', '--', '--weak', '--role=host', "--port=$port", "--duration=$DurationSeconds", "--output=$directory/host.json")
            $hostId = Start-TrackedProcess -FilePath $godot -ArgumentList $hostArgs -Label "Weak host $profileName $seedValue" -OutputLog (Join-Path $directory 'host.log')
            $runs += [pscustomobject]@{ Directory=$directory; HostId=$hostId; ProxyId=0; GuestId=0; Port=$port; Seed=$seedValue; Started=Get-Date }
        }
        foreach ($run in $runs) {
            $until = (Get-Date).AddSeconds(100)
            while ((Get-Date) -lt $until) {
                $log = Get-Content -Raw -LiteralPath (Join-Path $run.Directory 'host.log') -ErrorAction SilentlyContinue
                if ($log -match 'WEAK_HOST_READY') { break }
                $errorText = Get-Content -Raw -LiteralPath (Join-Path $run.Directory 'host.log.err') -ErrorAction SilentlyContinue
                if ($errorText -match 'SCRIPT ERROR|ERROR:') { throw "Host error: $errorText" }
                $process = Get-Process -Id $run.HostId -ErrorAction SilentlyContinue
                if (-not $process) { throw "Host failed: $($run.Directory)" }
                Start-Sleep -Milliseconds 200
            }
            if ($log -notmatch 'WEAK_HOST_READY') { throw 'Host did not become ready.' }
            $proxyPort = $run.Port + 1
            $proxyArgs = @('--headless', '--path', $script:ProjectRoot, '--script', 'res://tests/network/udp_impairment_proxy.gd', '--', "--port=$proxyPort", "--target-port=$($run.Port)", "--profile=$profileName", "--seed=$($run.Seed)", "--output=$($run.Directory)/proxy.json", "--stop-file=$($run.Directory)/proxy.stop", "--lifetime=$($DurationSeconds + 150)")
            $run.ProxyId = Start-TrackedProcess -FilePath $godot -ArgumentList $proxyArgs -Label "UDP impairment $profileName $($run.Seed)" -OutputLog (Join-Path $run.Directory 'proxy.log')
            $guestArgs = @('--headless', '--path', $script:ProjectRoot, '--script', 'res://tests/network/network_guest.gd', '--', '--weak', '--role=guest', "--port=$proxyPort", "--duration=$DurationSeconds", "--output=$($run.Directory)/guest.json")
            $run.GuestId = Start-TrackedProcess -FilePath $godot -ArgumentList $guestArgs -Label "Weak guest $profileName $($run.Seed)" -OutputLog (Join-Path $run.Directory 'guest.log')
            $run.Started = Get-Date
        }
        foreach ($run in $runs) {
            $process = Get-Process -Id $run.GuestId -ErrorAction SilentlyContinue
            $remaining = [Math]::Max(1000, ($DurationSeconds + 160 - ((Get-Date) - $run.Started).TotalSeconds) * 1000)
            if ($process -and -not $process.WaitForExit([int]$remaining)) { Stop-Process -Id $run.GuestId -Force }
            $hostProcess = Get-Process -Id $run.HostId -ErrorAction SilentlyContinue
            if ($hostProcess) { [void]$hostProcess.WaitForExit(8000) }
            New-Item -ItemType File -Path (Join-Path $run.Directory 'proxy.stop') -Force | Out-Null
            $proxy = Get-Process -Id $run.ProxyId -ErrorAction SilentlyContinue
            if ($proxy) { [void]$proxy.WaitForExit(5000) }
            $guestPath = Join-Path $run.Directory 'guest.json'
            $result = if (Test-Path -LiteralPath $guestPath) { Get-Content -Raw -LiteralPath $guestPath | ConvertFrom-Json } else { $null }
            $errors = @(Get-ChildItem -LiteralPath $run.Directory -Filter '*.err' | Where-Object { $_.Length -gt 0 })
            $hostPath = Join-Path $run.Directory 'host.json'
            $hostResult = if (Test-Path -LiteralPath $hostPath) { Get-Content -Raw -LiteralPath $hostPath | ConvertFrom-Json } else { $null }
            $correct = $null -ne $result -and $null -ne $hostResult -and $result.failures.Count -eq 0 -and $hostResult.failures.Count -eq 0 -and $errors.Count -eq 0 -and ($hostResult.loads -join ',') -eq '50,100,200'
            $responsive = $correct -and $result.ack_ms.count -gt 0 -and $result.rtt_ms.count -gt 0 -and $result.ack_ms.p95 -le ($result.rtt_ms.p95 + 300)
            $recoveryMs = $null
            $proxyPath = Join-Path $run.Directory 'proxy.json'
            $proxyResult = if (Test-Path -LiteralPath $proxyPath) { Get-Content -Raw -LiteralPath $proxyPath | ConvertFrom-Json } else { $null }
            if ($profileName -eq 'outage' -and $result -and $proxyResult) {
                $firstAfter = @($result.snapshot_unix_ms | Where-Object { $_ -ge $proxyResult.outage_end_unix_ms } | Select-Object -First 1)
                if ($firstAfter.Count -gt 0) { $recoveryMs = $firstAfter[0] - $proxyResult.outage_end_unix_ms }
                $responsive = $responsive -and $null -ne $recoveryMs -and $recoveryMs -le 5000
            }
            $entry = [ordered]@{ profile=$profileName; seed=$run.Seed; correctness=$correct; responsive=$responsive; recovery_ms=$recoveryMs; result=$result; directory=$run.Directory; concurrent_seeds=$seeds.Count }
            $summary += $entry
            Write-Output "WEAK_RUN profile=$profileName seed=$($run.Seed) correct=$correct responsive=$responsive recovery_ms=$recoveryMs"
        }
    } finally {
        foreach ($run in $runs) {
            foreach ($ownedId in @($run.GuestId, $run.ProxyId, $run.HostId)) {
                if ($ownedId -gt 0) {
                    $process = Get-Process -Id $ownedId -ErrorAction SilentlyContinue
                    if ($process) { Stop-Process -Id $ownedId -Force }
                    Remove-TrackedProcess -ProcessId $ownedId
                }
            }
        }
        $summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultRoot 'summary.json')
    }
}
Write-Output "WEAK_MATRIX_COMPLETE $resultRoot"
$failedRuns = @($summary | Where-Object { -not $_.correctness -or -not $_.responsive })
if ($failedRuns.Count -gt 0) {
    throw "Weak-network validation failed in $($failedRuns.Count) of $($summary.Count) rounds. See $resultRoot/summary.json."
}
