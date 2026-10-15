[CmdletBinding()]
param(
    [ValidateSet('version', 'import', 'script', 'export')]
    [string]$Action = 'version',
    [string]$Script,
    [string]$Pack,
    [string]$Preset = 'Windows Desktop',
    [string]$Output = 'build\GAIA_Frontier.exe',
    [string]$GodotPath,
    [string]$LogFile,
    [switch]$Rendered,
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 0,
    [string[]]$Arguments = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$godot = Get-TrustedGodotPath -RequestedPath $GodotPath
$godotArguments = @()
if ($Rendered -and $Action -ne 'script') {
    throw 'Rendered mode is only supported for project scripts.'
}

switch ($Action) {
    'version' {
        if ($Arguments.Count -gt 0) { throw 'The version action does not accept extra arguments.' }
        $godotArguments = @('--version')
    }
    'import' {
        if ($Arguments.Count -gt 0) { throw 'The import action does not accept extra arguments.' }
        $godotArguments = @('--headless', '--editor', '--path', $script:ProjectRoot, '--quit')
    }
    'script' {
        if (-not $Script) { throw 'The script action requires -Script res://path.' }
        $scriptPath = Resolve-ProjectScript -Script $Script
        foreach ($argument in $Arguments) {
            if ($argument -match '^(--path|--editor|--path=|--editor=)') {
                throw "The wrapper owns the project path and editor mode: $argument"
            }
        }
        $displayArguments = @()
        if (-not $Rendered) { $displayArguments += '--headless' }
        if ($Pack) {
            $packPath = Resolve-ProjectPath -Path $Pack
            if ([IO.Path]::GetExtension($packPath) -notin @('.exe', '.pck')) { throw 'Pack must be a project-local EXE or PCK.' }
            # Validate the exported resources with the editor engine; export
            # templates intentionally disable --script and path overrides.
            $isolatedRoot = Join-Path $script:ProjectRoot '.godot\pack-validation'
            [void][IO.Directory]::CreateDirectory($isolatedRoot)
            $godotArguments = $displayArguments + @('--path', $isolatedRoot, '--main-pack', $packPath, '--script', $scriptPath.Replace('\', '/')) + $Arguments
        } else {
            $godotArguments = $displayArguments + @('--path', $script:ProjectRoot, '--script', $Script) + $Arguments
        }
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

$startParameters = @{
    FilePath     = $godot
    ArgumentList = $godotArguments
    Label        = "Godot $Action"
    TimeoutSeconds = $TimeoutSeconds
    Wait         = $true
}
if ($LogFile) {
    $logPath = Resolve-ProjectPath -Path $LogFile -AllowMissing
    $startParameters.OutputLog = $logPath
    $startParameters.ErrorLog = $logPath + '.err'
}
$exitCode = Start-TrackedProcess @startParameters
if ($exitCode -ne 0) {
    throw "Godot $Action failed with exit code $exitCode."
}
