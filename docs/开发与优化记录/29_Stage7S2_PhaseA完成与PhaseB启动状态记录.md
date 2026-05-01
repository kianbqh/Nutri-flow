# 29 Stage7S2 Phase A 完成与 Phase B 启动状态记录

## 1. 文档目的

本记录用于沉淀本轮对 Stage7S2 的最新状态检查结果，重点确认 Phase A 是否已经完整完成、Phase A full-val 是否已经生成，以及当前实验是否已经进入 Phase B。

## 2. 本轮检查范围

本轮主要检查了以下资产：

1. [nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_master.log](nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_master.log)
2. [nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_eval/stage7s2_eval_tiny_img512_semask_m100_b010_phaseA_10ep_fullval/eval_summary.json](nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_eval/stage7s2_eval_tiny_img512_semask_m100_b010_phaseA_10ep_fullval/eval_summary.json)
3. [nutri-ai-mcp/weights_by_category/foodseg103/stage7s2/stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep/per_class_iou_history.jsonl](nutri-ai-mcp/weights_by_category/foodseg103/stage7s2/stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep/per_class_iou_history.jsonl)
4. 当前 Stage7S2 orchestrator 与训练进程状态

## 3. 当前实验状态

截至本次检查，Stage7S2 已从“Phase A 训练中”推进到以下状态：

1. Phase A `stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep` 已完成。
2. Phase A full-val `stage7s2_eval_tiny_img512_semask_m100_b010_phaseA_10ep_fullval` 已完成。
3. 当前实验已经进入 Phase B `stage7s2_tiny_img512_semask_m110_b020_phaseB_8ep`。
4. gate 文件尚未生成，因此整个 Stage7S2 还没有结束。

## 4. 主日志确认结果

主日志当前已经明确写出：

1. `DONE stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep`
2. `DONE stage7s2_eval_tiny_img512_semask_m100_b010_phaseA_10ep_fullval`
3. `START stage7s2_tiny_img512_semask_m110_b020_phaseB_8ep`

这说明当前状态已经不是“只有训练在跑”，而是 Phase A 整段已经闭环，Phase B 已经开始接续执行。

## 5. Phase A 已确认结果

### 5.1 Phase A full-val 摘要

`eval_summary.json` 显示：

1. `val_mIoU = 0.30339578026615355`
2. `nonzero_non_bg_classes = 95`
3. `full_val = true`

### 5.2 Phase A 训练内验证情况

从 `per_class_iou_history.jsonl` 可见：

1. epoch 1 的训练内验证 mIoU 为 `0.288800510269718`
2. epoch 10 的训练内验证 mIoU 为 `0.29274263200659295`

这说明 Phase A 至少在训练内验证层面没有出现明显的大幅跳升，整体增益较温和。

## 6. 当前阶段判断

当前已经能得到一个明确判断：

1. Stage7S2 至少已经具备了第一份正式 full-val 结果。
2. 这份 Phase A full-val 结果暂时低于 Stage7S1 winner 的 `0.3199287227568812`。
3. 覆盖类数也降到了 `95`，低于此前预期的 `97-98` 区间。

因此，就当前已知情况而言，S7S2 Phase A 还没有证明自己优于 Stage7S1 winner。

## 7. 当前运行态

本轮检查到以下活跃进程：

1. orchestrator 进程仍在运行。
2. 当前活跃 Python 进程已经切换到 Phase B 的 `train_stage5a.py`。

这说明实验链路没有中断，而是在按计划继续推进到第二阶段。

## 8. 当前尚未完成的部分

截至本次检查，以下内容尚未完成：

1. Phase B 训练
2. Phase B full-val
3. Stage7S2 最终 gate 决策

因此，现在还不能把 Stage7S2 写成终版结论，只能说“Phase A 已结束，且当前结果偏弱，等待 Phase B 与最终 gate 再定”。

## 9. 工程结论

本轮状态检查表明，Stage7S2 已经真正进入有结果可看的阶段，但第一份正式 full-val 信号并不强。当前更合理的态度不是提前判死，也不是误判成功，而是继续让 Phase B 跑完，再用 gate 决定这条结构增强路线是否值得保留。