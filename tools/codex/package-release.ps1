[CmdletBinding()]
param(
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$')]
    [string]$Version = 'v0.2.0-alpha.1'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
$executable = Resolve-ProjectPath -Path 'build\GAIA_Frontier.exe'
$license = Resolve-ProjectPath -Path 'build\releases\GODOT-LICENSES.txt'
$releaseRoot = Resolve-ProjectPath -Path ('build\releases\' + $Version) -AllowMissing
if (Test-Path -LiteralPath $releaseRoot) { throw "Release output exists; inspect before creating a replacement: $releaseRoot" }
$portable = Join-Path $releaseRoot ('GAIA-Frontier-' + $Version + '-Windows-x64')
[void][IO.Directory]::CreateDirectory($portable)
$releaseExe = Join-Path $releaseRoot 'GAIA_Frontier.exe'
Copy-Item -LiteralPath $executable -Destination $releaseExe
Copy-Item -LiteralPath $executable -Destination (Join-Path $portable 'GAIA_Frontier.exe')
Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'tools\server\start-exported-server.ps1') -Destination $portable
Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'tools\server\player-guide.txt') -Destination $portable
Copy-Item -LiteralPath $license -Destination $portable
$zip = $portable + '.zip'
Compress-Archive -LiteralPath $portable -DestinationPath $zip -CompressionLevel Optimal
$sums = @()
foreach ($file in @($releaseExe, $zip)) {
    $item = Get-Item -LiteralPath $file
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $sums += $hash + '  ' + $item.Name
    Write-Output ("RELEASE_ASSET {0} bytes={1} sha256={2}" -f $item.Name, $item.Length, $hash)
}
[IO.File]::WriteAllLines((Join-Path $releaseRoot 'SHA256SUMS.txt'), $sums, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText(($executable + '.sha256'), $sums[0] + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "RELEASE_PACKAGE_READY $releaseRoot"
