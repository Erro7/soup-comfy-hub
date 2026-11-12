#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

MODEL_PROFILE="${MODEL_PROFILE:-all}"
WAN_REPO="${WAN_REPO:-Comfy-Org/Wan_2.1_ComfyUI_repackaged}"
WAN_MODEL="${WAN_MODEL:-split_files/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors}"
MODEL_CACHE_ROOT="${COMFY_DIR}/models/.modelscope"

runtime_require_venv
runtime_require_comfy
mkdir -p "${MODEL_CACHE_ROOT}"

MS_PYTHON=""
if python3 -c 'import modelscope' >/dev/null 2>&1; then
  MS_PYTHON="$(command -v python3)"
  echo "Using ModelScope preinstalled by the Notebook image: ${MS_PYTHON}"
else
  runtime_activate_venv
  if ! python -c 'import modelscope' >/dev/null 2>&1; then
    MODELSCOPE_PIP_INDEX_URL="${MODELSCOPE_PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
    echo "Installing optional ModelScope downloader from ${MODELSCOPE_PIP_INDEX_URL}"
    python -m pip install --index-url "${MODELSCOPE_PIP_INDEX_URL}" modelscope
  fi
  MS_PYTHON="${VENV_DIR}/bin/python"
fi

ms_snapshot() {
  local repo="$1" local_dir="$2"
  shift 2
  "${MS_PYTHON}" - "${repo}" "${local_dir}" "$@" <<'PY'
import os
import sys
from modelscope import snapshot_download

repo, local_dir, *patterns = sys.argv[1:]
kwargs = {
    "model_id": repo,
    "local_dir": local_dir,
}
revision = os.environ.get("MODEL_REVISION", "").strip()
if revision:
    kwargs["revision"] = revision
if patterns:
    kwargs["allow_patterns"] = patterns
snapshot_download(**kwargs)
PY
}

link_model() {
  local source="$1" target="$2"
  [ -f "${source}" ] || {
    echo "Downloaded model file was not found: ${source}" >&2
    return 1
  }
  mkdir -p "$(dirname "${target}")"
  ln -sfn "${source}" "${target}"
  echo "Linked $(basename "${target}") -> ${target}"
}

download_video_models() {
  local cache="${MODEL_CACHE_ROOT}/${WAN_REPO//\//--}"
  local vae="split_files/vae/wan_2.1_vae.safetensors"
  local text="split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
  local clip="split_files/clip_vision/clip_vision_h.safetensors"

  echo "Downloading video profile from ${WAN_REPO}"
  ms_snapshot "${WAN_REPO}" "${cache}" "${WAN_MODEL}" "${vae}" "${text}" "${clip}"

  link_model "${cache}/${WAN_MODEL}"     "${COMFY_DIR}/models/diffusion_models/$(basename "${WAN_MODEL}")"
  link_model "${cache}/${vae}"     "${COMFY_DIR}/models/vae/wan_2.1_vae.safetensors"
  link_model "${cache}/${text}"     "${COMFY_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
  link_model "${cache}/${clip}"     "${COMFY_DIR}/models/clip_vision/clip_vision_h.safetensors"
}

download_image_models() {
  local sdxl_repo="${SDXL_REPO:-AI-ModelScope/stable-diffusion-xl-base-1.0}"
  local instant_repo="${INSTANTID_REPO:-InstantX/InstantID}"
  local ip_repo="${IPADAPTER_REPO:-AI-ModelScope/IP-Adapter}"
  local insight_repo="${INSIGHTFACE_REPO:-deepghs/insightface}"
  local sdxl_cache="${MODEL_CACHE_ROOT}/${sdxl_repo//\//--}"
  local instant_cache="${MODEL_CACHE_ROOT}/${instant_repo//\//--}"
  local ip_cache="${MODEL_CACHE_ROOT}/${ip_repo//\//--}"
  local insight_cache="${MODEL_CACHE_ROOT}/${insight_repo//\//--}"

  echo "Downloading image profile."
  ms_snapshot "${sdxl_repo}" "${sdxl_cache}" "sd_xl_base_1.0.safetensors"
  link_model "${sdxl_cache}/sd_xl_base_1.0.safetensors"     "${COMFY_DIR}/models/checkpoints/sd_xl_base_1.0.safetensors"

  ms_snapshot "${instant_repo}" "${instant_cache}"     "ip-adapter.bin" "ControlNetModel/diffusion_pytorch_model.safetensors"
  link_model "${instant_cache}/ip-adapter.bin"     "${COMFY_DIR}/models/instantid/ip-adapter.bin"
  link_model "${instant_cache}/ControlNetModel/diffusion_pytorch_model.safetensors"     "${COMFY_DIR}/models/controlnet/instantid/diffusion_pytorch_model.safetensors"

  ms_snapshot "${ip_repo}" "${ip_cache}"     "sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"     "models/image_encoder/model.safetensors"
  link_model "${ip_cache}/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"     "${COMFY_DIR}/models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors"
  link_model "${ip_cache}/models/image_encoder/model.safetensors"     "${COMFY_DIR}/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"

  ms_snapshot "${insight_repo}" "${insight_cache}"
  local antelope_dir
  antelope_dir="$(find "${insight_cache}" -type d -name antelopev2 -print -quit)"
  [ -n "${antelope_dir}" ] || {
    echo "antelopev2 was not found in ${insight_repo}" >&2
    return 1
  }
  mkdir -p "${COMFY_DIR}/models/insightface/models"
  ln -sfn "${antelope_dir}" "${COMFY_DIR}/models/insightface/models/antelopev2"
}

download_custom_model() {
  : "${MODEL_ID:?MODEL_ID is required for MODEL_PROFILE=custom}"
  : "${MODEL_FILE:?MODEL_FILE is required for MODEL_PROFILE=custom}"
  : "${MODEL_DIR:?MODEL_DIR is required for MODEL_PROFILE=custom}"
  case "${MODEL_DIR}" in
    /*|*..*) echo "MODEL_DIR must be a relative directory inside ComfyUI/models" >&2; return 2 ;;
  esac
  case "${MODEL_FILE}" in
    *\**|*\?*|*\[*)
      echo "MODEL_FILE must be one exact repository path, not a glob." >&2
      return 2
      ;;
  esac

  local cache="${MODEL_CACHE_ROOT}/custom-${MODEL_ID//\//--}"
  echo "Downloading custom model ${MODEL_ID}:${MODEL_FILE}"
  ms_snapshot "${MODEL_ID}" "${cache}" "${MODEL_FILE}"
  link_model "${cache}/${MODEL_FILE}"     "${COMFY_DIR}/models/${MODEL_DIR}/$(basename "${MODEL_FILE}")"
}

case "${MODEL_PROFILE}" in
  image)
    download_image_models
    ;;
  video)
    download_video_models
    ;;
  all)
    download_image_models
    download_video_models
    ;;
  custom)
    download_custom_model
    ;;
  *)
    echo "MODEL_PROFILE must be image, video, all, or custom" >&2
    exit 2
    ;;
esac

echo "Model profile '${MODEL_PROFILE}' is ready. Run: MODEL_PROFILE=${MODEL_PROFILE} make doctor"
