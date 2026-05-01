# 25 Stage7S1 阶段性结果归档与分析记录

## 1. 文档目的

本记录用于沉淀本轮对 Stage7S1 实验结果的核查、阶段性分析与归档动作，确保实验结论、当前运行状态和后续建议都被单独记录下来，便于论文撰写与后续实验衔接。

## 2. 触发背景

在 Stage7S1 启动后，用户要求：

1. 检查当前实验结果。
2. 按既有实验报告风格归档结果分析。
3. 给出下一步建议。

由于该实验采用 detached 方式后台运行，因此不能只看计划文档，必须结合主日志、评估摘要和运行目录来确认当前真实进度。

## 3. 核查过程

本轮主要核查了以下实验资产：

1. `stage7s1_master.log`
2. `stage7s1/` 训练输出目录
3. `stage7s1_eval/` 评估输出目录
4. `stage7s1_tiny_img512_mask135_cls095_phaseA_12ep/per_class_iou_history.jsonl`
5. `stage7s1_eval_tiny_img512_mask135_cls095_phaseA_12ep_fullval/eval_summary.json`
6. 当前 Stage7S1 运行进程状态

## 4. 当前实验状态

核查时确认：

1. Phase A 训练已经完成。
2. Phase A full-val 评估已经完成。
3. Phase B 已经启动并正在继续运行。
4. `stage7s1_gate_decision.json` 尚未生成，因此整个 Stage7S1 还没有完成最终门控。

这意味着本轮可以归档的是“Stage7S1 阶段性实验结果”，还不能下最终 gate 结论。

## 5. 已确认的关键结果

### 5.1 Phase A full-val 结果

`stage7s1_eval_tiny_img512_mask135_cls095_phaseA_12ep_fullval/eval_summary.json` 显示：

1. `val_mIoU = 0.3199287227568812`
2. `nonzero_non_bg_classes = 98`
3. `full_val = true`

### 5.2 与当前主基线对比

对照当前在线主基线 Stage6S6 PhaseC：

1. Stage6S6 PhaseC full-val：`0.3169905754109746`
2. Stage6S6 PhaseC nonzero_non_bg_classes：`98`

差值为：

1. `mIoU +0.0029381473459066387`
2. 覆盖类数持平（`98 -> 98`）

### 5.3 训练内验证现象

Phase A 的训练内验证曲线并不算特别强：

1. 12 个验证点中，最佳记录出现在最早阶段。
2. 后续大部分点位徘徊在 `0.305 ~ 0.311` 区间。

但最终 full-val 却明显优于 Stage6S6 当前基线，这说明“训练内 500 batch 验证”并不能稳定代替最终 full-val 判定。

## 6. 结论与分析

### 6.1 当前已被支持的结论

截至本轮归档时，Stage7S1 已经至少证明了一点：

1. 温和的 mask 偏置策略（`loss_mask_weight=1.35`, `loss_cls_weight=0.95`）是有效的。
2. 它在不损失类别覆盖的前提下，把 full-val mIoU 从 `0.316991` 推高到了 `0.319929`。

### 6.2 当前最重要的工程认识

本轮最值得沉淀的不只是数值提升本身，还包括一个方法论结论：

1. 训练内子集验证不一定能准确反映 full-val 排名。
2. 因此 Stage7 系列继续坚持“阶段 full-val + 门控选优”是必要的。
3. 如果只看 Phase A 训练曲线，反而可能错误地低估这条路线的价值。

### 6.3 目前还不能下的结论

由于 Phase B 尚未完成，本轮还不能断言：

1. Stage7S1 最终冠军一定是 Phase A。
2. 更强的 mask 偏置（`1.60 / 0.90`）一定无效。

这些问题仍要等 Phase B full-val 和最终 gate 文件生成后再决定。

## 7. 已归档结果

本轮已新增正式实验分析文档：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_experiment_report.md`

该文档会作为 Stage7S1 的阶段性实验报告，后续待 Phase B 与 gate 完成后可继续追加或修订为终稿。

## 8. 下一步建议

1. 让 Phase B 按当前脚本继续跑完，不要因为 Phase A 已经变好就提前打断；否则会失去完整 gate 证据。
2. 如果 Phase B full-val 低于 Phase A 超过 `0.0005`，或者覆盖类数下降，则应直接 gate 回 Phase A。
3. 如果最终 gate 仍选中 Phase A，可将其作为新的 S7 候选基线，再设计更温和的 S7S2，而不是继续盲目加大 mask 权重。
4. 后续若继续做 S7 扩展，建议把阶段性 proxy validation 的代表性补强，例如增加中期 full-val 或适度扩大 `max_val_batches`。

## 9. 工程结论

这次归档说明了一件很重要的事：当前 Stage7 并不是“还没结果”，而是已经出现了明确的正向阶段成果。真正需要保持克制的地方，不是怀疑这条路线有没有用，而是在最终 gate 完成前，不要把 Phase A 的阶段胜利误写成整个 Stage7S1 的最终胜利。
