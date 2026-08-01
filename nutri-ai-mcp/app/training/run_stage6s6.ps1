$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'training_env.ps1')
$trainDir = "$root\app\training"
$dataset = "$root\data\FoodSeg103_hf"
$outRoot = "$root\weights_by_category\foodseg103"
$stage6s6Out = "$outRoot\stage6s6"
$stage6s6EvalOut = "$outRoot\stage6s6_eval"
$weightsFile = "$trainDir\class_distribution.json"
$masterLog = "$outRoot\stage6s6_master.log"
$gateDecision = "$outRoot\stage6s6_gate_decision.json"

$ckptStart = "$outRoot\stage6s5\stage6s5_tiny_img512_phaseA_70ep\best_stage6s5_tiny_img512_phaseA_70ep.pth"

New-Item -ItemType Directory -Path $stage6s6Out -Force | Out-Null
New-Item -ItemType Directory -Path $stage6s6EvalOut -Force | Out-Null

"[$(Get-Date -Format o)] START Stage6S6 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

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

# Phase A
Run-Step -Name 'stage6s6_tiny_img512_phaseA_50ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 50 --lr 1.0e-4 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s6Out' --run_name 'stage6s6_tiny_img512_phaseA_50ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptStart' --class_weights_file '$weightsFile'"
)

$bestA = "$stage6s6Out\stage6s6_tiny_img512_phaseA_50ep\best_stage6s6_tiny_img512_phaseA_50ep.pth"
if (!(Test-Path $bestA)) {
    throw "Missing checkpoint for phase B: $bestA"
}

Run-Step -Name 'stage6s6_eval_tiny_img512_phaseA_50ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s6EvalOut' --run_name 'stage6s6_eval_tiny_img512_phaseA_50ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestA'"
)

# Phase B
Run-Step -Name 'stage6s6_tiny_img512_phaseB_30ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 30 --lr 7e-5 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s6Out' --run_name 'stage6s6_tiny_img512_phaseB_30ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$bestA' --class_weights_file '$weightsFile'"
)

$bestB = "$stage6s6Out\stage6s6_tiny_img512_phaseB_30ep\best_stage6s6_tiny_img512_phaseB_30ep.pth"
if (!(Test-Path $bestB)) {
    throw "Missing checkpoint for B-eval: $bestB"
}

Run-Step -Name 'stage6s6_eval_tiny_img512_phaseB_30ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s6EvalOut' --run_name 'stage6s6_eval_tiny_img512_phaseB_30ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestB'"
)

# Gate A/B by full-val mIoU
$evalA = "$stage6s6EvalOut\stage6s6_eval_tiny_img512_phaseA_50ep_fullval\eval_summary.json"
$evalB = "$stage6s6EvalOut\stage6s6_eval_tiny_img512_phaseB_30ep_fullval\eval_summary.json"
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
if mb >= ma:
    winner = 'B'
    ckpt = r'''$bestB'''
    m = mb
else:
    winner = 'A'
    ckpt = r'''$bestA'''
    m = ma
print(json.dumps({'winner': winner, 'winner_mIoU': m, 'checkpoint': ckpt, 'phaseA_mIoU': ma, 'phaseB_mIoU': mb}))
"@

$gateObj = $gateResult | ConvertFrom-Json
$gateObj | ConvertTo-Json -Depth 6 | Out-File -FilePath $gateDecision -Encoding UTF8
"[$(Get-Date -Format o)] GATE  winner=$($gateObj.winner) mIoU=$($gateObj.winner_mIoU)" | Out-File -FilePath $masterLog -Encoding UTF8 -Append

$ckptGate = [string]$gateObj.checkpoint
if (!(Test-Path $ckptGate)) {
    throw "Gate checkpoint missing: $ckptGate"
}

# Phase C
Run-Step -Name 'stage6s6_tiny_img512_phaseC_20ep' -Command (
    "& '$py' '$trainDir\train_stage5a.py' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --epochs 20 --lr 5e-5 --num_classes 104 " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s6Out' --run_name 'stage6s6_tiny_img512_phaseC_20ep' " +
    "--device cuda --checkpoint_every 5 --resume_from '$ckptGate' --class_weights_file '$weightsFile'"
)

$bestC = "$stage6s6Out\stage6s6_tiny_img512_phaseC_20ep\best_stage6s6_tiny_img512_phaseC_20ep.pth"
if (!(Test-Path $bestC)) {
    throw "Missing checkpoint for C-eval: $bestC"
}

Run-Step -Name 'stage6s6_eval_tiny_img512_phaseC_20ep_fullval' -Command (
    "& '$py' '$trainDir\eval_stage5b.py' " +
    "--hf_dataset_dir '$dataset' --output_dir '$stage6s6EvalOut' --run_name 'stage6s6_eval_tiny_img512_phaseC_20ep_fullval' " +
    "--backbone 'swin_tiny_patch4_window7_224' --img_size 512 --batch_size 1 --num_classes 104 --device cuda --max_val_batches 0 " +
    "--checkpoint '$bestC'"
)

"[$(Get-Date -Format o)] ALL DONE Stage6S6 pipeline" | Out-File -FilePath $masterLog -Encoding UTF8 -Append
