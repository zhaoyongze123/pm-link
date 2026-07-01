#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_ENV="${DEPLOY_ENV:-stage}"
ENV_FILE="${DEPLOY_ENV_FILE:-${ROOT_DIR}/script/docker/env/${DEPLOY_ENV}.env}"
ENV_EXAMPLE_FILE="${DEPLOY_ENV_EXAMPLE_FILE:-${ROOT_DIR}/script/docker/env/${DEPLOY_ENV}.env.example}"
SERVER_IMAGE="${SERVER_IMAGE:-ruoyi-server:local}"
ADMIN_IMAGE="${ADMIN_IMAGE:-ruoyi-admin:local}"
SERVER_TAR="${SERVER_TAR:-ruoyi-server-local.tar}"
ADMIN_TAR="${ADMIN_TAR:-ruoyi-admin-local.tar}"
DB_NAME="${DB_NAME:-ruoyi-vue-pro}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
LOCAL_DB_HOST="${LOCAL_DB_HOST:-127.0.0.1}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-3306}"
LOCAL_DB_USER="${LOCAL_DB_USER:-root}"
LOCAL_DB_PASSWORD="${LOCAL_DB_PASSWORD:-123456}"
REMOTE_DB_CONTAINER="${REMOTE_DB_CONTAINER:-ruoyi-mysql}"
DB_DUMP_GZ="${DB_DUMP_GZ:-ruoyi-vue-pro.sql.gz}"
IMPORT_DATABASE="${IMPORT_DATABASE:-false}"
REMOTE_ENV_BASENAME="${REMOTE_ENV_BASENAME:-ruoyi-deploy.env}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: $1" >&2
    exit 1
  fi
}

