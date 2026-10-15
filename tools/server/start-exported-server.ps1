[CmdletBinding()]
param(
    [string]$GamePath = '',
    [string]$BindAddress = '127.0.0.1',
    [ValidateRange(1024, 65535)][int]$Port = 24562
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GamePath)) {
    $GamePath = Join-Path $PSScriptRoot 'GAIA_Frontier.exe'
    if (-not (Test-Path -LiteralPath $GamePath)) {
        $GamePath = Join-Path $PSScriptRoot '../../build/GAIA_Frontier.exe'
    }
}
$executable = (Resolve-Path -LiteralPath $GamePath).Path
Start-Process -FilePath $executable -ArgumentList @('--headless', '--', '--dedicated', "--bind=$BindAddress", "--port=$Port") -WindowStyle Hidden -PassThru
