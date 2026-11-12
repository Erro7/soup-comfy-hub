#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

source "${PROJECT_DIR}/scripts/pip_mirror.sh"
configure_pip_mirror

resolve_github_url() {
  local url="$1"
  local prefix="${GITHUB_MIRROR_PREFIX:-auto}"
  local timezone="${TZ:-}"
  if [[ -z "${timezone}" && -r /etc/timezone ]]; then
    timezone="$(tr -d '[:space:]' < /etc/timezone)"
  fi
  if [[ "${prefix}" == "auto" ]]; then
    # File-download proxies such as ghfast.top do not implement Git Smart HTTP
    # and must never be used as a git clone remote.
    prefix=""
  elif [[ "${prefix}" == "off" || "${prefix}" == "direct" ]]; then
    prefix=""
  fi
  printf '%s%s' "${prefix}" "${url}"
}

GITHUB_ACCELERATOR_FAILED=0

sync_repository() {
  local repo="$1" target="$2"
  local source_url
  source_url="$(resolve_github_url "${repo}")"
  if [ "${GITHUB_ACCELERATOR_FAILED}" = "1" ]; then
    source_url="${repo}"
  fi

  if [ -d "${target}/.git" ]; then
    git -C "${target}" remote set-url origin "${source_url}"
    if ! git -C "${target}" pull --ff-only; then
      if [ "${source_url}" = "${repo}" ]; then
        return 1
      fi
      echo "GitHub accelerator failed; retrying direct: ${repo}" >&2
      GITHUB_ACCELERATOR_FAILED=1
      git -C "${target}" remote set-url origin "${repo}"
      git -C "${target}" pull --ff-only
    fi
    return
  fi

  if [ -e "${target}" ]; then
    if [ -d "${target}" ] && [ -z "$(find "${target}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      rmdir "${target}"
    else
      echo "Cannot clone into non-empty partial directory: ${target}" >&2
      return 1
    fi
  fi

  echo "Cloning ${source_url}"
  if ! git clone --depth 1 "${source_url}" "${target}"; then
    if [ "${source_url}" = "${repo}" ]; then
      return 1
    fi
    [ ! -d "${target}" ] || rmdir "${target}" 2>/dev/null || true
    echo "GitHub accelerator failed; retrying direct: ${repo}" >&2
    GITHUB_ACCELERATOR_FAILED=1
    git clone --depth 1 "${repo}" "${target}"
  fi
}

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

PIP_STATE_FILE="${DATA_DIR}/.pip-index-url"
if pip_index_changed "${PIP_STATE_FILE}"; then
  echo "Package index changed; rebuilding the project virtual environment."
  python3 -m venv --clear "${VENV_DIR}"
else
  python3 -m venv "${VENV_DIR}"
fi
source "${VENV_DIR}/bin/activate"
prepare_pip_cache "${PIP_STATE_FILE}"
# Record immediately so an interrupted install resumes instead of clearing the
# partially populated persistent venv again on the next container start.
record_pip_environment "${PIP_STATE_FILE}"
if [ "${UPGRADE_PIP_TOOLCHAIN:-0}" = "1" ]; then
  python -m pip install --upgrade pip
fi
python -m pip install -r "${PROJECT_DIR}/requirements.txt"
if [ "${INSTALL_GRADIO_UI:-0}" = "1" ]; then
  python -m pip install -r "${PROJECT_DIR}/requirements-ui.txt"
fi
if [ "${INSTALL_SOUP:-0}" = "1" ]; then
  python -m pip install 'soup-cli[train]'
fi

sync_repository https://github.com/Comfy-Org/ComfyUI.git "${COMFY_DIR}"
python -m pip install -r "${COMFY_DIR}/requirements.txt"

install_node() {
  local repo="$1" name="$2"
  sync_repository "${repo}" "${COMFY_DIR}/custom_nodes/${name}"
  if [ -f "${COMFY_DIR}/custom_nodes/${name}/requirements.txt" ]; then
    python -m pip install -r "${COMFY_DIR}/custom_nodes/${name}/requirements.txt"
  fi
}

install_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite
install_node https://github.com/city96/ComfyUI-GGUF.git ComfyUI-GGUF
install_node https://github.com/cubiq/ComfyUI_InstantID.git ComfyUI_InstantID
install_node https://github.com/cubiq/ComfyUI_IPAdapter_plus.git ComfyUI_IPAdapter_plus
if [ "${INSTALL_POSE_GALLERY:-0}" = "1" ]; then
  install_node https://github.com/anhao/ai-pose-gallery-zh.git ai-pose-gallery-zh
fi

mkdir -p "${TASK_OUTPUT_DIR}" "${PROJECT_DIR}/logs" "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}"
touch "${DATA_DIR}/.runtime-ready"
[ -f "${PROJECT_DIR}/.env" ] || cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
echo "Persistent runtime ready at ${DATA_DIR}. Edit ${PROJECT_DIR}/.env, then run make models and make up."
