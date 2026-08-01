package com.nutriflow.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Slf4j
@Service
public class GoalAssistantService {

    private static final List<String> ALLOWED_GOALS = List.of(
            "WEIGHT_LOSS", "MUSCLE_GAIN", "MAINTENANCE", "GENERAL_HEALTH"
    );
    private static final List<String> ALLOWED_RESTRICTIONS = List.of(
            "high_sugar", "spicy", "dairy", "lactose", "gluten", "seafood", "nuts"
    );
    private static final Pattern AGE_PATTERN = Pattern.compile("(\\d{1,3})\\s*(?:岁|周岁)");
    private static final Pattern HEIGHT_CM_PATTERN = Pattern.compile(
            "(?:身高(?:是|为)?\\s*)?(\\d{2,3}(?:\\.\\d+)?)\\s*(?:cm|厘米|公分)",
            Pattern.CASE_INSENSITIVE
    );
    private static final Pattern HEIGHT_M_PATTERN = Pattern.compile(
            "(?:身高(?:是|为)?\\s*)?([12](?:\\.\\d{1,2}))\\s*米"
    );
    private static final Pattern WEIGHT_KG_PATTERN = Pattern.compile(
            "(?:体重(?:是|为)?\\s*)?(\\d{2,3}(?:\\.\\d+)?)\\s*(?:kg|公斤|千克)",
            Pattern.CASE_INSENSITIVE
    );
    private static final Pattern WEIGHT_JIN_PATTERN = Pattern.compile(
            "(?:体重(?:是|为)?\\s*)?(\\d{2,3}(?:\\.\\d+)?)\\s*斤"
    );
    private static final Pattern CALORIE_PATTERN = Pattern.compile(
            "(?:每天|每日|一天)?\\s*(?:控制在|目标(?:是|为)?|摄入)?\\s*(\\d{3,4})\\s*(?:kcal|千卡|大卡)",
            Pattern.CASE_INSENSITIVE
    );
    private static final Pattern WEEKLY_EXERCISE_PATTERN = Pattern.compile(
            "(?:每周|一周)\\D{0,8}(\\d{1,2})\\s*次"
    );

    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;
    private final String apiKey;
    private final String baseUrl;
    private final String model;
    private final double temperature;
    private final int timeoutSeconds;

