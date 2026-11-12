#!/usr/bin/env bash
set -Eeuo pipefail

# Compatibility entrypoint. The implementation is intentionally standalone.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/tools/cloudflared.sh" "${1:-status}"
