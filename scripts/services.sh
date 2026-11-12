#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-status}"

read_pid() {
  [ -f "${SERVICES_PID_FILE}" ] || return 1
  local pid
  pid="$(<"${SERVICES_PID_FILE}")"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "${pid}"
}

case "${ACTION}" in
  stop)
    if ! pid="$(read_pid)" || ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${SERVICES_PID_FILE}"
      echo "Services are not running."
      exit 0
    fi
    kill "${pid}"
    for _ in $(seq 1 20); do
      kill -0 "${pid}" 2>/dev/null || break
      sleep 0.25
    done
    if kill -0 "${pid}" 2>/dev/null; then
      echo "Supervisor ${pid} did not stop cleanly." >&2
      exit 1
    fi
    rm -f "${SERVICES_PID_FILE}"
    echo "Services stopped."
    ;;
  status)
    if pid="$(read_pid)" && kill -0 "${pid}" 2>/dev/null; then
      echo "RUNNING supervisor_pid=${pid}"
      exit 0
    fi
    rm -f "${SERVICES_PID_FILE}"
    echo "STOPPED"
    exit 1
    ;;
  logs)
    mkdir -p "${LOG_DIR}"
    touch "${LOG_DIR}/comfyui.log" "${LOG_DIR}/gateway.log"
    exec tail -n "${LOG_LINES:-100}" -F "${LOG_DIR}/comfyui.log" "${LOG_DIR}/gateway.log"
    ;;
  *)
    echo "Usage: scripts/services.sh [stop|status|logs]" >&2
    exit 2
    ;;
esac
