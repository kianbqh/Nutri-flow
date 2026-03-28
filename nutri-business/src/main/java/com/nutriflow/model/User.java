package com.nutriflow.model;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 64)
    private String username;

    @Column(nullable = false, unique = true, length = 128)
    private String email;

    @Column(name = "password_hash", nullable = false, length = 256)
    private String passwordHash;

    @Column(name = "health_goal", length = 32)
    private String healthGoal = "GENERAL_HEALTH";

    @Column(name = "daily_calorie_target")
    private Integer dailyCalorieTarget = 2000;

    @Column(name = "dietary_restrictions", columnDefinition = "json")
    private String dietaryRestrictions;

    /** Optional biometric fields – used for BMR-based calorie personalisation. */
    @Column(name = "height_cm")
    private Integer heightCm;

    @Column(name = "weight_kg")
    private Double weightKg;

    @Column(name = "gender", length = 10)
    private String gender; // MALE | FEMALE | OTHER

    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "updated_at")
    private LocalDateTime updatedAt = LocalDateTime.now();
}
