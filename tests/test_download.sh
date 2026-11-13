#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_DIR}/scripts/lib/download.sh"

TZ=Asia/Shanghai
export TZ
test "$(download_resolve_url https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64)" = \
  "https://ghfast.top/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
test "$(download_resolve_url https://example.com/file)" = "https://example.com/file"

TZ=Etc/UTC
test "$(download_resolve_url https://github.com/owner/repo/releases/download/v1/file)" = \
  "https://github.com/owner/repo/releases/download/v1/file"

TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT
mkdir -p "${TEMP_ROOT}/bin"
export DOWNLOAD_TEST_LOG="${TEMP_ROOT}/requests"
export DOWNLOAD_TEST_COUNT="${TEMP_ROOT}/count"

cat > "${TEMP_ROOT}/bin/curl" <<'FAKE'
#!/usr/bin/env bash
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "${url}" >> "${DOWNLOAD_TEST_LOG}"
count=0
[ ! -f "${DOWNLOAD_TEST_COUNT}" ] || count="$(cat "${DOWNLOAD_TEST_COUNT}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${DOWNLOAD_TEST_COUNT}"
if [ "${count}" -eq 1 ]; then exit 22; fi
printf 'binary-data' > "${output}"
FAKE
chmod +x "${TEMP_ROOT}/bin/curl"

PATH="${TEMP_ROOT}/bin:/usr/bin:/bin"
export PATH
TZ=Asia/Shanghai
export TZ
download_atomic \
  https://github.com/owner/repo/releases/download/v1/file \
  "${TEMP_ROOT}/result" 0755

test -x "${TEMP_ROOT}/result"
test "$(cat "${TEMP_ROOT}/result")" = binary-data
test "$(sed -n '1p' "${DOWNLOAD_TEST_LOG}")" = \
  "https://ghfast.top/https://github.com/owner/repo/releases/download/v1/file"
test "$(sed -n '2p' "${DOWNLOAD_TEST_LOG}")" = \
  "https://github.com/owner/repo/releases/download/v1/file"

echo "GitHub single-file download regression: PASS"
