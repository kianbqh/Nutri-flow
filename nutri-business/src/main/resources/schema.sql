SET @users_phone_exists = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME = 'phone'
);

SET @users_phone_sql = IF(
    @users_phone_exists = 0,
    'ALTER TABLE `users` ADD COLUMN `phone` VARCHAR(20) DEFAULT NULL AFTER `password_hash`',
    'SELECT 1'
);

PREPARE stmt_users_phone FROM @users_phone_sql;
EXECUTE stmt_users_phone;
DEALLOCATE PREPARE stmt_users_phone;

SET @users_nickname_exists = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND COLUMN_NAME = 'nickname'
);

SET @users_nickname_sql = IF(
    @users_nickname_exists = 0,
    'ALTER TABLE `users` ADD COLUMN `nickname` VARCHAR(24) DEFAULT NULL AFTER `phone`',
    'SELECT 1'
);

PREPARE stmt_users_nickname FROM @users_nickname_sql;
EXECUTE stmt_users_nickname;
DEALLOCATE PREPARE stmt_users_nickname;

SET @users_nickname_key_exists = (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND INDEX_NAME = 'uk_users_nickname'
);

SET @users_nickname_key_sql = IF(
    @users_nickname_key_exists = 0,
    'ALTER TABLE `users` ADD CONSTRAINT `uk_users_nickname` UNIQUE (`nickname`)',
    'SELECT 1'
);

PREPARE stmt_users_nickname_key FROM @users_nickname_key_sql;
EXECUTE stmt_users_nickname_key;
DEALLOCATE PREPARE stmt_users_nickname_key;

UPDATE `users`
SET `phone` = '13800000001'
WHERE `id` = 1 AND (`phone` IS NULL OR TRIM(`phone`) = '');