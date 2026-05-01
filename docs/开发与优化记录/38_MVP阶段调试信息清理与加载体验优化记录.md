# 38 MVP阶段调试信息清理与加载体验优化记录

## 1. 文档目的

本记录用于沉淀 Nutri-flow 在接近 MVP 冻结阶段，对用户可见调试信息做的一次集中清理，重点说明：

1. 为什么此时要主动删掉任务号、工作流路径和调试标记。
2. 本轮具体删掉了哪些对普通用户无价值的信息。
3. 本轮如何把“分析中”页面改得更贴近真实用户预期。

## 2. 触发背景

随着移动端主链路逐步稳定，当前产品状态已经从“联调优先”转向“MVP 体验优先”。

在此前版本中，界面里还保留了一些明显偏工程联调的信息：

1. 结果页中的任务号。
2. 结果页中的工作流模式与工作流路径。
3. Flutter 右上角 DEBUG 标记。
4. 上传成功后直接提示 taskId。
5. 处理中页面展示 taskId 和偏调试视角的等待文案。
6. Web 历史页中直接展示任务 ID。

这些信息在开发阶段有帮助，但在 MVP 阶段会显著拉低产品完成度，也会打断普通用户对“拍照 -> 等待 -> 看结果”这条路径的自然理解。

## 3. 本轮优化目标

本轮的目标不是改功能逻辑，而是对用户可见信息层做最后一轮收口：

1. 删除所有不面向普通用户的调试信息。
2. 让“分析中”页面给出更符合实际体验的预期提示。
3. 保留必要的结果说明，但不再暴露内部实现路径。

## 4. 本轮改动

### 4.1 关闭 Flutter DEBUG 标记

在 `nutri-mobile/lib/main.dart` 中设置：

1. `debugShowCheckedModeBanner: false`

这样移动端页面右上角不再显示 DEBUG 标志，视觉上更接近正式产品状态。

### 4.2 删除结果页中的调试信息

在 `nutri-mobile/lib/pages/result_page.dart` 中删除了以下用户无感知收益的信息：

1. 任务号展示
2. 任务号复制按钮
3. 工作流模式 Chip
4. 工作流路径整块卡片

同时也清理了与这些展示直接绑定的辅助函数与剪贴板依赖，避免保留无意义代码残留。

### 4.3 优化上传成功后的提示语

在 `nutri-mobile/lib/pages/upload_page.dart` 中，上传成功后的 SnackBar 不再提示 taskId，而改为用户导向文案：

1. `已开始分析，通常 10-20 秒可查看热量结果。`

这一步的目的是把反馈从“系统内部编号”转换为“用户下一步预期”。

### 4.4 优化处理中页面体验

在 `nutri-mobile/lib/pages/processing_page.dart` 中做了三类调整：

1. 删除任务号展示
2. 删除“已等待 xx 秒”这类偏联调性质的说明
3. 把状态文案改成更贴近普通用户的表达

同时新增了基于状态的引导提示：

1. 默认提示通常约 `10-20 秒`完成图片识别、热量计算和建议生成
2. 若等待较久，则提示“这次分析比平时稍久一些，请再等待片刻”
3. 超时或失败时则改为重试导向文案，而不是内部查询语气

### 4.5 清理历史页中的调试信息

在 `nutri-web/src/views/HistoryView.vue` 中删除：

1. `任务ID: {{ item.taskId }}`

虽然这不是移动端 Flutter 页，但它同样是用户可见历史入口中的一部分，继续保留会让整体产品显得仍停留在调试态。

## 5. 涉及文件

本轮涉及以下文件：

1. `nutri-mobile/lib/main.dart`
2. `nutri-mobile/lib/pages/upload_page.dart`
3. `nutri-mobile/lib/pages/processing_page.dart`
4. `nutri-mobile/lib/pages/result_page.dart`
5. `nutri-web/src/views/HistoryView.vue`
6. `docs/开发与优化记录/38_MVP阶段调试信息清理与加载体验优化记录.md`

## 6. 验证动作

### 6.1 Flutter 静态分析

已执行：

1. `flutter analyze lib/main.dart lib/pages/upload_page.dart lib/pages/processing_page.dart lib/pages/result_page.dart`

结果为：

1. `Analyzing 4 items... No issues found!`

### 6.2 编辑器错误检查

对以下文件执行错误检查后，未发现新增问题：

1. `main.dart`
2. `upload_page.dart`
3. `processing_page.dart`
4. `result_page.dart`

### 6.3 前端发布动作

本轮继续沿用受管前端脚本方式发布最新界面：

1. `scripts/frontend-web-down.ps1`
2. `scripts/frontend-web-up.ps1`

避免再依赖不稳定的 `flutter attach` 或临时热重载链路。

## 7. 工程结论

在 MVP 冻结前，界面质量的关键已经不再只是“功能能否跑通”，而是用户看到的内容是否真的围绕用户目标组织。本轮清理说明：

1. 任务号、工作流路径、调试标记这类信息虽然对开发者有价值，但对普通用户几乎没有正向作用。
2. “分析中”页面的核心不是暴露内部状态，而是给用户一个稳定、可信的等待预期。
3. 当产品进入 MVP 阶段后，界面应该更多服务于“理解结果”和“完成任务”，而不是继续服务于联调过程本身。