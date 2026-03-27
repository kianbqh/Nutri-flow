package com.nutriflow.controller;

import com.nutriflow.mq.FoodAnalysisProducer;
import com.nutriflow.mq.ImageAnalysisTaskMessage;
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
import java.util.Map;
import java.util.UUID;

/**
 * REST endpoint for meal-image upload and analysis trigger.
 *
 * <p>Flow:
 * <ol>
 *   <li>Client uploads image → stored in OSS.</li>
 *   <li>Pre-signed URL + task metadata published to RabbitMQ.</li>
 *   <li>nutri-agent consumes the message and performs AI analysis.</li>
 * </ol>
 */
@Slf4j
@RestController
@RequestMapping("/v1/diet-logs")
@RequiredArgsConstructor
public class DietLogController {

    private final OssService ossService;
    private final FoodAnalysisProducer producer;

    /**
     * Upload a meal image and dispatch an analysis task.
     *
     * @param userId   authenticated user ID (header or param – simplified for scaffold)
     * @param mealType one of BREAKFAST, LUNCH, DINNER, SNACK
     * @param file     the meal image
     * @return taskId for polling
     */
    @PostMapping("/upload")
    public ResponseEntity<Map<String, String>> uploadMealImage(
            @RequestHeader("X-User-Id") @NotBlank String userId,
            @RequestParam @Pattern(regexp = "BREAKFAST|LUNCH|DINNER|SNACK") String mealType,
            @RequestParam("file") MultipartFile file) throws IOException {

        String ossKey = ossService.uploadMealImage(userId, mealType, file);
        String imageUrl = ossService.generatePresignedUrl(ossKey);
        String taskId = UUID.randomUUID().toString();

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
}
