const ADMIN_ROLE_CODES = new Set(['super_admin', 'dept_admin']);
const REMOVED_HOME_PATHS = new Set(['/analytics', '/workspace', '/dashboard']);
const OA_LITE_HOME_PATH = '/oa-lite';

export function isAdminUser(roles: string[] = []) {
  return roles.some((role) => ADMIN_ROLE_CODES.has(role));
}

export function resolveUserHomePath(
  defaultHomePath: string,
  homePath?: string,
  roles: string[] = [],
) {
  if (!isAdminUser(roles)) {
    return OA_LITE_HOME_PATH;
  }
  if (!homePath || REMOVED_HOME_PATHS.has(homePath)) {
    return defaultHomePath;
  }
  return homePath;
}

export { OA_LITE_HOME_PATH };
