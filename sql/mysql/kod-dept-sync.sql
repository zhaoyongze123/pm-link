START TRANSACTION;

-- 仅处理租户 1：先清掉旧部门引用，避免删除部门后留下悬挂 dept_id
UPDATE system_users
SET dept_id = NULL
WHERE tenant_id = 1;

-- 清理引用旧部门 ID 的角色数据范围，避免遗留无效部门编号
UPDATE system_role
SET data_scope_dept_ids = ''
WHERE tenant_id = 1
  AND data_scope_dept_ids <> '';

-- 清空租户 1 现有部门树
DELETE FROM system_dept
WHERE tenant_id = 1;

-- 按可道云当前组织树重建部门
INSERT INTO system_dept
(`id`, `name`, `parent_id`, `sort`, `leader_user_id`, `phone`, `email`, `status`,
 `creator`, `create_time`, `updater`, `update_time`, `deleted`, `tenant_id`)
VALUES
  (1, '总公司', 0, 1, 150, NULL, NULL, 0, 'kod-sso-sync', NOW(), 'kod-sso-sync', NOW(), b'0', 1),
  (2, '销售部', 1, 1, 151, NULL, NULL, 0, 'kod-sso-sync', NOW(), 'kod-sso-sync', NOW(), b'0', 1),
  (3, '项目部', 1, 2, NULL, NULL, NULL, 0, 'kod-sso-sync', NOW(), 'kod-sso-sync', NOW(), b'0', 1),
  (4, '财务部', 1, 3, NULL, NULL, NULL, 0, 'kod-sso-sync', NOW(), 'kod-sso-sync', NOW(), b'0', 1),
  (5, '行政人事部', 1, 4, NULL, NULL, NULL, 0, 'kod-sso-sync', NOW(), 'kod-sso-sync', NOW(), b'0', 1);

-- 根据当前可道云绑定资料回填用户部门
UPDATE system_users
SET dept_id = 1
WHERE tenant_id = 1
  AND id = 150;

UPDATE system_users
SET dept_id = 2
WHERE tenant_id = 1
  AND id = 151;

COMMIT;
