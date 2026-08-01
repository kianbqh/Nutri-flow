package com.nutriflow.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class TaskTraceService {

    private static final ZoneId REPORTING_ZONE = ZoneId.of("Asia/Shanghai");
    private static final List<StageDefinition> STAGES = List.of(
            new StageDefinition("UPLOAD", "接收上传", "Gateway / API"),
            new StageDefinition("QUEUE", "进入任务队列", "RabbitMQ"),
            new StageDefinition("AGENT", "Agent 接收", "Nutri Agent"),
            new StageDefinition("SEGMENTATION", "食物分割", "Inference"),
            new StageDefinition("ADVICE", "营养建议", "Agent / LLM"),
            new StageDefinition("RESULT_QUEUE", "返回结果队列", "RabbitMQ"),
            new StageDefinition("DATABASE", "写入结果", "Business / MySQL")
    );

    private final JdbcTemplate jdbcTemplate;

    public void recordEvent(
            String taskId,
            String stage,
            String state,
            String serviceName,
            String detail,
            Double durationMs
    ) {
        if (taskId == null || taskId.isBlank()) {
            return;
        }
        try {
            jdbcTemplate.update("""
                    INSERT INTO task_trace_events
                      (task_id, stage, state, service_name, detail, duration_ms)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    taskId,
                    normalized(stage, 32, "UNKNOWN"),
                    normalized(state, 16, "RUNNING"),
                    normalized(serviceName, 32, "unknown"),
                    clipped(detail, 512),
                    durationMs
            );
        } catch (Exception exception) {
            log.warn("Task trace event was not persisted task_id={} stage={}: {}",
                    taskId, stage, exception.getMessage());
        }
    }

    public List<Map<String, Object>> recentTasks(int requestedLimit) {
        int limit = Math.max(5, Math.min(requestedLimit, 50));
        return jdbcTemplate.query("""
                SELECT d.task_id, d.meal_type, d.logged_at, d.analysis_result,
                       MAX(e.occurred_at) AS last_event_at
                FROM diet_logs d
                LEFT JOIN task_trace_events e ON e.task_id = d.task_id
                GROUP BY d.id, d.task_id, d.meal_type, d.logged_at, d.analysis_result
                ORDER BY d.logged_at DESC
                LIMIT ?
                """, (rs, rowNum) -> {
            Map<String, Object> task = new LinkedHashMap<>();
            task.put("taskId", rs.getString("task_id"));
            task.put("mealType", rs.getString("meal_type"));
            task.put("status", resultStatus(rs.getString("analysis_result")));
            task.put("startedAt", timestamp(rs.getTimestamp("logged_at")));
            task.put("updatedAt", timestamp(rs.getTimestamp("last_event_at")));
            return task;
        }, limit);
    }

    public Map<String, Object> taskTrace(String taskId) {
        List<Map<String, Object>> taskRows = jdbcTemplate.query("""
                SELECT task_id, meal_type, logged_at, analysis_result
                FROM diet_logs WHERE task_id = ? LIMIT 1
                """, (rs, rowNum) -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("taskId", rs.getString("task_id"));
            row.put("mealType", rs.getString("meal_type"));
            row.put("startedAtRaw", rs.getTimestamp("logged_at"));
            row.put("analysisResult", rs.getString("analysis_result"));
            return row;
        }, taskId);

        if (taskRows.isEmpty()) {
            return null;
        }

        Map<String, Object> taskRow = taskRows.getFirst();
        Timestamp startedAt = (Timestamp) taskRow.get("startedAtRaw");
        String taskStatus = resultStatus((String) taskRow.get("analysisResult"));
        List<TraceEvent> events = queryEvents(taskId);
        Map<String, TraceEvent> latestByStage = new LinkedHashMap<>();
        for (TraceEvent event : events) {
            latestByStage.put(event.stage(), event);
        }

        boolean legacyCompleted = events.isEmpty() && !"PENDING".equals(taskStatus);
        int furthestIndex = -1;
        for (int index = 0; index < STAGES.size(); index++) {
            if (latestByStage.containsKey(STAGES.get(index).code())) {
                furthestIndex = index;
            }
        }

        List<Map<String, Object>> stageViews = new ArrayList<>();
        int currentStageIndex = 0;
        for (int index = 0; index < STAGES.size(); index++) {
            StageDefinition definition = STAGES.get(index);
            TraceEvent event = latestByStage.get(definition.code());
            String stageStatus = "WAITING";
            boolean inferred = false;

            if (legacyCompleted || (index < furthestIndex && event == null)) {
                stageStatus = "COMPLETED";
                inferred = true;
            }
            if (event != null) {
                stageStatus = event.state();
            }
            if ("DATABASE".equals(definition.code()) && !"PENDING".equals(taskStatus)) {
                stageStatus = taskStatus;
                inferred = event == null;
            }

            if ("RUNNING".equals(stageStatus) || "FAILED".equals(stageStatus)) {
                currentStageIndex = index;
            } else if ("COMPLETED".equals(stageStatus) && index < STAGES.size() - 1) {
                currentStageIndex = Math.max(currentStageIndex, index + 1);
            }

            Map<String, Object> stageView = new LinkedHashMap<>();
            stageView.put("code", definition.code());
            stageView.put("label", definition.label());
            stageView.put("service", definition.service());
            stageView.put("status", stageStatus);
            stageView.put("detail", event == null ? null : event.detail());
            stageView.put("occurredAt", event == null ? null : timestamp(event.occurredAt()));
            stageView.put("durationMs", event == null ? null : event.durationMs());
            stageView.put("inferred", inferred);
            stageViews.add(stageView);
        }

        if ("COMPLETED".equals(taskStatus) || "FAILED".equals(taskStatus)) {
            currentStageIndex = STAGES.size() - 1;
        }

        Timestamp lastEventAt = events.isEmpty()
                ? startedAt
                : events.getLast().occurredAt();
        long wallClockElapsedMs = Math.max(0, Duration.between(
                startedAt.toLocalDateTime(),
                ("PENDING".equals(taskStatus) ? LocalDateTime.now() : lastEventAt.toLocalDateTime())
        ).toMillis());
        long measuredStageMs = Math.round(events.stream()
                .map(TraceEvent::durationMs)
                .filter(value -> value != null && value > 0)
                .mapToDouble(Double::doubleValue)
                .sum());
        long elapsedMs = Math.max(wallClockElapsedMs, measuredStageMs);
        boolean stalled = "PENDING".equals(taskStatus)
                && Duration.between(lastEventAt.toLocalDateTime(), LocalDateTime.now()).toSeconds() >= 60;

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("taskId", taskId);
        response.put("mealType", taskRow.get("mealType"));
        response.put("status", taskStatus);
        response.put("currentStage", STAGES.get(currentStageIndex).code());
        response.put("currentStageLabel", STAGES.get(currentStageIndex).label());
        response.put("startedAt", timestamp(startedAt));
        response.put("updatedAt", timestamp(lastEventAt));
        response.put("elapsedMs", elapsedMs);
        response.put("stalled", stalled);
        response.put("stages", stageViews);
        response.put("events", events.stream().map(this::eventView).toList());
        return response;
    }

    private List<TraceEvent> queryEvents(String taskId) {
        return jdbcTemplate.query("""
                SELECT stage, state, service_name, detail, duration_ms, occurred_at
                FROM task_trace_events
                WHERE task_id = ?
                ORDER BY occurred_at ASC, id ASC
                """, (rs, rowNum) -> new TraceEvent(
                rs.getString("stage"),
                rs.getString("state"),
                rs.getString("service_name"),
                rs.getString("detail"),
                rs.getObject("duration_ms") == null ? null : rs.getDouble("duration_ms"),
                rs.getTimestamp("occurred_at")
        ), taskId);
    }

    private Map<String, Object> eventView(TraceEvent event) {
        Map<String, Object> view = new LinkedHashMap<>();
        view.put("stage", event.stage());
        view.put("state", event.state());
        view.put("service", event.service());
        view.put("detail", event.detail());
        view.put("durationMs", event.durationMs());
        view.put("occurredAt", timestamp(event.occurredAt()));
        return view;
    }

    private String resultStatus(String analysisResult) {
        if (analysisResult == null || analysisResult.isBlank()) {
            return "PENDING";
        }
        return analysisResult.contains("\"status\":\"FAILED\"")
                || analysisResult.contains("\"status\": \"FAILED\"")
                ? "FAILED"
                : "COMPLETED";
    }

    private String timestamp(Timestamp value) {
        if (value == null) {
            return null;
        }
        return value.toLocalDateTime().atZone(REPORTING_ZONE).toOffsetDateTime().toString();
    }

    private String normalized(String value, int maxLength, String fallback) {
        String normalized = value == null ? "" : value.trim().toUpperCase();
        if (normalized.isBlank()) {
            normalized = fallback;
        }
        return clipped(normalized, maxLength);
    }

    private String clipped(String value, int maxLength) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String normalized = value.trim();
        return normalized.length() <= maxLength ? normalized : normalized.substring(0, maxLength);
    }

    private record StageDefinition(String code, String label, String service) {}

    private record TraceEvent(
            String stage,
            String state,
            String service,
            String detail,
            Double durationMs,
            Timestamp occurredAt
    ) {}
}
