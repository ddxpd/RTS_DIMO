$ErrorActionPreference = 'Stop'
$target = 'D:\project\godot_project\rts_host_p2p_prototype\.git'
$backupPath = 'D:\project\godot_project\rts_host_p2p_prototype\agent_md\sandbox-git-owner-before-20260929.json'
$resultPath = 'D:\project\godot_project\rts_host_p2p_prototype\agent_md\sandbox-git-owner-result-20260929.json'
try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'An elevated Windows administrator token is required.' }
    $item = Get-Item -Force -LiteralPath $target
    if ($item.FullName -ne $target -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unexpected target; refusing ownership change.' }
    $backup = Get-Content -Raw -LiteralPath $backupPath | ConvertFrom-Json
    $before = Get-Acl -LiteralPath $target
    $beforeDacl = $before.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
    if ($backup.Path -ne $target -or $backup.Dacl -ne $beforeDacl) { throw 'Backup does not match current permissions; refusing change.' }
    & "$env:SystemRoot\System32\icacls.exe" $target /setowner 'DESKTOP-A69SF8I\happydog'
    if ($LASTEXITCODE -ne 0) { throw 'icacls ownership update failed.' }
    $after = Get-Acl -LiteralPath $target
    $afterDacl = $after.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
    if ($after.Owner -ne 'DESKTOP-A69SF8I\happydog') { throw 'Unexpected owner after repair.' }
    if ($beforeDacl -ne $afterDacl) { throw 'DACL unexpectedly changed.' }
    [pscustomobject]@{Status='PASS';Path=$target;BeforeOwner=$before.Owner;AfterOwner=$after.Owner;DaclUnchanged=$true;Recursive=$false;FinishedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 0
} catch {
    [pscustomobject]@{Status='FAIL';Error=$_.Exception.Message;FinishedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 1
}
