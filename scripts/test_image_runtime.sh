#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

runtime_require_venv
runtime_require_comfy

FACE_IMAGE="${IMAGE_TEST_FACE:-}"
OUTFIT_IMAGE="${IMAGE_TEST_OUTFIT:-}"
POSE_IMAGE="${IMAGE_TEST_POSE:-}"
for pair in "IMAGE_TEST_FACE:${FACE_IMAGE}" "IMAGE_TEST_OUTFIT:${OUTFIT_IMAGE}" "IMAGE_TEST_POSE:${POSE_IMAGE}"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  [ -f "${value}" ] || {
    echo "${name} must point to a readable image file; got: ${value:-<empty>}" >&2
    exit 2
  }
done

COMFY_LOCAL_URL="http://127.0.0.1:${COMFY_PORT:-8188}"
GATEWAY_LOCAL_URL="http://127.0.0.1:${GATEWAY_PORT:-8000}"
TEST_LOG="${LOG_DIR}/image-runtime-test-supervisor.log"
RESULT_FILE="${IMAGE_TEST_OUTPUT:-${TASK_OUTPUT_DIR}/step6-image-test.png}"
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

echo "Validating image nodes, models and workflow contract..."
COMFY_PROFILE=image MODEL_PROFILE=image bash "${SCRIPT_DIR}/doctor.sh"
"${VENV_DIR}/bin/python" "${PROJECT_DIR}/scripts/validate_workflows.py"

if pid_file_is_live; then
  echo "Using already-running services; they will not be stopped."
else
  mkdir -p "${LOG_DIR}"
  echo "Starting temporary ComfyUI + Gateway services..."
  COMFY_PROFILE=image bash "${SCRIPT_DIR}/start_services.sh" >"${TEST_LOG}" 2>&1 &
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
    echo "Service supervisor exited before image readiness." >&2
    tail -n 120 "${TEST_LOG}" >&2 || true
    exit 1
  fi
  sleep 1
done
[ "${ready}" = 1 ] || {
  echo "Image services did not become ready within ${timeout_seconds}s." >&2
  tail -n 120 "${LOG_DIR}/comfyui.log" >&2 || true
  exit 1
}

echo "Checking ComfyUI image custom-node classes..."
"${VENV_DIR}/bin/python" - "${COMFY_LOCAL_URL}/object_info" <<'PY'
import json
import sys
import urllib.request
required = {
    "InstantIDModelLoader",
    "InstantIDFaceAnalysis",
    "ApplyInstantID",
    "IPAdapterModelLoader",
    "IPAdapterAdvanced",
}
with urllib.request.urlopen(sys.argv[1], timeout=15) as response:
    nodes = json.load(response)
missing = sorted(required - set(nodes))
if missing:
    raise SystemExit(
        "Running ComfyUI is missing image nodes: "
        f"{missing}. Restart services after make init-image."
    )
print("ComfyUI image node classes are present")
PY

mkdir -p "$(dirname "${RESULT_FILE}")"
export IMAGE_TEST_FACE IMAGE_TEST_OUTFIT IMAGE_TEST_POSE RESULT_FILE
export IMAGE_TEST_URL="${GATEWAY_LOCAL_URL}/v1/images/edits"
export IMAGE_TEST_API_KEY="${API_KEY}"
export IMAGE_TEST_PROMPT="${IMAGE_TEST_PROMPT:-85mm commercial portrait, realistic skin texture, editorial lighting}"

echo "Submitting authenticated InstantID + IPAdapter image request..."
"${VENV_DIR}/bin/python" <<'PY'
import base64
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

def encoded(name: str) -> str:
    return base64.b64encode(Path(os.environ[name]).read_bytes()).decode()

payload = {
    "face_image_b64": encoded("IMAGE_TEST_FACE"),
    "outfit_image_b64": encoded("IMAGE_TEST_OUTFIT"),
    "pose_image_b64": encoded("IMAGE_TEST_POSE"),
    "prompt": os.environ["IMAGE_TEST_PROMPT"],
    "seed": 1,
}
request = urllib.request.Request(
    os.environ["IMAGE_TEST_URL"],
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": f"Bearer {os.environ['IMAGE_TEST_API_KEY']}",
        "Content-Type": "application/json",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(request, timeout=3700) as response:
        result = json.load(response)
except urllib.error.HTTPError as exc:
    body = exc.read().decode(errors="replace")
    raise SystemExit(f"Image API failed with HTTP {exc.code}: {body}") from exc

raw = base64.b64decode(result["image_base64"], validate=True)
if not raw.startswith((b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"RIFF")):
    raise SystemExit("Image API returned an unknown image format")
target = Path(os.environ["RESULT_FILE"])
target.write_bytes(raw)
print(f"Generated image: {target} ({len(raw)} bytes)")
print(f"ComfyUI prompt: {result['prompt_id']}")
PY

echo "Step 6 image runtime acceptance: PASS"
