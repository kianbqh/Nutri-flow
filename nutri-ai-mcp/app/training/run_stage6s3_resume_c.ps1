$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6s3Out = "$outRoot\stage6s3"
$stage6s3EvalOut = "$outRoot\stage6s3_eval"
$weightsFile = "$trainDir\class_distribution.json"
$masterLog = "$outRoot\stage6s3_master.log"

# Resume from the best checkpoint produced by Stage6S3-C before interruption.
$ckptResumeC = "$stage6s3Out\stage6s3_tiny_img512_continue30ep_froms2\best_stage6s3_tiny_img512_continue30ep_froms2.pth"
$resumeRunName = 'stage6s3_tiny_img512_continue30ep_froms2_resume17ep'
$evalRunName = 'stage6s3_eval_tiny_img512_continue30ep_froms2_resume17ep_fullval'

New-Item -ItemType Directory -Path $stage6s3Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6s3EvalOut -Force | Out-Null

function Run-Step {
    param(
        [string]$Name,
        [string]$Command
    )

    "[$(Get-Date -Format o)] START $Name" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
    try {
        Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Command exited with code $LASTEXITCODE"
        }
        "[$(Get-Date -Format o)] DONE  $Name" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
    }
    catch {
        "[$(Get-Date -Format o)] FAIL  $Name :: $($_.Exception.Message)" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
        throw
    }
}

if (!(Test-Path $ckptResumeC)) {
    throw "Missing checkpoint: $ckptResumeC"
}

"[$(Get-Date -Format o)] START Stage6S3-C RESUME pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

Run-Step -Name $resumeRunName -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 17 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3Out' --run_name '$resumeRunName' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptResumeC' --class_weights_file '$weightsFile'"
)

$bestResume = "$stage6s3Out\$resumeRunName\best_$resumeRunName.pth"
if (!(Test-Path $bestResume)) {
    throw "Missing checkpoint for eval: $bestResume"
}

Run-Step -Name $evalRunName -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3EvalOut' --run_name '$evalRunName' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestResume'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6S3-C RESUME pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
