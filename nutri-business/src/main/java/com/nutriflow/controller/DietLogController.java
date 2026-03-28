package com.nutriflow.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nutriflow.model.DietLog;
import com.nutriflow.mq.FoodAnalysisProducer;
import com.nutriflow.mq.ImageAnalysisTaskMessage;
import com.nutriflow.repository.DietLogRepository;
import com.nutriflow.service.OssService;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.Instant;
import java.util.LinkedHashMap;
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

    private final OssService ossService;
    private final FoodAnalysisProducer producer;
    private final DietLogRepository dietLogRepository;
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
            @RequestParam("file") MultipartFile file) throws IOException {

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
                .mealType(mealType)
                .createdAt(Instant.now())
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
                    resp.put("status", completed ? "COMPLETED" : "PENDING");
                    if (completed) {
                        try {
                            resp.put("analysisResult",
                                    objectMapper.readValue(log_.getAnalysisResult(), Object.class));
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
}
