[CmdletBinding()]
param(
    [ValidateSet('version', 'script')]
    [string]$Action = 'version',
    [string]$Script,
    [string]$BlendFile,
    [string]$BlenderPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$blender = if ($BlenderPath) {
    $candidate = [IO.Path]::GetFullPath($BlenderPath)
    if ([IO.Path]::GetFileName($candidate) -ne 'blender.exe' -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
        -not (Test-PathWithin -Candidate $candidate -Root 'D:\mysoftware\blender-5.2.2')) {
        throw 'BlenderPath must point to the trusted Blender installation.'
    }
    $candidate
} else {
    Get-TrustedBlenderPath
}

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

$exitCode = Start-TrackedProcess -FilePath $blender -ArgumentList $blenderArguments -Label "Blender $Action" -Wait
if ($exitCode -ne 0) {
    throw "Blender $Action failed with exit code $exitCode."
}

