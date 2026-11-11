#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

cd "${PROJECT_DIR}"
source "${VENV_DIR}/bin/activate"
mkdir -p logs outputs

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

python "${COMFY_DIR}/main.py" --listen 127.0.0.1 --port 8188 > logs/comfyui.log 2>&1 &
uvicorn gateway.main:app --host "${GATEWAY_HOST:-127.0.0.1}" --port "${GATEWAY_PORT:-8000}" > logs/gateway.log 2>&1 &

if [ "${ENABLE_CLOUDFLARED:-0}" = "1" ] && [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  command -v cloudflared >/dev/null || { echo "cloudflared is required when CLOUDFLARE_TUNNEL_TOKEN is set" >&2; exit 1; }
  cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}" > logs/cloudflared.log 2>&1 &
fi

echo $$ > logs/services.pid
wait -n
