#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-status}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-${SHELL_BIN_DIR}/cloudflared}"
TUNNEL_MODE="${CLOUDFLARE_TUNNEL_MODE:-auto}"
TUNNEL_TARGET="${CLOUDFLARE_TUNNEL_TARGET:-${COMFY_URL:-http://127.0.0.1:8188}}"

resolve_binary() {
  if command -v cloudflared >/dev/null 2>&1; then
    command -v cloudflared
  elif [ -x "${CLOUDFLARED_BIN}" ]; then
    printf '%s\n' "${CLOUDFLARED_BIN}"
  else
    return 1
  fi
}

install_cloudflared() {
  local arch asset url temp
  mkdir -p "${SHELL_BIN_DIR}"
  if binary="$(resolve_binary 2>/dev/null)"; then
    echo "cloudflared is already installed: ${binary}"
    "${binary}" --version
    return
  fi

  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  asset="cloudflared-linux-${arch}"
  url="${CLOUDFLARED_DOWNLOAD_URL:-https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}}"
  temp="${CLOUDFLARED_BIN}.download.$$"
  trap 'rm -f "${temp}"' EXIT

  echo "Installing cloudflared into persistent storage: ${CLOUDFLARED_BIN}"
  echo "Source: ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 -o "${temp}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${temp}" "${url}"
  else
    echo "curl or wget is required to install cloudflared." >&2
    exit 1
  fi
  chmod 0755 "${temp}"
  mv "${temp}" "${CLOUDFLARED_BIN}"
  trap - EXIT
  "${CLOUDFLARED_BIN}" --version
}

run_tunnel() {
  local binary mode
  binary="$(resolve_binary)" || {
    echo "cloudflared is not installed; run 'make tunnel-init' once." >&2
    exit 1
  }
  mode="${TUNNEL_MODE}"
  if [ "${mode}" = "auto" ]; then
    if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
      mode="named"
    else
      mode="quick"
    fi
  fi

  echo "Starting Cloudflare ${mode} tunnel -> ${TUNNEL_TARGET}"
  case "${mode}" in
    named)
      [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] || {
        echo "CLOUDFLARE_TUNNEL_TOKEN is required for named mode." >&2
        exit 2
      }
      exec "${binary}" --no-autoupdate tunnel run --token "${CLOUDFLARE_TUNNEL_TOKEN}"
      ;;
    quick)
      exec "${binary}" --no-autoupdate tunnel --url "${TUNNEL_TARGET}"
      ;;
    *)
      echo "CLOUDFLARE_TUNNEL_MODE must be auto, named, or quick." >&2
      exit 2
      ;;
  esac
}

show_status() {
  printf '%-24s %s\n' "enabled" "${ENABLE_CLOUDFLARED:-0}"
  printf '%-24s %s\n' "mode" "${TUNNEL_MODE}"
  printf '%-24s %s\n' "target" "${TUNNEL_TARGET}"
  printf '%-24s %s\n' "public URL" "${CLOUDFLARE_PUBLIC_URL:-not configured}"
  if binary="$(resolve_binary 2>/dev/null)"; then
    echo "OK   cloudflared: ${binary}"
    "${binary}" --version
  else
    echo "MISS cloudflared (make tunnel-init)"
  fi
  if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "OK   named tunnel token configured"
  else
    echo "INFO no named token; auto mode will use a temporary quick tunnel"
  fi
}

case "${ACTION}" in
  init) install_cloudflared ;;
  run) run_tunnel ;;
  status) show_status ;;
  *)
    echo "Usage: scripts/tunnel.sh [init|run|status]" >&2
    exit 2
    ;;
esac
