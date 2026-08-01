package com.nutriflow.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/v1/admin/dashboard")
@RequiredArgsConstructor
public class AdminDashboardController {

    private static final ZoneId REPORTING_ZONE = ZoneId.of("Asia/Shanghai");

    private final JdbcTemplate jdbcTemplate;
    private final ObjectMapper objectMapper;

    @Value("${nutri.admin.dashboard-key:}")
    private String dashboardKey;

    @GetMapping
    public ResponseEntity<?> getDashboard(
            @RequestHeader(value = "X-Nutri-Admin-Key", required = false) String providedKey
    ) {
        ResponseEntity<?> authorizationError = authorizationError(providedKey);
        if (authorizationError != null) {
            return authorizationError;
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
                "mode", "admin_protected_records",
                "notice", "看板不采集设备指纹、IP 或 User-Agent；数据库记录板块仅向管理员显示手机号"
        ));
        return noStore(response);
    }

    @GetMapping("/records")
    public ResponseEntity<?> getRecords(
            @RequestHeader(value = "X-Nutri-Admin-Key", required = false) String providedKey,
            @RequestParam(defaultValue = "users") String table,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size
    ) {
        ResponseEntity<?> authorizationError = authorizationError(providedKey);
        if (authorizationError != null) {
            return authorizationError;
        }

        int safePage = Math.max(0, page);
        int safeSize = Math.max(5, Math.min(size, 50));
        int offset = safePage * safeSize;

        return switch (table) {
            case "users" -> noStore(queryUserRecords(safePage, safeSize, offset));
            case "diet_logs" -> noStore(queryDietLogRecords(safePage, safeSize, offset));
            default -> ResponseEntity.badRequest()
                    .cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "不支持的数据表"));
        };
    }

    private Map<String, Object> queryUserRecords(int page, int size, int offset) {
        long total = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Long.class);
        List<Map<String, Object>> content = jdbcTemplate.query("""
                SELECT
                  u.id,
                  u.phone,
                  u.nickname,
                  u.health_goal,
                  u.daily_calorie_target,
                  u.height_cm,
                  u.weight_kg,
                  u.gender,
                  u.created_at,
                  u.updated_at,
                  COUNT(d.id) AS analysis_count,
                  MAX(d.logged_at) AS last_analysis_at
                FROM users u
                LEFT JOIN diet_logs d ON d.user_id = u.id
                GROUP BY
                  u.id, u.phone, u.nickname, u.health_goal, u.daily_calorie_target,
                  u.height_cm, u.weight_kg, u.gender, u.created_at, u.updated_at
                ORDER BY u.created_at DESC, u.id DESC
                LIMIT ? OFFSET ?
                """, (rs, rowNum) -> {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", rs.getLong("id"));
            item.put("phone", nullableString(rs, "phone"));
            item.put("nickname", nullableString(rs, "nickname"));
            item.put("healthGoal", nullableString(rs, "health_goal"));
            item.put("dailyCalorieTarget", nullableNumber(rs, "daily_calorie_target"));
            item.put("heightCm", nullableNumber(rs, "height_cm"));
            item.put("weightKg", nullableNumber(rs, "weight_kg"));
            item.put("gender", nullableString(rs, "gender"));
            item.put("analysisCount", rs.getLong("analysis_count"));
            item.put("createdAt", timestamp(rs, "created_at"));
            item.put("updatedAt", timestamp(rs, "updated_at"));
            item.put("lastAnalysisAt", timestamp(rs, "last_analysis_at"));
            return item;
        }, size, offset);
        return pageResponse("users", page, size, total, content);
    }

    private Map<String, Object> queryDietLogRecords(int page, int size, int offset) {
        long total = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM diet_logs", Long.class);
        List<Map<String, Object>> content = jdbcTemplate.query("""
                SELECT
                  d.id,
                  d.user_id,
                  u.phone,
                  d.task_id,
                  d.meal_type,
                  d.analysis_result,
                  d.logged_at
                FROM diet_logs d
                JOIN users u ON u.id = d.user_id
                ORDER BY d.logged_at DESC, d.id DESC
                LIMIT ? OFFSET ?
                """, (rs, rowNum) -> {
            Map<String, Object> item = new LinkedHashMap<>();
            String resultJson = rs.getString("analysis_result");
            item.put("id", rs.getLong("id"));
            item.put("userId", rs.getLong("user_id"));
            item.put("phone", nullableString(rs, "phone"));
            item.put("taskId", rs.getString("task_id"));
            item.put("mealType", rs.getString("meal_type"));
            item.put("loggedAt", timestamp(rs, "logged_at"));
            item.putAll(summarizeAnalysis(resultJson));
            return item;
        }, size, offset);
        return pageResponse("diet_logs", page, size, total, content);
    }

    private Map<String, Object> pageResponse(
            String table,
            int page,
            int size,
            long total,
            List<Map<String, Object>> content
    ) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("table", table);
        response.put("page", page);
        response.put("size", size);
        response.put("totalElements", total);
        response.put("totalPages", total == 0 ? 0 : (total + size - 1) / size);
        response.put("content", content);
        return response;
    }

    private Map<String, Object> summarizeAnalysis(String resultJson) {
        Map<String, Object> summary = new LinkedHashMap<>();
        if (resultJson == null || resultJson.isBlank()) {
            summary.put("status", "PENDING");
            summary.put("foodLabels", List.of());
            summary.put("totalCalories", null);
            summary.put("hasAdvice", false);
            return summary;
        }

        try {
            JsonNode root = objectMapper.readTree(resultJson);
            JsonNode segmentation = root.path("segmentationResult");
            JsonNode items = segmentation.path("detected_instances");
            if (!items.isArray()) {
                items = segmentation.path("detected_items");
            }

            Set<String> labels = new LinkedHashSet<>();
            double calories = 0.0;
            boolean hasCalories = false;
            if (items.isArray()) {
                for (JsonNode item : items) {
                    String label = firstText(item, "display_name", "displayName", "class_name", "className", "label");
                    if (!label.isBlank() && labels.size() < 8) {
                        labels.add(label);
                    }
                    JsonNode calorieNode = item.path("nutrition").path("calories_kcal");
                    if (!calorieNode.isNumber()) {
                        calorieNode = item.path("calories");
                    }
                    if (calorieNode.isNumber()) {
                        calories += calorieNode.asDouble();
                        hasCalories = true;
                    }
                }
            }

            if (!hasCalories && segmentation.path("total_calories_kcal").isNumber()) {
                calories = segmentation.path("total_calories_kcal").asDouble();
                hasCalories = true;
            }

            summary.put("status", root.path("status").asText("COMPLETED"));
            summary.put("foodLabels", List.copyOf(labels));
            summary.put("totalCalories", hasCalories ? Math.round(calories * 10.0) / 10.0 : null);
            JsonNode advice = root.path("adviceReport");
            summary.put("hasAdvice", !advice.isMissingNode() && !advice.isNull() && !advice.isEmpty());
        } catch (Exception ignored) {
            summary.put("status", "COMPLETED");
            summary.put("foodLabels", List.of());
            summary.put("totalCalories", null);
            summary.put("hasAdvice", false);
        }
        return summary;
    }

    private String firstText(JsonNode node, String... fields) {
        for (String field : fields) {
            String value = node.path(field).asText("").trim();
            if (!value.isBlank()) {
                return value;
            }
        }
        return "";
    }

    private Object nullableNumber(ResultSet rs, String column) throws SQLException {
        Object value = rs.getObject(column);
        return value instanceof Number ? value : null;
    }

    private String nullableString(ResultSet rs, String column) throws SQLException {
        String value = rs.getString(column);
        return value == null || value.isBlank() ? null : value;
    }

    private String timestamp(ResultSet rs, String column) throws SQLException {
        Timestamp value = rs.getTimestamp(column);
        if (value == null) {
            return null;
        }
        LocalDateTime localDateTime = value.toLocalDateTime();
        return localDateTime.atZone(REPORTING_ZONE).toOffsetDateTime().toString();
    }

    private ResponseEntity<?> authorizationError(String providedKey) {
        if (dashboardKey == null || dashboardKey.isBlank()) {
            return ResponseEntity.status(503)
                    .cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "数据看板尚未配置"));
        }
        if (!secureEquals(dashboardKey, providedKey)) {
            return ResponseEntity.status(403)
                    .cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "管理码不正确"));
        }
        return null;
    }

    private ResponseEntity<?> noStore(Object body) {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(body);
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
