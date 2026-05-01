# 28 Stage7S2 实验状态检查记录

## 1. 文档目的

本记录用于沉淀本轮对 Stage7S2 当前实验状态的核查结果，明确它此刻处于哪个阶段、是否已经产生正式评估资产，以及目前能得到哪些早期信号。

## 2. 核查范围

本轮主要检查了以下实验资产与运行态：

1. [nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_master.log](nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_master.log)
2. [nutri-ai-mcp/weights_by_category/foodseg103/service_logs/stage7s2_orchestrator_stderr.log](nutri-ai-mcp/weights_by_category/foodseg103/service_logs/stage7s2_orchestrator_stderr.log)
3. [nutri-ai-mcp/weights_by_category/foodseg103/stage7s2](nutri-ai-mcp/weights_by_category/foodseg103/stage7s2)
4. Stage7S2 相关 orchestrator 与训练进程状态

## 3. 当前实验状态

截至本次检查，Stage7S2 的最新状态是：

1. 最新一轮实验已重新启动。
2. 当前仍处于 Phase A 训练阶段。
3. 还没有进入 Phase A full-val 结束后的正式归档阶段。
4. 还没有生成 Stage7S2 的 gate 文件。

对应主日志可见：

1. 早先三次启动都已失败并留下 FAIL 记录。
2. 最新一轮已再次写入新的 START 记录。
3. 当前尚未出现新的 DONE、GATE 或 ALL DONE。

## 4. 当前已确认的运行态证据

本轮检查到以下活跃进程：

1. orchestrator 进程仍在运行，PID 为 70064。
2. Stage7S2 的训练进程仍在运行，PID 为 64744。

这说明当前不是“后台脚本已退出但日志没刷新”，而是训练链路确实仍在继续推进。

## 5. 当前已产出的阶段性结果

虽然还没有 full-val 摘要和 gate 文件，但当前训练日志已经给出一个早期信号：

1. 第 1 个 epoch 已完成。
2. 第 1 个 epoch 的训练平均 loss 为 7.9311。
3. 第 1 个 epoch 结束后的验证日志给出 mIoU 为 0.2888。
4. 当前已经保存了 epoch 1 checkpoint 和当前 best checkpoint。
5. 随后日志已经进入 Epoch 2，并持续打印 batch 日志。

这意味着当前实验已经越过“只能启动不能训练”的阶段，也已经越过“训练完第 1 个 epoch 但验证崩掉”的阶段。

## 6. 当前尚未产出的实验资产

截至本次检查，以下资产仍不存在：

1. `stage7s2_eval` 下的正式 `eval_summary.json`
2. `stage7s2_gate_decision.json`
3. Phase B 相关训练与评估产物

因此，当前还不能把这轮结果写成正式实验分析，只能把它视为“Phase A 正在推进中的状态检查”。

## 7. 当前结论

本轮状态检查可以明确三件事：

1. Stage7S2 目前没有停在旧的失败状态，而是已经重新恢复运行。
2. 当前实验仍处于 Phase A 训练中，尚未跑到 full-val 和 gate。
3. 目前唯一可报告的数值信号是 epoch 1 后的早期验证 mIoU 0.2888，这个数值还不足以拿来和 Stage7S1 winner 做正式结论比较。

## 8. 后续建议

1. 继续让当前这轮 Stage7S2 跑下去，不要在 Phase A 未完成前提前截断。
2. 等 Phase A full-val 出来后，再做第一次正式阶段分析。
3. 若后续 master log 写出 DONE Phase A 与评估摘要，再单独补一份阶段性结果归档文档。