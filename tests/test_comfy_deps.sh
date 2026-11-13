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
comfy-aimdo==0.6.0
comfy-kitchen==0.2.41
EOF

export PROJECT_DIR
export DATA_DIR="${TEMP_ROOT}/data"
export COMFY_DIR="${TEMP_ROOT}/ComfyUI"
export COMFY_REQUIREMENTS_FILE="${TEMP_ROOT}/requirements.txt"
export COMFY_CORE_REQUIREMENTS="${TEMP_ROOT}/core.txt"
export COMFY_VENDOR_REQUIREMENTS="${TEMP_ROOT}/vendor.txt"

bash "${PROJECT_DIR}/scripts/comfy_deps.sh" render
grep -q '^comfyui-frontend-package==' "${COMFY_VENDOR_REQUIREMENTS}"
grep -q '^comfyui-embedded-docs==' "${COMFY_VENDOR_REQUIREMENTS}"
grep -q '^comfy-aimdo==' "${COMFY_VENDOR_REQUIREMENTS}"
grep -q '^comfy-kitchen==' "${COMFY_VENDOR_REQUIREMENTS}"
! grep -qiE '^(comfyui-frontend-package|comfyui-embedded-docs|comfy-aimdo|comfy-kitchen)' "${COMFY_CORE_REQUIREMENTS}"
grep -q '^numpy' "${COMFY_CORE_REQUIREMENTS}"
grep -q '^aiohttp' "${COMFY_CORE_REQUIREMENTS}"
! grep -qiE '^(torch|torchvision|torchaudio)' "${COMFY_CORE_REQUIREMENTS}"
! grep -qi 'workflow-templates' "${COMFY_CORE_REQUIREMENTS}"

mkdir -p "${TEMP_ROOT}/venv/bin"
export COMFY_DEPS_TEST_LOG="${TEMP_ROOT}/pip.log"
cat > "${TEMP_ROOT}/venv/bin/python" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] && [ "${2:-}" = pip ]; then
  printf '%s|%s\n' "${PIP_INDEX_URL:-}" "$*" >> "${COMFY_DEPS_TEST_LOG}"
  case "$*" in
    *"--index-url https://pypi.tuna.tsinghua.edu.cn/simple "*) exit 1 ;;
  esac
fi
exit 0
FAKE
chmod +x "${TEMP_ROOT}/venv/bin/python"
export VENV_DIR="${TEMP_ROOT}/venv"
export PIP_MIRROR=tsinghua
export COMFY_TORCH_MODE=preinstalled
export COMFY_PACKAGE_INDEX_URL=auto
export TZ=Asia/Shanghai

bash "${PROJECT_DIR}/scripts/comfy_deps.sh" install
grep -q -- '--no-deps .*--index-url https://pypi.tuna.tsinghua.edu.cn/simple -r .*vendor.txt' "${COMFY_DEPS_TEST_LOG}"
grep -q -- '--no-deps .*--index-url https://mirrors.cloud.tencent.com/pypi/simple/ -r .*vendor.txt' "${COMFY_DEPS_TEST_LOG}"
grep -q 'https://pypi.tuna.tsinghua.edu.cn/simple|.*-r .*core.txt' "${COMFY_DEPS_TEST_LOG}"

echo "minimal ComfyUI dependency regression: PASS"
