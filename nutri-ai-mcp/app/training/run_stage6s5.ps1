$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'training_env.ps1')
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6s5Out = "$outRoot\stage6s5"
$stage6s5EvalOut = "$outRoot\stage6s5_eval"
$weightsFile = "$trainDir\class_distribution.json"

$ckptS4Best = "$outRoot\stage6s4\stage6s4_tiny_img512_froms3best_100ep\best_stage6s4_tiny_img512_froms3best_100ep.pth"

New-Item -ItemType Directory -Path $stage6s5Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6s5EvalOut -Force | Out-Null

$masterLog = "$outRoot\stage6s5_master.log"
"[$(Get-Date -Format o)] START Stage6S5 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

if (!(Test-Path $ckptS4Best)) {
    throw "Missing checkpoint: $ckptS4Best"
}

Run-Step -Name 'stage6s5_tiny_img512_phaseA_70ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 70 --lr 1.2e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s5Out' --run_name 'stage6s5_tiny_img512_phaseA_70ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptS4Best' --class_weights_file '$weightsFile'"
)

$bestA = "$stage6s5Out\stage6s5_tiny_img512_phaseA_70ep\best_stage6s5_tiny_img512_phaseA_70ep.pth"
if (!(Test-Path $bestA)) {
    throw "Missing checkpoint for phase B: $bestA"
}

Run-Step -Name 'stage6s5_tiny_img512_phaseB_40ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 40 --lr 8e-5 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s5Out' --run_name 'stage6s5_tiny_img512_phaseB_40ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$bestA' --class_weights_file '$weightsFile'"
)

$bestB = "$stage6s5Out\stage6s5_tiny_img512_phaseB_40ep\best_stage6s5_tiny_img512_phaseB_40ep.pth"
if (!(Test-Path $bestB)) {
    throw "Missing checkpoint for eval: $bestB"
}

Run-Step -Name 'stage6s5_eval_tiny_img512_phaseB_40ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s5EvalOut' --run_name 'stage6s5_eval_tiny_img512_phaseB_40ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestB'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6S5 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
