#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

runtime_activate_venv
runtime_require_comfy
if [ ! -f "${DATA_DIR}/state/comfy-profiles/core" ]; then
  echo "ComfyUI core profile is not initialized; run 'make init-core' first." >&2
  exit 1
fi
cd "${PROJECT_DIR}"
mkdir -p "${LOG_DIR}" "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}" "${TASK_OUTPUT_DIR}"

if [ -f "${SERVICES_PID_FILE}" ]; then
  existing_pid="$(<"${SERVICES_PID_FILE}")"
  if [[ "${existing_pid}" =~ ^[0-9]+$ ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    echo "Services are already running with supervisor PID ${existing_pid}." >&2
    exit 1
  fi
  rm -f "${SERVICES_PID_FILE}"
fi

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
  if [ -f "${SERVICES_PID_FILE}" ] && [ "$(<"${SERVICES_PID_FILE}")" = "$$" ]; then
    rm -f "${SERVICES_PID_FILE}"
  fi
}
trap cleanup EXIT INT TERM

echo $$ > "${SERVICES_PID_FILE}"

"${VENV_DIR}/bin/python" "${COMFY_DIR}/main.py"   --listen "${COMFY_HOST:-127.0.0.1}" --port "${COMFY_PORT:-8188}"   --input-directory "${COMFY_INPUT_DIR}"   --output-directory "${COMFY_OUTPUT_DIR}"   > "${LOG_DIR}/comfyui.log" 2>&1 &
COMFY_PID=$!

echo "Waiting for ComfyUI readiness..."
for attempt in $(seq 1 "${COMFY_STARTUP_TIMEOUT:-180}"); do
  if ! kill -0 "${COMFY_PID}" 2>/dev/null; then
    echo "ComfyUI exited during startup; see ${LOG_DIR}/comfyui.log" >&2
    exit 1
  fi
  if "${VENV_DIR}/bin/python" -c 'import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=2).read(1)' "${COMFY_URL:-http://127.0.0.1:8188}/system_stats" >/dev/null 2>&1; then
    break
  fi
  if [ "${attempt}" -eq "${COMFY_STARTUP_TIMEOUT:-180}" ]; then
    echo "ComfyUI did not become ready within ${COMFY_STARTUP_TIMEOUT:-180}s" >&2
    exit 1
  fi
  sleep 1
done

"${VENV_DIR}/bin/python" -m uvicorn gateway.main:app   --host "${GATEWAY_HOST:-127.0.0.1}"   --port "${GATEWAY_PORT:-8000}"   > "${LOG_DIR}/gateway.log" 2>&1 &
GATEWAY_PID=$!

GATEWAY_DISPLAY_HOST="${GATEWAY_HOST:-127.0.0.1}"
if [ "${GATEWAY_DISPLAY_HOST}" = "0.0.0.0" ] || [ "${GATEWAY_DISPLAY_HOST}" = "::" ]; then
  GATEWAY_DISPLAY_HOST="127.0.0.1"
fi
GATEWAY_LOCAL_URL="http://${GATEWAY_DISPLAY_HOST}:${GATEWAY_PORT:-8000}"

echo "Waiting for API Gateway readiness..."
for attempt in $(seq 1 "${GATEWAY_STARTUP_TIMEOUT:-60}"); do
  if ! kill -0 "${GATEWAY_PID}" 2>/dev/null; then
    echo "API Gateway exited during startup; see ${LOG_DIR}/gateway.log" >&2
    exit 1
  fi
  if "${VENV_DIR}/bin/python" -c 'import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=2).read(1)' "${GATEWAY_LOCAL_URL}/readyz" >/dev/null 2>&1; then
    break
  fi
  if [ "${attempt}" -eq "${GATEWAY_STARTUP_TIMEOUT:-60}" ]; then
    echo "API Gateway did not become ready within ${GATEWAY_STARTUP_TIMEOUT:-60}s" >&2
    exit 1
  fi
  sleep 1
done

if [ "${ENABLE_CLOUDFLARED:-0}" = "1" ]; then
  bash "${PROJECT_DIR}/scripts/tunnel.sh" run > "${LOG_DIR}/cloudflared.log" 2>&1 &
  CLOUDFLARED_PID=$!
  sleep 1
  if ! kill -0 "${CLOUDFLARED_PID}" 2>/dev/null; then
    echo "Cloudflare tunnel exited during startup; see ${LOG_DIR}/cloudflared.log" >&2
    exit 1
  fi
fi

echo
echo "Soup-Comfy-Hub is ready"
echo "  Comfy profile:  ${COMFY_PROFILE:-core}"
echo "  ComfyUI local:  ${COMFY_URL:-http://127.0.0.1:8188}"
if [ -n "${COMFY_PUBLIC_URL:-}" ]; then
  echo "  ComfyUI remote: ${COMFY_PUBLIC_URL%/}"
fi
echo "  API endpoint:   ${GATEWAY_LOCAL_URL}"
echo "  API docs:      ${GATEWAY_LOCAL_URL}/docs"
if [ -n "${GATEWAY_PUBLIC_URL:-}" ]; then
  echo "  Public API:    ${GATEWAY_PUBLIC_URL%/}"
fi
if [ "${ENABLE_CLOUDFLARED:-0}" = "1" ]; then
  if [ -n "${CLOUDFLARE_PUBLIC_URL:-}" ]; then
    echo "  Tunnel URL:    ${CLOUDFLARE_PUBLIC_URL%/}"
  else
    echo "  Tunnel URL:    see ${LOG_DIR}/cloudflared.log"
  fi
fi
echo "  Logs:          ${LOG_DIR}"
echo

wait -n
