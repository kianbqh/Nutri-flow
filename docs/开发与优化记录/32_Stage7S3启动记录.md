# 32 Stage7S3 启动记录

## 1. 文档目的

本记录用于沉淀 Stage7S3 的实际启动动作、当前编排方案与启动后核查结果，确保本轮从方案收敛进入真实执行时有独立留痕。

## 2. 触发背景

在 Stage7S2 最终归档与 S7S3 规划完成后，用户明确要求开始运行 S3。

因此，本轮目标不再是继续讨论方案，而是把 S7S3 训练编排脚本补齐并实际拉起。

## 3. 本轮启动前的控制判断

本轮先核对了现有训练入口，确认：

1. `train_stage5a.py` 已经支持 `mask_head_mode=binary`。
2. `train_stage5a.py` 已经支持 `boundary_loss_weight`。
3. `eval_stage5b.py` 已经支持 `mask_head_mode` 参数。
4. 从 Stage7S1 winner 继续启动所需的兼容加载逻辑已经存在。

因此，S7S3 不需要再修改 Python 训练逻辑，只需要新增 Stage7S3 的编排与 detached 启动脚本。

## 4. 本轮新增启动资产

本轮新增：

1. `nutri-ai-mcp/app/training/run_stage7s3.ps1`
2. `nutri-ai-mcp/app/training/start_stage7s3_detached.ps1`

其中：

1. Phase A：`stage7s3_tiny_img512_binmask135_b005_phaseA_10ep`
2. Phase B：`stage7s3_tiny_img512_binmask135_b010_phaseB_8ep`
3. gate 输出：`stage7s3_gate_decision.json`
4. 主日志：`stage7s3_master.log`

## 5. 当前 S7S3 设计

本轮执行的 S7S3 采用“最小侵入式边界增强”策略：

1. 起点回到 Stage7S1 winner，而不是 Stage7S2 winner。
2. 保持 `mask_head_mode=binary`。
3. 保持 `loss_cls_weight=0.95`、`loss_mask_weight=1.35`。
4. 只新增边界损失项。

参数为：

1. Phase A：`boundary_loss_weight=0.05`，`lr=1.5e-5`，`epochs=10`
2. Phase B：`boundary_loss_weight=0.10`，`lr=1.0e-5`，`epochs=8`

## 6. 启动后核查目标

本轮启动后重点检查：

1. detached orchestrator 是否已成功拉起。
2. `stage7s3_master.log` 是否已写出 `START Stage7S3 pipeline`。
3. 是否已经进入 Phase A 训练，而不是卡在脚本或参数错误阶段。
4. TensorBoard 是否继续可访问。

## 7. 当前状态

截至本记录更新时，Stage7S3 已成功启动并进入 Phase A。

当前已确认：

1. detached 启动脚本已成功返回，并拉起后台 orchestrator，启动时 PID=`23540`。
2. `stage7s3_master.log` 已写入：
	- `START Stage7S3 pipeline`
	- `START stage7s3_tiny_img512_binmask135_b005_phaseA_10ep`
3. 当前 orchestrator stderr 日志为空，说明暂未出现脚本级报错。
4. TensorBoard 继续可用，端口探测结果为 `TensorBoard6006Open=True`。

因此，本轮 Stage7S3 当前应表述为“已成功启动，正在执行 Phase A”，而不是“仅完成方案准备”。