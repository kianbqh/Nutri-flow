-- Nutri-Flow database initialization script
-- Run automatically by Docker Compose on first start

CREATE DATABASE IF NOT EXISTS nutri_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE nutri_db;

-- ── Users ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `users` (
  `id`           BIGINT       NOT NULL AUTO_INCREMENT,
  `username`     VARCHAR(64)  NOT NULL UNIQUE,
  `email`        VARCHAR(128) NOT NULL UNIQUE,
  `password_hash` VARCHAR(256) NOT NULL,
  `phone`        VARCHAR(20)  DEFAULT NULL,
  `nickname`     VARCHAR(24)  DEFAULT NULL,
  `health_goal`  VARCHAR(32)  DEFAULT 'GENERAL_HEALTH',
  `daily_calorie_target` INT DEFAULT 2000,
  `dietary_restrictions` JSON DEFAULT NULL,
  `height_cm`    INT          DEFAULT NULL COMMENT 'Body height in cm',
  `weight_kg`    DOUBLE       DEFAULT NULL COMMENT 'Body weight in kg',
  `gender`       VARCHAR(10)  DEFAULT NULL COMMENT 'MALE | FEMALE | OTHER',
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_users_nickname` (`nickname`),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default demo user for MVP end-to-end testing (X-User-Id: 1)
INSERT INTO `users` (
  `id`, `username`, `email`, `password_hash`, `phone`, `health_goal`, `daily_calorie_target`, `dietary_restrictions`
)
SELECT
  1, 'demo_user', 'demo@nutriflow.local', 'demo_hash_placeholder', '13800000001',
  'WEIGHT_LOSS', 1800, JSON_ARRAY('high_sugar')
WHERE NOT EXISTS (SELECT 1 FROM `users` WHERE `id` = 1);

-- ── Diet Logs ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `diet_logs` (
  `id`           BIGINT       NOT NULL AUTO_INCREMENT,
  `user_id`      BIGINT       NOT NULL,
  `task_id`      VARCHAR(36)  NOT NULL COMMENT 'UUID – links to MQ task',
  `meal_type`    VARCHAR(16)  NOT NULL,
  `oss_key`      VARCHAR(512) NOT NULL COMMENT 'Object key in MinIO/OSS',
  `analysis_result` JSON DEFAULT NULL COMMENT 'AI analysis result payload',
  `logged_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_id` (`task_id`),
  KEY `idx_user_logged` (`user_id`, `logged_at`),
  CONSTRAINT `fk_diet_log_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Structured, privacy-safe task lifecycle events used by the admin dashboard.
CREATE TABLE IF NOT EXISTS `task_trace_events` (
  `id`           BIGINT        NOT NULL AUTO_INCREMENT,
  `task_id`      VARCHAR(36)   NOT NULL,
  `stage`        VARCHAR(32)   NOT NULL,
  `state`        VARCHAR(16)   NOT NULL,
  `service_name` VARCHAR(32)   NOT NULL,
  `detail`       VARCHAR(512)  DEFAULT NULL,
  `duration_ms`  DECIMAL(12,2) DEFAULT NULL,
  `occurred_at`  DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_trace_task_time` (`task_id`, `occurred_at`),
  KEY `idx_trace_time` (`occurred_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
