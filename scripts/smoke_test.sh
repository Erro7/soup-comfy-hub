#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

curl -fsS "${GATEWAY_URL:-http://127.0.0.1:8000}/healthz" >/dev/null
curl -fsS "${GATEWAY_URL:-http://127.0.0.1:8000}/readyz" >/dev/null
curl -fsS "${COMFY_URL:-http://127.0.0.1:8188}/system_stats" >/dev/null
echo "Gateway -> ComfyUI API readiness checks passed"
