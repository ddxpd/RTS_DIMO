[CmdletBinding()]
param(
    [ValidateSet('install', 'start', 'stop', 'status', 'test', 'inventory-history', 'cleanup-history', 'cleanup-reviewed')]
    [string]$Action = 'start',
    [string]$VerificationManifest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$libraryDirectory = Join-Path $script:ProjectRoot 'tools\art_library'
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$libraryLabel = 'Personal art library'

if ($Action -eq 'install') {
    $npmPath = Join-Path (Split-Path -Parent $nodePath) 'node_modules\npm\bin\npm-cli.js'
    $installVerb = if (Test-Path (Join-Path $libraryDirectory 'package-lock.json')) { 'ci' } else { 'install' }
    $code = Start-TrackedProcess -FilePath $nodePath -ArgumentList @($npmPath, $installVerb, '--prefix', $libraryDirectory, '--no-audit', '--no-fund') -Label 'Art library dependency install' -Wait -TimeoutSeconds 300
    if ($code -ne 0) { throw "Dependency installation failed: $code" }
    return
}

$tracked = @(Read-TrackedProcesses | Where-Object { $_.Label -eq $libraryLabel })
if ($Action -eq 'stop') {
    foreach ($entry in $tracked) { Stop-TrackedProcess -ProcessId ([int]$entry.ProcessId) }
    return
}
if ($Action -eq 'status') {
    foreach ($entry in $tracked) { Get-Process -Id ([int]$entry.ProcessId) -ErrorAction SilentlyContinue | Select-Object Id,ProcessName }
    return
}
if (-not (Test-Path (Join-Path $libraryDirectory 'node_modules\sharp'))) {
    throw 'Install dependencies first: run-art-library.ps1 -Action install'
}
if ($Action -eq 'test') {
    $testLog = Join-Path $script:ProjectRoot '.local\art-library-test.log'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $testLog) | Out-Null
    $code = Start-TrackedProcess -FilePath $nodePath -ArgumentList @((Join-Path $libraryDirectory 'test.mjs')) -Label 'Art library tests' -OutputLog $testLog -Wait -TimeoutSeconds 180
    Get-Content -LiteralPath $testLog -Encoding UTF8
    Get-Content -LiteralPath ($testLog + '.err') -Encoding UTF8
    $testText = (Get-Content -Raw -LiteralPath $testLog) + (Get-Content -Raw -LiteralPath ($testLog + '.err'))
    if ($code -ne 0 -or $testText -notmatch 'ART_LIBRARY_TEST PASS checks=' -or $testText -match 'ART_LIBRARY_TEST FAILED') { throw "Art library tests failed: $code" }
    return
}
if ($Action -in @('inventory-history', 'cleanup-history', 'cleanup-reviewed')) {
    if (@($tracked | Where-Object { Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue }).Count) { throw 'Stop the personal library before maintenance to prevent concurrent catalogue writes.' }
    $maintenanceLog = Join-Path $script:ProjectRoot ('.local\art-library-' + $Action + '.log')
    $maintenanceArgs = @((Join-Path $libraryDirectory 'maintenance.mjs'), $Action)
    if ($VerificationManifest) {
        if ($Action -ne 'cleanup-reviewed') { throw 'VerificationManifest is only valid for cleanup-reviewed.' }
        $maintenanceArgs += $VerificationManifest
    }
    $code = Start-TrackedProcess -FilePath $nodePath -ArgumentList $maintenanceArgs -Label 'Art library maintenance' -OutputLog $maintenanceLog -Wait -TimeoutSeconds 300
    Get-Content -LiteralPath $maintenanceLog -Encoding UTF8
    Get-Content -LiteralPath ($maintenanceLog + '.err') -Encoding UTF8
    if ($code -ne 0 -or (Get-Item ($maintenanceLog + '.err')).Length -ne 0) { throw "Art library maintenance failed: $code" }
    return
}
foreach ($entry in $tracked) {
    if (Get-Process -Id ([int]$entry.ProcessId) -ErrorAction SilentlyContinue) {
        Write-Output 'Art library is already running: http://127.0.0.1:8810'
        return
    }
    Remove-TrackedProcess -ProcessId ([int]$entry.ProcessId)
}
$logDirectory = Join-Path $script:ProjectRoot '.local\art-library'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$libraryPid = Start-TrackedProcess -FilePath $nodePath -ArgumentList @((Join-Path $libraryDirectory 'server.mjs')) -Label $libraryLabel -OutputLog (Join-Path $logDirectory 'server.log')
$ready = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 200
    if (-not (Get-Process -Id $libraryPid -ErrorAction SilentlyContinue)) {
        Remove-TrackedProcess -ProcessId $libraryPid
        throw "Server startup failed; see $logDirectory\server.log.err"
    }
    try {
        $catalog = Invoke-RestMethod -Uri 'http://127.0.0.1:8810/api/catalog' -TimeoutSec 1
        if ($catalog.localOnly) { $ready = $true; break }
    } catch { }
}
if (-not $ready) { throw "Server did not become ready; see $logDirectory\server.log.err" }
Write-Output 'Open http://127.0.0.1:8810 in your browser. Local computer only.'
