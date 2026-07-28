Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pidDir = Join-Path $repoRoot ".runtime/pids"

function Stop-AgentPythonProcesses {
    $py = Get-CimInstance Win32_Process -Filter "Name='python.exe'"
    foreach ($proc in $py) {
        $cmd = [string]$proc.CommandLine
        $looksLikeNewManagedAgent = $cmd -like "*nutri-agent*" -and $cmd -like "*main.py*"
        $looksLikeLegacyManagedAgent = $cmd -eq '"G:\GraduationProj_Nutri-flow\envs\test\python.exe" main.py'
        if ($looksLikeNewManagedAgent -or $looksLikeLegacyManagedAgent) {
            Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction SilentlyContinue
            Write-Output "[stop] agent child PID=$($proc.ProcessId)"
        }
    }
}

function Stop-ListenerProcess {
    param([string]$Name, [int]$Port)

    try {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
            Select-Object -ExpandProperty OwningProcess -Unique
    } catch {
        return
    }

    foreach ($procId in $listeners) {
        try {
            Stop-Process -Id ([int]$procId) -Force -ErrorAction Stop
            Write-Output "[stop] $Name listener PID=$procId"
        } catch {
            Write-Output "[warn] $Name listener PID=$procId already stopped or inaccessible"
        }
    }
}

function Stop-ByPidFile {
    param([string]$Name)

    $pidFile = Join-Path $pidDir ("{0}.pid" -f $Name)
    if (-not (Test-Path $pidFile)) {
        Write-Output "[skip] $Name pid file not found"
        return
    }

    $raw = (Get-Content -Path $pidFile -Raw).Trim()
    $managedPid = 0
    if (-not [int]::TryParse($raw, [ref]$managedPid)) {
        Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
        Write-Output "[skip] $Name invalid pid file"
        return
    }

    try {
        Stop-Process -Id $managedPid -Force -ErrorAction Stop
        Write-Output "[stop] $Name PID=$managedPid"
    } catch {
        Write-Output "[warn] $Name PID=$managedPid already stopped or inaccessible"
    }

    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $pidDir)) {
    Write-Output "No managed pid directory found: $pidDir"
    exit 0
}

Stop-ByPidFile -Name "agent"
Stop-ByPidFile -Name "inference"
Stop-ByPidFile -Name "business"

Stop-AgentPythonProcesses
Stop-ListenerProcess -Name "inference" -Port 18001
Stop-ListenerProcess -Name "business" -Port 18080

Write-Output "Managed services stopped."
