# 33 Stage7S3 数值失稳排查与重启记录

## 1. 文档目的

本记录用于沉淀一次 Stage7S3 运行中途的数值稳定性排查，明确说明为什么 TensorBoard 中出现 value 为空的现象，并记录对应修复与重启动作。

## 2. 触发背景

在 Stage7S3 启动后，用户检查实验状态时发现 TensorBoard 中对应 value 为空，因此需要判断：

1. 是 TensorBoard 本身没有写入数据。
2. 还是训练已经写入了异常值，导致图上无法正常显示。

## 3. 本轮实际核查结果

本轮首先核查了以下资产：

1. `stage7s3_master.log`
2. `service_logs/stage7s3_orchestrator_stderr.log`
3. 当前 Stage7S3 运行目录的事件与评估文件落盘情况

核查后确认：

1. Stage7S3 确实已经进入 Phase A，而不是未启动。
2. 但在原始首轮运行中，从 `Epoch 1, Batch 10/4983` 开始，`Loss / Cls / Mask / Boundary` 全部变成了 `nan`。
3. 因此，TensorBoard 中的 value 为空，并不是“没跑到数据点”，而是“写入的是非有限值”。

## 4. 为什么会出现 value 为空

本轮最终判断是：S7S3 这次 value 为空的直接原因，不是前端或 TensorBoard UI，而是训练数值已经失稳。

原始日志中已经明确写出：

1. `Epoch 1, Batch 10/4983, Loss: nan, Cls: nan, Mask: nan, Boundary: nan`
2. 后续 batch 持续保持 `nan`

因此，TensorBoard 无法给出有效 scalar value，表面现象就会表现为空值、断点或没有有效曲线。

## 5. 根因判断

本轮对照 Stage7S1 与 S7S3 的差异后，可以把问题收敛到一个很小的变量范围：

1. Stage7S1 同样是 `binary` mask head，并且从同一个 winner checkpoint 继续启动，本身是稳定的。
2. Stage7S3 相比 Stage7S1 的新增变量，核心就是 `boundary_loss_weight` 与对应 boundary loss 路径。
3. 当前 `BoundaryConsistencyLoss` 在 binary head 下原先走的是：
   - `sigmoid(logits)`
   - `compute_soft_boundary_map(prob)`
   - `torch.logit(pred_boundary)`
   - `binary_cross_entropy_with_logits(...)`

这条路径在 resumed binary head 已经较饱和时，数值梯度容易变得不稳定，最终在训练很早期就把参数更新推向非有限值。

## 6. 本轮修复动作

本轮已对 `train_stage5a.py` 做两项修复：

1. 对 binary head 的 boundary loss，改为直接从原始 mask logits 计算边界 logits，而不是再走 `prob -> logit(prob)` 这条更敏感的路径。
2. 在训练循环中加入 `torch.isfinite(loss_total)` 拦截，一旦再次出现非有限值，会直接抛错终止，而不会继续把整轮训练写成 `nan`。

## 7. 修复后验证结果

本轮没有直接盲目重启正式实验，而是先做了两级验证：

1. 极端饱和 binary logits 的 loss 片段测试：loss 有限、梯度有限。
2. 使用 S7S3 Phase A 同参数做 12-batch 短跑验证：
   - `Epoch 1, Batch 10/4983, Loss: 31.4360, Cls: 0.0049, Mask: 0.0193, Boundary: 628.1072`
   - 已不再出现 `nan`

这说明修复后的路径至少已经通过最关键的“第一个日志点不炸掉”验证。

## 8. 当前状态

在完成修复和短跑验证后，本轮已重新拉起正式 Stage7S3 orchestrator。

当前应将 Stage7S3 状态表述为：

1. 首轮运行已确认数值失稳。
2. 原因已定位到 binary head 下的 boundary loss 数值路径。
3. 代码已修复并完成窄验证。
4. 正式 S7S3 已重新启动，继续进入 Phase A。

## 9. 工程结论

这次问题说明一个关键点：TensorBoard 的“空 value”不一定代表没有写日志，也可能是训练已经写入了 `nan`。对当前 Stage7S3 而言，真正的问题是数值稳定性，而不是可视化链路本身。加入 fail-fast 非有限值拦截后，后续再出现类似问题时，就不会再让实验静默跑坏很久才被发现。