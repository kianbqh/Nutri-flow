# 45_应用端默认分割模型切换到Stage7S1记录

## 1. 背景

本轮确认应用端当前开发环境默认使用的分割模型，并判断是否需要切换到更新的最优 checkpoint。

排查结果表明：

1. 应用端推理服务并不是自动跟随最新实验 winner。
2. 当前开发环境实际由 `scripts/dev-up.ps1` 中的 `NUTRI_SEG_CHECKPOINT` 控制。
3. 在本次切换前，默认 checkpoint 仍然指向 Stage6S6 PhaseC，而不是已经验证更优的 Stage7S1 winner。

## 2. 切换前后模型

### 2.1 切换前

应用端默认模型：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage6s6/stage6s6_tiny_img512_phaseC_20ep/best_stage6s6_tiny_img512_phaseC_20ep.pth`

对应 full-val 结果：

1. `val_mIoU = 0.3169905754109746`
2. `nonzero_non_bg_classes = 98`

### 2.2 切换后

应用端默认模型已改为：

1. `nutri-ai-mcp/weights_by_category/foodseg103/stage7s1/stage7s1_tiny_img512_mask135_cls095_phaseA_12ep/best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth`

对应 full-val 结果：

1. `val_mIoU = 0.3199287227568812`
2. `nonzero_non_bg_classes = 98`

## 3. 提升幅度

Stage7S1 winner 相比原应用端默认模型 Stage6S6 PhaseC：

1. 绝对提升：`+0.0029381473459066`
2. 相对提升：约 `+0.93%`
3. 类别覆盖：`98 -> 98`，无回退

这意味着：

1. 这次提升不是靠牺牲覆盖换来的。
2. 输入分辨率仍然是 `512`。
3. backbone 仍然是 `swin_tiny_patch4_window7_224`。
4. 对当前推理链路没有新增部署负担。

## 4. 为什么值得切换

本次切换成立的原因很明确：

1. Stage7S1 是当前已验证、已归档、且优于 Stage6S6 的稳定主线 winner。
2. 它在 full-val 上有真实净提升，而不是阶段性 proxy 提升。
3. 它没有带来类别覆盖退化。
4. 它不改变当前线上使用的输入尺寸、backbone 和推理接口，因此切换成本很低。

从工程角度看，这属于“低风险换取稳定净收益”的升级，而不是高风险试验性替换。

## 5. 实际修改

本次修改文件：

1. `scripts/dev-up.ps1`

修改内容：

1. 将默认 `NUTRI_SEG_CHECKPOINT` 从 Stage6S6 PhaseC best 切换为 Stage7S1 Phase A best。

随后执行：

1. `powershell -ExecutionPolicy Bypass -File scripts/dev-restart-all.ps1 -SkipDocker`

使新的 checkpoint 配置进入当前运行态。

## 6. 运行态验证

本次不是只停留在脚本配置修改，而是完成了两步验证：

### 6.1 supervisor 配置验证

重启后生成的 `.runtime/supervisors/inference.ps1` 已确认指向：

1. `best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth`

### 6.2 真实推理验证

使用 `nutri-ai-mcp/data/smoke/images/smoke_001.jpg` 向 `http://127.0.0.1:8001/v1/segment` 发送一次真实推理请求后，返回结果中的 `model_version` 为：

1. `swin-t-bifpn-ca-v1@best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth`

且请求成功返回 `200`，说明当前运行态已经实际使用 Stage7S1 模型完成推理，而不是只改了静态配置。

## 7. 结论

本轮已将应用端默认分割模型从 Stage6S6 PhaseC 切换到 Stage7S1 winner。

这次切换的判断依据是：

1. Stage7S1 相比原默认模型有约 `+0.00294` 的 full-val 提升。
2. 相对提升约 `+0.93%`。
3. 覆盖保持不变。
4. 不增加现有推理部署复杂度。

因此，这次替换是值得的，且已经完成实际生效验证。