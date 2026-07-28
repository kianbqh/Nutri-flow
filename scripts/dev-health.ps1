param(
    [string]$QueueName = "nutri.food.analysis.task"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$inferencePort = 18001
$businessPort = 18080

function Test-PortListening {
    param([int]$Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
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

function Test-HttpJson {
    param(
        [string]$Url,
        [int]$TimeoutSec = 5
    )
    try {
        $resp = Invoke-RestMethod -Uri $Url -TimeoutSec $TimeoutSec
        return @{ ok = $true; body = $resp }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Get-RabbitQueueState {
    param([string]$Queue)

    $pair = "nutri_mq:nutri_mq_pass"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    $headers = @{ Authorization = "Basic $b64" }

    try {
        $q = Invoke-RestMethod -Uri ("http://127.0.0.1:15672/api/queues/%2F/{0}" -f $Queue) -Headers $headers -TimeoutSec 8
        return @{
            ok = $true
            consumers = [int]$q.consumers
            messages = [int]$q.messages
            ready = [int]$q.messages_ready
            unacked = [int]$q.messages_unacknowledged
            state = [string]$q.state
        }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

$rows = @()

$pid8001 = Test-PortListening -Port $inferencePort
$rows += [pscustomobject]@{
    Check = "Port $inferencePort (inference)"
    Status = if ($pid8001) { "OK" } else { "DOWN" }
    Detail = if ($pid8001) { "TCP connect success" } else { "No listener" }
}

$pid8080 = Test-PortListening -Port $businessPort
$rows += [pscustomobject]@{
    Check = "Port $businessPort (business)"
    Status = if ($pid8080) { "OK" } else { "DOWN" }
    Detail = if ($pid8080) { "TCP connect success" } else { "No listener" }
}

$healthInf = Test-HttpJson -Url "http://127.0.0.1:$inferencePort/health"
$rows += [pscustomobject]@{
    Check = "GET /health"
    Status = if ($healthInf.ok) { "OK" } else { "FAIL" }
    Detail = if ($healthInf.ok) { "inference reachable" } else { $healthInf.error }
}

$healthBiz = Test-HttpJson -Url "http://127.0.0.1:$businessPort/api/v1/diet-logs?page=0&size=1&userId=1"
$rows += [pscustomobject]@{
    Check = "GET /api/v1/diet-logs"
    Status = if ($healthBiz.ok) { "OK" } else { "FAIL" }
    Detail = if ($healthBiz.ok) { "business reachable" } else { $healthBiz.error }
}

$qState = Get-RabbitQueueState -Queue $QueueName
if ($qState.ok) {
    $consumerOk = $qState.consumers -ge 1
    $rows += [pscustomobject]@{
        Check = "RabbitMQ task consumer"
        Status = if ($consumerOk) { "OK" } else { "FAIL" }
        Detail = "consumers=$($qState.consumers), messages=$($qState.messages), ready=$($qState.ready), unacked=$($qState.unacked)"
    }
} else {
    $rows += [pscustomobject]@{
        Check = "RabbitMQ task consumer"
        Status = "FAIL"
        Detail = $qState.error
    }
}

$rows | Format-Table -AutoSize | Out-String | Write-Output

$hasFailure = $rows | Where-Object { $_.Status -ne "OK" }
if ($hasFailure) {
    exit 1
}

exit 0
