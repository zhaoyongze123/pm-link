SET NAMES utf8mb4;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'applicant_name') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `applicant_name` varchar(64) DEFAULT NULL COMMENT ''申请人姓名快照'' AFTER `user_id`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'dept_id') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `dept_id` bigint DEFAULT NULL COMMENT ''部门编号'' AFTER `applicant_name`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'dept_name') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `dept_name` varchar(100) DEFAULT NULL COMMENT ''部门名称快照'' AFTER `dept_id`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'file_name') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `file_name` varchar(255) DEFAULT NULL COMMENT ''文件名称'' AFTER `type`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'file_count') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `file_count` int DEFAULT NULL COMMENT ''文件份数'' AFTER `file_name`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'counterpart_unit') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `counterpart_unit` varchar(255) DEFAULT NULL COMMENT ''对方单位'' AFTER `day`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'external_carry') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `external_carry` bit(1) DEFAULT b''0'' COMMENT ''是否外带'' AFTER `counterpart_unit`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'operator_name') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `operator_name` varchar(64) DEFAULT NULL COMMENT ''经办人'' AFTER `external_carry`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'attachment_urls') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `attachment_urls` text COMMENT ''附件地址 JSON'' AFTER `operator_name`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_seal' AND COLUMN_NAME = 'remark') = 0,
    'ALTER TABLE `bpm_oa_seal` ADD COLUMN `remark` varchar(500) DEFAULT NULL COMMENT ''备注'' AFTER `attachment_urls`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `bpm_oa_document` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '合同/文件审批主键',
  `user_id` bigint NOT NULL COMMENT '申请人用户编号',
  `applicant_name` varchar(64) DEFAULT NULL COMMENT '申请人姓名快照',
  `dept_id` bigint DEFAULT NULL COMMENT '部门编号',
  `dept_name` varchar(100) DEFAULT NULL COMMENT '部门名称快照',
  `file_type` varchar(100) NOT NULL COMMENT '文件类型',
  `title` varchar(255) NOT NULL COMMENT '文件标题',
  `related_project` varchar(255) DEFAULT NULL COMMENT '关联项目',
  `counterpart_unit` varchar(255) DEFAULT NULL COMMENT '对方单位',
  `amount` decimal(18, 2) DEFAULT NULL COMMENT '金额',
  `reason` varchar(1000) NOT NULL COMMENT '审批事由',
  `attachment_body_urls` text COMMENT '附件正文地址 JSON',
  `attachment_extra_urls` text COMMENT '附件补充材料地址 JSON',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `status` int NOT NULL DEFAULT '1' COMMENT '审批状态',
  `process_instance_id` varchar(64) DEFAULT NULL COMMENT '流程实例编号',
  `creator` varchar(64) DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT '1' COMMENT '租户编号',
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_process_instance_id` (`process_instance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OA 合同/文件审批';

CREATE TABLE IF NOT EXISTS `bpm_oa_project` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '项目立项申请主键',
  `user_id` bigint NOT NULL COMMENT '申请人用户编号',
  `applicant_name` varchar(64) DEFAULT NULL COMMENT '申请人姓名快照',
  `dept_id` bigint DEFAULT NULL COMMENT '部门编号',
  `dept_name` varchar(100) DEFAULT NULL COMMENT '部门名称快照',
  `project_name` varchar(255) NOT NULL COMMENT '项目名称',
  `project_type` varchar(100) NOT NULL COMMENT '项目类型',
  `owner_unit` varchar(255) NOT NULL COMMENT '业主单位',
  `project_source` varchar(255) NOT NULL COMMENT '项目来源',
  `project_leader_id` bigint NOT NULL COMMENT '项目负责人用户编号',
  `project_leader_name` varchar(64) DEFAULT NULL COMMENT '项目负责人姓名',
  `project_overview` text COMMENT '项目概况',
  `project_amount` decimal(18, 2) NOT NULL COMMENT '合同金额/预估金额',
  `planned_start_time` datetime NOT NULL COMMENT '计划开始时间',
  `planned_end_time` datetime NOT NULL COMMENT '计划结束时间',
  `participant_dept_ids` text COMMENT '参与部门编号 JSON',
  `participant_dept_names` varchar(500) DEFAULT NULL COMMENT '参与部门名称',
  `risk_description` text COMMENT '风险说明',
  `attachment_urls` text COMMENT '附件地址 JSON',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `status` int NOT NULL DEFAULT '1' COMMENT '审批状态',
  `process_instance_id` varchar(64) DEFAULT NULL COMMENT '流程实例编号',
  `creator` varchar(64) DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT '1' COMMENT '租户编号',
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_process_instance_id` (`process_instance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OA 项目立项申请';

CREATE TABLE IF NOT EXISTS `bpm_oa_staffing` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '项目人员调配申请主键',
  `user_id` bigint NOT NULL COMMENT '申请人用户编号',
  `applicant_name` varchar(64) DEFAULT NULL COMMENT '申请人姓名快照',
  `dept_id` bigint DEFAULT NULL COMMENT '部门编号',
  `dept_name` varchar(100) DEFAULT NULL COMMENT '部门名称快照',
  `project_name` varchar(255) NOT NULL COMMENT '所属项目',
  `member_ids` text COMMENT '调入/调出人员编号 JSON',
  `member_names` varchar(500) DEFAULT NULL COMMENT '调入/调出人员姓名',
  `reason` varchar(1000) NOT NULL COMMENT '调配原因',
  `transfer_time` datetime NOT NULL COMMENT '调配时间',
  `expected_work_period` varchar(255) NOT NULL COMMENT '预计工作周期',
  `target_unit` varchar(255) NOT NULL COMMENT '接收部门或项目组',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `status` int NOT NULL DEFAULT '1' COMMENT '审批状态',
  `process_instance_id` varchar(64) DEFAULT NULL COMMENT '流程实例编号',
  `creator` varchar(64) DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT '1' COMMENT '租户编号',
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_process_instance_id` (`process_instance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OA 项目人员调配申请';

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6516, '合同/文件审批', '', 2, 6, 5, 'document', 'fa:file-text-o', 'bpm/oa/document/index', 'BpmOADocument', 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6516);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6517, '合同/文件审批查询', 'bpm:oa-leave:query', 3, 1, 6516, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6517);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6518, '合同/文件审批创建', 'bpm:oa-leave:create', 3, 2, 6516, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6518);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6519, '项目立项申请', '', 2, 7, 5, 'project', 'fa:folder-open-o', 'bpm/oa/project/index', 'BpmOAProject', 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6519);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6520, '项目立项申请查询', 'bpm:oa-leave:query', 3, 1, 6519, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6520);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6521, '项目立项申请创建', 'bpm:oa-leave:create', 3, 2, 6519, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6521);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6522, '项目人员调配申请', '', 2, 8, 5, 'staffing', 'fa:users', 'bpm/oa/staffing/index', 'BpmOAStaffing', 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6522);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6523, '项目人员调配申请查询', 'bpm:oa-leave:query', 3, 1, 6522, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6523);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6524, '项目人员调配申请创建', 'bpm:oa-leave:create', 3, 2, 6522, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6524);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7016, 2, 6516, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6516);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7017, 2, 6517, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6517);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7018, 2, 6518, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6518);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7019, 2, 6519, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6519);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7020, 2, 6520, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6520);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7021, 2, 6521, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6521);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7022, 2, 6522, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6522);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7023, 2, 6523, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6523);

INSERT INTO `system_role_menu` (`id`, `role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 7024, 2, 6524, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6524);
