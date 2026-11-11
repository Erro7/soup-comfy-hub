#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
WAN_REPO="${WAN_REPO:-Comfy-Org/Wan_2.1_ComfyUI_repackaged}"
WAN_MODEL="${WAN_MODEL:-split_files/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors}"

source "${VENV_DIR}/bin/activate"
if ! python -c 'import modelscope' >/dev/null 2>&1; then
  MODELSCOPE_PIP_INDEX_URL="${MODELSCOPE_PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
  echo "Installing optional ModelScope downloader from ${MODELSCOPE_PIP_INDEX_URL}"
  python -m pip install --index-url "${MODELSCOPE_PIP_INDEX_URL}" modelscope
fi
mkdir -p "${COMFY_DIR}/models/vae" "${COMFY_DIR}/models/text_encoders" "${COMFY_DIR}/models/diffusion_models"

python - "${WAN_REPO}" "${COMFY_DIR}" <<'PY'
import sys
from pathlib import Path
from modelscope import snapshot_download

repo, root = sys.argv[1], Path(sys.argv[2])
cache = root / "models" / ".modelscope" / repo.replace("/", "--")
snapshot_download(repo, local_dir=str(cache), allow_patterns=[
    "split_files/vae/wan_2.1_vae.safetensors",
    "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors",
    "split_files/clip_vision/clip_vision_h.safetensors",
])

patterns = {
    "vae": ("*vae*.safetensors", "*VAE*.pth", "*vae*.pth"),
    "text_encoders": ("*umt5*", "*clip*xlm*"),
    "clip_vision": ("*clip_vision*",),
}
for destination, globs in patterns.items():
    target = root / "models" / destination
    for pattern in globs:
        for source in cache.rglob(pattern):
            if source.is_file():
                link = target / source.name
                if not link.exists():
                    link.symlink_to(source)
PY

modelscope download --model "${WAN_REPO}" --include "${WAN_MODEL}" --local_dir "${COMFY_DIR}/models/.wan-download"
ln -sf "${COMFY_DIR}/models/.wan-download/${WAN_MODEL}" "${COMFY_DIR}/models/diffusion_models/$(basename "${WAN_MODEL}")"

echo "Downloading the SDXL/InstantID/IPAdapter baseline..."
mkdir -p "${COMFY_DIR}/models/checkpoints" "${COMFY_DIR}/models/instantid" "${COMFY_DIR}/models/controlnet/instantid" "${COMFY_DIR}/models/ipadapter" "${COMFY_DIR}/models/clip_vision" "${COMFY_DIR}/models/insightface/models"
modelscope download --model AI-ModelScope/stable-diffusion-xl-base-1.0 --include sd_xl_base_1.0.safetensors --local_dir "${COMFY_DIR}/models/checkpoints"
modelscope download --model InstantX/InstantID --include ip-adapter.bin ControlNetModel/diffusion_pytorch_model.safetensors --local_dir "${COMFY_DIR}/models/.instantid-download"
ln -sf "${COMFY_DIR}/models/.instantid-download/ip-adapter.bin" "${COMFY_DIR}/models/instantid/ip-adapter.bin"
ln -sf "${COMFY_DIR}/models/.instantid-download/ControlNetModel/diffusion_pytorch_model.safetensors" "${COMFY_DIR}/models/controlnet/instantid/diffusion_pytorch_model.safetensors"
modelscope download --model "${IPADAPTER_REPO:-AI-ModelScope/IP-Adapter}" --include sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors models/image_encoder/model.safetensors --local_dir "${COMFY_DIR}/models/.ipadapter-download"
ln -sf "${COMFY_DIR}/models/.ipadapter-download/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors" "${COMFY_DIR}/models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors"
ln -sf "${COMFY_DIR}/models/.ipadapter-download/models/image_encoder/model.safetensors" "${COMFY_DIR}/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"
modelscope download --model "${INSIGHTFACE_REPO:-deepghs/insightface}" --local_dir "${COMFY_DIR}/models/.insightface-download"
ANTELOPE_DIR="$(find "${COMFY_DIR}/models/.insightface-download" -type d -name antelopev2 -print -quit)"
if [ -z "${ANTELOPE_DIR}" ]; then
  echo "antelopev2 was not found in ${INSIGHTFACE_REPO:-deepghs/insightface}" >&2
  exit 1
fi
ln -sfn "${ANTELOPE_DIR}" "${COMFY_DIR}/models/insightface/models/antelopev2"

echo "Model download finished. Run 'make doctor' before starting services."
