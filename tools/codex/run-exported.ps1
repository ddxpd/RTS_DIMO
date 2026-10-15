[CmdletBinding()]
param(
    [string]$Output = 'build\IronFront.exe',
    [string]$LogFile = '.godot\exported-smoke.log',
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
$processId = Start-TrackedProcess -FilePath $outputPath -ArgumentList @('--smoke', '--log-file', $logPath) -Label 'Exported game smoke run'
Start-Sleep -Seconds $DurationSeconds

try {
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ($process.HasExited) {
        Remove-TrackedProcess -ProcessId $processId
        throw "Exported game exited during the ${DurationSeconds}s smoke run with code $($process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $logPath)) { throw "Exported smoke log was not created: $logPath" }
    $logText = Get-Content -Raw -LiteralPath $logPath
    if ($logText -match 'SCRIPT ERROR|(?m)^ERROR:') { throw "Exported game logged startup errors: $logPath" }
    Write-Output "EXPORTED_GAME_SMOKE_PASS PID $processId alive_after_${DurationSeconds}s"
} catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
    Remove-TrackedProcess -ProcessId $processId
    throw "Exported game exited before the ${DurationSeconds}s smoke check."
}
