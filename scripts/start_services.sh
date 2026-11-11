#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="${WORKSPACE:-/mnt/workspace}"
PROJECT_DIR="${PROJECT_DIR:-${WORKSPACE}/soup-comfy-hub}"
COMFY_DIR="${COMFY_DIR:-${WORKSPACE}/ComfyUI}"
VENV_DIR="${VENV_DIR:-${WORKSPACE}/venv}"

cd "${PROJECT_DIR}"
source "${VENV_DIR}/bin/activate"
set -a
source .env
set +a
mkdir -p logs outputs

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

python "${COMFY_DIR}/main.py" --listen 127.0.0.1 --port 8188 > logs/comfyui.log 2>&1 &
uvicorn gateway.main:app --host 127.0.0.1 --port 8000 > logs/gateway.log 2>&1 &

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  command -v cloudflared >/dev/null || { echo "cloudflared is required when CLOUDFLARE_TUNNEL_TOKEN is set" >&2; exit 1; }
  cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}" > logs/cloudflared.log 2>&1 &
fi

echo $$ > logs/services.pid
wait -n
