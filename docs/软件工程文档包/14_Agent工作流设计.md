# Nutri-flow Agent 工作流设计（可实现版）

版本：v1.0  
目标：明确 agent 在“分割 -> 检索 -> 建议 -> 回传”中的状态、分支和降级策略，确保跨层联通稳定。

## 1. 工作流目标

1. 在正常情况下输出个性化建议（FULL 模式）。
2. 在分割失败或识别为空时，仍输出可解释基础建议（CALORIE_ONLY 模式）。
3. 保证结果消息可被 business 层稳定消费并写回任务。

## 2. 状态定义（AgentState）

输入：

1. task_id
2. user_id
3. image_url
4. meal_type
5. callback_routing_key
6. user_context

中间态：

1. segmentation_result
2. detected_labels（标准化标签）
3. workflow_mode（FULL/CALORIE_ONLY）
4. workflow_trace（按节点追加的可读路径）
5. user_memory
6. rag_context

输出：

1. advice_report
2. error

## 3. 节点与责任

1. call_mcp_segmentation
- 调用推理服务 `/v1/segment`。
- 解析 detected_items。
- 标准化提取标签（label/class_name/display_name）。
- 若无标签则设置 workflow_mode=CALORIE_ONLY。

2. fetch_user_memory
- 按 user_id + detected_labels 查询 Chroma 用户记忆。

3. rag_nutrition_lookup
- 按 detected_labels 查询营养知识库。

4. generate_advice
- FULL 模式：LLM 综合分割 + 记忆 + RAG + 画像生成建议。
- CALORIE_ONLY 模式：跳过检索，返回规则化基础建议。

5. publish_result
- 发布包含 taskId/status/adviceReport/segmentationResult 的结果消息。
- 同时透传 workflowMode/detectedLabels/workflowTrace/error，方便业务与前端回放路径。

## 4. 分支规则

路由点：call_mcp_segmentation 之后

1. detected_labels 非空 -> FULL 路径
2. detected_labels 为空 -> CALORIE_ONLY 路径（直接进入 generate_advice）

## 5. 失败与降级

1. MCP 调用失败：segmentation_result 写入 error，workflow_mode=CALORIE_ONLY。
2. Chroma 不可用：记忆或 RAG 文本退化为 unavailable 文案。
3. LLM 不可用：generate_advice 返回按 healthGoal 规则生成的建议。
4. 结果回传失败：日志记录错误，消息层重试由消费/发布侧保证。
5. workflow_trace 作为诊断信息保留，不影响主业务结果写回。

## 6. 消息契约（Agent -> Business）

最小必需字段：

1. taskId
2. userId
3. status
4. adviceReport
5. segmentationResult
6. workflowMode
7. workflowTrace
8. error

status 规则：

1. adviceReport 非空 -> COMPLETED
2. adviceReport 为空 -> FAILED

## 7. 与移动端联通点

1. DietLogController `/v1/diet-logs/{taskId}/status` 返回 analysisResult。
2. 移动端解析 analysisResult.adviceReport + analysisResult.workflowMode + analysisResult.workflowTrace。
3. 移动端结果页可点击实例查看详情，并显示工作流路径。

## 8. 后续优化建议

1. 增加节点耗时统计，便于判断是推理慢还是检索慢。
2. 在 result payload 中增加 confidenceLevel 与 kcalRange，提升可解释性。
3. 对 generate_advice 增加结构化输出（JSON schema），便于前端分段展示。
