#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

if [ ! -x "${VENV_DIR}/bin/python" ] || [ ! -f "${COMFY_DIR}/main.py" ]; then
  echo "Runtime is not initialized. Rebuild the image, or run 'make init' in Notebook mode." >&2
  exit 1
fi

mkdir -p "${COMFY_DIR}/models" "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}" "${TASK_OUTPUT_DIR}" "${DATA_DIR}/logs"

if [ "${AUTO_DOWNLOAD_MODELS:-0}" = "1" ] && [ ! -e "${COMFY_DIR}/models/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors" ]; then
  bash "${SCRIPT_DIR}/download_models.sh"
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi
exec bash "${SCRIPT_DIR}/start_services.sh"
