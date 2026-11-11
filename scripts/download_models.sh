#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="${WORKSPACE:-/mnt/workspace}"
COMFY_DIR="${COMFY_DIR:-${WORKSPACE}/ComfyUI}"
VENV_DIR="${VENV_DIR:-${WORKSPACE}/venv}"
WAN_REPO="${WAN_REPO:-Comfy-Org/Wan_2.1_ComfyUI_repackaged}"
WAN_QUANT_REPO="${WAN_QUANT_REPO:-}"

source "${VENV_DIR}/bin/activate"
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

if [ -n "${WAN_QUANT_REPO}" ]; then
  modelscope download --model "${WAN_QUANT_REPO}" --local_dir "${COMFY_DIR}/models/diffusion_models"
else
  echo "Base Wan components downloaded. Set WAN_QUANT_REPO to a trusted FP8/GGUF ModelScope repository for the 14B diffusion model."
fi
