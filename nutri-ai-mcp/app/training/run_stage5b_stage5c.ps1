$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage5bOut = "$outRoot\stage5b"
$stage5cOut = "$outRoot\stage5c"
$placeholderWeights = "$trainDir\class_distribution.json"
$realWeights = "$trainDir\class_distribution_real.json"

$tinyBest = "$outRoot\stage5a\stage5a_tiny_classweight_50ep\best_stage5a_tiny_classweight_50ep.pth"
$baseBest = "$outRoot\stage5a\stage5a_base_classweight_50ep\best_stage5a_base_classweight_50ep.pth"

New-Item -ItemType Directory -Path $stage5bOut -Force | Out-Null
New-Item -ItemType Directory -Path $stage5cOut -Force | Out-Null

$masterLog = "$outRoot\stage5b_stage5c_master.log"
"[$(Get-Date -Format o)] START Stage5B+Stage5C pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

function Run-Step {
    param(
        [string]$Name,
        [string]$Command
    )

    "[$(Get-Date -Format o)] START $Name" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
    try {
        Invoke-Expression $Command
        "[$(Get-Date -Format o)] DONE  $Name" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
    }
    catch {
        "[$(Get-Date -Format o)] FAIL  $Name :: $($_.Exception.Message)" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
        throw
    }
}

# Stage5B: Full-validation confirmation
Run-Step -Name 'stage5b_tiny_fullval_from_stage5a_best' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' " +
    "--output_dir '$stage5bOut' " +
    "--run_name 'stage5b_tiny_fullval_from_stage5a_best' " +
    "--backbone 'swin_tiny_patch4_window7_224' " +
    "--batch_size 2 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$tinyBest'"
)

Run-Step -Name 'stage5b_base_fullval_from_stage5a_best' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' " +
    "--output_dir '$stage5bOut' " +
    "--run_name 'stage5b_base_fullval_from_stage5a_best' " +
    "--backbone 'swin_base_patch4_window7_224' " +
    "--batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$baseBest'"
)

# Stage5C: Placeholder weight baseline (20 epochs)
Run-Step -Name 'stage5c_tiny_placeholderw_20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --batch_size 2 --epochs 20 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage5cOut' --run_name 'stage5c_tiny_placeholderw_20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$tinyBest' --class_weights_file '$placeholderWeights'"
)

Run-Step -Name 'stage5c_base_placeholderw_20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_base_patch4_window7_224' --batch_size 1 --epochs 20 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage5cOut' --run_name 'stage5c_base_placeholderw_20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$baseBest' --class_weights_file '$placeholderWeights'"
)

# Stage5C: Real weight runs (20 epochs)
Run-Step -Name 'stage5c_tiny_realw_20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --batch_size 2 --epochs 20 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage5cOut' --run_name 'stage5c_tiny_realw_20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$tinyBest' --class_weights_file '$realWeights'"
)

Run-Step -Name 'stage5c_base_realw_20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_base_patch4_window7_224' --batch_size 1 --epochs 20 --lr 2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage5cOut' --run_name 'stage5c_base_realw_20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$baseBest' --class_weights_file '$realWeights'"
)

"[$(Get-Date -Format o)] ALL DONE Stage5B+Stage5C pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
