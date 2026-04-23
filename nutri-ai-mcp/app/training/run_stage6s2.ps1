$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6s2Out = "$outRoot\stage6s2"
$stage6s2EvalOut = "$outRoot\stage6s2_eval"
$weightsFile = "$trainDir\class_distribution.json"

$ckpt384Best = "$outRoot\stage6\stage6_tiny_img384_placeholderw_30ep\best_stage6_tiny_img384_placeholderw_30ep.pth"
$ckptStage5aTinyBest = "$outRoot\stage5a\stage5a_tiny_classweight_50ep\best_stage5a_tiny_classweight_50ep.pth"

New-Item -ItemType Directory -Path $stage6s2Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6s2EvalOut -Force | Out-Null

$masterLog = "$outRoot\stage6s2_master.log"
"[$(Get-Date -Format o)] START Stage6S2 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

if (!(Test-Path $ckpt384Best)) {
    throw "Missing checkpoint: $ckpt384Best"
}
if (!(Test-Path $ckptStage5aTinyBest)) {
    throw "Missing checkpoint: $ckptStage5aTinyBest"
}

# Stage6S2-A: Continue 384 from Stage6-S1 best
Run-Step -Name 'stage6s2_tiny_img384_continue20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 384 --batch_size 1 --epochs 20 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s2Out' --run_name 'stage6s2_tiny_img384_continue20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckpt384Best' --class_weights_file '$weightsFile'"
)

$best384s2 = "$stage6s2Out\stage6s2_tiny_img384_continue20ep\best_stage6s2_tiny_img384_continue20ep.pth"
if (!(Test-Path $best384s2)) {
    throw "Missing checkpoint for eval: $best384s2"
}

Run-Step -Name 'stage6s2_eval_tiny_img384_continue20ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s2EvalOut' --run_name 'stage6s2_eval_tiny_img384_continue20ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 384 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best384s2'"
)

# Stage6S2-B: 512 full run (same epoch budget as Stage6-S1)
Run-Step -Name 'stage6s2_tiny_img512_placeholderw_30ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 30 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s2Out' --run_name 'stage6s2_tiny_img512_placeholderw_30ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptStage5aTinyBest' --class_weights_file '$weightsFile'"
)

$best512s2 = "$stage6s2Out\stage6s2_tiny_img512_placeholderw_30ep\best_stage6s2_tiny_img512_placeholderw_30ep.pth"
if (!(Test-Path $best512s2)) {
    throw "Missing checkpoint for eval: $best512s2"
}

Run-Step -Name 'stage6s2_eval_tiny_img512_placeholderw_30ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s2EvalOut' --run_name 'stage6s2_eval_tiny_img512_placeholderw_30ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best512s2'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6S2 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
