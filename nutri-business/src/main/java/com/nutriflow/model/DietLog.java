package com.nutriflow.model;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "diet_logs")
public class DietLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "task_id", nullable = false, length = 36)
    private String taskId;

    @Column(name = "meal_type", nullable = false, length = 16)
    private String mealType;

    @Column(name = "oss_key", nullable = false, length = 512)
    private String ossKey;

    @Column(name = "analysis_result", columnDefinition = "json")
    private String analysisResult;

    @Column(name = "logged_at", updatable = false)
    private LocalDateTime loggedAt = LocalDateTime.now();
}
