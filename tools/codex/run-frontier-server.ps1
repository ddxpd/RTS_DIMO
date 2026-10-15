[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$BindAddress = '127.0.0.1',
    [string]$ExportedOutput,
    [ValidateRange(1024, 65535)][int]$Port = 24562,
    [ValidateRange(0, 60)][int]$SmokeSeconds = 0,
    [ValidateRange(0, 3600)][int]$TimeoutSeconds = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$godot = if ($ExportedOutput) { Resolve-ProjectPath -Path $ExportedOutput } else { Get-TrustedGodotPath -RequestedPath $GodotPath }
$arguments = @('--headless')
if (-not $ExportedOutput) { $arguments += @('--path', $script:ProjectRoot) }
$arguments += @('--', '--dedicated', "--bind=$BindAddress", "--port=$Port")
if ($SmokeSeconds -gt 0) {
    $logPath = Join-Path $script:ProjectRoot '.godot/frontier-server-smoke.log'
    $serverProcessId = Start-TrackedProcess -FilePath $godot -ArgumentList $arguments -Label 'GAIA server smoke' -OutputLog $logPath
    try {
        Start-Sleep -Seconds $SmokeSeconds
        $process = Get-Process -Id $serverProcessId -ErrorAction Stop
        $logText = Get-Content -Raw -LiteralPath $logPath
        $errors = Get-Content -Raw -LiteralPath ($logPath + '.err')
        if ($logText -notmatch 'GAIA service .+: OK' -or $errors -match 'SCRIPT ERROR|(?m)^ERROR:') { throw 'Dedicated service did not start cleanly.' }
        Write-Output 'FRONTIER_EXPORTED_SERVER_PASS'
    } finally {
        Stop-Process -Id $serverProcessId -ErrorAction SilentlyContinue
        Remove-TrackedProcess -ProcessId $serverProcessId
    }
    exit
}
$code = Start-TrackedProcess -FilePath $godot -ArgumentList $arguments -Label 'GAIA dedicated server' -OutputLog (Join-Path $script:ProjectRoot '.godot/frontier-server.log') -TimeoutSeconds $TimeoutSeconds -Wait
if ($code -ne 0) { throw "Server exited with code $code" }
