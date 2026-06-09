SET NAMES utf8mb4;

SET @sql = IF(
    (SELECT COUNT(*) FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bpm_oa_overtime' AND COLUMN_NAME = 'work_date') = 0,
    'ALTER TABLE `bpm_oa_overtime`
      ADD COLUMN `work_date` date DEFAULT NULL COMMENT ''加班日期'' AFTER `type`,
      ADD COLUMN `duration_hours` decimal(6,2) DEFAULT NULL COMMENT ''加班时长（小时）'' AFTER `end_time`,
      ADD COLUMN `work_location` varchar(255) DEFAULT NULL COMMENT ''加班地点'' AFTER `duration_hours`,
      ADD COLUMN `work_content` varchar(1000) DEFAULT NULL COMMENT ''加班内容'' AFTER `work_location`,
      ADD COLUMN `compensation_type` tinyint DEFAULT NULL COMMENT ''补偿方式'' AFTER `work_content`,
      ADD COLUMN `project_name` varchar(255) DEFAULT NULL COMMENT ''关联项目'' AFTER `compensation_type`,
      ADD COLUMN `remark` varchar(500) DEFAULT NULL COMMENT ''备注'' AFTER `project_name`',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `bpm_oa_outing` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '临时外出申请主键',
  `user_id` bigint NOT NULL COMMENT '申请人用户编号',
  `type` int NOT NULL COMMENT '外出类型',
  `outing_date` date NOT NULL COMMENT '外出日期',
  `start_time` datetime NOT NULL COMMENT '开始时间',
  `end_time` datetime NOT NULL COMMENT '结束时间',
  `duration_hours` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '外出时长（小时）',
  `destination` varchar(255) DEFAULT NULL COMMENT '外出地点',
  `outside_office` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否离院',
  `contact_mobile` varchar(32) DEFAULT NULL COMMENT '联系电话',
  `companion_names` varchar(255) DEFAULT NULL COMMENT '同行人员',
  `reason` varchar(1000) NOT NULL COMMENT '外出事由',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `status` int NOT NULL DEFAULT '1' COMMENT '审批状态',
  `process_instance_id` varchar(64) DEFAULT NULL COMMENT '流程实例编号',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `creator` varchar(64) DEFAULT '' COMMENT '创建者',
  `updater` varchar(64) DEFAULT '' COMMENT '更新者',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT '1' COMMENT '租户编号',
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_process_instance_id` (`process_instance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OA 临时外出申请';

CREATE TABLE IF NOT EXISTS `bpm_oa_leave_cancel` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '销假申请主键',
  `user_id` bigint NOT NULL COMMENT '申请人用户编号',
  `type` tinyint NOT NULL COMMENT '销假类型',
  `reason` varchar(200) NOT NULL COMMENT '销假原因',
  `start_time` datetime NOT NULL COMMENT '开始时间',
  `end_time` datetime NOT NULL COMMENT '结束时间',
  `day` tinyint NOT NULL DEFAULT '0' COMMENT '销假天数',
  `status` tinyint NOT NULL DEFAULT '1' COMMENT '审批状态',
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OA 销假申请';

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6525, '临时外出', '', 2, 9, 5, 'outing', 'fa:location-arrow', 'bpm/oa/outing/index', 'BpmOAOuting', 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6525);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6526, '临时外出查询', 'bpm:oa-leave:query', 3, 1, 6525, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6526);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6527, '临时外出创建', 'bpm:oa-leave:create', 3, 2, 6525, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6527);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6528, '销假', '', 2, 10, 5, 'leaveCancel', 'fa:undo', 'bpm/oa/leave-cancel/index', 'BpmOALeaveCancel', 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6528);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6529, '销假查询', 'bpm:oa-leave:query', 3, 1, 6528, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6529);

INSERT INTO `system_menu` (`id`, `name`, `permission`, `type`, `sort`, `parent_id`, `path`, `icon`, `component`, `component_name`, `status`, `visible`, `keep_alive`, `always_show`, `creator`, `create_time`, `updater`, `update_time`, `deleted`)
SELECT 6530, '销假创建', 'bpm:oa-leave:create', 3, 2, 6528, '', '', '', NULL, 0, b'1', b'1', b'1', '1', NOW(), '1', NOW(), b'0'
WHERE NOT EXISTS (SELECT 1 FROM `system_menu` WHERE `id` = 6530);

INSERT INTO `system_role_menu` (`role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 2, 6525, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6525);

INSERT INTO `system_role_menu` (`role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 2, 6526, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6526);

INSERT INTO `system_role_menu` (`role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 2, 6527, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6527);

INSERT INTO `system_role_menu` (`role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 2, 6528, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6528);

INSERT INTO `system_role_menu` (`role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 2, 6529, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6529);

INSERT INTO `system_role_menu` (`role_id`, `menu_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 2, 6530, '1', NOW(), '1', NOW(), b'0', 1
WHERE NOT EXISTS (SELECT 1 FROM `system_role_menu` WHERE `role_id` = 2 AND `menu_id` = 6530);
