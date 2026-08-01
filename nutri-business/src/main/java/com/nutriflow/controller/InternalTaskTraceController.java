package com.nutriflow.controller;

import com.nutriflow.service.TaskTraceService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

@RestController
@RequestMapping("/v1/internal/task-traces")
@RequiredArgsConstructor
public class InternalTaskTraceController {

    private final TaskTraceService taskTraceService;

    @Value("${nutri.internal.trace-key:}")
    private String traceKey;

    @PostMapping("/events")
    public ResponseEntity<?> recordEvent(
            @RequestHeader(value = "X-Nutri-Trace-Key", required = false) String providedKey,
            @RequestBody TraceEventRequest request
    ) {
        if (traceKey == null || traceKey.isBlank()) {
            return ResponseEntity.status(503).cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "Task tracing is not configured"));
        }
        if (!secureEquals(traceKey, providedKey)) {
            return ResponseEntity.status(403).cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "Forbidden"));
        }
        if (request == null || request.taskId() == null || request.taskId().isBlank()) {
            return ResponseEntity.badRequest().cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "taskId is required"));
        }

        taskTraceService.recordEvent(
                request.taskId(),
                request.stage(),
                request.state(),
                request.service(),
                request.detail(),
                request.durationMs()
        );
        return ResponseEntity.accepted().cacheControl(CacheControl.noStore())
                .body(Map.of("accepted", true));
    }

    private boolean secureEquals(String expected, String actual) {
        if (actual == null) {
            return false;
        }
        return MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                actual.getBytes(StandardCharsets.UTF_8)
        );
    }

    public record TraceEventRequest(
            String taskId,
            String stage,
            String state,
            String service,
            String detail,
            Double durationMs
    ) {}
}
