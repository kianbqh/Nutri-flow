# 41 Stage8S1 长尾重采样长线实验规划与启动记录

## 1. 背景

在完成 Stage7S1、Stage7S2、Stage7S3 后，当前训练主线结论已经比较明确：

1. Stage7S1 winner 仍是现阶段最优 checkpoint。
2. semantic mask head 路线未超过当前主线。
3. boundary loss 路线比 S7S2 更稳，但仍未跑赢 S7S1。

因此，继续在 head 结构或 boundary loss 上扩大变量范围，已经不是当前最优先的方向。

用户本轮的新要求是：

1. 按之前流程先完成规划落档。
2. 直接启动一个约 8 小时的长线实验。
3. 本次实验要有明确提升预期，并尽量结合 FoodSeg103 数据集论文特点和当前产品落地场景。

## 2. 已确认基线

本轮规划以当前仓库内已验证资产为依据：

1. Stage6S6 PhaseC full-val：`0.3169905754109746`，覆盖 `98`。
2. Stage7S1 winner full-val：`0.3199287227568812`，覆盖 `98`。
3. Stage7S2 winner full-val：`0.31064224543370683`，覆盖 `96`。
4. Stage7S3 winner full-val：`0.3115215702123807`，覆盖 `96`。

当前最合理的起点仍然是：

1. `stage7s1_tiny_img512_mask135_cls095_phaseA_12ep` 的 best checkpoint。

## 3. 根因判断与实验假设

### 3.1 当前还没有被充分验证的变量

排查现有训练代码后发现：

1. `data_loader.py` 中其实已经实现了 `WeightedRandomSampler`。
2. 但当前 Stage5A/Stage7 主训练脚本并没有把这个能力暴露出来。
3. 这意味着现有主线虽然已经有 class-weighted focal loss，但图像级采样仍然是均匀采样。

### 3.2 为什么这件事与 FoodSeg103 论文特征一致

FoodSeg103 数据集论文《A Large-Scale Benchmark for Food Image Segmentation》（ACM MM 2021）强调的是：

1. 食物图像是细粒度 ingredient-level segmentation。
2. 每张图往往同时包含多个食材标签。
3. 数据来自真实 Recipe1M 场景，类别分布天然不均衡。

对当前仓库来说，这意味着真正还没充分打到的点，不是再换一个更重 backbone，而是：

1. 让长尾类别在训练样本层面获得更稳定曝光。
2. 在保持当前稳定部署骨架不变的前提下，减少频繁类对训练后段的主导。

### 3.3 与当前落地场景的匹配关系

当前产品落地链路已经固定在：

1. `Swin-Tiny + 512` 推理主线。
2. 业务系统中以稳定返回、部署一致性和可维护性优先。

因此，本轮实验不选择直接切换更重 backbone，而选择：

1. 保持现有推理架构与输入分辨率。
2. 只引入“长尾重采样”这一低侵入变量。
3. 用较长的多阶段低学习率精修去放大这一变量的收益。

### 3.4 核心假设

本轮 Stage8S1 的核心假设是：

1. 在 Stage7S1 winner 的稳定参数组合上，加入 weighted sampler 可以改善长尾类别曝光。
2. 结合 40+30+20 的长线三阶段精修，full-val mIoU 有机会稳定超过 `0.3199287`。
3. 若该路线成立，收益应同时体现在：
   - 最终 full-val mIoU 提升。
   - 非背景有效类覆盖不退化，最好维持 `>=98`。

## 4. 方案设计

### 4.1 实验 ID

1. 实验 ID：`Stage8S1`
2. 路径定位：`长尾重采样 + 稳定主线长线精修`

### 4.2 起始 checkpoint

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1/stage7s1_tiny_img512_mask135_cls095_phaseA_12ep/best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth`

### 4.3 固定不动的主线参数

为确保变量可解释，本轮保留 Stage7S1 已验证有效的稳定配置：

1. backbone=`swin_tiny_patch4_window7_224`
2. img_size=`512`
3. batch_size=`1`
4. loss_cls_weight=`0.95`
5. loss_mask_weight=`1.35`
6. mask_head_mode=`binary`
7. boundary_loss_weight=`0.0`

### 4.4 本轮新增变量

1. 启用 `--use_weighted_sampler`
2. 采用三阶段长线低学习率精修：
   - Phase A：40 epoch，lr=`2.5e-5`
   - Phase B：30 epoch，lr=`1.5e-5`
   - Phase C：20 epoch，lr=`1.0e-5`

### 4.5 门控策略

1. A/B 阶段完成后，先以 full-val mIoU 做第一轮 gate。
2. 若 mIoU 差值小于 `epsilon=0.0005`，则用 `nonzero_non_bg_classes` 作为 tie-break。
3. Gate winner 再进入 C 阶段。
4. C 阶段完成后，再与 A/B winner 做最终 gate。

## 5. 预计时长

基于 Stage7S1 主日志中的真实耗时：

1. 512 分辨率、batch_size=1、2000 train batches 的单 epoch 耗时约 4 分钟级。
2. 90 epoch 主训练量级约 6 到 7 小时。
3. 再加上 weighted sampler 初始化和三次 full-val，整体预计约 7 到 8 小时。

因此本轮适合作为睡前拉起的整夜实验。

## 6. 本轮新增落地产物

本轮规划阶段新增以下资产：

1. `nutri-ai-mcp/app/training/run_stage8s1.ps1`
2. `nutri-ai-mcp/app/training/start_stage8s1_detached.ps1`
3. `nutri-ai-mcp/weights_by_category/foodseg103/stage8s1_plan.md`
4. `docs/开发与优化记录/41_Stage8S1长尾重采样长线实验规划与启动记录.md`
5. `train_stage5a.py` 已补齐 `--use_weighted_sampler` 参数透传。
6. 启动前已执行一次极小烟雾验证：
   - run_name=`stage8s1_smoke_ws_1ep_1batch`
   - `--use_weighted_sampler` 已成功生效
   - resume checkpoint、日志落盘与 1 epoch 训练均已跑通

## 7. 启动方式

正式启动方式为：

1. 先通过 `start_stage8s1_detached.ps1` 后台拉起 orchestrator。
2. TensorBoard 保持沿用 `6006` 端口。
3. 编排日志写入 `stage8s1_master.log`。
4. 服务日志写入 `weights_by_category/foodseg103/service_logs/`。

## 8. 启动结果

本轮已通过 detached 脚本正式拉起 Stage8S1，当前已确认：

1. orchestrator PID=`44332`
2. TensorBoard `6006` 端口已打开
3. 服务日志目录：`nutri-ai-mcp/weights_by_category/foodseg103/service_logs/`
4. 主日志 `stage8s1_master.log` 已写出：
   - `START Stage8S1 pipeline`
   - `START stage8s1_tiny_img512_ws_m135_c095_phaseA_40ep`
5. `stage8s1/` 目录已创建首个训练子目录：
   - `stage8s1_tiny_img512_ws_m135_c095_phaseA_40ep`
6. orchestrator stderr 日志已开始输出训练初始化信息：
   - class weights 已加载
   - FoodSeg103 train/validation split 已加载

这说明本轮 Stage8S1 已经从“规划完成”进入“正式运行中”状态，而不是停留在脚本准备阶段。

## 9. 工程结论

Stage8S1 的核心价值，不是继续扩大模型结构变量，而是在当前最稳的 S7S1 主线上，补上此前未被真正验证的“图像级长尾重采样”这一训练杠杆。它既贴合 FoodSeg103 的长尾数据特征，也更符合当前产品落地场景对稳定、可部署、可解释优化的要求。