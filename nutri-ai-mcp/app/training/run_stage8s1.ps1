$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'training_env.ps1')
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage8Out = "$outRoot\stage8s1"
$stage8EvalOut = "$outRoot\stage8s1_eval"
$weightsFile = "$trainDir\class_distribution.json"
$masterLog = "$outRoot\stage8s1_master.log"
$gateDecision = "$outRoot\stage8s1_gate_decision.json"

$ckptStart = "$outRoot\stage7s1\stage7s1_tiny_img512_mask135_cls095_phaseA_12ep\best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth"

New-Item -ItemType Directory -Path $stage8Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage8EvalOut -Force | Out-Null

"[$(Get-Date -Format o)] START Stage8S1 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

Run-Step -Name 'stage8s1_tiny_img512_ws_m135_c095_phaseA_40ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 40 --lr 2.5e-5 --num_classes 104 " +
    "--loss_cls_weight 0.95 --loss_mask_weight 1.35 --mask_head_mode binary --boundary_loss_weight 0.0 " +
    "--max_train_batches 2000 --max_val_batches 500 --use_weighted_sampler " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage8Out' --run_name 'stage8s1_tiny_img512_ws_m135_c095_phaseA_40ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptStart' --class_weights_file '$weightsFile'"
)

$bestA = "$stage8Out\stage8s1_tiny_img512_ws_m135_c095_phaseA_40ep\best_stage8s1_tiny_img512_ws_m135_c095_phaseA_40ep.pth"
if (!(Test-Path $bestA)) {
    throw "Missing checkpoint for phase A eval: $bestA"
}

Run-Step -Name 'stage8s1_eval_tiny_img512_ws_m135_c095_phaseA_40ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage8EvalOut' --run_name 'stage8s1_eval_tiny_img512_ws_m135_c095_phaseA_40ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestA'"
)

Run-Step -Name 'stage8s1_tiny_img512_ws_m135_c095_phaseB_30ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 30 --lr 1.5e-5 --num_classes 104 " +
    "--loss_cls_weight 0.95 --loss_mask_weight 1.35 --mask_head_mode binary --boundary_loss_weight 0.0 " +
    "--max_train_batches 2000 --max_val_batches 500 --use_weighted_sampler " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage8Out' --run_name 'stage8s1_tiny_img512_ws_m135_c095_phaseB_30ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$bestA' --class_weights_file '$weightsFile'"
)

$bestB = "$stage8Out\stage8s1_tiny_img512_ws_m135_c095_phaseB_30ep\best_stage8s1_tiny_img512_ws_m135_c095_phaseB_30ep.pth"
if (!(Test-Path $bestB)) {
    throw "Missing checkpoint for phase B eval: $bestB"
}

Run-Step -Name 'stage8s1_eval_tiny_img512_ws_m135_c095_phaseB_30ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage8EvalOut' --run_name 'stage8s1_eval_tiny_img512_ws_m135_c095_phaseB_30ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestB'"
)

$evalA = "$stage8EvalOut\stage8s1_eval_tiny_img512_ws_m135_c095_phaseA_40ep_fullval\eval_summary.json"
$evalB = "$stage8EvalOut\stage8s1_eval_tiny_img512_ws_m135_c095_phaseB_30ep_fullval\eval_summary.json"
if (!(Test-Path $evalA) -or !(Test-Path $evalB)) {
    throw "Missing eval summary for A/B gate: $evalA or $evalB"
}

$abGateResult = & "$py" -c @"
import json
from pathlib import Path

eps = 0.0005
pa = Path(r'''$evalA''')
pb = Path(r'''$evalB''')
a = json.loads(pa.read_text(encoding='utf-8'))
b = json.loads(pb.read_text(encoding='utf-8'))
ma = float(a['val_mIoU'])
mb = float(b['val_mIoU'])
ca = int(a.get('nonzero_non_bg_classes', 0))
cb = int(b.get('nonzero_non_bg_classes', 0))
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
    'ab_winner': winner,
    'ab_winner_checkpoint': ckpt,
    'phaseA_mIoU': ma,
    'phaseB_mIoU': mb,
    'phaseA_nonzero_non_bg_classes': ca,
    'phaseB_nonzero_non_bg_classes': cb,
    'epsilon': eps,
}))
"@

