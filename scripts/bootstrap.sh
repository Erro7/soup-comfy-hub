#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${PROJECT_DIR}/scripts/pip_mirror.sh"

configure_pip_mirror
LEGACY_PIP_CACHE="${DATA_DIR}/pip-cache"
if [ -d "${LEGACY_PIP_CACHE}" ] && [ ! -e "${PIP_CACHE_DIR}" ]; then
  mkdir -p "${CACHE_DIR}"
  mv "${LEGACY_PIP_CACHE}" "${PIP_CACHE_DIR}"
  echo "Migrated legacy pip cache to ${PIP_CACHE_DIR}"
fi
mkdir -p "${DATA_DIR}" "${PIP_CACHE_DIR}" "${TASK_OUTPUT_DIR}" "${LOG_DIR}"

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

if ! command -v ffmpeg >/dev/null; then
  if command -v apt-get >/dev/null && [ "$(id -u)" -eq 0 ]; then
    apt-get update
    apt-get install -y --no-install-recommends ffmpeg
  else
    echo "ffmpeg is missing; install it with your system package manager" >&2
    exit 1
  fi
fi

resolve_github_url() {
  local url="$1"
  local prefix="${GITHUB_MIRROR_PREFIX:-auto}"
  case "${prefix}" in
    auto|off|direct|"") prefix="" ;;
  esac
  printf '%s%s' "${prefix}" "${url}"
}

GITHUB_ACCELERATOR_FAILED=0

sync_repository() {
  local repo="$1" target="$2" source_url
  source_url="$(resolve_github_url "${repo}")"
  [ "${GITHUB_ACCELERATOR_FAILED}" = "0" ] || source_url="${repo}"

  if [ -d "${target}/.git" ]; then
    git -C "${target}" remote set-url origin "${source_url}"
    if ! git -C "${target}" pull --ff-only; then
      [ "${source_url}" != "${repo}" ] || return 1
      echo "Git mirror failed; retrying direct: ${repo}" >&2
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

  if ! git clone --depth 1 "${source_url}" "${target}"; then
    [ "${source_url}" != "${repo}" ] || return 1
    [ ! -d "${target}" ] || rmdir "${target}" 2>/dev/null || true
    echo "Git mirror failed; retrying direct: ${repo}" >&2
    GITHUB_ACCELERATOR_FAILED=1
    git clone --depth 1 "${repo}" "${target}"
  fi
}

PIP_STATE_FILE="${DATA_DIR}/.pip-index-url"
if pip_index_changed "${PIP_STATE_FILE}"; then
  echo "Package index changed; rebuilding the persistent venv."
  python3 -m venv --clear "${VENV_DIR}"
else
  python3 -m venv "${VENV_DIR}"
fi

runtime_activate_venv
prepare_pip_cache "${PIP_STATE_FILE}"
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

COMFY_API_REQUIREMENTS=""
cleanup_bootstrap() {
  [ -z "${COMFY_API_REQUIREMENTS}" ] || rm -f "${COMFY_API_REQUIREMENTS}"
}
trap cleanup_bootstrap EXIT

if [ "${INSTALL_COMFY_WORKFLOW_TEMPLATES:-0}" = "1" ]; then
  python -m pip install -r "${COMFY_DIR}/requirements.txt"
else
  COMFY_API_REQUIREMENTS="$(mktemp "${DATA_DIR}/comfy-api-requirements.XXXXXX")"
  grep -vE '^[[:space:]]*comfyui-workflow-templates([=<>!~ ].*)?$'     "${COMFY_DIR}/requirements.txt" > "${COMFY_API_REQUIREMENTS}"
  echo "Installing ComfyUI API dependencies (template media assets skipped)."
  python -m pip install -r "${COMFY_API_REQUIREMENTS}"
  rm -f "${COMFY_API_REQUIREMENTS}"
  COMFY_API_REQUIREMENTS=""
fi

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

mkdir -p "${COMFY_INPUT_DIR}" "${COMFY_OUTPUT_DIR}" "${TASK_OUTPUT_DIR}" "${LOG_DIR}"
touch "${DATA_DIR}/.runtime-ready"
[ -f "${PROJECT_DIR}/.env" ] || cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
echo "Persistent runtime ready at ${DATA_DIR}."
echo "Next: make models && make doctor && make up"
