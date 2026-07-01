ALTER TABLE `party_file`
  ADD COLUMN `storage_type` tinyint NOT NULL DEFAULT 1 COMMENT '存储类型 1本地 2可道云' AFTER `attachment_file_ids`,
  ADD COLUMN `kod_source_id` bigint NULL DEFAULT NULL COMMENT '可道云目录来源编号' AFTER `storage_type`,
  ADD COLUMN `kod_folder_path` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL COMMENT '可道云目录路径' AFTER `kod_source_id`,
  ADD COLUMN `kod_folder_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL COMMENT '可道云目录名称' AFTER `kod_folder_path`,
  ADD KEY `idx_kod_source_id` (`kod_source_id`) USING BTREE;

CREATE TABLE IF NOT EXISTS `party_file_kod_source`  (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '来源编号',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '来源名称',
  `base_url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '可道云地址',
  `app_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'appName',
  `access_token` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '访问令牌',
  `service_username` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL COMMENT '服务账号',
  `service_password` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL COMMENT '服务密码(加密)',
  `token_expire_time` datetime NULL DEFAULT NULL COMMENT '令牌过期时间',
  `root_folder_path` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '根目录路径',
  `root_folder_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '根目录名称',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `is_default` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否默认',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_party_file_kod_source_name` (`name`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '党务文件可道云目录来源表';

ALTER TABLE `party_file_kod_source`
  ADD COLUMN IF NOT EXISTS `service_username` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL COMMENT '服务账号' AFTER `access_token`,
  ADD COLUMN IF NOT EXISTS `service_password` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL COMMENT '服务密码(加密)' AFTER `service_username`,
  ADD COLUMN IF NOT EXISTS `token_expire_time` datetime NULL DEFAULT NULL COMMENT '令牌过期时间' AFTER `service_password`;

CREATE TABLE IF NOT EXISTS `party_file_kod_attachment`  (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键',
  `file_id` bigint NOT NULL COMMENT '本地文件记录编号',
  `kod_source_id` bigint NOT NULL COMMENT '可道云来源编号',
  `kod_file_path` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '可道云文件路径',
  `kod_parent_path` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '可道云父目录路径',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_party_file_kod_attachment_file_id` (`file_id`) USING BTREE,
  KEY `idx_party_file_kod_attachment_source_id` (`kod_source_id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '党务文件可道云附件映射表';