    public GoalAssistantService(
            ObjectMapper objectMapper,
            @Value("${nutri.llm.api-key:}") String apiKey,
            @Value("${nutri.llm.base-url:https://api.moonshot.cn/v1}") String baseUrl,
            @Value("${nutri.llm.model:moonshot-v1-8k}") String model,
            @Value("${nutri.llm.temperature:0.3}") double temperature,
            @Value("${nutri.llm.timeout-seconds:40}") int timeoutSeconds
    ) {
        this.objectMapper = objectMapper;
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.baseUrl = stripTrailingSlash(baseUrl);
        this.model = model;
        this.temperature = temperature;
        this.timeoutSeconds = Math.max(5, timeoutSeconds);
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(Math.min(this.timeoutSeconds, 15)))
                .build();
    }

    public GoalParseResult parse(GoalParseInput input) {
        GoalParseResult fallback = parseWithRules(input);
        if (apiKey.isBlank()) {
            return fallback;
        }

        try {
            GoalParseResult llmResult = parseWithLlm(input);
            return merge(input, llmResult, fallback);
        } catch (Exception e) {
            log.warn("Goal assistant LLM request failed; using rule parser: {}", e.getMessage());
            return fallback;
        }
    }

    private GoalParseResult parseWithLlm(GoalParseInput input) throws Exception {
        String systemPrompt = """
                你是 NutriFlow 的健康目标信息提取器。只提取用户明确说出的信息，不猜测未知字段。
                返回一个 JSON 对象，不要 Markdown。字段必须为：
                healthGoal: WEIGHT_LOSS|MUSCLE_GAIN|MAINTENANCE|GENERAL_HEALTH；
                age: 1-120 的整数或 null；
                heightCm: 50-260 的整数或 null；
                weightKg: 20-300 的数字或 null；
                gender: MALE|FEMALE|null；
                activityLevel: LOW|MEDIUM|HIGH|null；
                dailyCalorieTarget: 500-5000 的整数或 null；
                dietaryRestrictions: 数组，只能包含 high_sugar, spicy, dairy, lactose, gluten, seafood, nuts；
                summary: 80 字以内中文总结。
                明确的原文信息优先于当前资料。没有明确健康目标时使用 GENERAL_HEALTH。
                每周 5 次及以上规律训练视为 HIGH，2-4 次视为 MEDIUM，0-1 次视为 LOW。
                提到血糖偏高、控制血糖或少吃甜食时，dietaryRestrictions 应包含 high_sugar。
                """;

        Map<String, Object> context = new LinkedHashMap<>();
        context.put("rawText", input.rawText());
        context.put("currentAge", input.age());
        context.put("currentHeightCm", input.heightCm());
        context.put("currentWeightKg", input.weightKg());
        context.put("currentGender", input.gender());
        context.put("currentActivityLevel", input.activityLevel());
        Map<String, Object> requestBody = Map.of(
                "model", model,
                "temperature", temperature,
                "response_format", Map.of("type", "json_object"),
                "messages", List.of(
                        Map.of("role", "system", "content", systemPrompt),
                        Map.of("role", "user", "content", objectMapper.writeValueAsString(context))
                )
        );

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(baseUrl + "/chat/completions"))
                .timeout(Duration.ofSeconds(timeoutSeconds))
                .header("Authorization", "Bearer " + apiKey)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(requestBody)))
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new IllegalStateException("provider returned HTTP " + response.statusCode());
        }

        JsonNode root = objectMapper.readTree(response.body());
        String content = root.path("choices").path(0).path("message").path("content").asText("");
        if (content.isBlank()) {
            throw new IllegalStateException("provider returned empty content");
        }
        JsonNode parsed = objectMapper.readTree(stripJsonFence(content));
        return fromJson(parsed);
    }

    private GoalParseResult parseWithRules(GoalParseInput input) {
        String text = input.rawText() == null ? "" : input.rawText().toLowerCase(Locale.ROOT);

        String healthGoal = "GENERAL_HEALTH";
        if (containsAny(text, "减脂", "减肥", "瘦身", "weight loss", "fat loss")) {
            healthGoal = "WEIGHT_LOSS";
        } else if (containsAny(text, "增肌", "增重", "muscle", "bulk")) {
            healthGoal = "MUSCLE_GAIN";
        } else if (containsAny(text, "维持", "保持体重", "maintenance")) {
            healthGoal = "MAINTENANCE";
        }

        Integer age = extractInt(text, AGE_PATTERN, 1, 120);
        Integer heightCm = extractInt(text, HEIGHT_CM_PATTERN, 50, 260);
        if (heightCm == null) {
            Double heightM = extractDouble(text, HEIGHT_M_PATTERN, 0.5, 2.6);
            heightCm = heightM == null ? null : (int) Math.round(heightM * 100);
        }
        Double weightKg = extractDouble(text, WEIGHT_KG_PATTERN, 20, 300);
        if (weightKg == null) {
            Double weightJin = extractDouble(text, WEIGHT_JIN_PATTERN, 40, 600);
            weightKg = weightJin == null ? null : Math.round(weightJin * 5.0) / 10.0;
        }

        String gender = null;
        if (containsAny(text, "女生", "女性", "女士", "女，", "女。", "女 ")) {
            gender = "FEMALE";
        } else if (containsAny(text, "男生", "男性", "男士", "男，", "男。", "男 ")) {
            gender = "MALE";
        }

        String activityLevel = parseActivityLevel(text);
        Integer explicitCalories = extractInt(text, CALORIE_PATTERN, 500, 5000);
        List<String> restrictions = parseRestrictions(text);

        GoalParseInput mergedInput = new GoalParseInput(
                input.rawText(),
                firstNonNull(age, input.age()),
                firstNonNull(heightCm, input.heightCm()),
                firstNonNull(weightKg, input.weightKg()),
                firstNonBlank(gender, input.gender()),
                firstNonBlank(activityLevel, input.activityLevel())
        );
        Integer calorieTarget = explicitCalories == null
                ? estimateCalorieTarget(mergedInput, healthGoal)
                : explicitCalories;
        String summary = buildSummary(healthGoal, age, heightCm, weightKg, gender, activityLevel, restrictions);

        return new GoalParseResult(
                healthGoal,
                calorieTarget,
                restrictions,
                summary,
                age,
                heightCm,
                weightKg,
                gender,
                activityLevel
        );
    }

    private GoalParseResult merge(GoalParseInput input, GoalParseResult llm, GoalParseResult fallback) {
        String llmGoal = ALLOWED_GOALS.contains(llm.healthGoal()) ? llm.healthGoal() : "GENERAL_HEALTH";
        String goal = "GENERAL_HEALTH".equals(fallback.healthGoal()) ? llmGoal : fallback.healthGoal();
        Integer age = firstNonNull(fallback.age(), bounded(llm.age(), 1, 120));
        Integer height = firstNonNull(fallback.heightCm(), bounded(llm.heightCm(), 50, 260));
        Double weight = firstNonNull(fallback.weightKg(), bounded(llm.weightKg(), 20, 300));
        String llmGender = Set.of("MALE", "FEMALE").contains(normalize(llm.gender())) ? normalize(llm.gender()) : null;
        String gender = firstNonBlank(fallback.gender(), llmGender);
        String llmActivity = Set.of("LOW", "MEDIUM", "HIGH").contains(normalize(llm.activityLevel()))
                ? normalize(llm.activityLevel())
                : null;
        String activity = firstNonBlank(fallback.activityLevel(), llmActivity);
        Integer explicitCalories = extractInt(
                input.rawText() == null ? "" : input.rawText(),
                CALORIE_PATTERN,
                500,
                5000
        );
        Integer calories = firstNonNull(explicitCalories, bounded(llm.dailyCalorieTarget(), 500, 5000));
        if (calories == null) {
            GoalParseInput mergedInput = new GoalParseInput("", age, height, weight, gender, activity);
            calories = estimateCalorieTarget(mergedInput, goal);
        }

        LinkedHashSet<String> restrictions = new LinkedHashSet<>();
        for (String restriction : llm.dietaryRestrictions()) {
            if (ALLOWED_RESTRICTIONS.contains(restriction)) restrictions.add(restriction);
        }
        restrictions.addAll(fallback.dietaryRestrictions());
        String summary = llm.summary() == null || llm.summary().isBlank()
                ? fallback.summary()
                : llm.summary().trim();

        return new GoalParseResult(
                goal,
                calories,
                List.copyOf(restrictions),
                summary,
                age,
                height,
                weight,
                gender,
                activity
        );
    }

    private GoalParseResult fromJson(JsonNode node) {
        List<String> restrictions = new ArrayList<>();
        node.path("dietaryRestrictions").forEach(value -> restrictions.add(value.asText("")));
        return new GoalParseResult(
                normalize(node.path("healthGoal").asText("")),
                nullableInt(node.get("dailyCalorieTarget")),
                restrictions,
                node.path("summary").asText(""),
                nullableInt(node.get("age")),
                nullableInt(node.get("heightCm")),
                nullableDouble(node.get("weightKg")),
                normalize(node.path("gender").asText("")),
                normalize(node.path("activityLevel").asText(""))
        );
    }

    private Integer estimateCalorieTarget(GoalParseInput input, String goal) {
        if (input.weightKg() == null || input.heightCm() == null || input.age() == null) {
            return switch (goal) {
                case "WEIGHT_LOSS" -> 1800;
                case "MUSCLE_GAIN" -> 2400;
                case "MAINTENANCE" -> 2100;
                default -> 2000;
            };
        }

        String gender = normalize(input.gender());
        double genderOffset = "MALE".equals(gender) ? 5 : "FEMALE".equals(gender) ? -161 : -78;
        double bmr = 10 * input.weightKg() + 6.25 * input.heightCm() - 5 * input.age() + genderOffset;
        double factor = switch (normalize(input.activityLevel())) {
            case "LOW" -> 1.3;
            case "HIGH" -> 1.65;
            default -> 1.5;
        };
        double target = switch (goal) {
            case "WEIGHT_LOSS" -> bmr * factor - 350;
            case "MUSCLE_GAIN" -> bmr * factor + 250;
            default -> bmr * factor;
        };
        return (int) Math.max(1200, Math.min(3200, Math.round(target)));
    }

    private String parseActivityLevel(String text) {
        if (containsAny(text, "久坐", "不运动", "很少运动", "活动量低")) {
            return "LOW";
        }
        if (containsAny(text, "每天运动", "高强度", "重体力", "活动量高")) {
            return "HIGH";
        }
        Matcher matcher = WEEKLY_EXERCISE_PATTERN.matcher(text);
        if (matcher.find()) {
            int count = Integer.parseInt(matcher.group(1));
            if (count <= 1) return "LOW";
            if (count >= 5) return "HIGH";
            return "MEDIUM";
        }
        if (containsAny(text, "规律运动", "适量运动", "活动量中")) {
            return "MEDIUM";
        }
        return null;
    }

    private List<String> parseRestrictions(String text) {
        LinkedHashSet<String> restrictions = new LinkedHashSet<>();
        Map<String, String> keywords = Map.ofEntries(
                Map.entry("控糖", "high_sugar"),
                Map.entry("少糖", "high_sugar"),
                Map.entry("甜食", "high_sugar"),
                Map.entry("血糖", "high_sugar"),
                Map.entry("少辣", "spicy"),
                Map.entry("不吃辣", "spicy"),
                Map.entry("乳糖", "lactose"),
                Map.entry("牛奶", "dairy"),
                Map.entry("乳制品", "dairy"),
                Map.entry("海鲜", "seafood"),
                Map.entry("花生", "nuts"),
                Map.entry("坚果", "nuts"),
                Map.entry("麸质", "gluten")
        );
        keywords.forEach((keyword, code) -> {
            if (text.contains(keyword)) restrictions.add(code);
        });
        return List.copyOf(restrictions);
    }

    private String buildSummary(
            String goal,
            Integer age,
            Integer height,
            Double weight,
            String gender,
            String activity,
            List<String> restrictions
    ) {
        String goalText = switch (goal) {
            case "WEIGHT_LOSS" -> "减脂";
            case "MUSCLE_GAIN" -> "增肌";
            case "MAINTENANCE" -> "维持体重";
            default -> "综合健康";
        };
        List<String> details = new ArrayList<>();
        if (age != null) details.add(age + " 岁");
        if (height != null) details.add("身高 " + height + " cm");
        if (weight != null) details.add("体重 " + weight + " kg");
        if (gender != null) details.add("MALE".equals(gender) ? "男性" : "女性");
        if (activity != null) details.add("活动量" + switch (activity) {
            case "LOW" -> "低";
            case "HIGH" -> "高";
            default -> "中";
        });
        String base = details.isEmpty()
                ? "已识别为" + goalText + "目标。"
                : "已识别为" + goalText + "目标，并提取：" + String.join("、", details) + "。";
        return restrictions.isEmpty() ? base : base + "饮食限制已同步整理。";
    }

    private Integer extractInt(String text, Pattern pattern, int min, int max) {
        Double value = extractDouble(text, pattern, min, max);
        return value == null ? null : (int) Math.round(value);
    }

    private Double extractDouble(String text, Pattern pattern, double min, double max) {
        Matcher matcher = pattern.matcher(text);
        if (!matcher.find()) return null;
        double value = Double.parseDouble(matcher.group(1));
        return value >= min && value <= max ? value : null;
    }

    private boolean containsAny(String text, String... keywords) {
        for (String keyword : keywords) {
            if (text.contains(keyword)) return true;
        }
        return false;
    }

    private static String stripTrailingSlash(String value) {
        String normalized = value == null ? "" : value.trim();
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }

    private static String stripJsonFence(String value) {
        String text = value.trim();
        if (text.startsWith("```")) {
            text = text.replaceFirst("^```(?:json)?\\s*", "");
            text = text.replaceFirst("\\s*```$", "");
        }
        return text;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
    }

    private static Integer nullableInt(JsonNode node) {
        return node == null || node.isNull() || !node.isNumber() ? null : node.intValue();
    }

    private static Double nullableDouble(JsonNode node) {
        return node == null || node.isNull() || !node.isNumber() ? null : node.doubleValue();
    }

    private static Integer bounded(Integer value, int min, int max) {
        return value != null && value >= min && value <= max ? value : null;
    }

    private static Double bounded(Double value, double min, double max) {
        return value != null && value >= min && value <= max ? value : null;
    }

    private static <T> T firstNonNull(T primary, T fallback) {
        return primary == null ? fallback : primary;
    }

    private static String firstNonBlank(String primary, String fallback) {
        return primary == null || primary.isBlank() ? fallback : primary;
    }

    public record GoalParseInput(
            String rawText,
            Integer age,
            Integer heightCm,
            Double weightKg,
            String gender,
            String activityLevel
    ) {
    }

    public record GoalParseResult(
            String healthGoal,
            Integer dailyCalorieTarget,
            List<String> dietaryRestrictions,
            String summary,
            Integer age,
            Integer heightCm,
            Double weightKg,
            String gender,
            String activityLevel
    ) {
    }
}
