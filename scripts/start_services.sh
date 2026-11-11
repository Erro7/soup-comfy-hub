#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

cd "${PROJECT_DIR}"
source "${VENV_DIR}/bin/activate"
LOG_DIR="${DATA_DIR}/logs"
mkdir -p "${LOG_DIR}" "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}" "${TASK_OUTPUT_DIR}"

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

python "${COMFY_DIR}/main.py" \
  --listen 127.0.0.1 --port 8188 \
  --input-directory "${COMFY_INPUT_DIR}" \
  --output-directory "${COMFY_OUTPUT_DIR}" \
  > "${LOG_DIR}/comfyui.log" 2>&1 &
COMFY_PID=$!

echo "Waiting for ComfyUI readiness..."
for attempt in $(seq 1 "${COMFY_STARTUP_TIMEOUT:-180}"); do
  if ! kill -0 "${COMFY_PID}" 2>/dev/null; then
    echo "ComfyUI exited during startup; see ${LOG_DIR}/comfyui.log" >&2
    exit 1
  fi
  if curl -fsS "${COMFY_URL:-http://127.0.0.1:8188}/system_stats" >/dev/null 2>&1; then
    break
  fi
  if [ "${attempt}" -eq "${COMFY_STARTUP_TIMEOUT:-180}" ]; then
    echo "ComfyUI did not become ready within ${COMFY_STARTUP_TIMEOUT:-180}s" >&2
    exit 1
  fi
  sleep 1
done

uvicorn gateway.main:app --host "${GATEWAY_HOST:-127.0.0.1}" --port "${GATEWAY_PORT:-8000}" > "${LOG_DIR}/gateway.log" 2>&1 &

if [ "${ENABLE_CLOUDFLARED:-0}" = "1" ] && [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  command -v cloudflared >/dev/null || { echo "cloudflared is required when CLOUDFLARE_TUNNEL_TOKEN is set" >&2; exit 1; }
  cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}" > "${LOG_DIR}/cloudflared.log" 2>&1 &
fi

echo $$ > "${LOG_DIR}/services.pid"
wait -n
