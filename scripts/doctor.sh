#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

fail=0
check_file() { if [ -e "$1" ]; then echo "OK   $2"; else echo "MISS $2 -> $1"; fail=1; fi; }
check_dir() { if [ -d "$1" ]; then echo "OK   $2"; else echo "MISS $2 -> $1"; fail=1; fi; }

check_file "${VENV_DIR}/bin/python" "Python venv"
check_file "${COMFY_DIR}/main.py" "ComfyUI"
check_dir "${COMFY_DIR}/custom_nodes/ComfyUI-VideoHelperSuite" "VideoHelperSuite"
check_dir "${COMFY_DIR}/custom_nodes/ComfyUI_InstantID" "InstantID nodes"
check_dir "${COMFY_DIR}/custom_nodes/ComfyUI_IPAdapter_plus" "IPAdapter nodes"
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
