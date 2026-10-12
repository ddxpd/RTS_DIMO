[CmdletBinding()]
param([string]$PreservedManifest = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$python = (Get-Command python.exe -ErrorAction Stop).Source
$auditArgs = @((Join-Path $PSScriptRoot 'check-structure.py'))
if ($PreservedManifest) { $auditArgs += (Resolve-ProjectPath -Path $PreservedManifest) }
& $python @auditArgs
if ($LASTEXITCODE -ne 0) { throw 'Structure audit failed.' }
