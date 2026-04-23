$ErrorActionPreference = 'Stop'

$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$masterLog = "$root\weights_by_category\foodseg103\stage6s3_master.log"
$serviceLogDir = "$root\weights_by_category\foodseg103\service_logs"

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

Write-Output "TensorBoardPort6006Open: $portOpen"

$procs = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match 'tensorboard\.main|run_stage6s3\.ps1|train_stage5a\.py|eval_stage5b\.py'
}

Write-Output ("RelatedProcessCount: " + ($procs | Measure-Object).Count)
$procs | Select-Object ProcessId, Name, CreationDate, CommandLine | Format-List

if (Test-Path $masterLog) {
    Write-Output "`n=== stage6s3_master.log (tail) ==="
    Get-Content $masterLog -Tail 12
}

if (Test-Path $serviceLogDir) {
    Write-Output "`n=== service_logs files ==="
    Get-ChildItem $serviceLogDir -File | Select-Object Name, LastWriteTime, Length
}
