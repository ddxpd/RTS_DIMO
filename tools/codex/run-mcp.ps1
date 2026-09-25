[CmdletBinding()]
param(
    [ValidateSet('blender-http', 'blender-stdio', 'gallery', 'stop')]
    [string]$Action = 'blender-http',
    [ValidateRange(8000, 8999)]
    [int]$Port = 8766
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

$blenderMcp = 'D:\mysoftware\blender_mcp\mcp\.venv\Scripts\blender-mcp.exe'
$python = 'D:\mysoftware\blender_mcp\mcp\.venv\Scripts\python.exe'
$galleryScript = Join-Path $script:ProjectRoot 'tools\effect-gallery\server.py'

switch ($Action) {
    'blender-http' {
        if (-not (Test-Path -LiteralPath $blenderMcp -PathType Leaf)) {
            throw "Blender MCP launcher was not found: $blenderMcp"
        }
        [void](Start-TrackedProcess -FilePath $blenderMcp -ArgumentList @('--transport', 'http', '--host', '127.0.0.1', '--port', [string]$Port) -Label "Blender MCP HTTP $Port")
    }
    'blender-stdio' {
        if (-not (Test-Path -LiteralPath $blenderMcp -PathType Leaf)) {
            throw "Blender MCP launcher was not found: $blenderMcp"
        }
        # Keep stdin/stdout attached for the MCP protocol; Start-Process would
        # detach the stdio streams needed by a Codex MCP client.
        & $blenderMcp '--transport' 'stdio'
        if ($LASTEXITCODE -ne 0) { throw "Blender MCP stdio exited with code $LASTEXITCODE." }
    }
    'gallery' {
        if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
            throw "Project Python interpreter was not found: $python"
        }
        if (-not (Test-Path -LiteralPath $galleryScript -PathType Leaf)) {
            throw "Gallery server was not found: $galleryScript"
        }
        [void](Start-TrackedProcess -FilePath $python -ArgumentList @($galleryScript, '--bind', '127.0.0.1', '--port', [string]$Port, '--directory', (Join-Path $script:ProjectRoot 'tools\effect-gallery')) -Label "Effect gallery $Port")
    }
    'stop' {
        & (Join-Path $PSScriptRoot 'cleanup-project-processes.ps1') -StopTracked
    }
}
