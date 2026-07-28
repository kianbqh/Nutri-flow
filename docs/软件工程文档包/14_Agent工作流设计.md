# Agent Workflow Design

Version: v1.1

The Nutri-flow agent consumes image-analysis tasks from RabbitMQ, calls the
segmentation service, enriches the result with user context and nutrition
knowledge, generates advice, and publishes the final result back to the
business service.

## Flow

```text
RabbitMQ task
    -> call_mcp_segmentation
    -> hydrate_context
        -> fetch_user_memory
        -> rag_nutrition_lookup
    -> generate_advice
    -> publish_result
```

Despite the historical node name `call_mcp_segmentation`, the production path
uses the FastAPI REST endpoint `/v1/segment`. The model service also exposes an
MCP SSE tool interface for protocol experiments.

## State

Input fields:

- `task_id`
- `user_id`
- `image_url`
- `image_base64`
- `meal_type`
- `callback_routing_key`
- `user_context`

Intermediate fields:

- `segmentation_result`
- `detected_labels`
- `workflow_mode`
- `workflow_trace`
- `user_memory`
- `rag_context`

Output fields:

- `advice_report`
- `error`

## Modes

- `FULL`: food labels are detected, so the agent uses segmentation, memory,
  nutrition retrieval, and advice generation.
- `CALORIE_ONLY`: segmentation is empty or degraded, so the agent returns
  rule-based fallback advice instead of failing the whole user flow.

## Failure Handling

- Segmentation service failure: retry/self-heal if local, then local inference
  fallback if possible.
- Chroma unavailable: continue with fallback memory or nutrition text.
- LLM unavailable: return deterministic rule-based advice.
- Result publishing failure: handled by the RabbitMQ consumer retry logic.

## Result Contract

The agent publishes:

- `taskId`
- `userId`
- `status`
- `adviceReport`
- `segmentationResult`
- `workflowMode`
- `detectedLabels`
- `workflowTrace`
- `error`

`workflowTrace` is kept for debugging and demo explanation; it should not block
the main user-facing result.
