# Invoked by the fixed verify-permissions.ps1 entry point. Build a real duplicate
# environment block in this test process, then restore the original in finally.
# No registry/user/machine environment writes or environment values in output.
$ErrorActionPreference = 'Stop'
$fixtureProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not ('ProjectEnvironmentFixture' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class ProjectEnvironmentFixture {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr GetEnvironmentStringsW();
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool FreeEnvironmentStringsW(IntPtr block);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool SetEnvironmentStringsW(string block);
    public static string[] Read() {
        IntPtr block = GetEnvironmentStringsW();
        if (block == IntPtr.Zero) throw new Win32Exception();
        try {
            var entries = new List<string>();
            IntPtr cursor = block;
            while (Marshal.ReadInt16(cursor) != 0) {
                string entry = Marshal.PtrToStringUni(cursor);
                entries.Add(entry);
                cursor = IntPtr.Add(cursor, (entry.Length + 1) * 2);
            }
            return entries.ToArray();
        } finally { FreeEnvironmentStringsW(block); }
    }
    public static void Write(string[] entries) {
        if (!SetEnvironmentStringsW(string.Join("\0", entries) + "\0\0"))
            throw new Win32Exception();
    }
}
'@
}

$savedEntries = [ProjectEnvironmentFixture]::Read()
$savedVariables = [Environment]::GetEnvironmentVariables()
$savedPath = Get-ProcessPathState -Variables $savedVariables
if ($savedPath.Count -ne 1 -or [string]::IsNullOrEmpty($savedPath.Value)) {
    throw 'The native duplicate fixture requires one nonempty effective Path.'
}
$fixtureEntries = [Collections.Generic.List[string]]::new()
foreach ($entry in $savedEntries) {
    if ($entry.StartsWith('Path=', [StringComparison]::OrdinalIgnoreCase)) {
        $fixtureEntries.Add('Path=' + $savedPath.Value)
        $fixtureEntries.Add('PATH=' + $savedPath.Value)
    } else {
        $fixtureEntries.Add($entry)
    }
}
try {
    [ProjectEnvironmentFixture]::Write($fixtureEntries.ToArray())
    if ((Get-ProcessPathState -Variables ([Environment]::GetEnvironmentVariables())).Count -ne 2) {
        throw 'Native fixture did not create both Path and PATH.'
    }
    # Exercise the actual fixed wrapper under the duplicate environment, not
    # just the helper. Its import must normalize before launching Godot.
    $fixtureLog = Join-Path $fixtureProjectRoot '.godot\path-native-regression.log'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fixtureLog) | Out-Null
    & (Join-Path $fixtureProjectRoot 'tools\codex\run-godot.ps1') -Action version -LogFile $fixtureLog -TimeoutSeconds 20
    $repairedVariables = [Environment]::GetEnvironmentVariables()
    $repairedPath = Get-ProcessPathState -Variables $repairedVariables
    if ($repairedPath.Count -ne 1 -or $repairedPath.Value -cne $savedPath.Value) {
        throw 'Native duplicate repair changed the effective Path or retained duplicates.'
    }
    if ($savedVariables.Count -ne $repairedVariables.Count) {
        throw 'Native duplicate repair changed unrelated environment entries.'
    }
    foreach ($key in $savedVariables.Keys) {
        if ([string]$key -ieq 'Path') { continue }
        if (-not $repairedVariables.Contains($key) -or $savedVariables[$key] -cne $repairedVariables[$key]) {
            throw 'Native duplicate repair changed an unrelated environment entry.'
        }
    }
    Repair-ProcessPathCasing
} finally {
    [ProjectEnvironmentFixture]::Write($savedEntries)
}
if ([string]::Join([char]0, [ProjectEnvironmentFixture]::Read()) -cne [string]::Join([char]0, $savedEntries)) {
    throw 'Native fixture did not restore the original process environment.'
}
Write-Output 'PROCESS_PATH_NATIVE PASS (real duplicate repaired; Godot started; all values preserved; fixture restored)'
