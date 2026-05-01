package com.nutriflow.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nutriflow.model.DietLog;
import com.nutriflow.model.User;
import com.nutriflow.mq.FoodAnalysisProducer;
import com.nutriflow.mq.ImageAnalysisTaskMessage;
import com.nutriflow.repository.DietLogRepository;
import com.nutriflow.repository.UserRepository;
import com.nutriflow.service.OssService;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.http.MediaType;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageOutputStream;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * REST endpoint for meal-image upload and analysis trigger.
 *
 * <p>Flow:
 * <ol>
 *   <li>Client uploads image → stored in OSS.</li>
 *   <li>A {@link DietLog} row is created immediately (analysisResult = null = PENDING).</li>
 *   <li>Pre-signed URL + task metadata published to RabbitMQ.</li>
 *   <li>nutri-agent consumes the message, performs AI analysis, and publishes the
 *       result back.  {@link com.nutriflow.mq.FoodAnalysisResultConsumer} writes
 *       the payload into the DietLog row.</li>
 *   <li>Frontend polls {@code GET /v1/diet-logs/{taskId}/status} until COMPLETED.</li>
 * </ol>
 */
@Slf4j
@RestController
@RequestMapping("/v1/diet-logs")
@RequiredArgsConstructor
public class DietLogController {

    private static final long PENDING_TIMEOUT_SECONDS = 420;
    private static final int ANALYSIS_IMAGE_MAX_SIDE = 1024;
    private static final float ANALYSIS_IMAGE_JPEG_QUALITY = 0.82f;

    private final OssService ossService;
    private final FoodAnalysisProducer producer;
    private final DietLogRepository dietLogRepository;
    private final UserRepository userRepository;
    private final ObjectMapper objectMapper;

