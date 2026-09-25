[CmdletBinding()]
param(
    [ValidateSet('version', 'script', 'export')]
    [string]$Action = 'version',
    [string]$Script,
    [string]$Preset = 'Windows Desktop',
    [string]$Output = 'build\IronFront.exe',
    [string]$GodotPath,
    [string[]]$Arguments = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$godotArguments = @()

switch ($Action) {
    'version' {
        if ($Arguments.Count -gt 0) { throw 'The version action does not accept extra arguments.' }
        $godotArguments = @('--version')
    }
    'script' {
        if (-not $Script) { throw 'The script action requires -Script res://path.' }
        [void](Resolve-ProjectScript -Script $Script)
        foreach ($argument in $Arguments) {
            if ($argument -match '^(--path|--editor|--path=|--editor=)') {
                throw "The wrapper owns the project path and editor mode: $argument"
            }
        }
        $godotArguments = @('--headless', '--path', $script:ProjectRoot, '--script', $Script) + $Arguments
    }
    'export' {
        $outputPath = Resolve-ProjectPath -Path $Output -AllowMissing
        if ([IO.Path]::GetExtension($outputPath) -ne '.exe') {
            throw 'Godot export output must be a project-local .exe file.'
        }
        if ($Arguments.Count -gt 0) { throw 'Use the fixed export action instead of arbitrary Godot arguments.' }
        $godotArguments = @('--headless', '--path', $script:ProjectRoot, '--export-release', $Preset, $outputPath)
    }
}

$exitCode = Start-TrackedProcess -FilePath $godot -ArgumentList $godotArguments -Label "Godot $Action" -Wait
if ($exitCode -ne 0) {
    throw "Godot $Action failed with exit code $exitCode."
}

