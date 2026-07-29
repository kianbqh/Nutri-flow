package com.nutriflow.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/v1/admin/dashboard")
@RequiredArgsConstructor
public class AdminDashboardController {

    private static final ZoneId REPORTING_ZONE = ZoneId.of("Asia/Shanghai");

    private final JdbcTemplate jdbcTemplate;

    @Value("${nutri.admin.dashboard-key:}")
    private String dashboardKey;

    @GetMapping
    public ResponseEntity<?> getDashboard(
            @RequestHeader(value = "X-Nutri-Admin-Key", required = false) String providedKey
    ) {
        if (dashboardKey == null || dashboardKey.isBlank()) {
            return ResponseEntity.status(503).body(Map.of("error", "数据看板尚未配置"));
        }
        if (!secureEquals(dashboardKey, providedKey)) {
            return ResponseEntity.status(403).body(Map.of("error", "管理码不正确"));
        }

        Map<String, Object> rawSummary = jdbcTemplate.queryForMap("""
                SELECT
                  (SELECT COUNT(*) FROM users) AS total_users,
                  (SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE) AS users_today,
                  (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL 7 DAY) AS users_7d,
                  (SELECT COUNT(DISTINCT user_id) FROM diet_logs) AS users_with_meals,
                  (SELECT COUNT(DISTINCT user_id) FROM diet_logs
                     WHERE logged_at >= NOW() - INTERVAL 7 DAY) AS active_users_7d,
                  (SELECT COUNT(*) FROM diet_logs) AS total_analyses,
                  (SELECT COUNT(*) FROM diet_logs WHERE logged_at >= CURRENT_DATE) AS analyses_today,
                  (SELECT COUNT(*) FROM diet_logs
                     WHERE logged_at >= NOW() - INTERVAL 7 DAY) AS analyses_7d,
                  (SELECT COUNT(*) FROM diet_logs
                     WHERE analysis_result IS NOT NULL) AS finished_analyses
                """);

        long totalAnalyses = number(rawSummary.get("total_analyses"));
        long finishedAnalyses = number(rawSummary.get("finished_analyses"));
        double completionRate = totalAnalyses == 0
                ? 0.0
                : Math.round((finishedAnalyses * 1000.0) / totalAnalyses) / 10.0;

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalUsers", number(rawSummary.get("total_users")));
        summary.put("usersToday", number(rawSummary.get("users_today")));
        summary.put("users7d", number(rawSummary.get("users_7d")));
        summary.put("usersWithMeals", number(rawSummary.get("users_with_meals")));
        summary.put("activeUsers7d", number(rawSummary.get("active_users_7d")));
        summary.put("totalAnalyses", totalAnalyses);
        summary.put("analysesToday", number(rawSummary.get("analyses_today")));
        summary.put("analyses7d", number(rawSummary.get("analyses_7d")));
        summary.put("finishedAnalyses", finishedAnalyses);
        summary.put("completionRate", completionRate);

        Map<LocalDate, Long> userCounts = queryDailyCounts(
                "SELECT DATE(created_at) AS day, COUNT(*) AS amount " +
                        "FROM users WHERE created_at >= CURRENT_DATE - INTERVAL 13 DAY " +
                        "GROUP BY DATE(created_at)"
        );
        Map<LocalDate, Long> analysisCounts = queryDailyCounts(
                "SELECT DATE(logged_at) AS day, COUNT(*) AS amount " +
                        "FROM diet_logs WHERE logged_at >= CURRENT_DATE - INTERVAL 13 DAY " +
                        "GROUP BY DATE(logged_at)"
        );
        LocalDate today = LocalDate.now(REPORTING_ZONE);
        List<Map<String, Object>> daily = new ArrayList<>();
        for (int offset = 13; offset >= 0; offset--) {
            LocalDate date = today.minusDays(offset);
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("date", date.toString());
            item.put("newUsers", userCounts.getOrDefault(date, 0L));
            item.put("analyses", analysisCounts.getOrDefault(date, 0L));
            daily.add(item);
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("generatedAt", OffsetDateTime.now(REPORTING_ZONE).toString());
        response.put("summary", summary);
        response.put("daily", daily);
        response.put("goalDistribution", queryDistribution(
                "SELECT COALESCE(NULLIF(health_goal, ''), 'UNSET') AS label, COUNT(*) AS amount " +
                        "FROM users GROUP BY COALESCE(NULLIF(health_goal, ''), 'UNSET') ORDER BY amount DESC"
        ));
        response.put("mealTypeDistribution", queryDistribution(
                "SELECT COALESCE(NULLIF(meal_type, ''), 'UNKNOWN') AS label, COUNT(*) AS amount " +
                        "FROM diet_logs GROUP BY COALESCE(NULLIF(meal_type, ''), 'UNKNOWN') ORDER BY amount DESC"
        ));
        response.put("privacy", Map.of(
                "deviceTrackingEnabled", false,
                "mode", "server_aggregate_only",
                "notice", "看板不采集设备指纹、IP 或 User-Agent，也不返回手机号"
        ));
        return ResponseEntity.ok(response);
    }

    private Map<LocalDate, Long> queryDailyCounts(String sql) {
        Map<LocalDate, Long> result = new LinkedHashMap<>();
        jdbcTemplate.query(sql, rs -> {
            if (rs.getDate("day") != null) {
                result.put(rs.getDate("day").toLocalDate(), rs.getLong("amount"));
            }
        });
        return result;
    }

    private List<Map<String, Object>> queryDistribution(String sql) {
        return jdbcTemplate.query(sql, (rs, rowNum) -> {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("label", rs.getString("label"));
            item.put("count", rs.getLong("amount"));
            return item;
        });
    }

    private long number(Object value) {
        return value instanceof Number number ? number.longValue() : 0L;
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
}
