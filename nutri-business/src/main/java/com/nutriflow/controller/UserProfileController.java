package com.nutriflow.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nutriflow.model.User;
import com.nutriflow.repository.UserRepository;
import com.nutriflow.service.UserNicknameService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Locale;

@RestController
@RequestMapping("/v1/users")
@RequiredArgsConstructor
public class UserProfileController {

    private static final List<String> ALLOWED_HEALTH_GOALS = List.of(
            "WEIGHT_LOSS", "MUSCLE_GAIN", "MAINTENANCE", "GENERAL_HEALTH"
    );

    private final UserRepository userRepository;
    private final ObjectMapper objectMapper;
    private final UserNicknameService userNicknameService;

    @GetMapping("/{userId}/profile")
    public ResponseEntity<?> getProfile(@PathVariable Long userId) {
        return userRepository.findById(userId)
                .<ResponseEntity<?>>map(user -> ResponseEntity.ok(toProfileResponse(userNicknameService.ensureNickname(user))))
                .orElseGet(() -> ResponseEntity.status(404).body(Map.of("error", "User not found")));
    }

    @PutMapping("/{userId}/profile")
    public ResponseEntity<?> updateProfile(@PathVariable Long userId, @Valid @RequestBody UpdateProfileRequest req) {
        if (!ALLOWED_HEALTH_GOALS.contains(req.getHealthGoal())) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "healthGoal must be one of WEIGHT_LOSS|MUSCLE_GAIN|MAINTENANCE|GENERAL_HEALTH"
            ));
        }

        return userRepository.findById(userId)
                .<ResponseEntity<?>>map(user -> {
                    user.setNickname(sanitizeNickname(req.getNickname()));
                    user.setHealthGoal(req.getHealthGoal());
                    user.setDailyCalorieTarget(req.getDailyCalorieTarget());
                    user.setDietaryRestrictions(toJson(req.getDietaryRestrictions()));
                    user.setHeightCm(req.getHeightCm());
                    user.setWeightKg(req.getWeightKg());
                    user.setGender(req.getGender());
                    user = userRepository.save(user);
                    user = userNicknameService.ensureNickname(user);
                    return ResponseEntity.ok(toProfileResponse(user));
                })
                .orElseGet(() -> ResponseEntity.status(404).body(Map.of("error", "User not found")));
    }

    @PostMapping("/{userId}/profile/assistant-parse")
    public ResponseEntity<?> parseGoalByAssistant(@PathVariable Long userId, @Valid @RequestBody GoalAssistantRequest req) {
        return userRepository.findById(userId)
                .<ResponseEntity<?>>map(user -> {
                    GoalAssistantResponse parsed = parseGoalText(req);
                    if (req.getApplyToProfile() != null && req.getApplyToProfile()) {
                        user.setHealthGoal(parsed.getHealthGoal());
                        user.setDailyCalorieTarget(parsed.getDailyCalorieTarget());
                        user.setDietaryRestrictions(toJson(parsed.getDietaryRestrictions()));
                        if (req.getHeightCm() != null) {
                            user.setHeightCm(req.getHeightCm());
                        }
                        if (req.getWeightKg() != null) {
                            user.setWeightKg(req.getWeightKg());
                        }
                        if (req.getGender() != null && !req.getGender().isBlank()) {
                            user.setGender(req.getGender().toUpperCase(Locale.ROOT));
                        }
                        userRepository.save(user);
                    }
                    return ResponseEntity.ok(parsed);
                })
                .orElseGet(() -> ResponseEntity.status(404).body(Map.of("error", "User not found")));
    }

    private GoalAssistantResponse parseGoalText(GoalAssistantRequest req) {
        String text = req.getRawText() == null ? "" : req.getRawText().toLowerCase(Locale.ROOT);

        String healthGoal = "GENERAL_HEALTH";
        if (containsAny(text, "减脂", "减肥", "瘦", "weight loss", "fat loss")) {
            healthGoal = "WEIGHT_LOSS";
        } else if (containsAny(text, "增肌", "增重", "muscle", "bulk")) {
            healthGoal = "MUSCLE_GAIN";
        } else if (containsAny(text, "维持", "保持", "maintenance")) {
            healthGoal = "MAINTENANCE";
        }

        List<String> restrictions = new ArrayList<>();
        Map<String, String> restrictionMap = new HashMap<>();
        restrictionMap.put("乳糖", "lactose");
        restrictionMap.put("牛奶", "dairy");
        restrictionMap.put("海鲜", "seafood");
        restrictionMap.put("花生", "peanut");
        restrictionMap.put("坚果", "nuts");
        restrictionMap.put("麸质", "gluten");
        restrictionMap.put("辣", "spicy");
        restrictionMap.put("甜", "high_sugar");
        restrictionMap.put("油", "high_fat");
        restrictionMap.forEach((k, v) -> {
            if (text.contains(k) && !restrictions.contains(v)) {
                restrictions.add(v);
            }
        });

        Integer kcal = estimateCalorieTarget(req, healthGoal);

        String summary = switch (healthGoal) {
            case "WEIGHT_LOSS" -> "识别到你的目标偏向减脂，建议先控制总热量和高糖高油食物。";
            case "MUSCLE_GAIN" -> "识别到你的目标偏向增肌，建议保证优质蛋白和规律训练。";
            case "MAINTENANCE" -> "识别到你的目标偏向体重维持，建议保持规律饮食。";
            default -> "识别到你的目标偏向综合健康，建议饮食均衡并适度运动。";
        };

        return new GoalAssistantResponse(healthGoal, kcal, restrictions, summary);
    }

    private Integer estimateCalorieTarget(GoalAssistantRequest req, String goal) {
        if (req.getDailyCalorieTarget() != null) {
            return req.getDailyCalorieTarget();
        }

        if (req.getWeightKg() == null || req.getHeightCm() == null || req.getAge() == null) {
            return switch (goal) {
                case "WEIGHT_LOSS" -> 1800;
                case "MUSCLE_GAIN" -> 2400;
                case "MAINTENANCE" -> 2100;
                default -> 2000;
            };
        }

        double bmr;
        String gender = req.getGender() == null ? "OTHER" : req.getGender().toUpperCase(Locale.ROOT);
        if ("MALE".equals(gender)) {
            bmr = 10 * req.getWeightKg() + 6.25 * req.getHeightCm() - 5 * req.getAge() + 5;
        } else {
            bmr = 10 * req.getWeightKg() + 6.25 * req.getHeightCm() - 5 * req.getAge() - 161;
        }

        double activityFactor = switch (req.getActivityLevel() == null ? "MEDIUM" : req.getActivityLevel().toUpperCase(Locale.ROOT)) {
            case "LOW" -> 1.3;
            case "HIGH" -> 1.65;
            default -> 1.5;
        };

        double tdee = bmr * activityFactor;
        double target = switch (goal) {
            case "WEIGHT_LOSS" -> tdee - 350;
            case "MUSCLE_GAIN" -> tdee + 250;
            case "MAINTENANCE" -> tdee;
            default -> tdee;
        };

        return (int) Math.max(1200, Math.min(3200, Math.round(target)));
    }

    private boolean containsAny(String text, String... keys) {
        for (String key : keys) {
            if (text.contains(key)) {
                return true;
            }
        }
        return false;
    }

    private ProfileResponse toProfileResponse(User user) {
        return new ProfileResponse(
                user.getId(),
                user.getPhone(),
                user.getNickname(),
                user.getHealthGoal(),
                user.getDailyCalorieTarget(),
                parseRestrictions(user.getDietaryRestrictions()),
                user.getHeightCm(),
                user.getWeightKg(),
                user.getGender()
        );
    }

    private String sanitizeNickname(String nickname) {
        if (nickname == null) {
            return null;
        }
        String trimmed = nickname.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private String toJson(List<String> restrictions) {
        try {
            return objectMapper.writeValueAsString(restrictions == null ? List.of() : restrictions);
        } catch (JsonProcessingException e) {
            return "[]";
        }
    }

    private List<String> parseRestrictions(String rawJson) {
        if (rawJson == null || rawJson.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(
                    rawJson,
                    objectMapper.getTypeFactory().constructCollectionType(List.class, String.class)
            );
        } catch (Exception e) {
            return List.of();
        }
    }

    @Data
    public static class UpdateProfileRequest {
        @Size(max = 24)
        private String nickname;

        @NotBlank
        private String healthGoal;

        @Min(500)
        @Max(5000)
        private Integer dailyCalorieTarget;

        private List<String> dietaryRestrictions = new ArrayList<>();
        private Integer heightCm;
        private Double weightKg;
        private String gender;
    }

    @Data
    @AllArgsConstructor
    public static class ProfileResponse {
        private Long userId;
        private String phone;
        private String nickname;
        private String healthGoal;
        private Integer dailyCalorieTarget;
        private List<String> dietaryRestrictions;
        private Integer heightCm;
        private Double weightKg;
        private String gender;
    }

    @Data
    public static class GoalAssistantRequest {
        @NotBlank
        private String rawText;
        private Integer dailyCalorieTarget;
        private Integer age;
        private Integer heightCm;
        private Double weightKg;
        private String gender;
        private String activityLevel;
        private Boolean applyToProfile = false;
    }

    @Data
    @AllArgsConstructor
    public static class GoalAssistantResponse {
        private String healthGoal;
        private Integer dailyCalorieTarget;
        private List<String> dietaryRestrictions;
        private String summary;
    }
}
