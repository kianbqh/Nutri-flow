$ErrorActionPreference = 'Stop'

$py = 'G:\GraduationProj_Nutri-flow\envs\test\python.exe'
$root = 'G:\GraduationProj_Nutri-flow\Nutri-flow\nutri-ai-mcp'
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage7Out = "$outRoot\stage7s3"
$stage7EvalOut = "$outRoot\stage7s3_eval"
$weightsFile = "$trainDir\class_distribution.json"
$masterLog = "$outRoot\stage7s3_master.log"
$gateDecision = "$outRoot\stage7s3_gate_decision.json"

$ckptStart = "$outRoot\stage7s1\stage7s1_tiny_img512_mask135_cls095_phaseA_12ep\best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth"

New-Item -ItemType Directory -Path $stage7Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage7EvalOut -Force | Out-Null

"[$(Get-Date -Format o)] START Stage7S3 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

if (!(Test-Path $ckptStart)) {
    throw "Missing checkpoint: $ckptStart"
}

Run-Step -Name 'stage7s3_tiny_img512_binmask135_b005_phaseA_10ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 10 --lr 1.5e-5 --num_classes 104 " +
    "--loss_cls_weight 0.95 --loss_mask_weight 1.35 --boundary_loss_weight 0.05 --mask_head_mode binary " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage7Out' --run_name 'stage7s3_tiny_img512_binmask135_b005_phaseA_10ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptStart' --class_weights_file '$weightsFile'"
)

$bestA = "$stage7Out\stage7s3_tiny_img512_binmask135_b005_phaseA_10ep\best_stage7s3_tiny_img512_binmask135_b005_phaseA_10ep.pth"
if (!(Test-Path $bestA)) {
    throw "Missing checkpoint for phase A eval: $bestA"
}

Run-Step -Name 'stage7s3_eval_tiny_img512_binmask135_b005_phaseA_10ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage7EvalOut' --run_name 'stage7s3_eval_tiny_img512_binmask135_b005_phaseA_10ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 --mask_head_mode binary " +
    "--checkpoint '$bestA'"
)

Run-Step -Name 'stage7s3_tiny_img512_binmask135_b010_phaseB_8ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 8 --lr 1.0e-5 --num_classes 104 " +
    "--loss_cls_weight 0.95 --loss_mask_weight 1.35 --boundary_loss_weight 0.10 --mask_head_mode binary " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage7Out' --run_name 'stage7s3_tiny_img512_binmask135_b010_phaseB_8ep' " +
    "--device cuda --checkpoint_every 4 --resume_from '$bestA' --class_weights_file '$weightsFile'"
)

$bestB = "$stage7Out\stage7s3_tiny_img512_binmask135_b010_phaseB_8ep\best_stage7s3_tiny_img512_binmask135_b010_phaseB_8ep.pth"
if (!(Test-Path $bestB)) {
    throw "Missing checkpoint for phase B eval: $bestB"
}

Run-Step -Name 'stage7s3_eval_tiny_img512_binmask135_b010_phaseB_8ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage7EvalOut' --run_name 'stage7s3_eval_tiny_img512_binmask135_b010_phaseB_8ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 --mask_head_mode binary " +
    "--checkpoint '$bestB'"
)

$evalA = "$stage7EvalOut\stage7s3_eval_tiny_img512_binmask135_b005_phaseA_10ep_fullval\eval_summary.json"
$evalB = "$stage7EvalOut\stage7s3_eval_tiny_img512_binmask135_b010_phaseB_8ep_fullval\eval_summary.json"
if (!(Test-Path $evalA) -or !(Test-Path $evalB)) {
    throw "Missing eval summary for gate: $evalA or $evalB"
}

$gateResult = & "$py" -c @"
import json
from pathlib import Path
pa = Path(r'''$evalA''')
pb = Path(r'''$evalB''')
a = json.loads(pa.read_text(encoding='utf-8'))
b = json.loads(pb.read_text(encoding='utf-8'))
ma = float(a['val_mIoU'])
mb = float(b['val_mIoU'])
ca = int(a.get('nonzero_non_bg_classes', 0))
cb = int(b.get('nonzero_non_bg_classes', 0))
eps = 0.0005
if mb > ma + eps:
    winner = 'B'
    ckpt = r'''$bestB'''
elif ma > mb + eps:
    winner = 'A'
    ckpt = r'''$bestA'''
else:
    if cb >= ca:
        winner = 'B'
        ckpt = r'''$bestB'''
    else:
        winner = 'A'
        ckpt = r'''$bestA'''
print(json.dumps({
    'winner': winner,
    'checkpoint': ckpt,
    'phaseA_mIoU': ma,
    'phaseB_mIoU': mb,
    'phaseA_nonzero_non_bg_classes': ca,
    'phaseB_nonzero_non_bg_classes': cb,
    'epsilon': eps
}))
"@

$gateObj = $gateResult | ConvertFrom-Json
$gateObj | ConvertTo-Json -Depth 6 | Out-File -FilePath $gateDecision -Encoding UTF8
"[$(Get-Date -Format o)] GATE winner=$($gateObj.winner) phaseA=$($gateObj.phaseA_mIoU) phaseB=$($gateObj.phaseB_mIoU)" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

"[$(Get-Date -Format o)] ALL DONE Stage7S3 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append