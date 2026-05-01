package com.nutriflow.controller;

import com.nutriflow.model.User;
import com.nutriflow.repository.UserRepository;
import com.nutriflow.service.UserNicknameService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ThreadLocalRandom;
import java.util.regex.Pattern;

@RestController
@RequestMapping("/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private static final Pattern PHONE_PATTERN = Pattern.compile("^1\\d{10}$");
    private static final Duration CODE_TTL = Duration.ofMinutes(5);
    private static final String DEFAULT_PASSWORD_PLACEHOLDER = "otp_login_no_password";

    private final UserRepository userRepository;
    private final StringRedisTemplate stringRedisTemplate;
    private final UserNicknameService userNicknameService;

    @PostMapping("/send-code")
    public ResponseEntity<?> sendCode(@Valid @RequestBody SendCodeRequest request) {
        String phone = normalizePhone(request.getPhone());
        if (!PHONE_PATTERN.matcher(phone).matches()) {
            return ResponseEntity.badRequest().body(new ErrorResponse("手机号格式不正确，应为 11 位大陆手机号"));
        }

        String code = String.format("%06d", ThreadLocalRandom.current().nextInt(0, 1_000_000));
        stringRedisTemplate.opsForValue().set(buildCodeKey(phone), code, CODE_TTL);

        return ResponseEntity.ok(new SendCodeResponse(
                phone,
                code,
                CODE_TTL.toSeconds(),
                "开发环境未接入真实短信通道，验证码直接返回用于测试"
        ));
    }

    @PostMapping("/verify-code")
    public ResponseEntity<?> verifyCode(@Valid @RequestBody VerifyCodeRequest request) {
        String phone = normalizePhone(request.getPhone());
        String inputCode = request.getCode() == null ? "" : request.getCode().trim();

        if (!PHONE_PATTERN.matcher(phone).matches()) {
            return ResponseEntity.badRequest().body(new ErrorResponse("手机号格式不正确，应为 11 位大陆手机号"));
        }
        if (inputCode.isBlank()) {
            return ResponseEntity.badRequest().body(new ErrorResponse("验证码不能为空"));
        }

        String cachedCode = stringRedisTemplate.opsForValue().get(buildCodeKey(phone));
        if (cachedCode == null || cachedCode.isBlank()) {
            return ResponseEntity.badRequest().body(new ErrorResponse("验证码已过期，请重新获取"));
        }
        if (!cachedCode.equals(inputCode)) {
            return ResponseEntity.badRequest().body(new ErrorResponse("验证码错误"));
        }

        stringRedisTemplate.delete(buildCodeKey(phone));

        boolean isNewUser = false;
        User user = userRepository.findByPhone(phone).orElse(null);
        if (user == null) {
            user = buildNewPhoneUser(phone);
            user = userRepository.save(user);
            isNewUser = true;
        }
        user = userNicknameService.ensureNickname(user);

        return ResponseEntity.ok(new VerifyCodeResponse(
                user.getId(),
                user.getPhone(),
                isNewUser,
                user.getHealthGoal(),
                user.getDailyCalorieTarget(),
                List.of()
        ));
    }

    private String buildCodeKey(String phone) {
        return "nutri:auth:code:" + phone;
    }

    private String normalizePhone(String rawPhone) {
        if (rawPhone == null) {
            return "";
        }
        return rawPhone.replaceAll("[^0-9]", "").trim();
    }

    private User buildNewPhoneUser(String phone) {
        User user = new User();
        user.setUsername("u_" + phone);
        user.setEmail(phone + "@phone.local");
        user.setPasswordHash(DEFAULT_PASSWORD_PLACEHOLDER);
        user.setPhone(phone);
        user.setHealthGoal("GENERAL_HEALTH");
        user.setDailyCalorieTarget(2000);
        user.setDietaryRestrictions("[]");
        user.setGender("OTHER");
        return user;
    }

    @Data
    public static class SendCodeRequest {
        @NotBlank
        private String phone;
    }

    @Data
    public static class VerifyCodeRequest {
        @NotBlank
        private String phone;

        @NotBlank
        private String code;
    }

    @Data
    @AllArgsConstructor
    public static class SendCodeResponse {
        private String phone;
        private String debugCode;
        private long expiresInSeconds;
        private String message;
    }

    @Data
    @AllArgsConstructor
    public static class VerifyCodeResponse {
        private Long userId;
        private String phone;
        private boolean isNewUser;
        private String healthGoal;
        private Integer dailyCalorieTarget;
        private List<String> dietaryRestrictions;
    }

    @Data
    @AllArgsConstructor
    public static class ErrorResponse {
        private String error;
    }
}