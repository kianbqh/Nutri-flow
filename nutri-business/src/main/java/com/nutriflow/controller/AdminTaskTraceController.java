package com.nutriflow.controller;

import com.nutriflow.service.TaskTraceService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

@RestController
@RequestMapping("/v1/admin/dashboard/task-traces")
@RequiredArgsConstructor
public class AdminTaskTraceController {

    private final TaskTraceService taskTraceService;

    @Value("${nutri.admin.dashboard-key:}")
    private String dashboardKey;

    @GetMapping("/recent")
    public ResponseEntity<?> recentTasks(
            @RequestHeader(value = "X-Nutri-Admin-Key", required = false) String providedKey,
            @RequestParam(defaultValue = "12") int limit
    ) {
        ResponseEntity<?> error = authorizationError(providedKey);
        if (error != null) {
            return error;
        }
        return noStore(Map.of("tasks", taskTraceService.recentTasks(limit)));
    }

    @GetMapping("/{taskId}")
    public ResponseEntity<?> taskTrace(
            @RequestHeader(value = "X-Nutri-Admin-Key", required = false) String providedKey,
            @PathVariable String taskId
    ) {
        ResponseEntity<?> error = authorizationError(providedKey);
        if (error != null) {
            return error;
        }
        Map<String, Object> trace = taskTraceService.taskTrace(taskId);
        if (trace == null) {
            return ResponseEntity.notFound().cacheControl(CacheControl.noStore()).build();
        }
        return noStore(trace);
    }

    private ResponseEntity<?> authorizationError(String providedKey) {
        if (dashboardKey == null || dashboardKey.isBlank()) {
            return ResponseEntity.status(503).cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "数据看板尚未配置"));
        }
        if (providedKey == null || !MessageDigest.isEqual(
                dashboardKey.getBytes(StandardCharsets.UTF_8),
                providedKey.getBytes(StandardCharsets.UTF_8))) {
            return ResponseEntity.status(403).cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "管理码不正确"));
        }
        return null;
    }

    private ResponseEntity<?> noStore(Object body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
