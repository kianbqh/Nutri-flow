$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'training_env.ps1')
$psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$serviceLogDir = "$root\weights_by_category\foodseg103\service_logs"
New-Item -ItemType Directory -Path $serviceLogDir -Force | Out-Null

# Keep TensorBoard available; start only when port 6006 is closed.
$portOpen = $false
try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect('127.0.0.1', 6006, $null, $null)
    $portOpen = $iar.AsyncWaitHandle.WaitOne(1000, $false) -and $client.Connected
    $client.Close()
}
catch {
    $portOpen = $false
}

if (-not $portOpen) {
    $tbStdOut = "$serviceLogDir\tensorboard_stdout.log"
    $tbStdErr = "$serviceLogDir\tensorboard_stderr.log"
    $tbArgs = '-m tensorboard.main --logdir_spec foodseg103:weights_by_category/foodseg103,smoke:weights_by_category/smoke --port 6006 --host 0.0.0.0'
    Start-Process -FilePath $py -ArgumentList $tbArgs -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $tbStdOut -RedirectStandardError $tbStdErr | Out-Null
}

$existing = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'run_stage7s1\.ps1' }
if ($existing) {
    Write-Output "Stage7S1 orchestrator already running: $($existing.ProcessId -join ', ')"
}
else {
    $s7StdOut = "$serviceLogDir\stage7s1_orchestrator_stdout.log"
    $s7StdErr = "$serviceLogDir\stage7s1_orchestrator_stderr.log"
    $s7Script = "$root\app\training\run_stage7s1.ps1"
    $s7Args = "-ExecutionPolicy Bypass -File `"$s7Script`""
    $proc = Start-Process -FilePath $psExe -ArgumentList $s7Args -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $s7StdOut -RedirectStandardError $s7StdErr -PassThru
    Write-Output "Started Stage7S1 orchestrator PID: $($proc.Id)"
}

Start-Sleep -Seconds 2
$portOpen2 = $false
try {
    $client2 = New-Object System.Net.Sockets.TcpClient
    $iar2 = $client2.BeginConnect('127.0.0.1', 6006, $null, $null)
    $portOpen2 = $iar2.AsyncWaitHandle.WaitOne(1000, $false) -and $client2.Connected
    $client2.Close()
}
catch {
    $portOpen2 = $false
}

Write-Output "TensorBoardPort6006Open: $portOpen2"
Write-Output "TensorBoardUrl: http://127.0.0.1:6006"
Write-Output "ServiceLogs: $serviceLogDir"