#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

runtime_require_venv
runtime_require_comfy

COMFY_LOCAL_URL="http://127.0.0.1:${COMFY_PORT:-8188}"
GATEWAY_LOCAL_URL="http://127.0.0.1:${GATEWAY_PORT:-8000}"
TEST_LOG="${LOG_DIR}/core-runtime-test-supervisor.log"
STARTED_BY_TEST=0
SUPERVISOR_PID=""

pid_file_is_live() {
  [ -r "${SERVICES_PID_FILE}" ] || return 1
  local pid
  pid="$(<"${SERVICES_PID_FILE}")"
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null
}

cleanup() {
  if [ "${STARTED_BY_TEST}" = 1 ]; then
    bash "${SCRIPT_DIR}/services.sh" stop >/dev/null 2>&1 || true
    [ -z "${SUPERVISOR_PID}" ] || wait "${SUPERVISOR_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Validating the minimal ComfyUI core installation..."
COMFY_PROFILE=core MODEL_PROFILE=none bash "${SCRIPT_DIR}/doctor.sh"

if pid_file_is_live; then
  echo "Using the already-running project services; they will not be stopped."
else
  mkdir -p "${LOG_DIR}"
  echo "Starting temporary ComfyUI + Gateway services..."
  bash "${SCRIPT_DIR}/start_services.sh" >"${TEST_LOG}" 2>&1 &
  SUPERVISOR_PID=$!
  STARTED_BY_TEST=1
fi

timeout_seconds=$((
  ${COMFY_STARTUP_TIMEOUT:-180} + ${GATEWAY_STARTUP_TIMEOUT:-60} + 30
))
ready=0
for ((attempt=1; attempt<=timeout_seconds; attempt++)); do
  if "${VENV_DIR}/bin/python" - "${COMFY_LOCAL_URL}" "${GATEWAY_LOCAL_URL}" <<'PY' >/dev/null 2>&1
import sys
import urllib.request
for url in (sys.argv[1] + "/system_stats", sys.argv[2] + "/readyz"):
    with urllib.request.urlopen(url, timeout=2) as response:
        if response.status != 200:
            raise SystemExit(1)
PY
  then
    ready=1
    break
  fi
  if [ "${STARTED_BY_TEST}" = 1 ] && ! kill -0 "${SUPERVISOR_PID}" 2>/dev/null; then
    echo "Temporary service supervisor exited before readiness." >&2
    tail -n 120 "${TEST_LOG}" >&2 || true
    exit 1
  fi
  sleep 1
done

if [ "${ready}" != 1 ]; then
  echo "Core services did not become ready within ${timeout_seconds}s." >&2
  tail -n 120 "${TEST_LOG}" >&2 || true
  tail -n 120 "${LOG_DIR}/comfyui.log" >&2 || true
  tail -n 120 "${LOG_DIR}/gateway.log" >&2 || true
  exit 1
fi

echo "Checking Gateway -> ComfyUI readiness and API contract..."
GATEWAY_URL="${GATEWAY_LOCAL_URL}" COMFY_URL="${COMFY_LOCAL_URL}"   bash "${SCRIPT_DIR}/smoke_test.sh"

"${VENV_DIR}/bin/python" - "${GATEWAY_LOCAL_URL}/openapi.json" <<'PY'
import json
import sys
import urllib.request

required = {
    "/healthz",
    "/readyz",
    "/v1/images/edits",
    "/v1/videos/generations",
    "/v1/tasks/{task_id}",
}
with urllib.request.urlopen(sys.argv[1], timeout=5) as response:
    schema = json.load(response)
paths = set(schema.get("paths", {}))
missing = sorted(required - paths)
if missing:
    raise SystemExit(f"Gateway OpenAPI is missing required routes: {missing}")
print("Gateway core API routes are present")
PY

echo "Step 5 core runtime acceptance: PASS"
