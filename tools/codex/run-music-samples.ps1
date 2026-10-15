[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$python = (Get-Command python.exe -ErrorAction Stop).Source
$generator = Resolve-ProjectPath -Path 'assets/concept_art/music_samples/v1/compose.py'
& $python $generator
if ($LASTEXITCODE -ne 0) { throw "Music sample generation failed: $LASTEXITCODE" }
