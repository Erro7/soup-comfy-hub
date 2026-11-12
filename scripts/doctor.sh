#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

fail=0
check_file() { if [ -e "$1" ]; then echo "OK   $2"; else echo "MISS $2 -> $1"; fail=1; fi; }
check_dir() { if [ -d "$1" ]; then echo "OK   $2"; else echo "MISS $2 -> $1"; fail=1; fi; }

check_file "${VENV_DIR}/bin/python" "Python venv"
if [ -x "${VENV_DIR}/bin/python" ]; then
  if "${VENV_DIR}/bin/python" -c 'import fastapi, httpx, pydantic_settings' >/dev/null 2>&1; then
    echo "OK   Gateway Python dependencies"
    "${VENV_DIR}/bin/python" - <<'PY'
import torch
print(f"OK   torch={torch.__version__} cuda={torch.version.cuda}")
print(f"     torch_path={torch.__file__}")
PY
  else
    echo "MISS Gateway Python dependencies in ${VENV_DIR}"
    fail=1
  fi
fi
check_file "${DATA_DIR}/.runtime-ready" "Runtime marker"
check_file "${COMFY_DIR}/main.py" "ComfyUI"
check_dir "${COMFY_DIR}/custom_nodes/ComfyUI-VideoHelperSuite" "VideoHelperSuite"
check_dir "${COMFY_DIR}/custom_nodes/ComfyUI_InstantID" "InstantID nodes"
check_dir "${COMFY_DIR}/custom_nodes/ComfyUI_IPAdapter_plus" "IPAdapter nodes"
if [ "${INSTALL_POSE_GALLERY:-0}" = "1" ]; then
  check_dir "${COMFY_DIR}/custom_nodes/ai-pose-gallery-zh/comfyui_plugin" "AI pose gallery zh"
fi
if [ "${ENABLE_SOUP:-0}" = "1" ]; then
  if "${VENV_DIR}/bin/python" -m pip show soup-cli >/dev/null 2>&1; then
    echo "OK   optional Soup CLI"
  else
    echo "MISS Soup is enabled but soup-cli is not installed"
    fail=1
  fi
fi

check_file "${COMFY_DIR}/models/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors" "Wan 2.1 FP8"
check_file "${COMFY_DIR}/models/vae/wan_2.1_vae.safetensors" "Wan VAE"
check_file "${COMFY_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "Wan text encoder"
check_file "${COMFY_DIR}/models/instantid/ip-adapter.bin" "InstantID model"
check_file "${COMFY_DIR}/models/controlnet/instantid/diffusion_pytorch_model.safetensors" "InstantID ControlNet"
check_file "${COMFY_DIR}/models/checkpoints/sd_xl_base_1.0.safetensors" "SDXL base checkpoint"
check_file "${COMFY_DIR}/models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors" "IPAdapter SDXL"
check_file "${COMFY_DIR}/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" "CLIP Vision"
check_dir "${COMFY_DIR}/models/insightface/models/antelopev2" "InsightFace antelopev2"

if command -v nvidia-smi >/dev/null; then nvidia-smi --query-gpu=name,memory.total --format=csv,noheader; else echo "WARN nvidia-smi not found"; fi
exit "${fail}"
