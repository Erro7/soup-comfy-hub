#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${SCRIPT_DIR}/lib/venv.sh"

ACTION="${1:-status}"
shift || true

case "${ACTION}" in
  init|ensure) venv_ensure ;;
  status) venv_status ;;
  doctor) venv_doctor ;;
  python) runtime_require_venv; exec "${VENV_DIR}/bin/python" "$@" ;;
  exec) runtime_require_venv; [ "$#" -gt 0 ] || { echo "A command is required." >&2; exit 2; }; exec "$@" ;;
  help|-h|--help)
    echo "Usage: scripts/venv.sh [init|status|doctor|python|exec] [arguments...]"
    ;;
  *) echo "Unsupported venv action: ${ACTION}" >&2; exit 2 ;;
esac
