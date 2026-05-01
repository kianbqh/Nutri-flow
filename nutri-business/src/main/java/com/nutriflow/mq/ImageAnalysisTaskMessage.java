package com.nutriflow.mq;

import lombok.Builder;
import lombok.Data;
import lombok.extern.jackson.Jacksonized;

import java.time.Instant;
import java.util.List;

/**
 * MQ message published to the food-analysis task queue.
 * Mirrors contracts/image_analysis_task.schema.json.
 */
@Data
@Builder
@Jacksonized
public class ImageAnalysisTaskMessage {

    /** Globally unique task identifier (UUID). */
    private String taskId;

    /** The user who submitted the meal image. */
    private String userId;

    /** Pre-signed URL to fetch the image from OSS/MinIO. */
    private String imageUrl;

    /** Raw OSS object key for durable references. */
    private String ossKey;

    /** Optional resized JPEG payload for downstream inference without OSS re-fetch. */
    private String analysisImageBase64;

    /** BREAKFAST | LUNCH | DINNER | SNACK */
    private String mealType;

    /** Task creation time (ISO-8601). */
    private Instant createdAt;

    /** Optional user health context passed at publish time. */
    private UserContext userContext;

    /** RabbitMQ routing key for the result callback (optional). */
    private String callbackRoutingKey;

    @Data
    @Builder
    @Jacksonized
    public static class UserContext {
        private List<String> dietaryRestrictions;
        private String healthGoal;
        private Integer dailyCalorieTarget;
        private Integer age;
        private Integer heightCm;
        private Double weightKg;
        private String gender;
        private String activityLevel;
    }
}
