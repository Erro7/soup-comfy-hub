#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
runtime_activate_venv

if [ "$#" -eq 0 ]; then
  echo "Usage: scripts/venv_exec.sh COMMAND [ARG ...]" >&2
  exit 2
fi
exec "$@"
