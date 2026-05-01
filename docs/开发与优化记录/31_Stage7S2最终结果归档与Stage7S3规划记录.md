# 31 Stage7S2 最终结果归档与 Stage7S3 规划记录

## 1. 文档目的

本记录用于完成两件事：

1. 将 Stage7S2 从“中间状态记录”正式收口为最终结果归档。
2. 基于已确认结论，给出下一轮 Stage7S3 的收敛规划，而不是继续在未收敛方向上扩大试验面。

## 2. 触发背景

在上一轮状态检查与 TensorBoard 恢复后，Stage7S2 的完成状态已经明确：

1. 实验已完整结束。
2. gate winner 已确定为 Phase B。
3. 但最终结果仍低于 Stage7S1 winner。

因此，当前不再缺“状态判断”，而是需要两项正式产物：

1. 一份可直接纳入实验资产目录的 Stage7S2 终版报告。
2. 一份更有希望的 S7S3 规划文档。

## 3. 本轮核查与归档资产

本轮基于以下已落盘资产完成整理：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_master.log`
2. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_gate_decision.json`
3. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_eval/stage7s2_eval_tiny_img512_semask_m100_b010_phaseA_10ep_fullval/eval_summary.json`
4. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_eval/stage7s2_eval_tiny_img512_semask_m110_b020_phaseB_8ep_fullval/eval_summary.json`
5. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1_gate_decision.json`
6. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_plan.md`

## 4. 已确认的最终结果

Stage7S2 最终结论如下：

1. Phase A full-val：`0.30339578026615355`，覆盖 `95`
2. Phase B full-val：`0.31064224543370683`，覆盖 `96`
3. Gate winner：`B`
4. 但 Stage7S2 winner 仍低于 Stage7S1 winner `0.3199287227568812`

因此，本轮可以形成一个明确工程判断：

1. S7S2 内部并非完全无效，Phase B 相比 Phase A 仍有正向提升。
2. 但整条 `semantic mask head + boundary loss` 路线，当前还没有跑赢现有主线。

## 5. 为什么 S7S3 不应直接延续 S7S2 路线

如果继续沿着 S7S2 的思路扩大实验，当前风险很高，原因有三点：

1. S7S2 同时改变了 head 结构和损失项，变量耦合过重，不利于归因。
2. semantic head 切换后，类别覆盖已经从 `98` 下滑到 `95/96`。
3. 当前真正显露出正向信号的更像是 boundary 约束，而不是 semantic head 本身。

因此，更合理的 S7S3 不是“更强的 semantic head 版本”，而是“回到已验证主线，只单独保留 boundary 约束”这一条更小变量方案。

## 6. 本轮新增产物

本轮已新增两份正式文档：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_experiment_report.md`
2. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s3_plan.md`

其中：

1. `stage7s2_experiment_report.md` 负责把 S7S2 终版结果、对比、原因分析和结论完整收口。
2. `stage7s3_plan.md` 负责定义下一轮最小侵入式边界增强路线。

## 7. S7S3 的收敛方向

当前 S7S3 采用如下思路：

1. 起点回到 Stage7S1 winner，而不是 Stage7S2 winner。
2. 保持 `mask_head_mode=binary`，不再继续改 semantic head。
3. 保持 `loss_mask_weight=1.35`、`loss_cls_weight=0.95` 这一组已验证主线参数。
4. 只新增低权重 `boundary_loss_weight`，通过 A/B 两阶段验证其真实价值。

这种做法的好处是：

1. 变量更少，更容易归因。
2. 风险更低，不会一次性打乱当前主线稳定性。
3. 若仍无收益，就可以更有把握地停止这条边界增强路线，而不是一直怀疑是结构切换方式有问题。

## 8. 当前状态

截至本记录：

1. Stage7S2 终版报告已补齐。
2. Stage7S3 计划已补齐。
3. 开发记录索引已更新。
4. 尚未启动 Stage7S3 训练流程。

这意味着当前已经具备“随时可启动下一轮”的文档准备状态，但还没有实际消耗算力重新开跑。

## 9. 工程结论

Stage7S2 的价值不在于它直接产出了新的主线 winner，而在于它帮助当前主线识别出了一条更清晰的决策边界：边界约束值得继续研究，但 semantic head 切换不应和边界约束一起作为默认推进方向。基于这个边界收敛出来的 Stage7S3，才是下一轮更值得执行的方案。