# 24 Stage7S1 掩码连贯性实验规划与启动记录

## 1. 文档目的

本记录用于说明新实验 S7 的规划起点、实验假设、运行方式以及 TensorBoard 观测安排，确保本轮 ai-mcp 层模型优化具备明确目标和可追溯实验资产。

## 2. 问题背景

当前最优模型虽然已经在整体指标和链路可用性上满足系统要求，但从前端交互结果看，仍然存在“局部区域过于细碎”的现象。仅靠前端可视化收敛可以改善观感，但若要从模型侧继续优化，需要围绕 mask 连贯性做进一步实验。

## 3. S7 的核心目标

本轮 S7 聚焦于“掩码连贯性与碎片控制”，目标不是推翻现有 Stage6 主线，而是在 Stage6S6 最优 checkpoint 基础上做短周期、低风险的细调验证：

1. 尝试提升 mask 质量在总损失中的占比。
2. 观察 full-val mIoU 是否能保持不退化。
3. 为后续 qualitative 结果是否更连贯提供一个模型侧验证入口。

## 4. 实验假设

### H1

在 Stage6S6 best checkpoint 基础上，适度提高 `loss_mask_weight`、略微降低 `loss_cls_weight`，能够让模型对前景区域连贯性更敏感。

### H2

如果这种调整不会显著拉低 full-val mIoU 和覆盖率，那么它值得继续作为 Stage7 主线推进。

## 5. 实验设计概述

本轮实验命名为 `Stage7S1`，采用短周期双阶段门控结构：

1. Phase A：温和提升 mask 权重，先看是否出现正向信号。
2. Phase B：在 A 的 best 基础上继续提高 mask 权重，验证更激进的掩码偏置是否仍然可控。
3. A/B 结束后按 full-val 结果进行门控选优。

## 6. 存档与运行规范

本轮继续沿用现有阶段实验规范：

1. 计划文档放在 `nutri-ai-mcp/weights_by_category/foodseg103/`。
2. 训练与评估输出分别落到 `stage7s1/` 与 `stage7s1_eval/`。
3. 编排过程写入 `stage7s1_master.log`。
4. TensorBoard 继续使用 6006 端口，日志按现有 `foodseg103` 目录统一可视化。

## 7. 启动结果

本轮会同步新增：

1. `run_stage7s1.ps1`
2. `start_stage7s1_detached.ps1`
3. `stage7s1_plan.md`

随后通过 detached 脚本拉起 S7S1 和 TensorBoard，便于后台持续训练与浏览器查看。

## 8. 实际启动状态

本轮已完成实际启动验证，当前状态如下：

1. Stage7S1 orchestrator 已启动，PID=`31956`
2. Stage7S1 Phase A 训练进程已启动
3. `stage7s1_master.log` 已写入：
	- `START Stage7S1 pipeline`
	- `START stage7s1_tiny_img512_mask135_cls095_phaseA_12ep`
4. TensorBoard 进程已启动，PID=`78480`
5. TensorBoard stderr 日志已输出：`TensorBoard 2.17.0 at http://0.0.0.0:6006/`
6. 本地访问地址确认可用：`http://127.0.0.1:6006`

需要说明的是，启动脚本里的首次 2 秒端口探测曾返回 `False`，但后续进程和日志复核已经确认这是“服务尚在拉起”的瞬时现象，不是启动失败。
