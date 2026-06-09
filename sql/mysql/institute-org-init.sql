START TRANSACTION;

-- 院内组织初始化脚本
-- 适用对象：tenant_id = 1
-- 执行策略：
-- 1. 清空租户 1 当前旧部门树（当前现场为：总公司/销售部/项目部/财务部/行政人事部）
-- 2. 重建院部 + 10 个业务部门
-- 3. 初始化岗位
-- 4. 创建/更新已知账号用户，并绑定部门、岗位、角色
-- 5. 缺少账号的人员暂不创建用户，仅保留在注释中等待补齐

SET @tenant_id := 1;
SET @creator := 'institute-org-init';
SET @default_password := '$2a$04$sEtimsHu9YCkYY4/oqElHem2Ijc9ld20eYO6lN.g/21NfLUTDLB9W';

-- 清理旧部门引用，避免删除部门后留下悬挂 dept_id
UPDATE system_users
SET dept_id = NULL
WHERE tenant_id = @tenant_id;

-- 清理角色自定义数据范围中的旧部门编号
UPDATE system_role
SET data_scope_dept_ids = ''
WHERE tenant_id = @tenant_id
  AND data_scope_dept_ids <> '';

-- 删除旧部门树
DELETE FROM system_dept
WHERE tenant_id = @tenant_id;

