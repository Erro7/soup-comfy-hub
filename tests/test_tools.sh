#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

export PROJECT_DIR
export DATA_DIR="${TEMP_ROOT}/persistent"
export TOOLS_HOME="${DATA_DIR}/tools"
export TOOLS_BIN_DIR="${TOOLS_HOME}/bin"
mkdir -p "${TOOLS_BIN_DIR}"

# shellcheck source=../scripts/lib/paths.sh
source "${PROJECT_DIR}/scripts/lib/paths.sh"
paths_export_runtime
[ "${TOOLS_HOME}" = "${TEMP_ROOT}/persistent/tools" ]
[ "${TOOLS_BIN_DIR}" = "${TEMP_ROOT}/persistent/tools/bin" ]

cat > "${TOOLS_BIN_DIR}/cloudflared" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "cloudflared test-version"
  exit 0
fi
printf '%s\n' "$@" > "${CLOUDFLARED_TEST_ARGS}"
FAKE
chmod 0755 "${TOOLS_BIN_DIR}/cloudflared"

status="$(CLOUDFLARE_TUNNEL_TOKEN=secret-value bash "${PROJECT_DIR}/scripts/tools/cloudflared.sh" status)"
grep -q "cloudflared test-version" <<<"${status}"
grep -q "token configured (hidden)" <<<"${status}"
! grep -q "secret-value" <<<"${status}"

export CLOUDFLARED_TEST_ARGS="${TEMP_ROOT}/args"
CLOUDFLARE_TUNNEL_TOKEN=secret-value bash "${PROJECT_DIR}/scripts/tools/cloudflared.sh" run
mapfile -t args < "${CLOUDFLARED_TEST_ARGS}"
[ "${args[0]}" = tunnel ]
[ "${args[1]}" = --no-autoupdate ]
[ "${args[2]}" = run ]
[ "${args[3]}" = --token ]
[ "${args[4]}" = secret-value ]

echo "portable tools regression: PASS"
