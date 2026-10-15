[CmdletBinding()]
param(
    [string]$Output = 'build\GAIA_Frontier.exe',
    [string]$LogFile = '.godot\exported-smoke.log',
    [switch]$Dedicated,
    [ValidateRange(1024, 65535)]
    [int]$Port = 24562,
    [ValidateRange(1, 60)]
    [int]$DurationSeconds = 5
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$outputPath = Resolve-ProjectPath -Path $Output
if ([IO.Path]::GetExtension($outputPath) -ne '.exe') {
    throw 'Exported smoke run requires a project-local .exe file.'
}

$logPath = Resolve-ProjectPath -Path $LogFile -AllowMissing
$arguments = @('--smoke', '--log-file', $logPath)
if ($Dedicated) { $arguments = @('--headless') + $arguments + @('--', '--dedicated', '--bind=127.0.0.1', "--port=$Port") }
$processId = Start-TrackedProcess -FilePath $outputPath -ArgumentList $arguments -Label 'Exported game smoke run' -OutputLog ($logPath + '.stdout') -ErrorLog ($logPath + '.err')
Start-Sleep -Seconds $DurationSeconds

try {
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ($process.HasExited) {
        Remove-TrackedProcess -ProcessId $processId
        throw "Exported game exited during the ${DurationSeconds}s smoke run with code $($process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $logPath)) { throw "Exported smoke log was not created: $logPath" }
    $logText = (Get-Content -Raw -LiteralPath $logPath) + (Get-Content -Raw -LiteralPath ($logPath + '.stdout')) + (Get-Content -Raw -LiteralPath ($logPath + '.err'))
    if ($logText -match 'SCRIPT ERROR|(?m)^ERROR:') { throw "Exported game logged startup errors: $logPath" }
    if ($Dedicated -and $logText -notmatch 'GAIA service 127\.0\.0\.1:\d+: OK') { throw "Exported server did not confirm its listener: $logPath" }
    Write-Output "EXPORTED_GAME_SMOKE_PASS PID $processId alive_after_${DurationSeconds}s"
} catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
    Remove-TrackedProcess -ProcessId $processId
    throw "Exported game exited before the ${DurationSeconds}s smoke check."
}
