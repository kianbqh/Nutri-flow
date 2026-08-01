$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'training_env.ps1')
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6s3Out = "$outRoot\stage6s3"
$stage6s3EvalOut = "$outRoot\stage6s3_eval"
$weightsFile = "$trainDir\class_distribution.json"

$ckpt384s2Best = "$outRoot\stage6s2\stage6s2_tiny_img384_continue20ep\best_stage6s2_tiny_img384_continue20ep.pth"
$ckpt512s2Best = "$outRoot\stage6s2\stage6s2_tiny_img512_placeholderw_30ep\best_stage6s2_tiny_img512_placeholderw_30ep.pth"

New-Item -ItemType Directory -Path $stage6s3Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6s3EvalOut -Force | Out-Null

$masterLog = "$outRoot\stage6s3_master.log"
"[$(Get-Date -Format o)] START Stage6S3 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

if (!(Test-Path $ckpt384s2Best)) {
    throw "Missing checkpoint: $ckpt384s2Best"
}
if (!(Test-Path $ckpt512s2Best)) {
    throw "Missing checkpoint: $ckpt512s2Best"
}

# Stage6S3-A: 384 continue 40 epochs from Stage6S2 384 best
Run-Step -Name 'stage6s3_tiny_img384_continue40ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 384 --batch_size 1 --epochs 40 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3Out' --run_name 'stage6s3_tiny_img384_continue40ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckpt384s2Best' --class_weights_file '$weightsFile'"
)

$best384s3 = "$stage6s3Out\stage6s3_tiny_img384_continue40ep\best_stage6s3_tiny_img384_continue40ep.pth"
if (!(Test-Path $best384s3)) {
    throw "Missing checkpoint for eval: $best384s3"
}

Run-Step -Name 'stage6s3_eval_tiny_img384_continue40ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3EvalOut' --run_name 'stage6s3_eval_tiny_img384_continue40ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 384 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best384s3'"
)

# Stage6S3-B: 512 fair start from 384 best, 40 epochs
Run-Step -Name 'stage6s3_tiny_img512_from384best_40ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 40 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3Out' --run_name 'stage6s3_tiny_img512_from384best_40ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckpt384s2Best' --class_weights_file '$weightsFile'"
)

$best512fair = "$stage6s3Out\stage6s3_tiny_img512_from384best_40ep\best_stage6s3_tiny_img512_from384best_40ep.pth"
if (!(Test-Path $best512fair)) {
    throw "Missing checkpoint for eval: $best512fair"
}

Run-Step -Name 'stage6s3_eval_tiny_img512_from384best_40ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3EvalOut' --run_name 'stage6s3_eval_tiny_img512_from384best_40ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best512fair'"
)

# Stage6S3-C: 512 continue from Stage6S2 512 best, 30 epochs
Run-Step -Name 'stage6s3_tiny_img512_continue30ep_froms2' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 30 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3Out' --run_name 'stage6s3_tiny_img512_continue30ep_froms2' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckpt512s2Best' --class_weights_file '$weightsFile'"
)

$best512cont = "$stage6s3Out\stage6s3_tiny_img512_continue30ep_froms2\best_stage6s3_tiny_img512_continue30ep_froms2.pth"
if (!(Test-Path $best512cont)) {
    throw "Missing checkpoint for eval: $best512cont"
}

Run-Step -Name 'stage6s3_eval_tiny_img512_continue30ep_froms2_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s3EvalOut' --run_name 'stage6s3_eval_tiny_img512_continue30ep_froms2_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best512cont'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6S3 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
