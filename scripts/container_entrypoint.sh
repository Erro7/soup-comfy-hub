#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

runtime_require_venv || {
  echo "Rebuild the image, or run 'make init' once in Notebook mode." >&2
  exit 1
}
runtime_require_comfy || {
  echo "Rebuild the image, or run 'make init' once in Notebook mode." >&2
  exit 1
}

mkdir -p "${COMFY_DIR}/models" "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}" "${TASK_OUTPUT_DIR}" "${LOG_DIR}"

if [ "${AUTO_DOWNLOAD_MODELS:-0}" = "1" ] && [ ! -e "${COMFY_DIR}/models/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors" ]; then
  bash "${SCRIPT_DIR}/download_models.sh"
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi
exec bash "${SCRIPT_DIR}/start_services.sh"
