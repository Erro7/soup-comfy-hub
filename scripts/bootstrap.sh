#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

source "${PROJECT_DIR}/scripts/pip_mirror.sh"
configure_pip_mirror

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
if ! command -v ffmpeg >/dev/null; then
  if command -v apt-get >/dev/null && [ "$(id -u)" -eq 0 ]; then
    apt-get update && apt-get install -y ffmpeg
  else
    echo "ffmpeg is missing; install it with your system package manager" >&2
    exit 1
  fi
fi

python3 -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"
prepare_pip_cache "${DATA_DIR}/.pip-index-url"
python -m pip install --upgrade pip wheel
python -m pip install -r "${PROJECT_DIR}/requirements.txt" 'soup-cli[train]' modelscope

if [ ! -d "${COMFY_DIR}/.git" ]; then
  git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "${COMFY_DIR}"
else
  git -C "${COMFY_DIR}" pull --ff-only
fi
python -m pip install -r "${COMFY_DIR}/requirements.txt"

install_node() {
  local repo="$1" name="$2"
  if [ ! -d "${COMFY_DIR}/custom_nodes/${name}/.git" ]; then
    git clone --depth 1 "${repo}" "${COMFY_DIR}/custom_nodes/${name}"
  else
    git -C "${COMFY_DIR}/custom_nodes/${name}" pull --ff-only
  fi
  if [ -f "${COMFY_DIR}/custom_nodes/${name}/requirements.txt" ]; then
    python -m pip install -r "${COMFY_DIR}/custom_nodes/${name}/requirements.txt"
  fi
}

install_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite
install_node https://github.com/city96/ComfyUI-GGUF.git ComfyUI-GGUF
install_node https://github.com/cubiq/ComfyUI_InstantID.git ComfyUI_InstantID
install_node https://github.com/cubiq/ComfyUI_IPAdapter_plus.git ComfyUI_IPAdapter_plus
if [ "${INSTALL_POSE_GALLERY:-1}" = "1" ]; then
  install_node https://github.com/anhao/ai-pose-gallery-zh.git ai-pose-gallery-zh
fi

mkdir -p "${TASK_OUTPUT_DIR}" "${PROJECT_DIR}/logs" "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}"
[ -f "${PROJECT_DIR}/.env" ] || cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
echo "Bootstrap complete. Edit ${PROJECT_DIR}/.env, then run make models and make up."