    /**
     * Upload a meal image and dispatch an analysis task.
     *
     * @param userId   authenticated user ID (header – simplified for scaffold)
     * @param mealType one of BREAKFAST, LUNCH, DINNER, SNACK
     * @param file     the meal image
     * @return taskId for polling
     */
    @PostMapping("/upload")
    public ResponseEntity<?> uploadMealImage(
            @RequestHeader("X-User-Id") @NotBlank String userId,
            @RequestParam @Pattern(regexp = "BREAKFAST|LUNCH|DINNER|SNACK") String mealType,
            @RequestParam(required = false) Integer age,
            @RequestParam(required = false) Integer heightCm,
            @RequestParam(required = false) Double weightKg,
            @RequestParam(required = false) String gender,
            @RequestParam(required = false) String activityLevel,
            @RequestParam("file") MultipartFile file) throws IOException {

        String analysisImageBase64 = buildAnalysisImageBase64(file);
        String ossKey = ossService.uploadMealImage(userId, mealType, file);
        String imageUrl = ossService.generatePresignedUrl(ossKey);
        String taskId = UUID.randomUUID().toString();

        // Validate userId is a numeric value (proper auth/JWT to be added later)
        long userIdLong;
        try {
            userIdLong = Long.parseLong(userId);
        } catch (NumberFormatException e) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "X-User-Id must be a numeric user ID"));
        }

        if (!userRepository.existsById(userIdLong)) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "User not found. Use X-User-Id=1 for local MVP demo."
            ));
        }

        DietLog dietLog = new DietLog();
        dietLog.setUserId(userIdLong);
        dietLog.setTaskId(taskId);
        dietLog.setMealType(mealType);
        dietLog.setOssKey(ossKey);
        dietLogRepository.save(dietLog);

        ImageAnalysisTaskMessage message = ImageAnalysisTaskMessage.builder()
                .taskId(taskId)
                .userId(userId)
                .imageUrl(imageUrl)
                .ossKey(ossKey)
                .analysisImageBase64(analysisImageBase64)
                .mealType(mealType)
                .createdAt(Instant.now())
                .userContext(buildUserContext(userIdLong, age, heightCm, weightKg, gender, activityLevel))
                .callbackRoutingKey("nutri.food.analysis.result")
                .build();

        producer.publishTask(message);

        log.info("Dispatched analysis task: taskId={}", taskId);
        return ResponseEntity.accepted().body(Map.of(
                "taskId", taskId,
                "ossKey", ossKey,
                "status", "PENDING"
        ));
    }

    /**
     * Poll the status of an analysis task.
     *
     * <p>Returns {@code PENDING} until nutri-agent writes the result, then
     * {@code COMPLETED} with the full analysis payload.
     *
     * @param taskId UUID returned by {@code /upload}
     */
    @GetMapping("/{taskId}/status")
    public ResponseEntity<Map<String, Object>> getTaskStatus(@PathVariable String taskId) {
        return dietLogRepository.findByTaskId(taskId)
                .map(log_ -> {
                    Map<String, Object> resp = new LinkedHashMap<>();
                    resp.put("taskId", log_.getTaskId());
                    boolean completed = log_.getAnalysisResult() != null;

                    if (!completed && isPendingTimedOut(log_)) {
                        String timeoutJson = buildPendingTimeoutResult(log_);
                        log_.setAnalysisResult(timeoutJson);
                        dietLogRepository.save(log_);
                        completed = true;
                    }

                    String derivedStatus = completed ? deriveStatus(log_.getAnalysisResult()) : "PENDING";
                    resp.put("status", derivedStatus);
                    if (completed) {
                        try {
                            var analysisNode = objectMapper.readTree(log_.getAnalysisResult());
                            resp.put("analysisResult", objectMapper.treeToValue(analysisNode, Object.class));
                            if ("FAILED".equalsIgnoreCase(derivedStatus)) {
                                String errorMsg = extractErrorMessage(analysisNode);
                                if (errorMsg != null && !errorMsg.isBlank()) {
                                    resp.put("errorMessage", errorMsg);
                                }
                            }
                        } catch (Exception e) {
                            resp.put("analysisResult", log_.getAnalysisResult());
                        }
                    } else {
                        resp.put("analysisResult", null);
                    }
                    return ResponseEntity.ok(resp);
                })
                .orElseGet(() -> {
                    Map<String, Object> resp = new LinkedHashMap<>();
                    resp.put("taskId", taskId);
                    resp.put("status", "PENDING");
                    resp.put("analysisResult", null);
                    return ResponseEntity.ok(resp);
                });
    }

    @GetMapping("/{taskId}/image")
    public ResponseEntity<?> getTaskImage(@PathVariable String taskId) {
        return dietLogRepository.findByTaskId(taskId)
                .map(log_ -> {
                    if (log_.getOssKey() == null || log_.getOssKey().isBlank()) {
                        return ResponseEntity.notFound().build();
                    }

                    try {
                        OssService.DownloadedObject image = ossService.downloadObject(log_.getOssKey());
                        MediaType mediaType = MediaType.APPLICATION_OCTET_STREAM;
                        if (image.getContentType() != null && !image.getContentType().isBlank()) {
                            try {
                                mediaType = MediaType.parseMediaType(image.getContentType());
                            } catch (Exception ignored) {
                                mediaType = MediaType.APPLICATION_OCTET_STREAM;
                            }
                        }

                        return ResponseEntity.ok()
                                .contentType(mediaType)
                                .body(image.getBytes());
                    } catch (Exception e) {
                        log.warn("Failed to load diet log image for taskId={}: {}", taskId, e.getMessage());
                        return ResponseEntity.internalServerError().body(Map.of(
                                "error", "加载历史图片失败"
                        ));
                    }
                })
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping
    public ResponseEntity<?> listUserDietLogs(
            @RequestParam Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size
    ) {
        int normalizedPage = Math.max(0, page);
        int normalizedSize = Math.min(50, Math.max(1, size));

        var pageData = dietLogRepository.findByUserIdOrderByLoggedAtDesc(
                userId,
                PageRequest.of(normalizedPage, normalizedSize)
        );

        List<Map<String, Object>> logs = pageData.getContent().stream().map(log_ -> {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("taskId", log_.getTaskId());
            item.put("mealType", log_.getMealType());
            item.put("loggedAt", log_.getLoggedAt().toInstant(ZoneOffset.UTC).toString());

            if (log_.getAnalysisResult() != null) {
                try {
                    var json = objectMapper.readTree(log_.getAnalysisResult());
                    item.put("status", json.path("status").asText("COMPLETED"));
                    item.put("adviceReport", json.path("adviceReport").asText(null));

                    var segmentation = json.path("segmentationResult");
                    var items = segmentation.path("detected_items");
                    item.put("detectedItemsCount", items.isArray() ? items.size() : 0);
                } catch (Exception e) {
                    item.put("status", "COMPLETED");
                    item.put("adviceReport", null);
                    item.put("detectedItemsCount", 0);
                }
            } else {
                item.put("status", "PENDING");
                item.put("adviceReport", null);
                item.put("detectedItemsCount", 0);
            }

            return item;
        }).toList();

        return ResponseEntity.ok(Map.of(
                "content", logs,
                "page", pageData.getNumber(),
                "size", pageData.getSize(),
                "totalElements", pageData.getTotalElements(),
                "totalPages", pageData.getTotalPages(),
                "hasNext", pageData.hasNext()
        ));
    }

    private ImageAnalysisTaskMessage.UserContext buildUserContext(
            long userId,
            Integer age,
            Integer heightCm,
            Double weightKg,
            String gender,
            String activityLevel
    ) {
        return userRepository.findById(userId)
                .map(user -> toUserContext(user, age, heightCm, weightKg, gender, activityLevel))
                .orElse(ImageAnalysisTaskMessage.UserContext.builder()
                        .dietaryRestrictions(Collections.emptyList())
                        .healthGoal("GENERAL_HEALTH")
                        .dailyCalorieTarget(2000)
                        .age(age)
                        .heightCm(heightCm)
                        .weightKg(weightKg)
                        .gender(gender == null || gender.isBlank() ? "OTHER" : gender)
                        .activityLevel(activityLevel)
                        .build());
    }

    private ImageAnalysisTaskMessage.UserContext toUserContext(
            User user,
            Integer age,
            Integer heightCm,
            Double weightKg,
            String gender,
            String activityLevel
    ) {
        return ImageAnalysisTaskMessage.UserContext.builder()
                .dietaryRestrictions(parseDietaryRestrictions(user.getDietaryRestrictions()))
                .healthGoal(user.getHealthGoal())
                .dailyCalorieTarget(user.getDailyCalorieTarget())
                .age(age)
                .heightCm(heightCm != null ? heightCm : user.getHeightCm())
                .weightKg(weightKg != null ? weightKg : user.getWeightKg())
                .gender(gender != null && !gender.isBlank() ? gender : user.getGender())
                .activityLevel(activityLevel)
                .build();
    }

    private List<String> parseDietaryRestrictions(String rawJson) {
        if (rawJson == null || rawJson.isBlank()) {
            return Collections.emptyList();
        }
        try {
            return objectMapper.readValue(
                    rawJson,
                    objectMapper.getTypeFactory().constructCollectionType(List.class, String.class)
            );
        } catch (Exception e) {
            log.warn("Unable to parse dietary_restrictions JSON: {}", rawJson);
            return Collections.emptyList();
        }
    }

    private String deriveStatus(String analysisResultJson) {
        try {
            return objectMapper.readTree(analysisResultJson).path("status").asText("COMPLETED");
        } catch (Exception e) {
            return "COMPLETED";
        }
    }

    private String extractErrorMessage(com.fasterxml.jackson.databind.JsonNode analysisNode) {
        if (analysisNode == null) {
            return null;
        }
        if (analysisNode.hasNonNull("error")) {
            return analysisNode.get("error").asText();
        }
        if (analysisNode.hasNonNull("errorMessage")) {
            return analysisNode.get("errorMessage").asText();
        }
        var segNode = analysisNode.path("segmentationResult");
        if (!segNode.isMissingNode() && segNode.hasNonNull("error")) {
            return segNode.get("error").asText();
        }
        return null;
    }

    private boolean isPendingTimedOut(DietLog log_) {
        LocalDateTime loggedAt = log_.getLoggedAt();
        if (loggedAt == null) {
            return false;
        }
        long ageSeconds = ChronoUnit.SECONDS.between(loggedAt, LocalDateTime.now());
        return ageSeconds >= PENDING_TIMEOUT_SECONDS;
    }

    private String buildPendingTimeoutResult(DietLog log_) {
        String timeoutSeconds = String.valueOf(PENDING_TIMEOUT_SECONDS);
        try {
            return objectMapper.writeValueAsString(Map.of(
                    "status", "FAILED",
                    "taskId", log_.getTaskId(),
                "error", "分析任务超时：超过" + timeoutSeconds + "秒仍未完成。请检查 nutri-agent 消费器与分割服务状态。",
                "errorMessage", "分析任务超时：超过" + timeoutSeconds + "秒仍未完成。请稍后重试。",
                    "workflowMode", "CALORIE_ONLY",
                    "workflowTrace", List.of("status_polling: pending timeout auto-failed")
            ));
        } catch (Exception e) {
            return "{\"status\":\"FAILED\",\"error\":\"分析任务超时\"}";
        }
    }

    private String buildAnalysisImageBase64(MultipartFile file) throws IOException {
        byte[] originalBytes = file.getBytes();
        if (originalBytes.length == 0) {
            return null;
        }

        try (ByteArrayInputStream input = new ByteArrayInputStream(originalBytes)) {
            BufferedImage source = ImageIO.read(input);
            if (source == null) {
                return Base64.getEncoder().encodeToString(originalBytes);
            }

            BufferedImage resized = resizeForAnalysis(source);
            byte[] encodedBytes = encodeJpeg(resized, ANALYSIS_IMAGE_JPEG_QUALITY);
            return Base64.getEncoder().encodeToString(encodedBytes);
        } catch (Exception exc) {
            log.warn("Failed to build inline analysis image payload, falling back to original bytes: {}", exc.getMessage());
            return Base64.getEncoder().encodeToString(originalBytes);
        }
    }

    private BufferedImage resizeForAnalysis(BufferedImage source) {
        int sourceWidth = source.getWidth();
        int sourceHeight = source.getHeight();
        int longSide = Math.max(sourceWidth, sourceHeight);
        if (longSide <= ANALYSIS_IMAGE_MAX_SIDE && source.getType() == BufferedImage.TYPE_INT_RGB) {
            return source;
        }

        double scale = longSide > ANALYSIS_IMAGE_MAX_SIDE
                ? (double) ANALYSIS_IMAGE_MAX_SIDE / (double) longSide
                : 1.0;
        int targetWidth = Math.max(1, (int) Math.round(sourceWidth * scale));
        int targetHeight = Math.max(1, (int) Math.round(sourceHeight * scale));

        BufferedImage resized = new BufferedImage(targetWidth, targetHeight, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = resized.createGraphics();
        try {
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, targetWidth, targetHeight);
            graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            graphics.drawImage(source, 0, 0, targetWidth, targetHeight, null);
        } finally {
            graphics.dispose();
        }
        return resized;
    }

    private byte[] encodeJpeg(BufferedImage image, float quality) throws IOException {
        try (ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            var writers = ImageIO.getImageWritersByFormatName("jpg");
            if (!writers.hasNext()) {
                ImageIO.write(image, "jpg", output);
                return output.toByteArray();
            }

            ImageWriter writer = writers.next();
            try (ImageOutputStream imageOutput = ImageIO.createImageOutputStream(output)) {
                writer.setOutput(imageOutput);
                ImageWriteParam writeParam = writer.getDefaultWriteParam();
                if (writeParam.canWriteCompressed()) {
                    writeParam.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
                    writeParam.setCompressionQuality(quality);
                }
                writer.write(null, new IIOImage(image, null, null), writeParam);
            } finally {
                writer.dispose();
            }
            return output.toByteArray();
        }
    }

}
