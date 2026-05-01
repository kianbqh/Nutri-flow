# 44 Stage8S1 最终结果归档与 Gate 分析记录

## 1. 文档目的

本记录用于在 Stage8S1 正式跑完后，完成这轮实验的最终收口，明确：

1. Stage8S1 是否已经完整结束。
2. A/B/C 三阶段的 full-val 结果分别是多少。
3. 为什么最终 winner 是 Phase B，而不是 Phase C。
4. 长尾重采样路线对当前主线的真实意义是什么。

## 2. 触发背景

在 [41_Stage8S1长尾重采样长线实验规划与启动记录.md](41_Stage8S1长尾重采样长线实验规划与启动记录.md) 中，已经完成了 Stage8S1 的规划与后台拉起。

因此，当前缺的已不再是“实验是否启动成功”的解释，而是：

1. 它是否已经完整跑通。
2. 最终 gate 结论是什么。
3. 是否值得把 Stage8S1 winner 提升为新的默认主线。

## 3. 本轮核查资产

本轮最终归档基于以下已落盘资产：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_master.log`
2. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_gate_decision.json`
3. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_eval/stage8s1_eval_tiny_img512_ws_m135_c095_phaseA_40ep_fullval/eval_summary.json`
4. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_eval/stage8s1_eval_tiny_img512_ws_m135_c095_phaseB_30ep_fullval/eval_summary.json`
5. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_eval/stage8s1_eval_tiny_img512_ws_m135_c095_phaseC_20ep_fullval/eval_summary.json`
6. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_gate_decision.json`
7. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_experiment_report.md`
8. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_plan.md`

## 4. 已确认的最终结果

截至本次核查，Stage8S1 已确认完整结束：

1. `stage8s1_master.log` 已完整写出 A/B/C 三阶段训练、三次 full-val 和最终 winner。
2. A/B 两阶段训练均已完成。
3. C 阶段训练已完成。
4. 三次 full-val 均已完成。
5. `stage8s1_gate_decision.json` 已生成最终 winner。

三阶段 full-val 结果为：

1. Phase A：`val_mIoU = 0.31159395430849546`，`nonzero_non_bg_classes = 98`
2. Phase B：`val_mIoU = 0.317085687005668`，`nonzero_non_bg_classes = 97`
3. Phase C：`val_mIoU = 0.31589528891280927`，`nonzero_non_bg_classes = 98`

最终 gate 结果为：

1. `ab_winner = B`
2. `final_winner = B`
3. `epsilon = 0.0005`

## 5. 为什么最终 gate 选择 B

### 5.1 A/B gate 为什么是 B

从纯 mIoU 数值看，Phase B 明显高于 Phase A：

1. `0.317085687005668 - 0.31159395430849546 = 0.00549173269717257`

这个差值显著大于 gate 设定的 `epsilon = 0.0005`，因此 A/B 阶段无需进入 coverage tie-break，Phase B 直接获胜。

### 5.2 最终为什么不是 C

Phase C 的结果虽然把覆盖重新拉回到 `98`，但 mIoU 明显低于 Phase B：

1. `0.317085687005668 - 0.31589528891280927 = 0.00119039809285876`

这个差值同样大于 `epsilon = 0.0005`，因此最终 gate 仍然直接保留 Phase B，而不是因为 C 跑得更久就自动上位。

## 6. 这轮结果说明了什么

### 6.1 Stage8S1 明显优于 Stage7S2 / Stage7S3

与近期两轮结构增强实验相比：

1. Stage7S2 winner：`0.31064224543370683`，覆盖 `96`
2. Stage7S3 winner：`0.3115215702123807`，覆盖 `96`
3. Stage8S1 winner：`0.317085687005668`，覆盖 `97`

这说明：

1. 当前回到稳定主线、只验证长尾重采样，比继续扩大结构变量更值得保留。
2. weighted sampler 不是无效变量，而是确实带来了可见正向收益。

### 6.2 但 Stage8S1 仍未超过 Stage7S1 winner

与当前默认主线相比：

1. Stage7S1 winner：`0.3199287227568812`，覆盖 `98`
2. Stage8S1 winner：`0.317085687005668`，覆盖 `97`

关键差值为：

1. full-val mIoU：`-0.0028430357512132`
2. 覆盖类数：`-1`

这说明 Stage8S1 虽然比 S7S2 / S7S3 更好，但还不够支撑替换 Stage7S1。

### 6.3 Stage8S1 只比 Stage6S6 略高，说明收益仍偏有限

对照上一代稳定基线 Stage6S6 PhaseC：

1. Stage6S6 PhaseC：`0.3169905754109746`，覆盖 `98`
2. Stage8S1 winner：`0.317085687005668`，覆盖 `97`

关键差值为：

1. full-val mIoU：`+0.0000951115946934422`
2. 覆盖类数：`-1`

这说明 weighted sampler 的收益方向是正的，但强度还不大，当前更像“可保留支线”而不是“新默认主线”。

### 6.4 C 阶段暴露出新的 trade-off

Phase C 的表现很有代表性：

1. 覆盖恢复到 `98`。
2. 但 mIoU 从 Phase B 的峰值回撤。

这意味着当前路线下已经出现比较清晰的张力：

1. B 阶段更像是“整体 mIoU 最优点”。
2. C 阶段更像是“覆盖回升，但平均质量回撤”。

这类 trade-off 也说明，当前不能简单用“继续长训”来放大 weighted sampler 的收益。

## 7. 当前状态

截至本记录，Stage8S1 已从“规划与启动”推进到“最终结果归档完成”。

当前对主线的工程判断应表述为：

1. Stage8S1 已完整跑通。
2. 最终 winner 为 Phase B。
3. Stage8S1 明显优于 Stage7S2 / Stage7S3。
4. Stage8S1 略高于 Stage6S6，但仍低于 Stage7S1 winner。
5. 当前默认主线仍应保持 Stage7S1 winner，而不是切换到 Stage8S1。

## 8. 本轮新增产物

本轮已补齐以下正式归档材料：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_experiment_report.md`
2. `docs/开发与优化记录/44_Stage8S1最终结果归档与Gate分析记录.md`

其中：

1. `stage8s1_experiment_report.md` 负责沉淀完整实验设计、结果对比和建议。
2. 本记录负责把 Stage8S1 与现有主线判断连接起来，形成开发过程闭环。

## 9. 工程结论

Stage8S1 的价值，不在于它已经产出了新的默认最优 checkpoint，而在于它把当前优化重点从近期收益不足的结构增强路线，重新拉回到了更贴近 FoodSeg103 长尾特性的采样策略路线。结论也因此更清晰：weighted sampler 值得继续保留为后续支线，但当前证据仍不足以支持替换 Stage7S1 作为新的默认主线。