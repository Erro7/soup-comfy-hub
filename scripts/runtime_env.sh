#!/usr/bin/env bash

# Portable defaults. Every value remains overridable by environment variables.
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
WORKSPACE="${WORKSPACE:-$(dirname "${PROJECT_DIR}")}"
DATA_DIR="${DATA_DIR:-${WORKSPACE}/soup-comfy-data}"
COMFY_DIR="${COMFY_DIR:-${DATA_DIR}/ComfyUI}"
VENV_DIR="${VENV_DIR:-${DATA_DIR}/venv}"

export PROJECT_DIR WORKSPACE DATA_DIR COMFY_DIR VENV_DIR
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${DATA_DIR}/pip-cache}"
export COMFY_INPUT_DIR="${COMFY_INPUT_DIR:-${COMFY_DIR}/input}"
export COMFY_OUTPUT_DIR="${COMFY_OUTPUT_DIR:-${COMFY_DIR}/output}"
export WORKFLOW_DIR="${WORKFLOW_DIR:-${PROJECT_DIR}/workflows}"
export SOUP_WORKSPACE="${SOUP_WORKSPACE:-${PROJECT_DIR}/soup_workspace}"
export TASK_OUTPUT_DIR="${TASK_OUTPUT_DIR:-${DATA_DIR}/outputs}"
export TASK_DB_PATH="${TASK_DB_PATH:-${DATA_DIR}/outputs/tasks.sqlite3}"
