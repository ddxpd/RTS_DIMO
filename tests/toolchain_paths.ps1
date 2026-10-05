# Invoked through verify-permissions.ps1 / Light Tooling. Fixtures never launch fake tools.
$ErrorActionPreference = 'Stop'
$realRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixtureRoot = Join-Path $realRoot ('.godot\toolchain-tests\' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$fixtureName = 'workspace ' + [char]0x6D4B + [char]0x8BD5
$firstRoot = Join-Path $fixtureRoot $fixtureName
$secondRoot = Join-Path $fixtureRoot 'relocated workspace'
$fakeTools = Join-Path $fixtureRoot 'installed tools'
[void][IO.Directory]::CreateDirectory($fakeTools)
$fakeGodot = Join-Path $fakeTools 'Godot_fixture_console.exe'
$fakeGui = Join-Path $fakeTools 'Godot_fixture.exe'
$fakeBlender = Join-Path $fakeTools 'blender.exe'
$fakeMcp = Join-Path $fakeTools 'blender-mcp.exe'
foreach ($file in @($fakeGodot, $fakeGui, $fakeBlender, $fakeMcp)) { [IO.File]::WriteAllBytes($file, [byte[]]@(0)) }

function Assert-ToolchainTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "TOOLCHAIN_TEST_FAILED: $Message" }
}

function Assert-ToolchainThrows {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -like $Pattern) { return }
        throw
    }
    throw "TOOLCHAIN_TEST_FAILED: expected error $Pattern"
}

