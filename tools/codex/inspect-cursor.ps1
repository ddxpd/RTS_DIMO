[CmdletBinding()]
param([ValidateRange(1, 60)][int]$DurationSeconds = 40)

# Read-only Win32 cursor inspection for tests/cursor_preview.gd. Does not send input.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class ProjectCursorProbe {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO {
        public int cbSize, flags; public IntPtr handle; public POINT position;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ICONINFO {
        [MarshalAs(UnmanagedType.Bool)] public bool icon;
        public uint xHotspot, yHotspot; public IntPtr mask, color;
    }
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO info);
    [DllImport("user32.dll")] public static extern bool GetIconInfo(IntPtr cursor, out ICONINFO info);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    public static int[] Capture(string filename) {
        // Opt this diagnostic thread into physical pixels, matching the Godot window.
        var previousDpi = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try { return CapturePhysical(filename); }
        finally { if (previousDpi != IntPtr.Zero) SetThreadDpiAwarenessContext(previousDpi); }
    }
    private static int[] CapturePhysical(string filename) {
        var info = new CURSORINFO(); info.cbSize = Marshal.SizeOf(info);
        if (!GetCursorInfo(ref info) || (info.flags & 1) == 0) throw new Exception("Cursor is not visible");
        ICONINFO icon;
        if (!GetIconInfo(info.handle, out icon)) throw new Exception("Cannot inspect cursor");
        try {
            using (var borrowed = Icon.FromHandle(info.handle))
            using (var bitmap = borrowed.ToBitmap()) {
                bitmap.Save(filename, System.Drawing.Imaging.ImageFormat.Png);
                uint foregroundPid;
                GetWindowThreadProcessId(GetForegroundWindow(), out foregroundPid);
                return new int[] { bitmap.Width, bitmap.Height, (int)icon.xHotspot, (int)icon.yHotspot, (int)foregroundPid };
            }
        } finally {
            if (icon.mask != IntPtr.Zero) DeleteObject(icon.mask);
            if (icon.color != IntPtr.Zero) DeleteObject(icon.color);
        }
    }
}
'@
$probePath = Join-Path $script:ProjectRoot '.godot\cursor-probe.json'
$outputDirectory = Join-Path $script:ProjectRoot '.godot\cursor-native'
[void][IO.Directory]::CreateDirectory($outputDirectory)
$results = @{}
$watch = [Diagnostics.Stopwatch]::StartNew()
while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds -and $results.Count -lt 5) {
    Start-Sleep -Milliseconds 100
    if (-not (Test-Path -LiteralPath $probePath)) { continue }
    try { $sample = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json } catch { continue }
    if ($null -eq $sample -or $sample.state -notin @('default', 'select', 'move', 'attack', 'blocked')) { continue }
    if ($results.ContainsKey($sample.state)) { continue }
    $process = Get-Process -Id $sample.pid -ErrorAction SilentlyContinue
    if ($null -eq $process -or $process.ProcessName -notlike 'Godot*') { continue }
    $path = Join-Path $outputDirectory ($sample.state + '.png')
    try { $actual = [ProjectCursorProbe]::Capture($path) } catch { continue }
    if ($actual[4] -ne $sample.pid) { continue }
    if ($actual[0] -ne 40 -or $actual[1] -ne 40 -or $actual[2] -ne $sample.hotspot_x -or $actual[3] -ne $sample.hotspot_y) {
        throw "Native cursor differs for $($sample.state): $($actual -join ',')"
    }
    $results[$sample.state] = $actual
    Write-Output "NATIVE_CURSOR_PASS $($sample.state) size=$($actual[0])x$($actual[1]) hotspot=$($actual[2]),$($actual[3])"
}
if ($results.Count -ne 5) { throw "Only $($results.Count)/5 cursor states captured. Run with the rendered cursor preview in foreground." }
