#!/usr/bin/env bash
set -euo pipefail

REMOTE_DEPLOY_DIR="${REMOTE_DEPLOY_DIR:-/home/daiwei/deployments/ruoyi-release}"
SERVER_TAR="${SERVER_TAR:-ruoyi-server-local.tar}"
ADMIN_TAR="${ADMIN_TAR:-ruoyi-admin-local.tar}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:48080/actuator/health}"
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-}"

if [ -n "${REMOTE_ENV_FILE}" ] && [ -f "${REMOTE_ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${REMOTE_ENV_FILE}"
  set +a
fi

cd "${REMOTE_DEPLOY_DIR}"

docker compose up -d mysql redis
docker compose stop server admin || true
docker compose rm -sf server admin || true

docker load -i "/tmp/${SERVER_TAR}"
docker load -i "/tmp/${ADMIN_TAR}"

docker compose up -d --no-build server admin

for i in $(seq 1 60); do
  if curl -fsS "${HEALTH_URL}" >/dev/null; then
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "[错误] 后端健康检查未通过: ${HEALTH_URL}" >&2
    exit 1
  fi
done

rm -f "/tmp/${SERVER_TAR}" "/tmp/${ADMIN_TAR}" "${REMOTE_ENV_FILE}"

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep 'ruoyi-'
curl -fsS "${HEALTH_URL}"
