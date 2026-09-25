[CmdletBinding()]
param(
    [switch]$StopTracked,
    [switch]$StopUntracked,
    [switch]$ReportOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-common.ps1')

if ($ReportOnly) {
    $StopTracked = $false
    $StopUntracked = $false
}

if ($StopTracked) {
    foreach ($entry in @(Read-TrackedProcesses)) {
        Stop-TrackedProcess -ProcessId ([int]$entry.ProcessId)
    }
    Write-TrackedProcesses -Processes @()
}

$projectMarker = $script:ProjectRoot.TrimEnd('\')
$trustedServiceMarkers = @(
    'D:\mysoftware\blender_mcp\mcp\.venv\Scripts\blender-mcp.exe',
    'D:\mysoftware\blender_mcp\mcp\.venv\Scripts\python.exe'
)
$processNames = @('Godot*.exe', 'blender.exe', 'blender-launcher.exe', 'blender-mcp.exe', 'python.exe', 'pythonw.exe')

function Get-RelevantProcessState {
    $projectProcesses = @()
    $sharedProcesses = @()
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $nameMatch = $false
        foreach ($pattern in $processNames) {
            if ($process.Name -like $pattern) { $nameMatch = $true; break }
        }
        if (-not $nameMatch) { continue }

        $commandLine = [string]$process.CommandLine
        if ($commandLine.IndexOf($projectMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $projectProcesses += $process
            continue
        }
        foreach ($marker in $trustedServiceMarkers) {
            if ($commandLine.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $sharedProcesses += $process
                break
            }
        }
    }
    return [pscustomobject]@{
        Project = @($projectProcesses)
        Shared  = @($sharedProcesses)
    }
}

$state = Get-RelevantProcessState

if ($StopUntracked) {
    foreach ($process in $state.Project) {
        try {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
            Write-Output "Stopped project process PID $($process.ProcessId): $($process.Name)"
        } catch {
            Write-Warning "Could not stop PID $($process.ProcessId): $($_.Exception.Message)"
        }
    }
    Start-Sleep -Milliseconds 200
    $state = Get-RelevantProcessState
}

$ports = @(24560, 8765, 8766)
$listeners = @()
foreach ($port in $ports) {
    $listeners += @(Get-NetTCPConnection -State Listen -LocalAddress 127.0.0.1 -LocalPort $port -ErrorAction SilentlyContinue)
    $listeners += @(Get-NetUDPEndpoint -LocalAddress 127.0.0.1 -LocalPort $port -ErrorAction SilentlyContinue)
}

if ($state.Project.Count -eq 0) {
    Write-Output 'PROJECT_PROCESSES none'
} else {
    Write-Output 'PROJECT_PROCESSES'
    $state.Project | Select-Object ProcessId, Name, CommandLine | Format-List
}

if ($state.Shared.Count -gt 0) {
    Write-Output 'SHARED_TOOL_PROCESSES (reported, not stopped)'
    $state.Shared | Select-Object ProcessId, Name, CommandLine | Format-List
}

if ($listeners.Count -eq 0) {
    Write-Output 'PROJECT_PORTS none (checked 24560, 8765, 8766)'
} else {
    Write-Output 'PROJECT_PORTS'
    $listeners | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize
}

if ($StopUntracked -and ($state.Project.Count -gt 0 -or $listeners.Count -gt 0)) {
    throw 'Project processes or ports remain after cleanup.'
}
