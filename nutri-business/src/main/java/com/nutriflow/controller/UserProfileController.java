package com.nutriflow.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nutriflow.model.User;
import com.nutriflow.repository.UserRepository;
import com.nutriflow.service.GoalAssistantService;
import com.nutriflow.service.GoalAssistantService.GoalParseInput;
import com.nutriflow.service.GoalAssistantService.GoalParseResult;
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
import java.util.List;
import java.util.Map;

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
    private final GoalAssistantService goalAssistantService;

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
                    GoalParseResult parsed = goalAssistantService.parse(new GoalParseInput(
                            req.getRawText(),
                            req.getAge(),
                            req.getHeightCm(),
                            req.getWeightKg(),
                            req.getGender(),
                            req.getActivityLevel()
                    ));
                    if (req.getApplyToProfile() != null && req.getApplyToProfile()) {
                        user.setHealthGoal(parsed.healthGoal());
                        user.setDailyCalorieTarget(parsed.dailyCalorieTarget());
                        user.setDietaryRestrictions(toJson(parsed.dietaryRestrictions()));
                        if (parsed.heightCm() != null) {
                            user.setHeightCm(parsed.heightCm());
                        }
                        if (parsed.weightKg() != null) {
                            user.setWeightKg(parsed.weightKg());
                        }
                        if (parsed.gender() != null && !parsed.gender().isBlank()) {
                            user.setGender(parsed.gender());
                        }
                        userRepository.save(user);
                    }
                    return ResponseEntity.ok(new GoalAssistantResponse(
                            parsed.healthGoal(),
                            parsed.dailyCalorieTarget(),
                            parsed.dietaryRestrictions(),
                            parsed.summary(),
                            parsed.age(),
                            parsed.heightCm(),
                            parsed.weightKg(),
                            parsed.gender(),
                            parsed.activityLevel()
                    ));
                })
                .orElseGet(() -> ResponseEntity.status(404).body(Map.of("error", "User not found")));
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
        private Integer age;
        private Integer heightCm;
        private Double weightKg;
        private String gender;
        private String activityLevel;
    }
}
