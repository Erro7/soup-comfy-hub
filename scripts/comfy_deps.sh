#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${SCRIPT_DIR}/pip_mirror.sh"

ACTION="${1:-install}"
SOURCE_REQUIREMENTS="${COMFY_REQUIREMENTS_FILE:-${COMFY_DIR}/requirements.txt}"
OUTPUT_REQUIREMENTS="${COMFY_CORE_REQUIREMENTS:-${DATA_DIR}/state/comfy-core-requirements.txt}"
VENDOR_REQUIREMENTS="${COMFY_VENDOR_REQUIREMENTS:-${DATA_DIR}/state/comfy-vendor-requirements.txt}"
TORCH_MODE="${COMFY_TORCH_MODE:-auto}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-}"
PACKAGE_INDEX_URL="${COMFY_PACKAGE_INDEX_URL:-https://pypi.org/simple}"
OPTIONAL_INDEX_URL="${COMFY_OPTIONAL_INDEX_URL:-${PACKAGE_INDEX_URL}}"

require_source() {
  [ -f "${SOURCE_REQUIREMENTS}" ] || {
    echo "ComfyUI requirements are missing: ${SOURCE_REQUIREMENTS}" >&2
    return 1
  }
}

render_core() {
  require_source
  mkdir -p "$(dirname "${OUTPUT_REQUIREMENTS}")" "$(dirname "${VENDOR_REQUIREMENTS}")"

  awk '
    {
      line = tolower($0)
      if (line ~ /^[[:space:]]*(comfyui-frontend-package|comfyui-embedded-docs|comfy-aimdo|comfy-kitchen)([<>=!~[:space:]].*)?$/) {
        print
      }
    }
  ' "${SOURCE_REQUIREMENTS}" > "${VENDOR_REQUIREMENTS}"

  awk '
    {
      line = tolower($0)
      if (line ~ /^[[:space:]]*(torch|torchvision|torchaudio)([<>=!~[:space:]].*)?$/) next
      if (line ~ /^[[:space:]]*comfyui-workflow-templates([<>=!~[:space:]].*)?$/) next
      if (line ~ /^[[:space:]]*comfyui-workflow-templates-media-assets-/) next
      if (line ~ /^[[:space:]]*(comfyui-frontend-package|comfyui-embedded-docs|comfy-aimdo|comfy-kitchen)([<>=!~[:space:]].*)?$/) next
      print
    }
  ' "${SOURCE_REQUIREMENTS}" > "${OUTPUT_REQUIREMENTS}"

  echo "Rendered mirror requirements: ${OUTPUT_REQUIREMENTS}"
  echo "Rendered official Comfy packages: ${VENDOR_REQUIREMENTS}"
}

torch_available() {
  "${VENV_DIR}/bin/python" - <<'PY' >/dev/null 2>&1
import torch
assert torch.__version__
PY
}

ensure_torch() {
  runtime_require_venv
  case "${TORCH_MODE}" in
    auto)
      if torch_available; then
        echo "Reusing available PyTorch/CUDA packages."
      else
        echo "PyTorch is not available in the selected environment." >&2
        echo "Use a platform Python that already provides torch, or explicitly set:" >&2
        echo "  COMFY_TORCH_MODE=install TORCH_INDEX_URL=<official-pytorch-index>" >&2
        return 1
      fi
      ;;
    preinstalled)
      torch_available || {
        echo "COMFY_TORCH_MODE=preinstalled but torch cannot be imported." >&2
        return 1
      }
      echo "Verified preinstalled PyTorch."
      ;;
    install)
      [ -n "${TORCH_INDEX_URL}" ] || {
        echo "TORCH_INDEX_URL is required when COMFY_TORCH_MODE=install." >&2
        return 1
      }
      echo "Installing PyTorch explicitly from: ${TORCH_INDEX_URL}"
      "${VENV_DIR}/bin/python" -m pip install --prefer-binary \
        --index-url "${TORCH_INDEX_URL}" torch torchvision torchaudio
      ;;
    *)
      echo "COMFY_TORCH_MODE must be auto, preinstalled, or install." >&2
      return 2
      ;;
  esac
}

install_optional_templates() {
  [ "${INSTALL_COMFY_WORKFLOW_TEMPLATES:-0}" = 1 ] || return 0
  local requirement
  requirement="$(grep -iE '^[[:space:]]*comfyui-workflow-templates([<>=!~[:space:]].*)?$' \
    "${SOURCE_REQUIREMENTS}" | head -n 1 || true)"
  [ -n "${requirement}" ] || {
    echo "No workflow-template requirement is declared by this ComfyUI revision."
    return
  }
  echo "Installing optional workflow templates from: ${OPTIONAL_INDEX_URL}"
  "${VENV_DIR}/bin/python" -m pip install --prefer-binary \
    --index-url "${OPTIONAL_INDEX_URL}" "${requirement}"
}

install_core() {
  runtime_require_venv
  configure_pip_mirror
  render_core
  ensure_torch
  if [ -s "${VENDOR_REQUIREMENTS}" ]; then
    echo "Installing Comfy-published packages from official index: ${PACKAGE_INDEX_URL}"
    "${VENV_DIR}/bin/python" -m pip install --prefer-binary --no-deps \
      --index-url "${PACKAGE_INDEX_URL}" -r "${VENDOR_REQUIREMENTS}"
  fi
  echo "Installing remaining ComfyUI dependencies from mirror: ${PIP_INDEX_URL}"
  "${VENV_DIR}/bin/python" -m pip install --prefer-binary -r "${OUTPUT_REQUIREMENTS}"
  install_optional_templates
}

show_status() {
  printf '%-28s %s\n' "requirements source" "${SOURCE_REQUIREMENTS}"
  printf '%-28s %s\n' "mirror requirements" "${OUTPUT_REQUIREMENTS}"
  printf '%-28s %s\n' "official requirements" "${VENDOR_REQUIREMENTS}"
  printf '%-28s %s\n' "Comfy package index" "${PACKAGE_INDEX_URL}"
  printf '%-28s %s\n' "torch mode" "${TORCH_MODE}"
  printf '%-28s %s\n' "workflow templates" "${INSTALL_COMFY_WORKFLOW_TEMPLATES:-0}"
  if [ -x "${VENV_DIR}/bin/python" ] && torch_available; then
    "${VENV_DIR}/bin/python" - <<'PY'
import torch
print(f"OK   torch={torch.__version__} cuda={torch.version.cuda}")
PY
  else
    echo "MISS torch"
  fi
}

case "${ACTION}" in
  render) render_core ;;
  install) install_core ;;
  status) show_status ;;
  torch) ensure_torch ;;
  help|-h|--help)
    echo "Usage: scripts/comfy_deps.sh [render|install|status|torch]"
    ;;
  *) echo "Unsupported action: ${ACTION}" >&2; exit 2 ;;
esac
