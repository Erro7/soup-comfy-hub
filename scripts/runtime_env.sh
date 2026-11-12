#!/usr/bin/env bash

# Portable defaults. Every value remains overridable by environment variables.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "${_SCRIPT_DIR}/lib/paths.sh"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${_SCRIPT_DIR}/.." && pwd)}"
if [ -f "${PROJECT_DIR}/.env" ]; then
  # .env supplies defaults; explicit shell/container variables take precedence.
  declare -A _runtime_env_before=()
  while IFS='=' read -r key value; do
    _runtime_env_before["${key}"]="${value}"
  done < <(env)
  set -a
  source "${PROJECT_DIR}/.env"
  set +a
  for key in "${!_runtime_env_before[@]}"; do
    export "${key}=${_runtime_env_before[${key}]}"
  done
  unset _runtime_env_before key value
fi
paths_export_runtime
COMFY_DIR="${COMFY_DIR:-${DATA_DIR}/ComfyUI}"
VENV_DIR="${VENV_DIR:-${DATA_DIR}/venv}"

export PROJECT_DIR WORKSPACE DATA_DIR COMFY_DIR VENV_DIR TOOLS_HOME TOOLS_BIN_DIR
export CACHE_DIR="${CACHE_DIR:-${DATA_DIR}/cache}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${CACHE_DIR}/pip}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-${CACHE_DIR}/uv}"
export MODELSCOPE_CACHE="${MODELSCOPE_CACHE:-${CACHE_DIR}/modelscope}"
export MODELSCOPE_CACHE_HOME="${MODELSCOPE_CACHE_HOME:-${MODELSCOPE_CACHE}}"
export HF_HOME="${HF_HOME:-${CACHE_DIR}/huggingface}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-${HF_HOME}/hub}"
export TORCH_HOME="${TORCH_HOME:-${CACHE_DIR}/torch}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${CACHE_DIR}/npm}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${CACHE_DIR}/xdg}"
export CUDA_CACHE_PATH="${CUDA_CACHE_PATH:-${CACHE_DIR}/cuda}"
export COMFY_INPUT_DIR="${COMFY_INPUT_DIR:-${COMFY_DIR}/input}"
export COMFY_OUTPUT_DIR="${COMFY_OUTPUT_DIR:-${COMFY_DIR}/output}"
export WORKFLOW_DIR="${WORKFLOW_DIR:-${PROJECT_DIR}/workflows}"
export SOUP_WORKSPACE="${SOUP_WORKSPACE:-${PROJECT_DIR}/soup_workspace}"
export TASK_OUTPUT_DIR="${TASK_OUTPUT_DIR:-${DATA_DIR}/outputs}"
export TASK_DB_PATH="${TASK_DB_PATH:-${DATA_DIR}/outputs/tasks.sqlite3}"

export LOG_DIR="${LOG_DIR:-${DATA_DIR}/logs}"
export SERVICES_PID_FILE="${SERVICES_PID_FILE:-${LOG_DIR}/services.pid}"
export SHELL_HOME="${SHELL_HOME:-${DATA_DIR}/shell}"
export SHELL_BIN_DIR="${SHELL_BIN_DIR:-${SHELL_HOME}/bin}"
export SHELL_STATE_DIR="${SHELL_STATE_DIR:-${SHELL_HOME}/state}"
export SHELL_HISTORY_DIR="${SHELL_HISTORY_DIR:-${SHELL_HOME}/history}"
paths_prepend "${TOOLS_BIN_DIR}"
paths_prepend "${SHELL_BIN_DIR}"

runtime_require_venv() {
  if [ ! -x "${VENV_DIR}/bin/python" ]; then
    echo "Persistent Python environment is missing: ${VENV_DIR}" >&2
    echo "Run 'make init' once before using this command." >&2
    return 1
  fi
}

runtime_activate_venv() {
  runtime_require_venv
  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"
  export PATH="${VENV_DIR}/bin:${PATH}"
}

runtime_require_comfy() {
  if [ ! -f "${COMFY_DIR}/main.py" ]; then
    echo "ComfyUI is missing: ${COMFY_DIR}" >&2
    echo "Run 'make init' once before using this command." >&2
    return 1
  fi
}
