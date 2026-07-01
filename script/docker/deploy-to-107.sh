#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_ENV=stage
IMPORT_DATABASE="${IMPORT_DATABASE:-true}"

exec "${ROOT_DIR}/script/docker/deploy.sh" "$@"
