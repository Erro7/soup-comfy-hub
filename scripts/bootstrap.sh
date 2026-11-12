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

select_base_python() {
  local requested="${PYTHON_BIN:-}"
  local candidate resolved
  if [ -n "${requested}" ]; then
    command -v "${requested}" >/dev/null 2>&1 || {
      echo "PYTHON_BIN is not executable: ${requested}" >&2
      return 1
    }
    command -v "${requested}"
    return
  fi
  for candidate in python python3 /opt/conda/bin/python; do
    resolved="$(command -v "${candidate}" 2>/dev/null || true)"
    [ -n "${resolved}" ] || continue
    if "${resolved}" -c 'import torch' >/dev/null 2>&1; then
      printf '%s\n' "${resolved}"
      return
    fi
  done
  command -v python3 2>/dev/null || command -v python 2>/dev/null || {
    echo "No usable Python interpreter was found." >&2
    return 1
  }
}

BASE_PYTHON="$(select_base_python)"
BASE_PYTHON="$("${BASE_PYTHON}" -c 'import os,sys; print(os.path.realpath(sys.executable))')"
echo "Selected base Python: ${BASE_PYTHON}"

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

VENV_SYSTEM_MODE="${VENV_USE_SYSTEM_SITE_PACKAGES:-auto}"
BASE_HAS_TORCH=0
"${BASE_PYTHON}" -c 'import torch' >/dev/null 2>&1 && BASE_HAS_TORCH=1
[ "${VENV_SYSTEM_MODE}" != "auto" ] || VENV_SYSTEM_MODE="${BASE_HAS_TORCH}"

case "${VENV_SYSTEM_MODE}" in
  1|true|yes)
    [ "${BASE_HAS_TORCH}" = "1" ] || {
      echo "Selected Python cannot import torch: ${BASE_PYTHON}" >&2
      echo "Set PYTHON_BIN to the interpreter preloaded with PyTorch." >&2
      exit 1
    }
    PYTHON_ID="$("${BASE_PYTHON}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    export PIP_ENV_FLAVOR="system-site-packages:${BASE_PYTHON}:${PYTHON_ID}"
    VENV_ARGS=(--system-site-packages)
    echo "Reusing PyTorch/CUDA packages from ${BASE_PYTHON}."
    ;;
  0|false|no)
    PYTHON_ID="$("${BASE_PYTHON}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    export PIP_ENV_FLAVOR="isolated:${BASE_PYTHON}:${PYTHON_ID}"
    VENV_ARGS=()
    ;;
  *)
    echo "VENV_USE_SYSTEM_SITE_PACKAGES must be auto, 1, or 0" >&2
    exit 2
    ;;
esac

PIP_STATE_FILE="${DATA_DIR}/.pip-index-url"
if pip_index_changed "${PIP_STATE_FILE}"; then
  echo "Python base/index mode changed; rebuilding only ${VENV_DIR} once."
  "${BASE_PYTHON}" -m venv --clear "${VENV_ARGS[@]}" "${VENV_DIR}"
else
  "${BASE_PYTHON}" -m venv "${VENV_ARGS[@]}" "${VENV_DIR}"
fi

runtime_activate_venv
if [[ "${PIP_ENV_FLAVOR}" == system-site-packages:* ]]; then
  python - <<'PY'
import torch
print(f"Verified inherited torch={torch.__version__} cuda={torch.version.cuda} path={torch.__file__}")
PY
fi
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
if [ "${INSTALL_CLOUDFLARED:-1}" = "1" ]; then
  bash "${PROJECT_DIR}/scripts/tools/cloudflared.sh" install
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
