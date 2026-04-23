$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$serviceLogDir = "$root\weights_by_category\foodseg103\service_logs"
New-Item -ItemType Directory -Path $serviceLogDir -Force | Out-Null

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

$existing = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'run_stage6s6_resume\.ps1' }
if ($existing) {
    Write-Output "Stage6S6 resume orchestrator already running: $($existing.ProcessId -join ', ')"
}
else {
    $s6StdOut = "$serviceLogDir\stage6s6_resume_orchestrator_stdout.log"
    $s6StdErr = "$serviceLogDir\stage6s6_resume_orchestrator_stderr.log"
    $s6Script = "$root\app\training\run_stage6s6_resume.ps1"
    $s6Args = "-ExecutionPolicy Bypass -File `"$s6Script`""
    $proc = Start-Process -FilePath $psExe -ArgumentList $s6Args -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $s6StdOut -RedirectStandardError $s6StdErr -PassThru
    Write-Output "Started Stage6S6 resume orchestrator PID: $($proc.Id)"
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
Write-Output "ServiceLogs: $serviceLogDir"