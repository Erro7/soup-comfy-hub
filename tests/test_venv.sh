#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

export PROJECT_DIR
export DATA_DIR="${TEMP_ROOT}/data"
export VENV_DIR="${TEMP_ROOT}/venv"
export VENV_USE_SYSTEM_SITE_PACKAGES=0
export PYTHON_BIN="$(command -v python3)"
export PIP_INDEX_URL=https://pypi.org/simple

bash "${PROJECT_DIR}/scripts/venv.sh" init
test -x "${VENV_DIR}/bin/python"
test -f "${DATA_DIR}/state/venv.env"
touch "${VENV_DIR}/reuse-marker"

export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
second="$(bash "${PROJECT_DIR}/scripts/venv.sh" init)"
grep -q 'Reusing persistent Python environment' <<<"${second}"
test -f "${VENV_DIR}/reuse-marker"

bash "${PROJECT_DIR}/scripts/venv.sh" doctor
bash "${PROJECT_DIR}/scripts/venv.sh" python -c 'import sys; assert sys.prefix != sys.base_prefix'
echo "persistent venv regression: PASS"
