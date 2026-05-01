param(
    [switch]$SkipDocker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot ".runtime"
$logDir = Join-Path $runtimeDir "logs"
$pidDir = Join-Path $runtimeDir "pids"
$supervisorDir = Join-Path $runtimeDir "supervisors"

$pythonExe = Join-Path $repoRoot "../envs/test/python.exe"
$mavenCmd = Join-Path $repoRoot ".tools/apache-maven-3.9.9/bin/mvn.cmd"
$checkpoint = Join-Path $repoRoot "nutri-ai-mcp/weights_by_category/foodseg103/stage7s1/stage7s1_tiny_img512_mask135_cls095_phaseA_12ep/best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth"

$pathsToCreate = @($runtimeDir, $logDir, $pidDir, $supervisorDir)
foreach ($p in $pathsToCreate) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

function Assert-PathExists {
    param([string]$PathValue, [string]$Name)
    if (-not (Test-Path $PathValue)) {
        throw "$Name not found: $PathValue"
    }
}

Assert-PathExists -PathValue $pythonExe -Name "Python"
Assert-PathExists -PathValue $mavenCmd -Name "Maven"
Assert-PathExists -PathValue $checkpoint -Name "Segmentation checkpoint"

function Get-PidFile {
    param([string]$Name)
    return Join-Path $pidDir ("{0}.pid" -f $Name)
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
    $pidFile = Get-PidFile -Name $Name
    Set-Content -Path $pidFile -Value $ProcessId
}

function Get-SupervisorScriptFile {
    param([string]$Name)
    return Join-Path $supervisorDir ("{0}.ps1" -f $Name)
}

function Get-PortListenerPid {
    param([int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        if ($conn -and $conn.Count -gt 0) {
            return [int]$conn[0].OwningProcess
        }
        return $null
    } catch {
        return $null
    }
}

function Stop-AgentPythonProcesses {
    $py = Get-CimInstance Win32_Process -Filter "Name='python.exe'"
    foreach ($proc in $py) {
        $cmd = [string]$proc.CommandLine
        if ($cmd -like "*nutri-agent*" -and $cmd -like "*main.py*") {
            Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-ManagedPowerShell {
    param(
        [string]$Name,
        [string]$WorkingDir,
        [string]$Command,
        [scriptblock]$HealthCheckScript
    )

    $existing = Read-ManagedPid -Name $Name
    if ($existing) {
        $healthy = $true
        if ($null -ne $HealthCheckScript) {
            try {
                $healthy = [bool](& $HealthCheckScript)
            } catch {
                $healthy = $false
            }
        }

        if ($healthy) {
            Write-Host "[skip] $Name already running (PID=$existing)"
            return $existing
        }

        Write-Output "[heal] $Name pid exists but health check failed, restarting"
        try {
            Stop-Process -Id $existing -Force -ErrorAction SilentlyContinue
        } catch {
        }
        Remove-Item -Path (Get-PidFile -Name $Name) -Force -ErrorAction SilentlyContinue
    }

    $stdout = Join-Path $logDir ("{0}.out.log" -f $Name)
    $stderr = Join-Path $logDir ("{0}.err.log" -f $Name)
    $scriptPath = Get-SupervisorScriptFile -Name $Name

    Set-Content -Path $scriptPath -Value $Command -Encoding UTF8
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath
    )

    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WorkingDirectory $WorkingDir -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    Write-ManagedPid -Name $Name -ProcessId $proc.Id
    Write-Host "[start] $Name PID=$($proc.Id)"
    return $proc.Id
}

function Wait-Http {
    param(
        [string]$Url,
        [int]$TimeoutSec = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-RestMethod -Uri $Url -TimeoutSec 5
            return $true
        } catch {
            Start-Sleep -Milliseconds 1200
        }
    }
    return $false
}

function Get-TaskQueueConsumers {
    $pair = "nutri_mq:nutri_mq_pass"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    $headers = @{ Authorization = "Basic $b64" }
    $q = Invoke-RestMethod -Uri "http://127.0.0.1:15672/api/queues/%2F/nutri.food.analysis.task" -Headers $headers -TimeoutSec 8
    return [int]$q.consumers
}

function Wait-QueueConsumer {
    param([int]$TimeoutSec = 45)

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $consumers = Get-TaskQueueConsumers
            if ($consumers -ge 1) {
                return $true
            }
        } catch {
        }
        Start-Sleep -Milliseconds 1200
    }
    return $false
}

function Test-QueueConsumerHealthy {
    try {
        return ((Get-TaskQueueConsumers) -ge 1)
    } catch {
        return $false
    }
}

if (-not $SkipDocker) {
    Write-Output "[infra] starting docker services"
    Push-Location $repoRoot
    try {
        docker compose up -d mysql redis rabbitmq minio chroma | Out-Null
    } finally {
        Pop-Location
    }
}

$inferenceCmd = @"
Set-Location '$repoRoot/nutri-ai-mcp'
`$env:NUTRI_SEG_CHECKPOINT = '$checkpoint'
`$env:NUTRI_SEG_INPUT_SIZE = '512'
while (`$true) {
    & '$pythonExe' -m uvicorn main:app --host 0.0.0.0 --port 8001
    `$exitCode = `$LASTEXITCODE
    Write-Output "[inference-supervisor] uvicorn exited with code=`$exitCode, restarting ..."
    Start-Sleep -Seconds 2
}
"@
if (Wait-Http -Url "http://127.0.0.1:8001/health" -TimeoutSec 2) {
    $managedInf = Read-ManagedPid -Name "inference"
    if ($managedInf) {
        Write-Host "[skip] inference already healthy on 8001"
    } else {
        Write-Output "[heal] inference is healthy but unmanaged; taking over supervision"
        $listener = Get-PortListenerPid -Port 8001
        if ($listener) {
            Stop-Process -Id $listener -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
        }
        $null = Start-ManagedPowerShell -Name "inference" -WorkingDir $repoRoot -Command $inferenceCmd -HealthCheckScript { Wait-Http -Url "http://127.0.0.1:8001/health" -TimeoutSec 2 }
    }
} else {
    $listener = Get-PortListenerPid -Port 8001
    if ($listener) {
        throw "Port 8001 is occupied by PID=$listener but inference health check failed"
    }
    $null = Start-ManagedPowerShell -Name "inference" -WorkingDir $repoRoot -Command $inferenceCmd -HealthCheckScript { Wait-Http -Url "http://127.0.0.1:8001/health" -TimeoutSec 2 }
}

$businessCmd = @"
Set-Location '$repoRoot/nutri-business'
while (`$true) {
    & '$mavenCmd' '-Dmaven.repo.local=$repoRoot/.tools/m2/repository' spring-boot:run
    `$exitCode = `$LASTEXITCODE
    Write-Output "[business-supervisor] spring-boot:run exited with code=`$exitCode, restarting ..."
    Start-Sleep -Seconds 2
}
"@
if (Wait-Http -Url "http://127.0.0.1:8080/api/v1/diet-logs?page=0&size=1&userId=1" -TimeoutSec 2) {
    $managedBiz = Read-ManagedPid -Name "business"
    if ($managedBiz) {
        Write-Host "[skip] business already healthy on 8080"
    } else {
        Write-Output "[heal] business is healthy but unmanaged; taking over supervision"
        $listener = Get-PortListenerPid -Port 8080
        if ($listener) {
            Stop-Process -Id $listener -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
        }
        $null = Start-ManagedPowerShell -Name "business" -WorkingDir $repoRoot -Command $businessCmd -HealthCheckScript { Wait-Http -Url "http://127.0.0.1:8080/api/v1/diet-logs?page=0&size=1&userId=1" -TimeoutSec 2 }
    }
} else {
    $listener = Get-PortListenerPid -Port 8080
    if ($listener) {
        throw "Port 8080 is occupied by PID=$listener but business endpoint is unhealthy"
    }
    $null = Start-ManagedPowerShell -Name "business" -WorkingDir $repoRoot -Command $businessCmd -HealthCheckScript { Wait-Http -Url "http://127.0.0.1:8080/api/v1/diet-logs?page=0&size=1&userId=1" -TimeoutSec 2 }
}

$agentCmd = @"
Set-Location '$repoRoot/nutri-agent'
`$env:NUTRI_MCP_SERVER_URL = 'http://127.0.0.1:8001'
`$env:NUTRI_BUSINESS_BASE_URL = 'http://127.0.0.1:8080/api/v1'
while (`$true) {
    & '$pythonExe' main.py
    `$exitCode = `$LASTEXITCODE
    Write-Output "[agent-supervisor] agent exited with code=`$exitCode, restarting ..."
    Start-Sleep -Seconds 2
}
"@
if (Test-QueueConsumerHealthy) {
    $managedAgent = Read-ManagedPid -Name "agent"
    if ($managedAgent) {
        Write-Host "[skip] agent consumer already healthy"
    } else {
        Write-Output "[heal] agent consumer is healthy but unmanaged; taking over supervision"
        Stop-AgentPythonProcesses
        Start-Sleep -Milliseconds 600
        $null = Start-ManagedPowerShell -Name "agent" -WorkingDir $repoRoot -Command $agentCmd -HealthCheckScript { Test-QueueConsumerHealthy }
    }
} else {
    $null = Start-ManagedPowerShell -Name "agent" -WorkingDir $repoRoot -Command $agentCmd -HealthCheckScript { Test-QueueConsumerHealthy }
}

Write-Output "[wait] checking service health"

if (-not (Wait-Http -Url "http://127.0.0.1:8001/health" -TimeoutSec 80)) {
    throw "Inference health check failed: http://127.0.0.1:8001/health"
}

if (-not (Wait-Http -Url "http://127.0.0.1:8080/api/v1/diet-logs?page=0&size=1&userId=1" -TimeoutSec 120)) {
    throw "Business health check failed: http://127.0.0.1:8080/api/v1/diet-logs"
}

if (-not (Wait-QueueConsumer -TimeoutSec 60)) {
    Write-Output "[heal] no RabbitMQ task consumer detected, restarting agent"
    $existingAgent = Read-ManagedPid -Name "agent"
    if ($existingAgent) {
        Stop-Process -Id $existingAgent -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Get-PidFile -Name "agent") -Force -ErrorAction SilentlyContinue
    }
    $null = Start-ManagedPowerShell -Name "agent" -WorkingDir $repoRoot -Command $agentCmd -HealthCheckScript { Test-QueueConsumerHealthy }

    if (-not (Wait-QueueConsumer -TimeoutSec 45)) {
        throw "RabbitMQ queue nutri.food.analysis.task still has 0 consumers after agent restart"
    }
}

Write-Output ""
Write-Output "Nutri-flow dev stack is ready"
Write-Output "- Inference : http://127.0.0.1:8001/health"
Write-Output "- Business  : http://127.0.0.1:8080/api/v1/diet-logs?page=0&size=1&userId=1"
Write-Output "- RabbitMQ  : http://127.0.0.1:15672  (nutri_mq / nutri_mq_pass)"
Write-Output "- Logs dir  : $logDir"
Write-Output ""
Write-Output "Run health check:"
Write-Output "  powershell -ExecutionPolicy Bypass -File scripts/dev-health.ps1"
exit 0
