$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

$serviceLogDir = "$root\weights_by_category\foodseg103\service_logs"
New-Item -ItemType Directory -Path $serviceLogDir -Force | Out-Null

# Keep TensorBoard alive; start only if port 6006 is not open.
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

$tbProc = $null
if (-not $portOpen) {
    $tbStdOut = "$serviceLogDir\tensorboard_stdout.log"
    $tbStdErr = "$serviceLogDir\tensorboard_stderr.log"
    $tbArgs = '-m tensorboard.main --logdir_spec foodseg103:weights_by_category/foodseg103,smoke:weights_by_category/smoke --port 6006 --host 0.0.0.0'
    $tbProc = Start-Process -FilePath $py -ArgumentList $tbArgs -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $tbStdOut -RedirectStandardError $tbStdErr -PassThru
}

# Avoid duplicate resume-C launch.
$existingResume = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'run_stage6s3_resume_c\.ps1' }
if ($existingResume) {
    Write-Output "Resume-C orchestrator already running: $($existingResume.ProcessId -join ', ')"
}
else {
    $s3StdOut = "$serviceLogDir\stage6s3_resume_c_stdout.log"
    $s3StdErr = "$serviceLogDir\stage6s3_resume_c_stderr.log"
    $s3Script = "$root\app\training\run_stage6s3_resume_c.ps1"
    $s3Args = "-ExecutionPolicy Bypass -File `"$s3Script`""
    $s3Proc = Start-Process -FilePath $psExe -ArgumentList $s3Args -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $s3StdOut -RedirectStandardError $s3StdErr -PassThru
    Write-Output "Started Resume-C orchestrator PID: $($s3Proc.Id)"
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

if ($tbProc) {
    Write-Output "Started TensorBoard PID: $($tbProc.Id)"
}
Write-Output "TensorBoardPort6006Open: $portOpen2"
Write-Output "ServiceLogs: $serviceLogDir"
