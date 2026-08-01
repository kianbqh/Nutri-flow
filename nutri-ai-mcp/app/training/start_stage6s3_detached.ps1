$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'training_env.ps1')
$psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

$serviceLogDir = "$root\weights_by_category\foodseg103\service_logs"
New-Item -ItemType Directory -Path $serviceLogDir -Force | Out-Null

function Stop-ProcessByCommandPattern {
    param(
        [string]$Pattern
    )

    $procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $Pattern }
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to stop process $($p.ProcessId): $($_.Exception.Message)"
        }
    }
}

# Clean old service processes first to avoid duplicate jobs writing to same outputs.
Stop-ProcessByCommandPattern -Pattern 'tensorboard\.main.*--port\s+6006'
Stop-ProcessByCommandPattern -Pattern 'run_stage6s3\.ps1'
Stop-ProcessByCommandPattern -Pattern 'train_stage5a\.py.*stage6s3_tiny_img384_continue40ep'
Stop-ProcessByCommandPattern -Pattern 'eval_stage5b\.py.*stage6s3_eval_'

$tbStdOut = "$serviceLogDir\tensorboard_stdout.log"
$tbStdErr = "$serviceLogDir\tensorboard_stderr.log"
$tbArgs = '-m tensorboard.main --logdir_spec foodseg103:weights_by_category/foodseg103,smoke:weights_by_category/smoke --port 6006 --host 0.0.0.0'

$tbProc = Start-Process -FilePath $py -ArgumentList $tbArgs -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $tbStdOut -RedirectStandardError $tbStdErr -PassThru

$s3StdOut = "$serviceLogDir\stage6s3_orchestrator_stdout.log"
$s3StdErr = "$serviceLogDir\stage6s3_orchestrator_stderr.log"
$s3Script = "$root\app\training\run_stage6s3.ps1"
$s3Args = "-ExecutionPolicy Bypass -File `"$s3Script`""

$s3Proc = Start-Process -FilePath $psExe -ArgumentList $s3Args -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $s3StdOut -RedirectStandardError $s3StdErr -PassThru

Start-Sleep -Seconds 2

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

Write-Output "Detached services started."
Write-Output "TensorBoard PID: $($tbProc.Id)"
Write-Output "Stage6S3 Orchestrator PID: $($s3Proc.Id)"
Write-Output "TensorBoardPort6006Open: $portOpen"
Write-Output "ServiceLogs: $serviceLogDir"
