[CmdletBinding()]
param(
    [string]$GamePath = (Join-Path $PSScriptRoot '../../build/IronFront.exe'),
    [string]$BindAddress = '127.0.0.1',
    [ValidateRange(1024, 65535)][int]$Port = 24562
)
$ErrorActionPreference = 'Stop'
$executable = (Resolve-Path -LiteralPath $GamePath).Path
Start-Process -FilePath $executable -ArgumentList @('--headless', '--', '--dedicated', "--bind=$BindAddress", "--port=$Port") -WindowStyle Hidden -PassThru
