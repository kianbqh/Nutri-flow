# 30 Stage7S2 完成状态检查与 TensorBoard 恢复记录

## 1. 文档目的

本记录用于沉淀一次“重启后状态恢复”操作，重点确认 Stage7S2 在机器重启前后的实际完成状态，并记录 TensorBoard 服务恢复过程。

## 2. 触发背景

用户反馈机器已重启，相关服务都掉了，因此需要：

1. 重新检查当前实验是否已经跑完。
2. 恢复 TensorBoard 服务，便于继续查看训练与评估曲线。

## 3. 实验状态核查结果

本轮首先核查了 `stage7s2_master.log`、`stage7s2_eval` 目录和 `stage7s2_gate_decision.json`。

确认结果如下：

1. Stage7S2 并不是“重启后中断在半路”，而是已经在重启前完整跑完。
2. 主日志已经写出：
   - `DONE stage7s2_tiny_img512_semask_m100_b010_phaseA_10ep`
   - `DONE stage7s2_eval_tiny_img512_semask_m100_b010_phaseA_10ep_fullval`
   - `DONE stage7s2_tiny_img512_semask_m110_b020_phaseB_8ep`
   - `DONE stage7s2_eval_tiny_img512_semask_m110_b020_phaseB_8ep_fullval`
   - `GATE winner=B phaseA=0.30339578026615355 phaseB=0.31064224543370683`
   - `ALL DONE Stage7S2 pipeline`

因此，这次机器重启掉的不是“正在运行中的实验”，而是 TensorBoard 与相关查看服务。

## 4. 已确认的最终实验结果

`stage7s2_gate_decision.json` 显示：

1. `winner = B`
2. `phaseA_mIoU = 0.30339578026615355`
3. `phaseB_mIoU = 0.31064224543370683`
4. `phaseA_nonzero_non_bg_classes = 95`
5. `phaseB_nonzero_non_bg_classes = 96`

Phase B 的正式 full-val 摘要显示：

1. `val_mIoU = 0.31064224543370683`
2. `nonzero_non_bg_classes = 96`
3. `full_val = true`

## 5. 当前结论

截至本次检查，Stage7S2 的最终状态已经明确：

1. 实验已结束。
2. 最终 gate winner 为 Phase B。
3. 但 Stage7S2 最终结果仍低于 Stage7S1 winner（`0.3199287227568812`）。

因此，当前更合理的工程结论是：

1. Stage7S2 这条“类别感知 mask head + boundary loss”结构增强路线，至少在这轮参数配置下没有超过 Stage7S1 主线。
2. 当前主线最优仍然应保持 Stage7S1 winner，而不是切换到 Stage7S2 winner。

## 6. TensorBoard 恢复结果

本轮检查发现：

1. 重启后 6006 端口未监听。
2. 系统中不存在 TensorBoard 相关进程。

随后已手动重新拉起 TensorBoard，当前状态如下：

1. `TensorBoard 2.17.0 at http://0.0.0.0:6006/`
2. 本地端口探测确认：`TensorBoard6006Open=True`
3. 当前访问地址恢复为：`http://127.0.0.1:6006`

## 7. 工程结论

这次恢复操作说明了一点：实验进程与可视化服务应分开看待。Stage7S2 本体已经完整结束，真正需要恢复的是 TensorBoard 可视化入口，而不是重新触发整条实验编排链路，否则会把已完成实验重新跑一遍。