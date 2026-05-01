param(
    [int]$Port = 57717
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pidDir = Join-Path $repoRoot ".runtime/pids"

function Get-PidFile {
    param([string]$Name)
    return Join-Path $pidDir ("{0}.pid" -f $Name)
}

function Stop-ByPidFile {
    param([string]$Name)

    $pidFile = Get-PidFile -Name $Name
    if (-not (Test-Path $pidFile)) {
        return
    }

    $raw = (Get-Content -Path $pidFile -Raw).Trim()
    $managedPid = 0
    if ([int]::TryParse($raw, [ref]$managedPid)) {
        try {
            Stop-Process -Id $managedPid -Force -ErrorAction Stop
            Write-Output "[stop] $Name PID=$managedPid"
        } catch {
            Write-Output "[warn] $Name PID=$managedPid already stopped or inaccessible"
        }
    }

    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}

function Stop-PortListener {
    param([int]$PortNumber)
    try {
        $listeners = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction Stop |
            Select-Object -ExpandProperty OwningProcess -Unique
    } catch {
        return
    }

    foreach ($pidValue in $listeners) {
        try {
            Stop-Process -Id ([int]$pidValue) -Force -ErrorAction Stop
            Write-Output "[stop] frontend-web listener PID=$pidValue"
        } catch {
            Write-Output "[warn] frontend-web listener PID=$pidValue already stopped or inaccessible"
        }
    }
}

function Stop-FrontendFlutterProcesses {
    $procs = Get-CimInstance Win32_Process
    foreach ($proc in $procs) {
        $cmd = [string]$proc.CommandLine
        if ($cmd -like '*flutter run -d web-server*' -or $cmd -like '*flutter.bat" run -d web-server*' -or ($cmd -like "*$repoRoot*" -and $cmd -like '*dart-sdk*')) {
            Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not (Test-Path $pidDir)) {
    Write-Output "No managed pid directory found: $pidDir"
    exit 0
}

Stop-ByPidFile -Name "frontend-web"
Stop-PortListener -PortNumber $Port
Stop-FrontendFlutterProcesses
Write-Output "Frontend web instance stopped."
