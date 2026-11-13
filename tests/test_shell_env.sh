#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

export PROJECT_DIR
export DATA_DIR="${TEMP_ROOT}/data"
export TOOLS_HOME="${TEMP_ROOT}/tools"
export VENV_DIR="${TEMP_ROOT}/missing-venv"
export SHELL_HOME="${TEMP_ROOT}/shell"
export CACHE_DIR="${TEMP_ROOT}/cache"
export INSTALL_ZSH=0
export INSTALL_OMZ=0
export PIP_MIRROR=pypi
export NPM_REGISTRY=https://registry.example.test/

bash "${PROJECT_DIR}/scripts/shell.sh" init
test -f "${SHELL_HOME}/env.sh"
test -f "${SHELL_HOME}/config/pip/pip.conf"
test -f "${SHELL_HOME}/config/npm/npmrc"
grep -q 'index-url = https://pypi.org/simple' "${SHELL_HOME}/config/pip/pip.conf"
grep -q 'registry=https://registry.example.test/' "${SHELL_HOME}/config/npm/npmrc"
grep -q "export TOOLS_HOME=\"${TOOLS_HOME}\"" "${SHELL_HOME}/env.sh"

status="$(bash "${PROJECT_DIR}/scripts/shell.sh" status)"
grep -q 'INFO project venv not initialized' <<<"${status}"
grep -q 'OK   persistent pip config' <<<"${status}"
grep -q 'OK   persistent npm config' <<<"${status}"

export EXPECTED_TOOLS_HOME="${TOOLS_HOME}"
SHELL_KIND=bash SHELL_COMMAND='test "$TOOLS_HOME" = "$EXPECTED_TOOLS_HOME"' \
  bash "${PROJECT_DIR}/scripts/shell.sh" run

bash "${PROJECT_DIR}/scripts/shell.sh" doctor
echo "flattened shell regression: PASS"