load_env_file() {
  if [ ! -f "${ENV_FILE}" ]; then
    if [ -f "${ENV_EXAMPLE_FILE}" ]; then
      echo "[提示] 未找到环境文件，回退到示例文件: ${ENV_EXAMPLE_FILE}"
      ENV_FILE="${ENV_EXAMPLE_FILE}"
    else
      echo "[错误] 环境文件不存在: ${ENV_FILE}" >&2
      exit 1
    fi
  fi
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

validate_value() {
  local name="$1"
  local value="${!name:-}"
  if [ -z "${value}" ] || [[ "${value}" == REPLACE_ME* ]]; then
    echo "[错误] 环境变量 ${name} 未配置完成，请检查 ${ENV_FILE}" >&2
    exit 1
  fi
}

validate_env() {
  validate_value SPRING_PROFILES_ACTIVE
  validate_value FRONTEND_ENV_FILE
  if [ ! -f "${ROOT_DIR}/${FRONTEND_ENV_FILE}" ]; then
    echo "[错误] 前端环境文件不存在: ${ROOT_DIR}/${FRONTEND_ENV_FILE}" >&2
    exit 1
  fi
  if [ "${DEPLOY_ENV}" != "dev" ]; then
    validate_value REMOTE_HOST
    validate_value REMOTE_USER
    validate_value REMOTE_DEPLOY_DIR
  fi
}

remote_sh() {
  if [ -n "${REMOTE_PASSWORD:-}" ]; then
    sshpass -p "${REMOTE_PASSWORD}" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "$@"
  else
    ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "$@"
  fi
}

copy_to_remote() {
  if [ -n "${REMOTE_PASSWORD:-}" ]; then
    sshpass -p "${REMOTE_PASSWORD}" scp -o StrictHostKeyChecking=no "$1" "${REMOTE_USER}@${REMOTE_HOST}:$2"
  else
    scp -o StrictHostKeyChecking=no "$1" "${REMOTE_USER}@${REMOTE_HOST}:$2"
  fi
}

build_backend_jar() {
  echo "[步骤] 构建后端 jar"
  (cd "${ROOT_DIR}" && mvn -pl yudao-server -am -DskipTests package)
}

build_images() {
  echo "[步骤] 构建后端镜像 ${SERVER_IMAGE}"
  (cd "${ROOT_DIR}" && docker buildx build --platform "${DOCKER_PLATFORM}" --load -f script/docker/backend.Dockerfile -t "${SERVER_IMAGE}" .)

  echo "[步骤] 构建前端镜像 ${ADMIN_IMAGE}，环境文件 ${FRONTEND_ENV_FILE}"
  (cd "${ROOT_DIR}" && docker buildx build --platform "${DOCKER_PLATFORM}" --load --build-arg FRONTEND_ENV_FILE="${FRONTEND_ENV_FILE}" -f script/docker/frontend.Dockerfile -t "${ADMIN_IMAGE}" .)
}

dump_database() {
  echo "[步骤] 导出本地数据库 ${DB_NAME}"
  rm -f "${ROOT_DIR}/${DB_DUMP_GZ}"
  mysqldump \
    -h"${LOCAL_DB_HOST}" \
    -P"${LOCAL_DB_PORT}" \
    -u"${LOCAL_DB_USER}" \
    -p"${LOCAL_DB_PASSWORD}" \
    --single-transaction \
    --routines \
    --triggers \
    --default-character-set=utf8mb4 \
    --set-gtid-purged=OFF \
    "${DB_NAME}" | gzip > "${ROOT_DIR}/${DB_DUMP_GZ}"
}

save_images() {
  echo "[步骤] 导出镜像 tar"
  (cd "${ROOT_DIR}" && docker save -o "${SERVER_TAR}" "${SERVER_IMAGE}")
  (cd "${ROOT_DIR}" && docker save -o "${ADMIN_TAR}" "${ADMIN_IMAGE}")
}

upload_artifacts() {
  echo "[步骤] 上传镜像到 ${REMOTE_HOST}"
  remote_sh "mkdir -p '${REMOTE_DEPLOY_DIR}'"
  copy_to_remote "${ROOT_DIR}/${SERVER_TAR}" "/tmp/${SERVER_TAR}"
  copy_to_remote "${ROOT_DIR}/${ADMIN_TAR}" "/tmp/${ADMIN_TAR}"
  copy_to_remote "${ROOT_DIR}/script/docker/remote-reload-app.sh" "/tmp/remote-reload-app.sh"
  copy_to_remote "${ROOT_DIR}/script/docker/docker-compose.yml" "${REMOTE_DEPLOY_DIR}/docker-compose.yml"
  copy_to_remote "${ENV_FILE}" "/tmp/${REMOTE_ENV_BASENAME}"
  if [ "${IMPORT_DATABASE}" = "true" ]; then
    copy_to_remote "${ROOT_DIR}/${DB_DUMP_GZ}" "/tmp/${DB_DUMP_GZ}"
  fi
}

deploy_remote_app_only() {
  echo "[步骤] 远端重载应用（不覆盖数据库）"
  remote_sh "chmod +x /tmp/remote-reload-app.sh && REMOTE_DEPLOY_DIR='${REMOTE_DEPLOY_DIR}' REMOTE_ENV_FILE='/tmp/${REMOTE_ENV_BASENAME}' SERVER_TAR='${SERVER_TAR}' ADMIN_TAR='${ADMIN_TAR}' /tmp/remote-reload-app.sh && rm -f /tmp/remote-reload-app.sh"
}

deploy_remote_with_db() {
  echo "[步骤] 远端停旧服务、导入镜像并覆盖数据库"
  remote_sh \
    "REMOTE_DEPLOY_DIR='${REMOTE_DEPLOY_DIR}' SERVER_TAR='${SERVER_TAR}' ADMIN_TAR='${ADMIN_TAR}' DB_DUMP_GZ='${DB_DUMP_GZ}' REMOTE_DB_CONTAINER='${REMOTE_DB_CONTAINER}' DB_NAME='${DB_NAME}' REMOTE_ENV_BASENAME='${REMOTE_ENV_BASENAME}' bash -s" <<'EOF'
set -euo pipefail

set -a
source "/tmp/${REMOTE_ENV_BASENAME}"
set +a

cd "${REMOTE_DEPLOY_DIR}"
docker compose up -d mysql redis
for i in $(seq 1 60); do
  if docker exec "${REMOTE_DB_CONTAINER}" mysqladmin ping -uroot -p123456 --silent >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "[错误] MySQL 在 120 秒内未就绪" >&2
    exit 1
  fi
done
printf 'DROP DATABASE IF EXISTS `%s`; CREATE DATABASE `%s` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "${DB_NAME}" "${DB_NAME}" | docker exec -i "${REMOTE_DB_CONTAINER}" mysql -uroot -p123456
gzip -dc "/tmp/${DB_DUMP_GZ}" | docker exec -i "${REMOTE_DB_CONTAINER}" mysql -uroot -p123456 "${DB_NAME}"
docker compose stop server admin || true
docker compose rm -sf server admin || true
docker load -i "/tmp/${SERVER_TAR}"
docker load -i "/tmp/${ADMIN_TAR}"
docker compose up -d --no-build server admin
rm -f "/tmp/${SERVER_TAR}" "/tmp/${ADMIN_TAR}" "/tmp/${DB_DUMP_GZ}" "/tmp/${REMOTE_ENV_BASENAME}" /tmp/remote-reload-app.sh
EOF
  remote_sh "curl -fsS http://127.0.0.1:48080/actuator/health"
}

print_summary() {
  echo "[完成] 环境 ${DEPLOY_ENV} 已部署到 ${REMOTE_HOST:-local}"
  echo "[提示] 前端预览地址: http://${REMOTE_HOST:-127.0.0.1}:${ADMIN_PORT:-18080}"
  echo "[提示] 后端健康检查: http://${REMOTE_HOST:-127.0.0.1}:${SERVER_PORT:-48080}/actuator/health"
}

main() {
  require_cmd mvn
  require_cmd docker
  require_cmd gzip
  load_env_file
  validate_env
  if [ "${DEPLOY_ENV}" != "dev" ]; then
    require_cmd scp
    require_cmd ssh
    require_cmd curl
    if [ -n "${REMOTE_PASSWORD:-}" ]; then
      require_cmd sshpass
    fi
  fi
  if [ "${IMPORT_DATABASE}" = "true" ]; then
    require_cmd mysqldump
  fi

  build_backend_jar
  build_images
  if [ "${IMPORT_DATABASE}" = "true" ]; then
    dump_database
  fi
  save_images
  upload_artifacts
  if [ "${IMPORT_DATABASE}" = "true" ]; then
    deploy_remote_with_db
  else
    deploy_remote_app_only
  fi
  print_summary
}

main "$@"
