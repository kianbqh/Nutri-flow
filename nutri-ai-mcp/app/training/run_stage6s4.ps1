$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6s4Out = "$outRoot\stage6s4"
$stage6s4EvalOut = "$outRoot\stage6s4_eval"
$weightsFile = "$trainDir\class_distribution.json"

$ckpt512S3Best = "$outRoot\stage6s3\stage6s3_tiny_img512_from384best_40ep\best_stage6s3_tiny_img512_from384best_40ep.pth"

New-Item -ItemType Directory -Path $stage6s4Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6s4EvalOut -Force | Out-Null

$masterLog = "$outRoot\stage6s4_master.log"
"[$(Get-Date -Format o)] START Stage6S4 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

if (!(Test-Path $ckpt512S3Best)) {
    throw "Missing checkpoint: $ckpt512S3Best"
}

Run-Step -Name 'stage6s4_tiny_img512_froms3best_100ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 100 --lr 1.5e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s4Out' --run_name 'stage6s4_tiny_img512_froms3best_100ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckpt512S3Best' --class_weights_file '$weightsFile'"
)

$bestS4 = "$stage6s4Out\stage6s4_tiny_img512_froms3best_100ep\best_stage6s4_tiny_img512_froms3best_100ep.pth"
if (!(Test-Path $bestS4)) {
    throw "Missing checkpoint for eval: $bestS4"
}

Run-Step -Name 'stage6s4_eval_tiny_img512_froms3best_100ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s4EvalOut' --run_name 'stage6s4_eval_tiny_img512_froms3best_100ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestS4'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6S4 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
