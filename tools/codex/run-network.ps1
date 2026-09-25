[CmdletBinding()]
param(
    [string]$GodotPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$networkScript = Join-Path $script:ProjectRoot 'tests\run_network_guest.ps1'
if (-not (Test-Path -LiteralPath $networkScript -PathType Leaf)) {
    throw "Network test runner was not found: $networkScript"
}

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $networkScript, '-GodotPath', $godot) -WorkingDirectory $script:ProjectRoot -WindowStyle Hidden -PassThru
Add-TrackedProcess -ProcessId $process.Id -Label 'Godot network test runner' -Executable $networkScript
try {
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Godot network test runner failed with exit code $($process.ExitCode)."
    }
} finally {
    Remove-TrackedProcess -ProcessId $process.Id
}
