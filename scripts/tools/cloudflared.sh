#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# shellcheck source=../lib/paths.sh
source "${PROJECT_DIR}/scripts/lib/paths.sh"
# shellcheck source=../lib/platform.sh
source "${PROJECT_DIR}/scripts/lib/platform.sh"
# shellcheck source=../lib/download.sh
source "${PROJECT_DIR}/scripts/lib/download.sh"

# Load project defaults without replacing values already supplied by the caller.
declare -A _tool_env=()
while IFS='=' read -r key value; do _tool_env["${key}"]="${value}"; done < <(env)
if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/.env"
  set +a
fi
for key in "${!_tool_env[@]}"; do export "${key}=${_tool_env[${key}]}"; done
unset _tool_env key value

paths_export_runtime
paths_prepend "${TOOLS_BIN_DIR}"

ACTION="${1:-status}"
MANAGED_BINARY="${TOOLS_BIN_DIR}/cloudflared"

resolve_binary() {
  if [ -n "${CLOUDFLARED_BIN:-}" ] && [ -x "${CLOUDFLARED_BIN}" ]; then
    printf '%s\n' "${CLOUDFLARED_BIN}"
  elif [ -x "${MANAGED_BINARY}" ]; then
    printf '%s\n' "${MANAGED_BINARY}"
  else
    command -v cloudflared 2>/dev/null
  fi
}

require_binary() {
  resolve_binary >/dev/null || {
    echo "cloudflared is not installed. Run: scripts/tools/cloudflared.sh install" >&2
    return 1
  }
}

require_token() {
  [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] || {
    echo "CLOUDFLARE_TUNNEL_TOKEN is required for a remotely managed tunnel." >&2
    return 1
  }
}

install_cli() {
  local os arch asset url
  mkdir -p "${TOOLS_BIN_DIR}"
  if [ -x "${MANAGED_BINARY}" ] && [ "${CLOUDFLARED_FORCE_INSTALL:-0}" != 1 ]; then
    echo "cloudflared already installed: ${MANAGED_BINARY}"
    download_version "${MANAGED_BINARY}"
    return
  fi
  platform_require_supported_binary
  os="$(platform_os)"
  arch="$(platform_arch)"
  asset="cloudflared-${os}-${arch}"
  url="${CLOUDFLARED_DOWNLOAD_URL:-https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}}"
  echo "Installing cloudflared: ${MANAGED_BINARY}"
  echo "Source: ${url}"
  download_atomic "${url}" "${MANAGED_BINARY}" 0755
  download_version "${MANAGED_BINARY}"
}

run_tunnel() {
  require_binary
  require_token
  exec "$(resolve_binary)" tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}"
}

show_status() {
  local binary=""
  printf '%-22s %s\n' platform "$(platform_kind)"
  printf '%-22s %s\n' "tools home" "${TOOLS_HOME}"
  printf '%-22s %s\n' "managed binary" "${MANAGED_BINARY}"
  printf '%-22s %s\n' "runtime enabled" "${ENABLE_CLOUDFLARED:-0}"
  printf '%-22s %s\n' "file mirror" "${GITHUB_FILE_MIRROR_PREFIX:-auto}"
  printf '%-22s %s\n' "public URL" "${CLOUDFLARE_PUBLIC_URL:-not configured}"
  if binary="$(resolve_binary 2>/dev/null)"; then
    echo "OK   cloudflared: ${binary}"
    download_version "${binary}" || true
  else
    echo "MISS cloudflared"
  fi
  if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "OK   tunnel token configured (hidden)"
  else
    echo "MISS CLOUDFLARE_TUNNEL_TOKEN"
  fi
}

service_install() {
  require_binary
  require_token
  platform_has_systemd || {
    echo "systemd is unavailable. Run the tunnel under the container/project supervisor." >&2
    return 1
  }
  [ "$(id -u)" -eq 0 ] || {
    echo "The official system service install requires root; foreground/supervised run does not." >&2
    return 1
  }
  "$(resolve_binary)" service install "${CLOUDFLARE_TUNNEL_TOKEN}"
  systemctl enable --now cloudflared
}

service_action() {
  local operation="$1"
  platform_has_systemd || {
    echo "systemd is unavailable. Use the container/project supervisor." >&2
    return 1
  }
  systemctl "${operation}" cloudflared
}

service_uninstall() {
  require_binary
  platform_has_systemd || { echo "systemd is unavailable." >&2; return 1; }
  [ "$(id -u)" -eq 0 ] || { echo "Service removal requires root." >&2; return 1; }
  systemctl disable --now cloudflared 2>/dev/null || true
  "$(resolve_binary)" service uninstall
}

print_help() {
  cat <<'EOF'
Usage: scripts/tools/cloudflared.sh ACTION

Actions:
  install|init       Install into the writable persistent tools directory
  run                Run a remotely managed tunnel using its token
  status             Show resolved paths and configuration without exposing secrets
  version            Print the selected cloudflared version
  service-install    Install the official systemd service (root Linux hosts only)
  service-start|service-stop|service-restart|service-status
  service-uninstall
  help

Overrides: TOOLS_HOME, TOOLS_BIN_DIR, CLOUDFLARED_BIN,
CLOUDFLARED_DOWNLOAD_URL, CLOUDFLARE_TUNNEL_TOKEN.
EOF
}

case "${ACTION}" in
  install|init) install_cli ;;
  run) run_tunnel ;;
  status) show_status ;;
  version) require_binary; download_version "$(resolve_binary)" ;;
  service-install) service_install ;;
  service-start) service_action start ;;
  service-stop) service_action stop ;;
  service-restart) service_action restart ;;
  service-status) service_action status ;;
  service-uninstall) service_uninstall ;;
  help|-h|--help) print_help ;;
  *) print_help >&2; exit 2 ;;
esac
