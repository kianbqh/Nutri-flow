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
  `health_goal`  VARCHAR(32)  DEFAULT 'GENERAL_HEALTH',
  `daily_calorie_target` INT DEFAULT 2000,
  `dietary_restrictions` JSON DEFAULT NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
  KEY `idx_user_logged` (`user_id`, `logged_at`),
  CONSTRAINT `fk_diet_log_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
