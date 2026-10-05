[CmdletBinding()]
param(
    [string]$Output = 'build\IronFront.exe',
    [ValidateRange(1, 60)]
    [int]$DurationSeconds = 5
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$outputPath = Resolve-ProjectPath -Path $Output
if ([IO.Path]::GetExtension($outputPath) -ne '.exe') {
    throw 'Exported smoke run requires a project-local .exe file.'
}

$processId = Start-TrackedProcess -FilePath $outputPath -ArgumentList @('--smoke') -Label 'Exported game smoke run'
Start-Sleep -Seconds $DurationSeconds

try {
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ($process.HasExited) {
        Remove-TrackedProcess -ProcessId $processId
        throw "Exported game exited during the ${DurationSeconds}s smoke run with code $($process.ExitCode)."
    }
    Write-Output "EXPORTED_GAME_SMOKE_PASS PID $processId alive_after_${DurationSeconds}s"
} catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
    Remove-TrackedProcess -ProcessId $processId
    throw "Exported game exited before the ${DurationSeconds}s smoke check."
}
