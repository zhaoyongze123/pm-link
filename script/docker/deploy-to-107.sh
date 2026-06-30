#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE_HOST="${REMOTE_HOST:-192.168.1.107}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PASSWORD="${REMOTE_PASSWORD:-000000}"
REMOTE_DEPLOY_DIR="${REMOTE_DEPLOY_DIR:-/home/daiwei/deployments/ruoyi-release}"
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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: $1" >&2
    exit 1
  fi
}

remote_sh() {
  sshpass -p "${REMOTE_PASSWORD}" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "$@"
}

copy_to_remote() {
  sshpass -p "${REMOTE_PASSWORD}" scp -o StrictHostKeyChecking=no "$1" "${REMOTE_USER}@${REMOTE_HOST}:$2"
}

build_backend_jar() {
  echo "[步骤] 构建后端 jar"
  (cd "${ROOT_DIR}" && mvn -pl yudao-server -am -DskipTests package)
}

build_images() {
  echo "[步骤] 构建后端镜像 ${SERVER_IMAGE}"
  (cd "${ROOT_DIR}" && docker buildx build --platform "${DOCKER_PLATFORM}" --load -f script/docker/backend.Dockerfile -t "${SERVER_IMAGE}" .)

  echo "[步骤] 构建前端镜像 ${ADMIN_IMAGE}"
  (cd "${ROOT_DIR}" && docker buildx build --platform "${DOCKER_PLATFORM}" --load -f script/docker/frontend.Dockerfile -t "${ADMIN_IMAGE}" .)
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

upload_and_deploy() {
  echo "[步骤] 上传镜像到 ${REMOTE_HOST}"
  copy_to_remote "${ROOT_DIR}/${SERVER_TAR}" "/tmp/${SERVER_TAR}"
  copy_to_remote "${ROOT_DIR}/${ADMIN_TAR}" "/tmp/${ADMIN_TAR}"
  copy_to_remote "${ROOT_DIR}/${DB_DUMP_GZ}" "/tmp/${DB_DUMP_GZ}"

  echo "[步骤] 远端停旧服务、导入镜像并覆盖数据库"
  sshpass -p "${REMOTE_PASSWORD}" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" \
    "REMOTE_DEPLOY_DIR='${REMOTE_DEPLOY_DIR}' SERVER_TAR='${SERVER_TAR}' ADMIN_TAR='${ADMIN_TAR}' DB_DUMP_GZ='${DB_DUMP_GZ}' REMOTE_DB_CONTAINER='${REMOTE_DB_CONTAINER}' DB_NAME='${DB_NAME}' bash -s" <<'EOF'
set -euo pipefail

cd "${REMOTE_DEPLOY_DIR}"
docker compose stop server admin
docker compose rm -sf server admin
docker load -i "/tmp/${SERVER_TAR}"
docker load -i "/tmp/${ADMIN_TAR}"
printf 'DROP DATABASE IF EXISTS `%s`; CREATE DATABASE `%s` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' "${DB_NAME}" "${DB_NAME}" | docker exec -i "${REMOTE_DB_CONTAINER}" mysql -uroot -p123456
gzip -dc "/tmp/${DB_DUMP_GZ}" | docker exec -i "${REMOTE_DB_CONTAINER}" mysql -uroot -p123456 "${DB_NAME}"
docker compose up -d --no-build server admin
rm -f "/tmp/${SERVER_TAR}" "/tmp/${ADMIN_TAR}" "/tmp/${DB_DUMP_GZ}"
EOF

  echo "[步骤] 远端健康检查"
  remote_sh "curl -fsS http://127.0.0.1:48080/actuator/health"
}

print_summary() {
  echo "[完成] 已完成本地构建、上传并在 ${REMOTE_HOST} 上重建 ruoyi-server / ruoyi-admin"
  echo "[提示] 前端预览地址: http://${REMOTE_HOST}:18080"
  echo "[提示] 后端健康检查: http://${REMOTE_HOST}:48080/actuator/health"
}

main() {
  require_cmd mvn
  require_cmd docker
  require_cmd sshpass
  require_cmd scp
  require_cmd ssh
  require_cmd curl
  require_cmd mysqldump
  require_cmd gzip

  build_backend_jar
  build_images
  dump_database
  save_images
  upload_and_deploy
  print_summary
}

main "$@"
