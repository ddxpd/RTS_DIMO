[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$GodotPath,
    [string]$BlenderPath,
    [string]$BlenderMcpPath,
    [string[]]$SearchRoot = @(),
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

# Discovery inspects filenames only. It never executes an unregistered candidate.
$previous = Read-ToolchainConfig -AllowMissing -AllowMoved
$next = [ordered]@{
    SchemaVersion = 1
    ProjectRoot = $script:ProjectRoot
    GodotPath = $null
    BlenderPath = $null
    BlenderMcpPath = $null
}
$explicit = @{ Godot = $GodotPath; Blender = $BlenderPath; BlenderMcp = $BlenderMcpPath }
foreach ($tool in @('Godot', 'Blender', 'BlenderMcp')) {
    $field = $tool + 'Path'
    $saved = if ($previous) { [string]$previous.$field } else { '' }
    $next[$field] = Find-LocalTool -Tool $tool -ExplicitPath $explicit[$tool] -ExistingPath $saved -SearchRoot $SearchRoot
    if (-not $next[$field]) { Write-Warning "$tool not found. Supply -$field to register it." }
}
if (-not $next.GodotPath) { throw 'Godot is required. Supply -GodotPath or -SearchRoot; no files were written.' }

$configText = ($next | ConvertTo-Json -Depth 4) + [Environment]::NewLine
$rulesText = Get-LocalRulesText
$changes = @(
    @{ Path = $script:ToolchainConfigPath; Text = $configText },
    @{ Path = $script:LocalRulesPath; Text = $rulesText }
)
foreach ($change in $changes) {
    $old = if (Test-Path -LiteralPath $change.Path -PathType Leaf) { [IO.File]::ReadAllText($change.Path) } else { '' }
    $change['Changed'] = $old -cne $change.Text
    if ($change.Changed) {
        Write-Output ('CHANGE ' + $change.Path)
        $beforeLines = if ($old) { @($old -split '\r?\n') } else { @('') }
        Compare-Object -ReferenceObject $beforeLines -DifferenceObject @($change.Text -split '\r?\n') |
            ForEach-Object { Write-Output ($_.SideIndicator + ' ' + $_.InputObject) }
    } else {
        Write-Output ('UNCHANGED ' + $change.Path)
    }
}
if ($CheckOnly) {
    Write-Output 'CHECK_ONLY: no files written or tools launched.'
    return
}

# Never silently overwrite user-authored rules, even in our generated filename.
if (Test-Path -LiteralPath $script:LocalRulesPath -PathType Leaf) {
    $oldRules = [IO.File]::ReadAllText($script:LocalRulesPath).Replace([string][char]13, '').TrimEnd()
    $previousRoot = if ($previous) { [string]$previous.ProjectRoot } else { $script:ProjectRoot }
    $managedRules = (Get-LocalRulesText -ProjectRoot $previousRoot).Replace([string][char]13, '').TrimEnd()
    if ($oldRules -cne $managedRules) {
        throw 'local-toolchain.rules contains unmanaged edits. Preserve them in a separate custom rules file before regenerating.'
    }
}
foreach ($relative in @('.codex', '.codex\rules', '.codex\toolchain.local.json', '.codex\rules\local-toolchain.rules')) {
    $candidate = Join-Path $script:ProjectRoot $relative
    if (Test-Path -LiteralPath $candidate) {
        if ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to write through a reparse point: $candidate"
        }
    }
}
if (@($changes | Where-Object { $_.Changed }).Count -eq 0) {
    Write-Output 'LOCAL_TOOLCHAIN_UNCHANGED'
    return
}
if ($PSCmdlet.ShouldProcess($script:ProjectRoot, 'Register tools and generate nine exact local command rules')) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:LocalRulesPath))
    foreach ($change in $changes) {
        if ($change.Changed) {
            [IO.File]::WriteAllText($change.Path, $change.Text, [Text.UTF8Encoding]::new($false))
        }
    }
    Write-Output 'LOCAL_TOOLCHAIN_READY: restart Codex to load rules in this trusted project.'
}
