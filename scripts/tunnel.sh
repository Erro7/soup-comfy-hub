#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-status}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-${SHELL_BIN_DIR}/cloudflared}"

resolve_binary() {
  if command -v cloudflared >/dev/null 2>&1; then
    command -v cloudflared
  elif [ -x "${CLOUDFLARED_BIN}" ]; then
    printf '%s\n' "${CLOUDFLARED_BIN}"
  else
    return 1
  fi
}

require_binary() {
  resolve_binary >/dev/null || {
    echo "cloudflared is not installed; run 'make init' or 'make tunnel-init'." >&2
    exit 1
  }
}

require_token() {
  [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] || {
    echo "CLOUDFLARE_TUNNEL_TOKEN is required for the remotely managed tunnel." >&2
    exit 2
  }
}

install_cloudflared() {
  local arch asset url temp binary
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
  require_binary
  require_token
  exec "$(resolve_binary)" tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}"
}

show_status() {
  local binary
  printf '%-24s %s\n' "installed by init" "${INSTALL_CLOUDFLARED:-1}"
  printf '%-24s %s\n' "enabled at runtime" "${ENABLE_CLOUDFLARED:-0}"
  printf '%-24s %s\n' "public URL" "${CLOUDFLARE_PUBLIC_URL:-not configured}"
  if binary="$(resolve_binary 2>/dev/null)"; then
    echo "OK   cloudflared: ${binary}"
    "${binary}" --version
  else
    echo "MISS cloudflared (make init or make tunnel-init)"
  fi
  if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "OK   remotely managed tunnel token configured"
  else
    echo "MISS CLOUDFLARE_TUNNEL_TOKEN"
  fi
}

service_install() {
  require_binary
  require_token
  if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
    echo "systemd is unavailable in this container." >&2
    echo "Use ENABLE_CLOUDFLARED=1 with 'make up'; the project supervisor will manage cloudflared." >&2
    exit 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: cloudflared service install <TUNNEL_TOKEN>" >&2
    exit 1
  fi
  "$(resolve_binary)" service install "${CLOUDFLARE_TUNNEL_TOKEN}"
  systemctl enable --now cloudflared
}

service_action() {
  local operation="$1"
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] || {
    echo "systemd is unavailable; use make up/down/status in this container." >&2
    exit 1
  }
  systemctl "${operation}" cloudflared
}

service_uninstall() {
  require_binary
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] || {
    echo "systemd is unavailable in this container." >&2
    exit 1
  }
  [ "$(id -u)" -eq 0 ] || { echo "Run this command as root." >&2; exit 1; }
  systemctl disable --now cloudflared 2>/dev/null || true
  "$(resolve_binary)" service uninstall
}

case "${ACTION}" in
  init) install_cloudflared ;;
  run) run_tunnel ;;
  status) show_status ;;
  service-install) service_install ;;
  service-start) service_action start ;;
  service-stop) service_action stop ;;
  service-restart) service_action restart ;;
  service-status) service_action status ;;
  service-uninstall) service_uninstall ;;
  *)
    echo "Usage: scripts/tunnel.sh [init|run|status|service-install|service-start|service-stop|service-restart|service-status|service-uninstall]" >&2
    exit 2
    ;;
esac