foreach ($root in @($firstRoot, $secondRoot)) {
    $destination = Join-Path $root 'tools\codex'
    [void][IO.Directory]::CreateDirectory($destination)
    foreach ($name in @('project-common.ps1', 'toolchain.ps1', 'setup-local.ps1')) {
        Copy-Item -LiteralPath (Join-Path $realRoot ('tools\codex\' + $name)) -Destination $destination
    }
}
$firstSetup = Join-Path $firstRoot 'tools\codex\setup-local.ps1'
$secondSetup = Join-Path $secondRoot 'tools\codex\setup-local.ps1'
$setupArgs = @('-GodotPath', $fakeGodot, '-BlenderPath', $fakeBlender, '-BlenderMcpPath', $fakeMcp)
$checkOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $firstSetup @setupArgs -CheckOnly
Assert-ToolchainTest ($LASTEXITCODE -eq 0) 'CheckOnly succeeded'
Assert-ToolchainTest (-not (Test-Path -LiteralPath (Join-Path $firstRoot '.codex'))) 'CheckOnly does not create config directories'

$setupOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $firstSetup @setupArgs
Assert-ToolchainTest ($LASTEXITCODE -eq 0) 'Initial setup succeeded'
$configFile = Join-Path $firstRoot '.codex\toolchain.local.json'
$rulesFile = Join-Path $firstRoot '.codex\rules\local-toolchain.rules'
$beforeConfig = Get-Item -LiteralPath $configFile
$beforeRules = Get-Item -LiteralPath $rulesFile
$repeatOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $firstSetup
Assert-ToolchainTest ($LASTEXITCODE -eq 0 -and $repeatOutput -contains 'LOCAL_TOOLCHAIN_UNCHANGED') 'Idempotent initialization'
Assert-ToolchainTest ((Get-Item -LiteralPath $configFile).LastWriteTimeUtc -eq $beforeConfig.LastWriteTimeUtc) 'Configuration timestamp unchanged'
Assert-ToolchainTest ((Get-Item -LiteralPath $rulesFile).LastWriteTimeUtc -eq $beforeRules.LastWriteTimeUtc) 'Rules timestamp unchanged'

# Work only in this script scope; calling validation retains its real root and helpers.
. (Join-Path $firstRoot 'tools\codex\project-common.ps1')
$firstLedger = $script:RuntimeDirectory
Assert-ToolchainTest ((Get-TrustedGodotPath) -eq $fakeGodot) 'Registered executable resolves in a Unicode/spaced workspace'
Assert-ToolchainThrows { Get-TrustedGodotPath -RequestedPath $fakeGui } '*not registered*'
Assert-ToolchainTest ((Select-ToolCandidate -Tool Godot -Candidates @($fakeGui, $fakeGodot)) -eq $fakeGodot) 'Console companion wins'
$otherGodot = Join-Path $fakeTools 'Godot_other_console.exe'
[IO.File]::WriteAllBytes($otherGodot, [byte[]]@(0))
Assert-ToolchainThrows { Select-ToolCandidate -Tool Godot -Candidates @($fakeGodot, $otherGodot) } '*Multiple Godot*'
Assert-ToolchainTest (@(Find-ToolsInDirectories -Tool Godot -Roots @($fakeTools) -Depth 0).Count -eq 3) 'Bounded directory discovery'
Assert-ToolchainTest ((Find-LocalTool -Tool Godot -ExplicitPath $otherGodot -ExistingPath $fakeGodot) -eq $otherGodot) 'Explicit selection overrides saved path'
Assert-ToolchainTest ((Find-LocalTool -Tool Godot -ExistingPath $fakeGodot) -eq $fakeGodot) 'Saved selection remains pinned'
$pathOnlyRoot = Join-Path $fixtureRoot 'path only'
[void][IO.Directory]::CreateDirectory($pathOnlyRoot)
$pathOnlyGodot = Join-Path $pathOnlyRoot 'Godot_path_console.exe'
[IO.File]::WriteAllBytes($pathOnlyGodot, [byte[]]@(0))
$originalPath = $env:Path
try {
    $env:Path = $pathOnlyRoot
    Assert-ToolchainTest ((Find-LocalTool -Tool Godot) -eq $pathOnlyGodot) 'PATH discovery'
    Assert-ToolchainTest ((Find-LocalTool -Tool Godot -ExistingPath $fakeGodot) -eq $fakeGodot) 'Saved path wins over PATH'
    Assert-ToolchainTest ((Find-LocalTool -Tool Godot -ExistingPath (Join-Path $fakeTools 'Godot_gone.exe')) -eq $pathOnlyGodot) 'Initialization rediscovers stale installation'
} finally { $env:Path = $originalPath }
Assert-ToolchainThrows { Resolve-ToolExecutable -Tool Godot -Path 'Godot.exe' } '*must be absolute*'
Assert-ToolchainThrows { Resolve-ToolExecutable -Tool Godot -Path (Join-Path $fakeTools 'missing.exe') } '*missing or invalid*'

$testConfig = Get-Content -Raw -LiteralPath $configFile -Encoding UTF8 | ConvertFrom-Json
$testConfig.BlenderPath = $null
[IO.File]::WriteAllText($configFile, ($testConfig | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Assert-ToolchainThrows { Get-TrustedBlenderPath } '*not configured*'
$testConfig.GodotPath = Join-Path $fakeTools 'Godot_missing.exe'
[IO.File]::WriteAllText($configFile, ($testConfig | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Assert-ToolchainThrows { Get-TrustedGodotPath } '*missing or invalid*'
$testConfig.GodotPath = $fakeGodot
$testConfig.BlenderPath = $fakeBlender
[IO.File]::WriteAllText($configFile, ($testConfig | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Assert-LocalRulesCurrent

$secondConfigDir = Join-Path $secondRoot '.codex\rules'
[void][IO.Directory]::CreateDirectory($secondConfigDir)
Copy-Item -LiteralPath $configFile -Destination (Join-Path $secondRoot '.codex\toolchain.local.json')
Copy-Item -LiteralPath $rulesFile -Destination $secondConfigDir
. (Join-Path $secondRoot 'tools\codex\project-common.ps1')
Assert-ToolchainTest ($script:RuntimeDirectory -ne $firstLedger) 'Separate checkout process ledgers'
Assert-ToolchainThrows { Get-TrustedGodotPath } '*project has moved*'
Assert-ToolchainThrows { Assert-LocalRulesCurrent } '*stale or modified*'
$movedOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $secondSetup
Assert-ToolchainTest ($LASTEXITCODE -eq 0) 'Relocated checkout can regenerate configuration'
Assert-LocalRulesCurrent
Assert-ToolchainTest ((Get-TrustedGodotPath) -eq $fakeGodot) 'Tool resolution after relocation'
$relocatedRules = [IO.File]::ReadAllText($script:LocalRulesPath)
Assert-ToolchainTest (-not $relocatedRules.Contains(($firstRoot | ConvertTo-Json -Compress))) 'Old workspace absent from generated rules'

# Generation must safely quote even paths on another drive; no drive is accessed.
$alternateRoot = 'Z:\portable workspace'
$alternateRules = Get-LocalRulesText -ProjectRoot $alternateRoot
Assert-ToolchainTest ($alternateRules.Contains(([IO.Path]::Combine($alternateRoot, 'tools\codex\run-godot.ps1') | ConvertTo-Json -Compress))) 'Other-drive rule generation'
Assert-ToolchainTest (@(Get-ToolWrapperNames).Count -eq 9) 'Exactly nine approved wrappers'
Assert-ToolchainTest ((Get-ToolWrapperNames) -notcontains 'setup-local.ps1') 'Setup has no self-approval rule'
[IO.File]::AppendAllText($script:LocalRulesPath, '# custom edit')
Assert-ToolchainThrows { Assert-LocalRulesCurrent } '*stale or modified*'

# Prove setup refuses to replace user modifications in the managed filename.
$customHash = (Get-FileHash -LiteralPath $script:LocalRulesPath).Hash
$priorErrorPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $refusal = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $secondSetup 2>&1
    $refusalCode = $LASTEXITCODE
} finally { $ErrorActionPreference = $priorErrorPreference }
Assert-ToolchainTest ($refusalCode -ne 0) 'Custom rules are not overwritten'
Assert-ToolchainTest ((Get-FileHash -LiteralPath $script:LocalRulesPath).Hash -eq $customHash) 'Custom rules preserved exactly'
Write-Output 'TOOLCHAIN_PATHS PASS (discovery, registration, optional/missing tools, Unicode/spaces, relocation, idempotency, rules and ledger isolation)'
