#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

cat > "${TEMP_ROOT}/requirements.txt" <<'EOF'
comfyui-frontend-package==1.59.1
comfyui-embedded-docs==0.5.16
comfyui-workflow-templates==0.9.0
comfyui-workflow-templates-media-assets-02==0.1.31
torch
torchvision>=0.20
torchaudio
numpy>=1.25
aiohttp>=3.11
EOF

export PROJECT_DIR
export DATA_DIR="${TEMP_ROOT}/data"
export COMFY_DIR="${TEMP_ROOT}/ComfyUI"
export COMFY_REQUIREMENTS_FILE="${TEMP_ROOT}/requirements.txt"
export COMFY_CORE_REQUIREMENTS="${TEMP_ROOT}/core.txt"

bash "${PROJECT_DIR}/scripts/comfy_deps.sh" render
grep -q '^comfyui-frontend-package==' "${COMFY_CORE_REQUIREMENTS}"
grep -q '^comfyui-embedded-docs==' "${COMFY_CORE_REQUIREMENTS}"
grep -q '^numpy' "${COMFY_CORE_REQUIREMENTS}"
grep -q '^aiohttp' "${COMFY_CORE_REQUIREMENTS}"
! grep -qiE '^(torch|torchvision|torchaudio)' "${COMFY_CORE_REQUIREMENTS}"
! grep -qi 'workflow-templates' "${COMFY_CORE_REQUIREMENTS}"

echo "minimal ComfyUI dependency regression: PASS"
