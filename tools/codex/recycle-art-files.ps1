[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$recycleRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Add-Type -Path (Join-Path $PSScriptRoot 'recycle-files.cs')
$recycleRequest = [Console]::In.ReadToEnd() | ConvertFrom-Json
$recycleResults = @()
foreach ($entry in @($recycleRequest.files)) {
    try {
        $target = [IO.Path]::GetFullPath([string]$entry.path)
        $relative = $target.Substring($recycleRoot.Length).TrimStart('\').Replace('\', '/')
        if (-not $target.StartsWith($recycleRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            ($relative -notlike 'assets/concept_art/*' -and $relative -notlike '.local/art-library/imports/*' -and $relative -notlike '.local/art-library-test-*/*')) { throw 'File is outside the allowed art/test roots.' }
        $item = Get-Item -LiteralPath $target -Force
        if ($item.PSIsContainer) { throw 'Only individual files may be recycled.' }
        $ancestor = $item
        while ($ancestor -and $ancestor.FullName -ne $recycleRoot) {
            if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed.' }
            $ancestor = if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
        }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne [string]$entry.sha256) { throw 'File content changed after confirmation.' }
        [ArtLibraryRecycle.Native]::Recycle($target)
        if (Test-Path -LiteralPath $target) { throw 'File is still present after recycle operation.' }
        $recycleResults += @{ id = $entry.id; success = $true }
    } catch { $recycleResults += @{ id = $entry.id; success = $false; error = $_.Exception.Message } }
}
@{ results = @($recycleResults) } | ConvertTo-Json -Depth 5 -Compress
