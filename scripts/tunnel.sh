#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-status}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-${SHELL_BIN_DIR}/cloudflared}"
CF_HOME="${CLOUDFLARE_CONFIG_DIR:-${DATA_DIR}/.cloudflared}"
CF_CONFIG="${CLOUDFLARE_CONFIG_FILE:-${CF_HOME}/config.yml}"
TUNNEL_NAME="${TUNNEL_NAME:-${CLOUDFLARE_TUNNEL_NAME:-soup-comfy}}"
TUNNEL_HOSTNAME="${TUNNEL_HOSTNAME:-${CLOUDFLARE_TUNNEL_HOSTNAME:-}}"
TUNNEL_SERVICE="${TUNNEL_SERVICE:-${CLOUDFLARE_TUNNEL_SERVICE:-${COMFY_URL:-http://127.0.0.1:8188}}}"

cf() {
  HOME="${DATA_DIR}" "$(resolve_binary)" "$@"
}

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
    echo "cloudflared is not installed; run 'make tunnel-init' once." >&2
    exit 1
  }
}

install_cloudflared() {
  local arch asset url temp binary
  mkdir -p "${SHELL_BIN_DIR}" "${CF_HOME}"
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

login_tunnel() {
  require_binary
  mkdir -p "${CF_HOME}"
  echo "Cloudflare account certificate will persist under: ${CF_HOME}"
  echo "Open the URL printed by cloudflared and select the zone for ${TUNNEL_HOSTNAME:-your hostname}."
  cf tunnel login
  [ -f "${CF_HOME}/cert.pem" ] || {
    echo "Login completed without ${CF_HOME}/cert.pem; verify the browser authorization flow." >&2
    exit 1
  }
}

tunnel_id() {
  require_binary
  cf tunnel list --output json | "${VENV_DIR}/bin/python" -c '
import json, os, sys
name = os.environ["CLOUDFLARE_TUNNEL_NAME_RESOLVED"]
matches = [item for item in json.load(sys.stdin) if item.get("name") == name and not item.get("deleted_at")]
if len(matches) != 1:
    raise SystemExit(f"expected one active tunnel named {name!r}, found {len(matches)}")
print(matches[0]["id"])
'
}

create_tunnel() {
  require_binary
  [ -f "${CF_HOME}/cert.pem" ] || {
    echo "Missing ${CF_HOME}/cert.pem; run 'make tunnel-login' first." >&2
    exit 1
  }
  mkdir -p "${CF_HOME}"
  if CLOUDFLARE_TUNNEL_NAME_RESOLVED="${TUNNEL_NAME}" tunnel_id >/dev/null 2>&1; then
    echo "Tunnel already exists: ${TUNNEL_NAME}"
  else
    cf tunnel create "${TUNNEL_NAME}"
  fi
  CLOUDFLARE_TUNNEL_NAME_RESOLVED="${TUNNEL_NAME}" tunnel_id
}

write_config() {
  local id credentials
  [ -n "${TUNNEL_HOSTNAME}" ] || {
    echo "CLOUDFLARE_TUNNEL_HOSTNAME is required." >&2
    exit 2
  }
  id="$(CLOUDFLARE_TUNNEL_NAME_RESOLVED="${TUNNEL_NAME}" tunnel_id)"
  credentials="${CF_HOME}/${id}.json"
  [ -f "${credentials}" ] || {
    echo "Missing tunnel credentials: ${credentials}" >&2
    exit 1
  }
  mkdir -p "${CF_HOME}"
  cat > "${CF_CONFIG}" <<EOF
tunnel: ${id}
credentials-file: ${credentials}

ingress:
  - hostname: ${TUNNEL_HOSTNAME}
    service: ${TUNNEL_SERVICE}
  - service: http_status:404
EOF
  chmod 0600 "${CF_CONFIG}" "${credentials}"
  echo "Wrote persistent tunnel config: ${CF_CONFIG}"
  cf tunnel --config "${CF_CONFIG}" ingress validate
}

route_dns() {
  [ -n "${TUNNEL_HOSTNAME}" ] || {
    echo "CLOUDFLARE_TUNNEL_HOSTNAME is required." >&2
    exit 2
  }
  cf tunnel route dns "${TUNNEL_NAME}" "${TUNNEL_HOSTNAME}"
}

setup_tunnel() {
  create_tunnel
  write_config
  route_dns
  echo "Registered ${TUNNEL_HOSTNAME} -> ${TUNNEL_SERVICE} through ${TUNNEL_NAME}."
}

run_tunnel() {
  require_binary
  [ -f "${CF_CONFIG}" ] || {
    echo "Missing ${CF_CONFIG}; run tunnel-login and tunnel-setup first." >&2
    exit 1
  }
  cf tunnel --config "${CF_CONFIG}" ingress validate
  exec env HOME="${DATA_DIR}" "$(resolve_binary)" --no-autoupdate tunnel --config "${CF_CONFIG}" run "${TUNNEL_NAME}"
}

show_status() {
  local binary
  printf '%-24s %s\n' "enabled" "${ENABLE_CLOUDFLARED:-0}"
  printf '%-24s %s\n' "name" "${TUNNEL_NAME}"
  printf '%-24s %s\n' "hostname" "${TUNNEL_HOSTNAME:-not configured}"
  printf '%-24s %s\n' "origin service" "${TUNNEL_SERVICE}"
  printf '%-24s %s\n' "config" "${CF_CONFIG}"
  if binary="$(resolve_binary 2>/dev/null)"; then
    echo "OK   cloudflared: ${binary}"
    "${binary}" --version
  else
    echo "MISS cloudflared (make tunnel-init)"
  fi
  [ -f "${CF_HOME}/cert.pem" ] && echo "OK   account certificate" || echo "MISS account certificate (make tunnel-login)"
  [ -f "${CF_CONFIG}" ] && echo "OK   tunnel config" || echo "MISS tunnel config (make tunnel-setup)"
  if resolve_binary >/dev/null 2>&1 && [ -f "${CF_HOME}/cert.pem" ]; then
    cf tunnel list || true
  fi
}

service_install() {
  require_binary
  [ -f "${CF_CONFIG}" ] || { echo "Missing ${CF_CONFIG}." >&2; exit 1; }
  if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
    echo "systemd is unavailable in this container." >&2
    echo "Use ENABLE_CLOUDFLARED=1 with 'make up'; the project supervisor will manage cloudflared." >&2
    exit 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: cloudflared --config ${CF_CONFIG} service install" >&2
    exit 1
  fi
  "$(resolve_binary)" --config "${CF_CONFIG}" service install
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
  login) login_tunnel ;;
  create) create_tunnel ;;
  setup) setup_tunnel ;;
  route) route_dns ;;
  validate) require_binary; cf tunnel --config "${CF_CONFIG}" ingress validate ;;
  run) run_tunnel ;;
  list) require_binary; cf tunnel list ;;
  info) require_binary; cf tunnel info "${TUNNEL_NAME}" ;;
  status) show_status ;;
  service-install) service_install ;;
  service-start) service_action start ;;
  service-stop) service_action stop ;;
  service-restart) service_action restart ;;
  service-status) service_action status ;;
  service-uninstall) service_uninstall ;;
  *)
    echo "Usage: scripts/tunnel.sh [init|login|create|setup|route|validate|run|list|info|status|service-install|service-start|service-stop|service-restart|service-status|service-uninstall]" >&2
    exit 2
    ;;
esac
