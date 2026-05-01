# 39 agent个性化营养建议增强记录

## 1. 背景

在现有 Nutri-flow 链路中，agent 已经具备以下基础能力：

1. 先做食物分割与营养估算。
2. 再读取用户历史记录。
3. 再结合健康目标生成 AI 建议。

但在实际结果中，建议文案仍然偏通用，更多是围绕“这顿饭是什么、热量大概多少、下一顿怎么吃”展开，用户侧能够明显感知到的问题有两个：

1. 建议没有稳定体现用户历史记录、健康目标与身体情况。
2. 即使前端输入了年龄、活动量等参数，最终建议里也不一定能看出这些因素被真正参考。

因此本轮目标不是简单“改提示词”，而是把个性化信号从前端输入一路打通到 agent 生成，并保证最终建议中可见。

## 2. 根因分析

### 2.1 个性化信号并未完整进入 MQ 任务

排查发现，RabbitMQ 任务消息 `ImageAnalysisTaskMessage.UserContext` 最初仅包含：

1. `healthGoal`
2. `dailyCalorieTarget`
3. `dietaryRestrictions`

这意味着 agent 在执行时虽然知道用户目标和限制，但并不知道：

1. 年龄
2. 活动量
3. 身高
4. 体重
5. 性别

其中身高、体重、性别在业务库 `users` 表里已有字段，但未被带入分析任务；年龄和活动量甚至没有稳定持久化入口。

### 2.2 前端资料页输入与上传任务之间断链

移动端 `ProfilePage` 中已经有：

1. 年龄输入框
2. 身高输入框
3. 体重输入框
4. 性别选择
5. 活动量选择

但在此前实现中：

1. 保存资料时只写入目标、热量和饮食限制。
2. 上传图片发起分析时没有把年龄、活动量等信息随任务一并发送。

这会造成用户以为自己“已经填过资料”，但 agent 实际拿不到这些参数。

### 2.3 即使 agent 拿到了参数，LLM 也不一定稳定显式输出

在初步增强提示词后，agent 已能将年龄、活动量、BMI 等结构化上下文送入模型，但真实任务结果表明：

1. LLM 有时会吸收这些信息却不显式写出来。
2. 用户最终仍无法确认建议是否真的个性化。

因此需要在 LLM 输出前增加一层“可见性兜底”，确保个性化依据稳定展示给用户。

## 3. 本轮优化目标

本轮优化目标分为三层：

1. 打通年龄、活动量、身高、体重、性别等参数从前端到 agent 的链路。
2. 让 agent 在内部推理时把这些参数与历史记录、健康目标共同参与建议生成。
3. 让最终展示结果中显式出现“个性化参考依据”，确保用户可感知。

## 4. 具体改动

### 4.1 扩展业务消息 userContext

在 `nutri-business/src/main/java/com/nutriflow/mq/ImageAnalysisTaskMessage.java` 中扩展 `UserContext`，新增：

1. `age`
2. `heightCm`
3. `weightKg`
4. `gender`
5. `activityLevel`

同时同步更新 `contracts/image_analysis_task.schema.json`，保证契约层与实现层一致。

### 4.2 上传任务支持随单带入年龄和活动量

在 `nutri-business/src/main/java/com/nutriflow/controller/DietLogController.java` 的上传接口中新增可选参数：

1. `age`
2. `heightCm`
3. `weightKg`
4. `gender`
5. `activityLevel`

上传图片时，业务层会将这些参数与数据库里的用户目标/限制/身体字段合并，构造成完整的 `userContext` 后再投递到 RabbitMQ。

### 4.3 移动端增加本地画像快照，避免年龄与活动量丢失

在 `nutri-mobile/lib/services/profile_context_service.dart` 中新增本地快照服务，用 `SharedPreferences` 存储：

1. 年龄
2. 身高
3. 体重
4. 性别
5. 活动量

设计原因：

1. 当前业务库 `users` 表已有身高、体重、性别，但没有年龄和活动量列。
2. 为避免额外改库，本轮先让年龄和活动量作为“分析任务快照”随单发送。
3. 这样无需扩表，也能先实现稳定个性化建议。

### 4.4 资料页保存与目标助手应用时同步保存快照

在 `nutri-mobile/lib/pages/profile_page.dart` 中：

1. 保存资料时，除调用后端 `updateProfile` 外，同时将年龄/活动量等写入本地快照。
2. 点击“解析并应用”时，也同步把当前年龄/活动量等信息写入本地快照。
3. 页面加载时优先将后端资料与本地快照合并回填，避免用户输入丢失。

### 4.5 上传分析时将快照一并带入

在 `nutri-mobile/lib/services/api_service.dart` 中，上传图片前先读取 `ProfileContextSnapshot`，并把以下字段作为 multipart form 一同上传：

1. `age`
2. `heightCm`
3. `weightKg`
4. `gender`
5. `activityLevel`