-- 初始化真实部门树
INSERT INTO system_dept
(`id`, `name`, `parent_id`, `sort`, `leader_user_id`, `phone`, `email`, `status`,
 `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
VALUES
  (201, '院部', 0, 1, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (202, '城市更新规划所', 201, 10, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (203, '城市设计所', 201, 20, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (204, '总体规划和专项规划所', 201, 30, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (205, '乡村规划所', 201, 40, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (206, '综合科（人事、行政、财务）', 201, 50, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (207, '规划研究室', 201, 60, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (208, '数字城市所', 201, 70, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (209, '交通市政规划所', 201, 80, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (210, '技术审查室', 201, 90, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id),
  (211, '综合科（经营）', 201, 100, NULL, NULL, NULL, 0, @creator, NOW(), @creator, NOW(), b'0', @tenant_id);

-- 初始化岗位。若已存在则保留，不重复插入
INSERT INTO system_post
(`code`, `name`, `sort`, `status`, `remark`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 'institute_president', '院长', 10, 0, '院内组织初始化', @creator, NOW(), @creator, NOW(), b'0', @tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM system_post WHERE code = 'institute_president' AND tenant_id = @tenant_id AND deleted = b'0'
);

INSERT INTO system_post
(`code`, `name`, `sort`, `status`, `remark`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 'institute_vice_president', '副院长', 20, 0, '院内组织初始化', @creator, NOW(), @creator, NOW(), b'0', @tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM system_post WHERE code = 'institute_vice_president' AND tenant_id = @tenant_id AND deleted = b'0'
);

INSERT INTO system_post
(`code`, `name`, `sort`, `status`, `remark`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 'institute_chief_engineer', '总工/师', 30, 0, '院内组织初始化', @creator, NOW(), @creator, NOW(), b'0', @tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM system_post WHERE code = 'institute_chief_engineer' AND tenant_id = @tenant_id AND deleted = b'0'
);

INSERT INTO system_post
(`code`, `name`, `sort`, `status`, `remark`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 'institute_director', '所长', 40, 0, '院内组织初始化', @creator, NOW(), @creator, NOW(), b'0', @tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM system_post WHERE code = 'institute_director' AND tenant_id = @tenant_id AND deleted = b'0'
);

INSERT INTO system_post
(`code`, `name`, `sort`, `status`, `remark`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 'institute_manager', '负责人', 50, 0, '院内组织初始化', @creator, NOW(), @creator, NOW(), b'0', @tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM system_post WHERE code = 'institute_manager' AND tenant_id = @tenant_id AND deleted = b'0'
);

-- 普通员工岗位复用现有 system_post.code = user，若不存在则补建
INSERT INTO system_post
(`code`, `name`, `sort`, `status`, `remark`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT 'user', '普通员工', 60, 0, '院内组织初始化', @creator, NOW(), @creator, NOW(), b'0', @tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM system_post WHERE code = 'user' AND tenant_id = @tenant_id AND deleted = b'0'
);

DROP TEMPORARY TABLE IF EXISTS tmp_institute_user;
CREATE TEMPORARY TABLE tmp_institute_user (
  username VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  nickname VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  dept_id BIGINT NULL,
  post_code VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  role_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  remark VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
);

INSERT INTO tmp_institute_user (username, nickname, dept_id, post_code, role_name, remark) VALUES
('侯斌超', '侯斌超', 201, 'institute_president', '普通用户', NULL),
('钱爱梅', '钱爱梅', 201, 'institute_vice_president', '普通用户', NULL),
('马倩', '马倩', 201, 'institute_vice_president', '普通用户', '兼城市更新规划所负责人'),
('邴燕萍', '邵燕萍', 201, 'institute_vice_president', '普通用户', '兼总体规划和专项规划所负责人'),
('张华', '张华', 201, 'institute_chief_engineer', '普通用户', '特殊审批链：直接到院长'),
('张龄', '张龄', 201, 'institute_chief_engineer', '普通用户', '特殊审批链：直接到院长'),
('濮卫民', '濮卫民', 203, 'institute_director', '普通用户', NULL),
('李丹', '李丹', 205, 'institute_director', '普通用户', NULL),
('苏莉', '苏莉', 206, 'institute_director', '普通用户', NULL),
('罗翔', '罗翔', 207, 'institute_director', '普通用户', NULL),
('缪云涛', '缪云涛', 209, 'institute_director', '普通用户', NULL),
('严己', '严己白', 210, 'institute_director', '普通用户', '审批时从张华/张龄/朱新捷三选一'),
('何志华', '何志华', 211, 'institute_manager', '普通用户', NULL),
('李豪杰', '李豪杰', 211, 'user', '普通用户', '特殊审批链：先到何志华，再到张华'),
('朱新捷', '朱新捷', 210, 'institute_chief_engineer', '普通用户', '特殊审批链：直接到院长'),
('赖志勇', '赖志勇', 207, 'user', '普通用户', '特殊审批链：到朱新捷'),
('金晨', '金晨', 201, 'user', '部门管理员', '可道云侧部门管理员'),
('曹慧霆', '曹慧霆', 207, 'user', '部门管理员', NULL),
('马书韵', '马书韵', 203, 'user', '普通用户', NULL),
('卜义洁', '卜义洁', 202, 'user', '普通用户', NULL),
('黄潇仪', '黄潇仪', 202, 'user', '普通用户', NULL),
('张皑宁', '张皑宁', 202, 'user', '普通用户', NULL),
('毛丹', '毛丹', 202, 'user', '普通用户', NULL),
('蔡萌', '蔡萌', 202, 'user', '普通用户', NULL),
('郭云', '郭云', 202, 'user', '普通用户', NULL),
('朱艺', '朱艺', 204, 'user', '普通用户', NULL),
('徐佳琪', '徐佳琪', 203, 'user', '普通用户', NULL),
('盛亦文', '盛亦文', 203, 'user', '普通用户', NULL),
('陈洁', '陈洁', 204, 'user', '普通用户', NULL),
('许纯', '许纯', 202, 'user', '普通用户', NULL),
('傅韵同', '傅韵同', 202, 'user', '普通用户', NULL),
('金晓辉', '金晓辉', 202, 'user', '普通用户', NULL),
('黄俣博', '黄俣博', 203, 'user', '普通用户', NULL),
('向悦维', '向悦维', 205, 'user', '普通用户', NULL),
('胡可欣', '胡可欣', 205, 'user', '普通用户', NULL),
('罗雅', '罗雅', 203, 'user', '普通用户', NULL),
('徐心怡', '徐心怡', 205, 'user', '普通用户', NULL),
('黄静荷', '黄静荷', 204, 'user', '普通用户', NULL),
('王思齐', '王思齐', 205, 'user', '普通用户', NULL),
('李乐卉', '李乐卉', 202, 'user', '普通用户', NULL),
('赵莉', '赵莉', 209, 'user', '普通用户', NULL),
('许璇璇', '许璇璇', 204, 'user', '普通用户', NULL),
('张坤喆', '张坤喆', 204, 'user', '普通用户', NULL),
('李朗荻', '李朗荻', 203, 'user', '普通用户', NULL),
('何宏福', '何宏福', 209, 'user', '普通用户', NULL),
('张伟丽', '张伟丽', 209, 'user', '普通用户', NULL),
('黄丽萍', '黄丽萍', 202, 'user', '普通用户', '曾挂数字城市所辅助部门'),
('张弛', '张弛', 209, 'user', '普通用户', NULL),
('陶甄宇', '陶甄宇', 209, 'user', '普通用户', NULL),
('沈昱', '沈昱', 209, 'user', '普通用户', NULL),
('张井芳', '张井芳', 204, 'user', '普通用户', NULL),
('王春平', '王春平', 204, 'user', '普通用户', NULL),
('杨震雷', '杨震雷', 209, 'user', '普通用户', NULL);

-- 新建缺失用户
INSERT INTO system_users
(`username`, `password`, `nickname`, `remark`, `dept_id`, `post_ids`, `email`, `mobile`, `sex`, `avatar`, `status`,
 `login_ip`, `login_date`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT
  u.username,
  @default_password,
  u.nickname,
  u.remark,
  u.dept_id,
  CONCAT('[', p.id, ']'),
  '',
  '',
  0,
  '',
  0,
  '',
  NULL,
  @creator,
  NOW(),
  @creator,
  NOW(),
  b'0',
  @tenant_id
FROM tmp_institute_user u
JOIN system_post p
  ON p.code = u.post_code
 AND p.tenant_id = @tenant_id
 AND p.deleted = b'0'
WHERE NOT EXISTS (
  SELECT 1
  FROM system_users su
  WHERE su.username = u.username
    AND su.tenant_id = @tenant_id
    AND su.deleted = b'0'
);

-- 回填已存在用户的昵称、部门、岗位
UPDATE system_users su
JOIN tmp_institute_user u
  ON u.username = su.username
JOIN system_post p
  ON p.code = u.post_code
 AND p.tenant_id = @tenant_id
 AND p.deleted = b'0'
SET
  su.nickname = u.nickname,
  su.remark = u.remark,
  su.dept_id = u.dept_id,
  su.post_ids = CONCAT('[', p.id, ']'),
  su.status = 0,
  su.updater = @creator,
  su.update_time = NOW()
WHERE su.tenant_id = @tenant_id
  AND su.deleted = b'0';

-- 绑定用户岗位关系表，避免仅写 system_users.post_ids 导致按岗位反查用户失效
INSERT INTO system_user_post
(`user_id`, `post_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT
  su.id,
  p.id,
  @creator,
  NOW(),
  @creator,
  NOW(),
  b'0',
  @tenant_id
FROM tmp_institute_user u
JOIN system_users su
  ON su.username = u.username
 AND su.tenant_id = @tenant_id
 AND su.deleted = b'0'
JOIN system_post p
  ON p.code = u.post_code
 AND p.tenant_id = @tenant_id
 AND p.deleted = b'0'
WHERE NOT EXISTS (
  SELECT 1
  FROM system_user_post sup
  WHERE sup.user_id = su.id
    AND sup.post_id = p.id
    AND sup.tenant_id = @tenant_id
    AND sup.deleted = b'0'
);

-- 回填部门负责人
UPDATE system_dept d
JOIN system_users u ON u.username = '侯斌超' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 201 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '马倩' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 202 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '濮卫民' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 203 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '邴燕萍' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 204 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '李丹' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 205 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '缪云涛' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 209 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '严己' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 210 AND d.tenant_id = @tenant_id;

-- 数字城市所、综合科（人事/行政/财务）、规划研究室、综合科（经营）当前负责人缺账号，保持 NULL
UPDATE system_dept d
JOIN system_users u ON u.username = '苏莉' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 206 AND d.tenant_id = @tenant_id;

UPDATE system_dept d
JOIN system_users u ON u.username = '罗翔' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 207 AND d.tenant_id = @tenant_id;

-- 数字城市所当前无负责人，保持 NULL

UPDATE system_dept d
JOIN system_users u ON u.username = '何志华' AND u.tenant_id = @tenant_id AND u.deleted = b'0'
SET d.leader_user_id = u.id
WHERE d.id = 211 AND d.tenant_id = @tenant_id;
-- 绑定角色
INSERT INTO system_user_role
(`user_id`, `role_id`, `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
SELECT
  su.id,
  sr.id,
  @creator,
  NOW(),
  @creator,
  NOW(),
  b'0',
  @tenant_id
FROM tmp_institute_user u
JOIN system_users su
  ON su.username = u.username
 AND su.tenant_id = @tenant_id
 AND su.deleted = b'0'
JOIN system_role sr
  ON sr.name = u.role_name
 AND sr.tenant_id = @tenant_id
 AND sr.deleted = b'0'
WHERE NOT EXISTS (
  SELECT 1
  FROM system_user_role ur
  WHERE ur.user_id = su.id
    AND ur.role_id = sr.id
    AND ur.tenant_id = @tenant_id
    AND ur.deleted = b'0'
);

-- 特殊审批链配置清单（供 BPM 流程节点配置）
-- 1. 张华、张龄、朱新捷：直接到院长
-- 2. 严己白：从 张华 / 张龄 / 朱新捷 三选一
-- 3. 赖志勇：固定到朱新捷
-- 4. 李豪杰：先到何志华，再到张华
--
-- 最小回归校验
SELECT id, name, parent_id, leader_user_id
FROM system_dept
WHERE tenant_id = @tenant_id
ORDER BY id;

SELECT username, nickname, dept_id, post_ids
FROM system_users
WHERE tenant_id = @tenant_id
  AND username IN ('侯斌超', '钱爱梅', '马倩', '邴燕萍', '张华', '张龄', '濮卫民', '李丹', '苏莉', '罗翔', '缪云涛', '严己', '何志华', '李豪杰', '朱新捷', '赖志勇')
ORDER BY username;

SELECT su.username, sr.name AS role_name
FROM system_user_role ur
JOIN system_users su ON su.id = ur.user_id
JOIN system_role sr ON sr.id = ur.role_id
WHERE ur.tenant_id = @tenant_id
  AND su.username IN ('侯斌超', '钱爱梅', '马倩', '邴燕萍', '张华', '张龄', '苏莉', '罗翔', '缪云涛', '严己', '何志华', '李豪杰', '朱新捷', '金晨', '曹慧霆')
ORDER BY su.username, sr.name;

COMMIT;
