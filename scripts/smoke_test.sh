#!/usr/bin/env bash
set -Eeuo pipefail
BASE_URL="${GATEWAY_URL:-http://127.0.0.1:8000}"
curl --fail --silent --show-error "${BASE_URL}/healthz"
echo
curl --fail --silent --show-error "${COMFY_URL:-http://127.0.0.1:8188}/system_stats" >/dev/null
echo "Gateway and ComfyUI smoke checks passed"
