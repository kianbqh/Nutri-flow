# 26 Stage7S1 最终结果归档与 Gate 分析记录

## 1. 文档目的

本记录用于沉淀 Stage7S1 全流程结束后的最终结果核查、gate 结论确认与后续建议，确保本轮 S7 首次实验从“阶段性正向信号”正式收口为“带门控结论的终版结果”。

## 2. 触发背景

在上一轮阶段性归档中，Stage7S1 仍停留在：

1. Phase A 已完成并优于 Stage6S6 基线。
2. Phase B 正在运行。
3. gate 文件尚未生成。

本轮用户要求继续按之前的要求分析结果，因此需要重新核查实验资产，确认当前是否已经具备终版分析条件。

## 3. 本轮核查资产

本轮重点核查了以下文件：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_master.log`
2. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_gate_decision.json`
3. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_eval/stage7s1_eval_tiny_img512_mask135_cls095_phaseA_12ep_fullval/eval_summary.json`
4. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_eval/stage7s1_eval_tiny_img512_mask160_cls090_phaseB_8ep_fullval/eval_summary.json`
5. 既有 `stage7s1_experiment_report.md`

## 4. 当前最终状态

本轮确认 Stage7S1 已经完整结束：

1. Phase A 训练完成。
2. Phase A full-val 完成。
3. Phase B 训练完成。
4. Phase B full-val 完成。
5. gate 文件已生成。
6. `stage7s1_master.log` 已写出 `ALL DONE Stage7S1 pipeline`。

因此，本轮不再是阶段性分析，而是可以直接给出最终 gate 结论。

## 5. 已确认的最终结果

### 5.1 Phase A

`eval_summary.json` 显示：

1. `val_mIoU = 0.3199287227568812`
2. `nonzero_non_bg_classes = 98`

### 5.2 Phase B

`eval_summary.json` 显示：

1. `val_mIoU = 0.31366883211262286`
2. `nonzero_non_bg_classes = 97`

### 5.3 Gate 结果

`stage7s1_gate_decision.json` 显示：

1. `winner = A`
2. `epsilon = 0.0005`
3. 最终保留 checkpoint 为 `best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth`

## 6. 与基线及阶段结果对比

对照 Stage6S6 PhaseC 当前主基线：

1. Stage6S6 PhaseC：`0.3169905754109746`，覆盖 `98`
2. Stage7S1 Phase A：`0.3199287227568812`，覆盖 `98`
3. Stage7S1 Phase B：`0.31366883211262286`，覆盖 `97`

得到三个关键判断：

1. Phase A 相比基线提升 `+0.0029381473459066387`，且覆盖持平。
2. Phase B 相比基线下降 `-0.0033217432983517354`，且覆盖减少 `1` 类。
3. Phase A 相比 Phase B 高出 `+0.006259890644258374`，并多保住 `1` 个非背景类别。

## 7. 结果分析

### 7.1 当前被明确验证的部分

Stage7S1 最终证明：

1. Mild mask bias 是有效路线。
2. `loss_mask_weight=1.35` 与 `loss_cls_weight=0.95` 这一档配置是当前可接受区间。
3. Stage7 的收益来自温和调参，而不是激进推高 mask 偏置。

### 7.2 当前被明确否定的部分

Stage7S1 也同时说明：

1. 更强的 mask 偏置不会自动继续带来收益。
2. `1.60 / 0.90` 这一档已经超过当前主线最优区间。
3. 当 mask 偏置过强时，不只是 mIoU 会掉，类别覆盖也会开始退化。

### 7.3 对验证机制的再次确认

这一轮 gate 结果也再次证明：

1. full-val gate 是必要的。
2. proxy validation 不能直接替代最终结论。
3. Stage7 的实验规范本身是合理的，因为它成功阻止了更激进配置误入主线。

## 8. 本轮归档动作

本轮已完成以下归档动作：

1. 将 `stage7s1_experiment_report.md` 从阶段性报告更新为最终归档版本。
2. 新增本记录文档，用于单独记录最终 gate 结论与工程分析。
3. 更新 `docs/开发与优化记录/README.md` 索引。

## 9. 后续建议

1. 以 Phase A winner 作为当前 Stage7 候选最优 checkpoint。
2. 下一轮若继续做 S7S2，应围绕 `mask_weight 1.35` 附近做温和微调，而不是继续走更激进方向。
3. 补一轮固定样例的 qualitative 对照，验证模型侧改进是否真的减少了前端“细碎感”。
4. 后续实验仍继续保留 full-val gate，不要只凭训练内曲线做判断。

## 10. 工程结论

Stage7S1 的真正价值不只是“比基线高了约 0.00294”，更重要的是它帮当前主线找到了一个可操作的优化边界：温和的 mask 偏置是有效的，过强的 mask 偏置会开始伤害最终泛化与类别覆盖。这个边界本身，就是下一轮 S7 继续推进时最重要的经验资产。