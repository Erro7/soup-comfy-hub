#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

fail=0
check_file() { if [ -e "$1" ]; then echo "OK   $2"; else echo "MISS $2 -> $1"; fail=1; fi; }
check_dir() { if [ -d "$1" ]; then echo "OK   $2"; else echo "MISS $2 -> $1"; fail=1; fi; }

check_file "${VENV_DIR}/bin/python" "Python venv"
if [ -x "${VENV_DIR}/bin/python" ]; then
  if "${VENV_DIR}/bin/python" -c 'import fastapi, httpx, pydantic_settings, uvicorn' >/dev/null 2>&1; then
    echo "OK   Gateway Python dependencies"
    if "${VENV_DIR}/bin/python" -c 'import torch' >/dev/null 2>&1; then
      "${VENV_DIR}/bin/python" - <<'PY'
import torch
print(f"OK   torch={torch.__version__} cuda={torch.version.cuda}")
print(f"     torch_path={torch.__file__}")
PY
    else
      echo "MISS PyTorch in the shared runtime"
      fail=1
    fi
  else
    echo "MISS Gateway Python dependencies in ${VENV_DIR}"
    fail=1
  fi
fi
COMFY_PROFILE="${COMFY_PROFILE:-core}"
case "${COMFY_PROFILE}" in core|image|video|all) ;; *)
  echo "MISS invalid COMFY_PROFILE=${COMFY_PROFILE}"
  fail=1
  ;;
esac
check_file "${DATA_DIR}/.runtime-ready" "Runtime marker"
check_file "${DATA_DIR}/state/comfy-profiles/core" "ComfyUI core profile marker"
check_file "${COMFY_DIR}/main.py" "ComfyUI"
if [ -x "${VENV_DIR}/bin/python" ]; then
  if "${VENV_DIR}/bin/python" -m pip show comfyui-frontend-package comfyui-embedded-docs >/dev/null 2>&1; then
    echo "OK   ComfyUI frontend and embedded docs"
  else
    echo "MISS ComfyUI core frontend packages"
    fail=1
  fi
fi
if [ "${COMFY_PROFILE}" = image ] || [ "${COMFY_PROFILE}" = all ]; then
  check_file "${DATA_DIR}/state/comfy-profiles/image" "ComfyUI image profile marker"
  check_dir "${COMFY_DIR}/custom_nodes/ComfyUI_InstantID" "InstantID nodes"
  check_dir "${COMFY_DIR}/custom_nodes/ComfyUI_IPAdapter_plus" "IPAdapter nodes"
  if [ "${INSTALL_POSE_GALLERY:-0}" = 1 ]; then
    check_dir "${COMFY_DIR}/custom_nodes/ai-pose-gallery-zh/comfyui_plugin" "AI pose gallery zh"
  fi
fi
if [ "${COMFY_PROFILE}" = video ] || [ "${COMFY_PROFILE}" = all ]; then
  check_file "${DATA_DIR}/state/comfy-profiles/video" "ComfyUI video profile marker"
  check_dir "${COMFY_DIR}/custom_nodes/ComfyUI-VideoHelperSuite" "VideoHelperSuite"
  check_dir "${COMFY_DIR}/custom_nodes/ComfyUI-GGUF" "GGUF nodes"
fi
if [ "${ENABLE_SOUP:-0}" = "1" ]; then
  if "${VENV_DIR}/bin/python" -m pip show soup-cli >/dev/null 2>&1; then
    echo "OK   optional Soup CLI"
  else
    echo "MISS Soup is enabled but soup-cli is not installed"
    fail=1
  fi
fi

MODEL_PROFILE="${MODEL_PROFILE:-all}"
WAN_MODEL="${WAN_MODEL:-split_files/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors}"

if [ "${MODEL_PROFILE}" = "video" ] || [ "${MODEL_PROFILE}" = "all" ]; then
  check_file "${COMFY_DIR}/models/diffusion_models/$(basename "${WAN_MODEL}")" "Wan diffusion model"
  check_file "${COMFY_DIR}/models/vae/wan_2.1_vae.safetensors" "Wan VAE"
  check_file "${COMFY_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "Wan text encoder"
fi

if [ "${MODEL_PROFILE}" = "image" ] || [ "${MODEL_PROFILE}" = "all" ]; then
  IMAGE_MODEL_MANIFEST="${IMAGE_MODEL_MANIFEST:-${PROJECT_DIR}/config/model-profiles/image.tsv}"
  check_file "${IMAGE_MODEL_MANIFEST}" "Image model manifest"
  if [ -f "${IMAGE_MODEL_MANIFEST}" ]; then
    while IFS='|' read -r kind model_repo source target; do
      [ -n "${kind}" ] || continue
      case "${kind}" in \#*) continue ;; esac
      case "${kind}" in
        file) check_file "${COMFY_DIR}/models/${target}" "Image model: ${target}" ;;
        tree) check_dir "${COMFY_DIR}/models/${target}" "Image model directory: ${target}" ;;
        *) echo "MISS unsupported image manifest kind: ${kind}"; fail=1 ;;
      esac
    done < "${IMAGE_MODEL_MANIFEST}"
  fi
fi

if [ "${MODEL_PROFILE}" = "custom" ]; then
  if [ -z "${MODEL_FILE:-}" ] || [ -z "${MODEL_DIR:-}" ]; then
    echo "MISS MODEL_FILE and MODEL_DIR are required for custom profile checks"
    fail=1
  else
    check_file "${COMFY_DIR}/models/${MODEL_DIR}/$(basename "${MODEL_FILE}")" "Custom model"
  fi
fi

if command -v nvidia-smi >/dev/null; then nvidia-smi --query-gpu=name,memory.total --format=csv,noheader; else echo "WARN nvidia-smi not found"; fi
exit "${fail}"