这样每次新任务都会携带完整画像快照进入 agent。

### 4.6 强化 agent 内部的个性化推理结构

在 `nutri-agent/app/nodes/fetch_user_memory.py` 中补充用户画像摘要，除目标/热量/限制外，还会加入：

1. 年龄
2. 活动水平
3. 身高
4. 体重
5. 性别
6. BMI 粗略判断

在 `nutri-agent/app/nodes/generate_advice.py` 中新增和增强了以下结构：

1. `Body Condition`：基于年龄、活动量、身高、体重、性别生成身体情况摘要。
2. 年龄阶段理由：例如中年阶段更强调蛋白分配、纤维与血糖稳定。
3. 活动量理由：高活动量更强调恢复所需蛋白与优质碳水，低活动量则更警惕热量盈余。
4. BMI 与目标一致性判断：例如减脂目标下 BMI 偏高时，建议关注稳定热量缺口而非极端节食。
5. 饮食限制代码归一化：修复移动端限制编码与 agent 内部规则不一致的问题。

### 4.7 增加“个性化参考依据”可见性兜底

为解决“LLM 有时参考了参数但不一定写出来”的问题，在 `generate_advice.py` 中新增：

1. `_build_personalization_basis(...)`
2. `_inject_personalization_basis(...)`

最终返回给前端的建议文本顶部会稳定追加一个“个性化参考依据”区块，显式列出：

1. 当前健康目标与每日热量目标
2. 当前餐次参考热量区间
3. 年龄、活动量、性别、BMI
4. 年龄/活动量带来的分析侧重点
5. 历史记录摘要（如最近完成记录数量）

这样即使 LLM 主正文没有稳定复述，用户仍然能看到本次建议为什么是“基于自己”的。

## 5. 运行态问题与处理

在验证阶段发现一个运行态问题：

1. RabbitMQ task consumer 数量异常增大，出现 `consumers=4`。
2. 说明旧版 `nutri-agent` 进程没有被彻底清理，可能与新版进程同时消费队列。

这会导致真实任务被旧进程处理，从而出现：

1. 代码明明已更新，但建议输出仍看不到新逻辑效果。

本轮额外做了以下清理：

1. 枚举所有以 `main.py` 方式运行的历史 Python 进程。
2. 强制结束旧的 agent 进程。
3. 重新执行 `scripts/dev-restart-all.ps1 -SkipDocker`。

清理后健康检查显示：

1. RabbitMQ task consumer 回落为 `consumers=1`

说明后续真实任务由单个最新版 agent 处理，验证结果才可信。

## 6. 验证结果

### 6.1 静态检查

已验证通过：

1. Flutter analyze：
   - `nutri-mobile/lib/services/profile_context_service.dart`
   - `nutri-mobile/lib/services/api_service.dart`
   - `nutri-mobile/lib/pages/profile_page.dart`
2. Python 编译：
   - `nutri-agent/app/nodes/fetch_user_memory.py`
   - `nutri-agent/app/nodes/generate_advice.py`
3. 编辑器错误检查：
   - Java / Dart / Python / JSON 相关改动文件均无新增错误。

### 6.2 真实任务回放验证

使用历史图片重新发起上传任务，并显式附带：

1. `age=46`
2. `heightCm=165`
3. `weightKg=68`
4. `gender=FEMALE`
5. `activityLevel=HIGH`

在清理旧 agent 进程并保证单消费者后，真实任务 `f7559649-d85a-41a3-9b6c-f56ddadabd79` 返回的建议中，已出现显式的“个性化参考依据”区块，并成功匹配到：

1. 年龄
2. 活动量
3. BMI
4. 目标
5. 身体情况

这说明本轮优化已不再停留在“内部使用了这些字段”，而是已经能在最终用户可见结果中稳定体现出来。

## 7. 当前限制

本轮仍有一个已知限制：

1. 年龄与活动量目前作为“分析任务快照”保存在移动端本地，并随上传任务发送。
2. 它们尚未正式入 `users` 表，也未进入 `GET /users/{id}/profile` 的长期后端存储链路。

这意味着：

1. 如果用户换设备或清除本地存储，这两项需要重新输入。
2. 当前实现优先解决“建议真正个性化”和“结果里可见”的问题，而不是先做完整资料建模。

## 8. 结论

本轮 agent 优化的核心成果不是简单修改提示词，而是完成了从“前端输入 -> 业务任务 -> agent 推理 -> 用户可见结果”的完整个性化链路增强。当前营养建议已经能够稳定参考：

1. 用户历史记录
2. 健康目标
3. 每日热量目标
4. 饮食限制
5. 年龄
6. 活动量
7. 身高 / 体重 / 性别 / BMI

并且这些参考理由已经能以显式文本形式出现在结果页中，用户可以直接看到建议为何是为自己生成的。