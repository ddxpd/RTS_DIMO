[CmdletBinding()]
param(
    [ValidateSet('version', 'script')]
    [string]$Action = 'version',
    [string]$Script,
    [string]$BlendFile,
    [string]$BlenderPath,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$blender = Get-TrustedBlenderPath -RequestedPath $BlenderPath

switch ($Action) {
    'version' {
        $blenderArguments = @('--version')
    }
    'script' {
        if (-not $Script) { throw 'The script action requires -Script res://path.py.' }
        $scriptPath = Resolve-ProjectScript -Script $Script
        if ([IO.Path]::GetExtension($scriptPath) -ne '.py') {
            throw 'Blender scripts must be project-local Python files.'
        }
        $blenderArguments = @('--background')
        if ($BlendFile) {
            $blendPath = Resolve-ProjectPath -Path $BlendFile
            if ([IO.Path]::GetExtension($blendPath) -ne '.blend') {
                throw 'BlendFile must be a project-local .blend file.'
            }
            $blenderArguments += @($blendPath)
        }
        $blenderArguments += @('--python', $scriptPath)
    }
}

$startParameters = @{
    FilePath     = $blender
    ArgumentList = $blenderArguments
    Label        = "Blender $Action"
    Wait         = $true
}
if ($LogFile) {
    $logPath = Resolve-ProjectPath -Path $LogFile -AllowMissing
    $startParameters.OutputLog = $logPath
    $startParameters.ErrorLog = $logPath + '.err'
}
$exitCode = Start-TrackedProcess @startParameters
if ($exitCode -ne 0) {
    throw "Blender $Action failed with exit code $exitCode."
}