$abGateObj = $abGateResult | ConvertFrom-Json
"[$(Get-Date -Format o)] GATE-AB winner=$($abGateObj.ab_winner) phaseA=$($abGateObj.phaseA_mIoU) phaseB=$($abGateObj.phaseB_mIoU)" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

$ckptGate = [string]$abGateObj.ab_winner_checkpoint
if (!(Test-Path $ckptGate)) {
    throw "Gate checkpoint missing: $ckptGate"
}

Run-Step -Name 'stage8s1_tiny_img512_ws_m135_c095_phaseC_20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 20 --lr 1.0e-5 --num_classes 104 " +
    "--loss_cls_weight 0.95 --loss_mask_weight 1.35 --mask_head_mode binary --boundary_loss_weight 0.0 " +
    "--max_train_batches 2000 --max_val_batches 500 --use_weighted_sampler " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage8Out' --run_name 'stage8s1_tiny_img512_ws_m135_c095_phaseC_20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptGate' --class_weights_file '$weightsFile'"
)

$bestC = "$stage8Out\stage8s1_tiny_img512_ws_m135_c095_phaseC_20ep\best_stage8s1_tiny_img512_ws_m135_c095_phaseC_20ep.pth"
if (!(Test-Path $bestC)) {
    throw "Missing checkpoint for phase C eval: $bestC"
}

Run-Step -Name 'stage8s1_eval_tiny_img512_ws_m135_c095_phaseC_20ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage8EvalOut' --run_name 'stage8s1_eval_tiny_img512_ws_m135_c095_phaseC_20ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestC'"
)

$evalC = "$stage8EvalOut\stage8s1_eval_tiny_img512_ws_m135_c095_phaseC_20ep_fullval\eval_summary.json"
if (!(Test-Path $evalC)) {
    throw "Missing eval summary for final gate: $evalC"
}

$finalGateResult = & "$py" -c @"
import json
from pathlib import Path

eps = 0.0005
pa = Path(r'''$evalA''')
pb = Path(r'''$evalB''')
pc = Path(r'''$evalC''')
a = json.loads(pa.read_text(encoding='utf-8'))
b = json.loads(pb.read_text(encoding='utf-8'))
c = json.loads(pc.read_text(encoding='utf-8'))

ma = float(a['val_mIoU'])
mb = float(b['val_mIoU'])
mc = float(c['val_mIoU'])
ca = int(a.get('nonzero_non_bg_classes', 0))
cb = int(b.get('nonzero_non_bg_classes', 0))
cc = int(c.get('nonzero_non_bg_classes', 0))

def choose(name_x, metric_x, cover_x, ckpt_x, name_y, metric_y, cover_y, ckpt_y):
    if metric_y > metric_x + eps:
        return name_y, metric_y, cover_y, ckpt_y
    if metric_x > metric_y + eps:
        return name_x, metric_x, cover_x, ckpt_x
    if cover_y >= cover_x:
        return name_y, metric_y, cover_y, ckpt_y
    return name_x, metric_x, cover_x, ckpt_x

ab_name, ab_metric, ab_cover, ab_ckpt = choose('A', ma, ca, r'''$bestA''', 'B', mb, cb, r'''$bestB''')
final_name, final_metric, final_cover, final_ckpt = choose(ab_name, ab_metric, ab_cover, ab_ckpt, 'C', mc, cc, r'''$bestC''')

print(json.dumps({
    'ab_winner': ab_name,
    'final_winner': final_name,
    'checkpoint': final_ckpt,
    'winner_mIoU': final_metric,
    'winner_nonzero_non_bg_classes': final_cover,
    'phaseA_mIoU': ma,
    'phaseB_mIoU': mb,
    'phaseC_mIoU': mc,
    'phaseA_nonzero_non_bg_classes': ca,
    'phaseB_nonzero_non_bg_classes': cb,
    'phaseC_nonzero_non_bg_classes': cc,
    'epsilon': eps,
}))
"@

$gateObj = $finalGateResult | ConvertFrom-Json
$gateObj | ConvertTo-Json -Depth 6 | Out-File -FilePath $gateDecision -Encoding UTF8
"[$(Get-Date -Format o)] FINAL winner=$($gateObj.final_winner) mIoU=$($gateObj.winner_mIoU) cover=$($gateObj.winner_nonzero_non_bg_classes)" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

"[$(Get-Date -Format o)] ALL DONE Stage8S1 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
