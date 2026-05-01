# 35 Stage7S3 最终结果归档与 Gate 分析记录

## 1. 文档目的

本记录用于在 Stage7S3 正式跑完后，完成这轮实验的最终收口，明确：

1. Stage7S3 是否已经完整结束。
2. A/B 两阶段的 full-val 结果分别是多少。
3. gate 为什么最终选择 Phase A。
4. 这轮最小侵入式 boundary loss 路线，对当前主线究竟意味着什么。

## 2. 触发背景

在 [33_Stage7S3数值失稳排查与重启记录.md](33_Stage7S3数值失稳排查与重启记录.md) 中，已经完成了 S7S3 首轮数值失稳的定位、修复和重启。

因此，当前缺的已不再是“为什么 value 为空”的解释，而是：

1. 修复后的正式 S7S3 是否已经完整跑通。
2. 最终 gate 结论是什么。
3. 是否值得把 S7S3 winner 提升为新主线。

## 3. 本轮核查资产

本轮最终归档基于以下已落盘资产：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_master.log`
2. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_gate_decision.json`
3. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_eval/stage7s3_eval_tiny_img512_binmask135_b005_phaseA_10ep_fullval/eval_summary.json`
4. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_eval/stage7s3_eval_tiny_img512_binmask135_b010_phaseB_8ep_fullval/eval_summary.json`
5. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_gate_decision.json`
6. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_experiment_report.md`
7. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_plan.md`

## 4. 已确认的最终结果

截至本次核查，Stage7S3 已确认完整结束：

1. `stage7s3_master.log` 已写出 `ALL DONE Stage7S3 pipeline`。
2. Phase A 与 Phase B 训练均已完成。
3. 两次 full-val 均已完成。
4. `stage7s3_gate_decision.json` 已生成最终 winner。

两阶段 full-val 结果为：

1. Phase A：`val_mIoU = 0.3115215702123807`，`nonzero_non_bg_classes = 96`
2. Phase B：`val_mIoU = 0.3118434845920488`，`nonzero_non_bg_classes = 95`

最终 gate 结果为：

1. `winner = A`
2. `epsilon = 0.0005`

## 5. 为什么 gate 最终选择 A

从纯 mIoU 数值看，Phase B 确实略高于 Phase A：

1. `0.3118434845920488 - 0.3115215702123807 = 0.0003219143796681`

但这个差值小于 gate 设定的 `epsilon = 0.0005`，因此不能直接以 mIoU 更高判胜，而要进入第二决策条件：

1. 对比 `nonzero_non_bg_classes`
2. Phase A = `96`
3. Phase B = `95`

因此，Stage7S3 最终 winner 不是 Phase B，而是覆盖更稳的 Phase A。

## 6. 这轮结果说明了什么

### 6.1 S7S3 比 S7S2 更接近主线

与 Stage7S2 winner 相比，S7S3 的 A/B 两个阶段都表现出更温和、更稳定的特征：

1. Stage7S2 winner（Phase B）：`0.31064224543370683`，覆盖 `96`
2. Stage7S3 Phase A：`0.3115215702123807`，覆盖 `96`
3. Stage7S3 Phase B：`0.3118434845920488`，覆盖 `95`

这说明“回到 binary head 主线，只单独引入低权重 boundary loss”确实比 S7S2 的 `semantic head + boundary loss` 更合理。

### 6.2 但 S7S3 仍未超过 Stage7S1 winner

与当前主线最佳结果相比：

1. Stage7S1 winner：`0.3199287227568812`，覆盖 `98`
2. Stage7S3 Phase A：差值 `-0.0084071525445005`，覆盖 `-2`
3. Stage7S3 Phase B：差值 `-0.0080852381648324`，覆盖 `-3`

这说明最小侵入式 boundary 路线虽然比 S7S2 更稳，但仍没有把整体 full-val 拉回 Stage7S1 的水平。

### 6.3 更强 boundary 权重并没有带来更好的综合收益

Phase B 的 mIoU 比 Phase A 略高，但覆盖更差，且增幅不足以跨过 epsilon。这个结果说明：

1. `boundary_loss_weight=0.10` 相比 `0.05` 确实还能继续推高一点局部指标。
2. 但这点提升不够稳，已经开始伴随类别覆盖退化。
3. 在当前主线上，继续加大 boundary 权重的收益风险比并不理想。

## 7. 本轮新增产物

本轮已补齐以下正式归档材料：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_experiment_report.md`
2. `docs/开发与优化记录/35_Stage7S3最终结果归档与Gate分析记录.md`

其中：

1. `stage7s3_experiment_report.md` 负责沉淀完整实验设计、结果对比和建议。
2. 本记录负责把 S7S3 与此前的数值排查、主线判断连接起来，形成开发过程闭环。

## 8. 当前状态

截至本记录，Stage7S3 已从“启动记录”“数值失稳排查记录”推进到“最终结果归档完成”的状态。

当前对主线的工程判断应表述为：

1. S7S3 已完整跑通。
2. 最终 winner 为 Phase A。
3. S7S3 优于 S7S2 winner，但仍低于 Stage7S1 winner。
4. 当前默认主线仍应保持 Stage7S1 winner，而不是切换到 S7S3 winner。

## 9. 工程结论

Stage7S3 的价值，在于它把 boundary-aware 路线从“结构变化过大、无法归因”的 S7S2，收敛成了一次变量可解释、结果可比较的最小侵入式验证。结论也因此更清晰：boundary loss 本身不是完全无效，但在当前主线下，它带来的增益还不足以支持替换 Stage7S1 作为新的默认最优 checkpoint。