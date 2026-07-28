param(
    [int]$Port = 57717
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot ".runtime"
$logDir = Join-Path $runtimeDir "logs"
$pidDir = Join-Path $runtimeDir "pids"
$supervisorDir = Join-Path $runtimeDir "supervisors"
$mobileDir = Join-Path $repoRoot "nutri-mobile"
$flutterBat = Join-Path $repoRoot ".tools/flutter_sdk_3.41.6/flutter/bin/flutter.bat"

$pathsToCreate = @($runtimeDir, $logDir, $pidDir, $supervisorDir)
foreach ($pathValue in $pathsToCreate) {
    if (-not (Test-Path $pathValue)) {
        New-Item -ItemType Directory -Path $pathValue -Force | Out-Null
    }
}

function Repair-ProcessPathEnvironment {
    $envVars = [Environment]::GetEnvironmentVariables("Process")
    $pathKeys = @($envVars.Keys | Where-Object { [string]$_ -ieq "Path" })
    if ($pathKeys.Count -le 1) {
        return
    }

    $pathValue = [Environment]::GetEnvironmentVariable("Path", "Process")
    if ([string]::IsNullOrWhiteSpace($pathValue)) {
        $pathValue = [Environment]::GetEnvironmentVariable("PATH", "Process")
    }

    foreach ($key in $pathKeys) {
        [Environment]::SetEnvironmentVariable([string]$key, $null, "Process")
    }
    [Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
}

Repair-ProcessPathEnvironment

if (-not (Test-Path $flutterBat)) {
    throw "Flutter SDK not found: $flutterBat"
}

function Get-PidFile {
    param([string]$Name)
    return Join-Path $pidDir ("{0}.pid" -f $Name)
}

function Get-SupervisorScriptFile {
    param([string]$Name)
    return Join-Path $supervisorDir ("{0}.ps1" -f $Name)
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    try {
        $null = Get-Process -Id $ProcessId -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Read-ManagedPid {
    param([string]$Name)

    $pidFile = Get-PidFile -Name $Name
    if (-not (Test-Path $pidFile)) {
        return $null
    }

    $raw = (Get-Content -Path $pidFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    $managedPid = 0
    if (-not [int]::TryParse($raw, [ref]$managedPid)) {
        return $null
    }

    if (Test-ProcessAlive -ProcessId $managedPid) {
        return $managedPid
    }

    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Write-ManagedPid {
    param([string]$Name, [int]$ProcessId)
    Set-Content -Path (Get-PidFile -Name $Name) -Value $ProcessId
}

function Test-PortListening {
    param([int]$PortNumber)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect("127.0.0.1", $PortNumber, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        if (-not $ok) {
            $tcp.Close()
            return $false
        }
        $tcp.EndConnect($iar)
        $tcp.Close()
        return $true
    } catch {
        return $false
    }
}

function Wait-PortListening {
    param(
        [int]$PortNumber,
        [int]$TimeoutSec = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortListening -PortNumber $PortNumber) {
            return $true
        }
        Start-Sleep -Milliseconds 1200
    }
    return $false
}

function Get-PortProcessInfo {
    param([int]$PortNumber)

    try {
        $listener = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction Stop |
            Select-Object -First 1
    } catch {
        return $null
    }

    if ($null -eq $listener) {
        return $null
    }

    try {
        return Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$listener.OwningProcess)
    } catch {
        return $null
    }
}

$name = "frontend-web"
$existingPid = Read-ManagedPid -Name $name
if ($existingPid -and (Test-PortListening -PortNumber $Port)) {
    Write-Host "[skip] frontend-web already running (PID=$existingPid, http://127.0.0.1:$Port)"
    exit 0
}

if ($existingPid) {
    try {
        Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
    } catch {
    }
    Remove-Item -Path (Get-PidFile -Name $name) -Force -ErrorAction SilentlyContinue
}

$portProc = Get-PortProcessInfo -PortNumber $Port
if ($null -ne $portProc) {
    $cmdLine = [string]$portProc.CommandLine
    $looksLikeManagedFlutter = $cmdLine -like "*flutter*" -or $cmdLine -like "*dart*" -or $cmdLine -like "*$repoRoot*"
    if (-not $looksLikeManagedFlutter) {
        throw "Port $Port is occupied by an unmanaged process: PID=$($portProc.ProcessId) CMD=$cmdLine"
    }
    Stop-Process -Id ([int]$portProc.ProcessId) -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}

$stdout = Join-Path $logDir "frontend-web.out.log"
$stderr = Join-Path $logDir "frontend-web.err.log"
$scriptPath = Get-SupervisorScriptFile -Name $name

$command = @"
Set-Location '$mobileDir'
`$env:PATH = '$repoRoot/.tools/flutter_sdk_3.41.6/flutter/bin;' + `$env:PATH
while (`$true) {
    & '$flutterBat' run -d web-server --release --web-hostname 127.0.0.1 --web-port $Port
    `$exitCode = `$LASTEXITCODE
    Write-Output "[frontend-web-supervisor] flutter run exited with code=`$exitCode, restarting ..."
    Start-Sleep -Seconds 2
}
"@

Set-Content -Path $scriptPath -Value $command -Encoding UTF8
$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
)

$proc = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WorkingDirectory $repoRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
Write-ManagedPid -Name $name -ProcessId $proc.Id
Write-Host "[start] frontend-web PID=$($proc.Id)"

if (-not (Wait-PortListening -PortNumber $Port -TimeoutSec 90)) {
    throw "Frontend web server failed to listen on http://127.0.0.1:$Port"
}

Write-Host "[ready] frontend-web http://127.0.0.1:$Port"
Write-Host "[logs] $stdout"
