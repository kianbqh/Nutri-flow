# 27 Stage7S2 结构增强实验规划与启动记录

## 1. 文档目的

本记录用于沉淀 Stage7S2 的规划依据、代码侧改动、启动方式与实验资产位置，确保本轮从 Stage7S1 过渡到新的结构增强实验时，过程与结论都有独立留痕。

## 2. 触发背景

Stage7S1 已经完整结束，并给出明确 gate 结论：

1. 温和 mask 偏置有效。
2. 更激进的 mask 偏置会导致 mIoU 和覆盖率退化。

这说明继续在原有二值 mask 头上只调 loss 权重，边际收益已经开始变小。因此，本轮 S7S2 不再沿用“只调权重”的最小变量策略，而是引入新的训练侧结构增强。

## 3. S7S2 的核心思路

本轮 S7S2 聚焦两个新增点：

1. 将单通道前景 mask head 升级为类别感知的 semantic mask head。
2. 在训练中加入 boundary-aware 辅助损失，直接约束边界连贯性。

这样做的目的，是让优化目标更贴近当前实际问题，即“类别区域边缘和连贯性”，而不是继续把所有非背景类别压缩成一个总前景区域来学习。

## 4. 本轮代码侧改动

本轮已完成以下训练侧接入：

1. `model_trainable.py` 增加 `mask_head_mode`，支持 `binary` 与 `semantic` 两种 mask head 模式。
2. `train_stage5a.py` 增加 `SemanticMaskLoss`。
3. `train_stage5a.py` 增加边界 target 构造与 `BoundaryConsistencyLoss`。
4. `train_stage5a.py` 增加兼容旧 checkpoint 的部分加载逻辑，使 S7S2 能从 Stage7S1 winner 继续启动。
5. `eval_stage5b.py` 增加 `mask_head_mode` 参数，确保可评估新结构 checkpoint。

## 5. 实验规划资产

本轮新增：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s2_plan.md`
2. `nutri-ai-mcp/app/training/run_stage7s2.ps1`
3. `nutri-ai-mcp/app/training/start_stage7s2_detached.ps1`

其中：

1. Phase A 采用较保守的 `boundary_loss_weight=0.10`。
2. Phase B 采用稍强的 `boundary_loss_weight=0.20` 与略高的 `loss_mask_weight`。
3. 仍沿用双阶段 full-val gate 机制，避免 proxy validation 误导最终判断。

## 6. 启动方式

本轮继续沿用 detached 启动方式：

1. TensorBoard 继续挂在 `http://127.0.0.1:6006`
2. Stage7S2 orchestrator 通过 `start_stage7s2_detached.ps1` 后台拉起
3. 编排过程写入 `stage7s2_master.log`

## 7. 本轮启动状态

本轮已经完成实际启动与修正验证，当前状态如下：

1. Stage7S2 orchestrator 已启动，当前有效 PID=`75968`。
2. `stage7s2_master.log` 已写入：
	- `START Stage7S2 pipeline`
	- `START stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep`
3. 当前 stderr 日志已经进入正常训练输出，Phase A 已完成前 100+ 个 batch 的持续训练日志打印。
4. TensorBoard 继续可访问：`http://127.0.0.1:6006`
5. 编排日志目录：`nutri-ai-mcp/weights_by_category/foodseg103/service_logs/`

### 7.1 启动过程中暴露并修复的问题

本轮首次启动没有一把过，实际暴露出两个局部实现问题，但都已在本轮修复：

1. `BoundaryConsistencyLoss` 初版使用 `binary_cross_entropy`，在 AMP/autocast 下不安全，首次启动时报错后已改为 `binary_cross_entropy_with_logits` 形式。
2. `compute_soft_boundary_map` 初版使用原地写入，导致反向传播触发 inplace autograd 错误，随后已改为纯函数式拼接实现。
3. 在继续推进到 epoch 末尾验证时，`evaluate()` 仍按旧的二元返回值解包 `build_semantic_targets()`，导致在第 1 个 epoch 训练结束后进入验证时报出 `too many values to unpack`，随后已修复为匹配当前三元返回结构，并重新拉起 Stage7S2。

也就是说，当前这轮运行不是“首次脚本直接成功”，而是经过三次局部修复后，已经重新进入真实训练状态。

### 7.2 最新实验状态

在修复验证入口解包问题后，Stage7S2 已于 `2026-04-29 00:19` 再次重启。

当前已确认：

1. `stage7s2_master.log` 已写入新一轮 `START Stage7S2 pipeline` 与 `START stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep`。
2. 最新 stderr 日志已经重新进入 Phase A 训练输出，说明这次不是停在启动阶段。
3. 截至本次记录时，尚未重新跑到 full-val 结束，因此当前状态应表述为“Phase A 训练中”，而不是“实验完成”。

## 8. 工程结论

Stage7S2 的意义不只是继续“再跑一个实验”，而是在当前主线已经找到 loss 权重边界之后，正式把优化焦点从“权重偏置”推进到“训练目标与解码结构是否更贴近真实边界问题”。