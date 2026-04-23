$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6Out = "$outRoot\stage6"
$stage6EvalOut = "$outRoot\stage6_eval"
$weightsFile = "$trainDir\class_distribution.json"
$tinyBest = "$outRoot\stage5a\stage5a_tiny_classweight_50ep\best_stage5a_tiny_classweight_50ep.pth"

New-Item -ItemType Directory -Path $stage6Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6EvalOut -Force | Out-Null

$masterLog = "$outRoot\stage6_master.log"
"[$(Get-Date -Format o)] START Stage6-S repair from 320" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

Run-Step -Name 'stage6_tiny_img320_placeholderw_30ep_repair' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 320 --batch_size 1 --epochs 30 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6Out' --run_name 'stage6_tiny_img320_placeholderw_30ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$tinyBest' --class_weights_file '$weightsFile'"
)

$best320 = "$stage6Out\stage6_tiny_img320_placeholderw_30ep\best_stage6_tiny_img320_placeholderw_30ep.pth"
if (!(Test-Path $best320)) {
    throw "Missing checkpoint for eval: $best320"
}

Run-Step -Name 'stage6_eval_tiny_img320_fullval_repair' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6EvalOut' --run_name 'stage6_eval_tiny_img320_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 320 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best320'"
)

Run-Step -Name 'stage6_tiny_img384_placeholderw_30ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 384 --batch_size 1 --epochs 30 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6Out' --run_name 'stage6_tiny_img384_placeholderw_30ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$tinyBest' --class_weights_file '$weightsFile'"
)

$best384 = "$stage6Out\stage6_tiny_img384_placeholderw_30ep\best_stage6_tiny_img384_placeholderw_30ep.pth"
if (!(Test-Path $best384)) {
    throw "Missing checkpoint for eval: $best384"
}

Run-Step -Name 'stage6_eval_tiny_img384_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6EvalOut' --run_name 'stage6_eval_tiny_img384_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 384 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$best384'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6-S repair from 320" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
