[CmdletBinding()]
param(
    [ValidateSet('install', 'start', 'stop', 'status', 'export', 'refresh', 'portraits', 'test')]
    [string]$Action = 'start',
    [switch]$Offline
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$toolDirectory = Join-Path $script:ProjectRoot 'tools\balance_designer'
$storeDirectory = Join-Path $script:ProjectRoot '.local\balance_designer'
$serviceLabel = 'Balance designer'
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $storeDirectory | Out-Null

if ($Action -eq 'install') {
    $npmPath = Join-Path (Split-Path -Parent $nodePath) 'node_modules\npm\bin\npm-cli.js'
    $verb = if (Test-Path (Join-Path $toolDirectory 'package-lock.json')) { 'ci' } else { 'install' }
    $installArgs = @($npmPath, $verb, '--prefix', $toolDirectory, '--no-audit', '--no-fund', '--ignore-scripts')
    if ($Offline) { $installArgs += '--offline' }
    $code = Start-TrackedProcess -FilePath $nodePath -ArgumentList $installArgs -Label 'Balance dependency install' -Wait -TimeoutSeconds 180
    if ($code -ne 0) { throw "Balance dependency installation failed: $code" }
    return
}

function Invoke-BalanceCapture([string]$Kind) {
    $captureLog = Join-Path $storeDirectory ($Kind + '.log')
    $captureArgs = @{
        Action = 'script'
        Script = "res://tools/balance_designer/$Kind.gd"
        TimeoutSeconds = 120
        LogFile = $captureLog
    }
    if ($Kind -eq 'portraits') { $captureArgs.Rendered = $true }
    & (Join-Path $PSScriptRoot 'run-godot.ps1') @captureArgs
    $captureText = (Get-Content -Raw -LiteralPath $captureLog -Encoding UTF8) + (Get-Content -Raw -LiteralPath ($captureLog + '.err') -Encoding UTF8)
    Write-Output $captureText
    $marker = if ($Kind -eq 'export') { 'BALANCE_EXPORT PASS' } else { 'BALANCE_PORTRAITS PASS' }
    if ($captureText -notmatch $marker -or $captureText -match 'SCRIPT ERROR|(?m)^ERROR:') { throw "Balance $Kind failed; see $captureLog" }
}

if ($Action -in @('export', 'portraits')) { Invoke-BalanceCapture $Action; return }
$tracked = @(Read-TrackedProcesses | Where-Object { $_.Label -eq $serviceLabel })
if ($Action -eq 'stop') {
    foreach ($entry in $tracked) { Stop-TrackedProcess -ProcessId ([int]$entry.ProcessId) }
    return
}
if ($Action -eq 'status') {
    foreach ($entry in $tracked) { Get-Process -Id ([int]$entry.ProcessId) -ErrorAction SilentlyContinue | Select-Object Id,ProcessName }
    return
}
if ($Action -eq 'refresh') {
    try { $current = Invoke-RestMethod -Uri 'http://127.0.0.1:8811/api/state' -TimeoutSec 3 }
    catch { throw 'Start the designer first, then refresh from its webpage or this wrapper.' }
    if (-not $current.localOnly -or -not $current.token) { throw 'Port 8811 is not the balance designer.' }
    $refreshBody = @{ op = 'refresh'; revision = $current.revision } | ConvertTo-Json -Compress
    $updated = Invoke-RestMethod -Uri 'http://127.0.0.1:8811/api/mutate' -Method Post -ContentType 'application/json' -Headers @{ 'X-Local-Token' = $current.token } -Body $refreshBody -TimeoutSec 150
    Write-Output "BALANCE_REFRESH PASS revision=$($updated.revision)"
    return
}
if ($Action -eq 'test') {
    if (-not (Test-Path (Join-Path $storeDirectory 'raw.json'))) { Invoke-BalanceCapture 'export' }
    $testLog = Join-Path $storeDirectory 'test.log'
    $code = Start-TrackedProcess -FilePath $nodePath -ArgumentList @((Join-Path $toolDirectory 'test.mjs')) -Label 'Balance designer tests' -OutputLog $testLog -Wait -TimeoutSeconds 180
    Get-Content -LiteralPath $testLog -Encoding UTF8
    Get-Content -LiteralPath ($testLog + '.err') -Encoding UTF8
    if ($code -ne 0 -or (Get-Content -Raw -LiteralPath $testLog) -notmatch 'BALANCE_TEST PASS') { throw "Balance tests failed: $code" }
    return
}
foreach ($entry in $tracked) {
    if (Get-Process -Id ([int]$entry.ProcessId) -ErrorAction SilentlyContinue) {
        Write-Output 'Balance designer already running: http://127.0.0.1:8811'
        return
    }
    Remove-TrackedProcess -ProcessId ([int]$entry.ProcessId)
}
$probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 8811)
try { $probe.Start() } catch { throw 'Port 8811 is already occupied. No process was stopped.' } finally { $probe.Stop() }
if (-not (Test-Path (Join-Path $storeDirectory 'state.json'))) { Invoke-BalanceCapture 'export' }
$servicePid = Start-TrackedProcess -FilePath $nodePath -ArgumentList @((Join-Path $toolDirectory 'server.mjs')) -Label $serviceLabel -OutputLog (Join-Path $storeDirectory 'server.log')
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 200
    if (-not (Get-Process -Id $servicePid -ErrorAction SilentlyContinue)) { Remove-TrackedProcess -ProcessId $servicePid; throw "Designer startup failed; see $storeDirectory\server.log.err" }
    try {
        $ready = Invoke-RestMethod -Uri 'http://127.0.0.1:8811/api/state' -TimeoutSec 1
        if ($ready.localOnly) { Write-Output 'Open http://127.0.0.1:8811 in your browser.'; return }
    } catch { }
}
Stop-TrackedProcess -ProcessId $servicePid
throw 'Designer startup timed out.'
