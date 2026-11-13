#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${SCRIPT_DIR}/pip_mirror.sh"
source "${SCRIPT_DIR}/lib/download.sh"

ACTION="${1:-install}"
SOURCE_REQUIREMENTS="${COMFY_REQUIREMENTS_FILE:-${COMFY_DIR}/requirements.txt}"
OUTPUT_REQUIREMENTS="${COMFY_CORE_REQUIREMENTS:-${DATA_DIR}/state/comfy-core-requirements.txt}"
VENDOR_REQUIREMENTS="${COMFY_VENDOR_REQUIREMENTS:-${DATA_DIR}/state/comfy-vendor-requirements.txt}"
TORCH_MODE="${COMFY_TORCH_MODE:-auto}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-}"
PACKAGE_INDEX_URL="${COMFY_PACKAGE_INDEX_URL:-auto}"
OPTIONAL_INDEX_URL="${COMFY_OPTIONAL_INDEX_URL:-https://pypi.org/simple}"

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

package_indexes() {
  local configured="${PACKAGE_INDEX_URL}" candidates=() seen=" " index
  if [ "${configured}" = auto ]; then
    if download_is_cn_timezone || [ -n "${MODELSCOPE_ENVIRONMENT:-}" ] || \
      [ -n "${MODELSCOPE_NOTEBOOK:-}" ] || [ -d /mnt/workspace ]; then
      candidates=(
        "${PIP_INDEX_URL}"
        "https://mirrors.cloud.tencent.com/pypi/simple/"
        "https://pypi.mirrors.ustc.edu.cn/simple/"
        "https://pypi.sjtu.edu.cn/simple/"
        "https://pypi.org/simple"
      )
    else
      candidates=("https://pypi.org/simple")
    fi
  else
    candidates=("${configured}")
    if [ -n "${COMFY_PACKAGE_FALLBACK_INDEX_URLS:-}" ]; then
      # shellcheck disable=SC2206
      candidates+=(${COMFY_PACKAGE_FALLBACK_INDEX_URLS})
    fi
  fi
  for index in "${candidates[@]}"; do
    [ -n "${index}" ] || continue
    case "${seen}" in *" ${index} "*) continue ;; esac
    seen="${seen}${index} "
    printf '%s\n' "${index}"
  done
}

install_vendor_packages() {
  [ -s "${VENDOR_REQUIREMENTS}" ] || return 0
  local index
  while IFS= read -r index; do
    echo "Trying Comfy-published packages from: ${index}"
    if "${VENV_DIR}/bin/python" -m pip install --prefer-binary --no-deps \
      --timeout "${COMFY_PACKAGE_TIMEOUT:-30}" --retries "${COMFY_PACKAGE_RETRIES:-1}" \
      --index-url "${index}" -r "${VENDOR_REQUIREMENTS}"; then
      echo "Installed Comfy-published packages from: ${index}"
      return 0
    fi
    echo "Comfy packages unavailable or slow source failed: ${index}" >&2
  done < <(package_indexes)
  echo "No configured index could install the required Comfy packages." >&2
  return 1
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
  install_vendor_packages
  echo "Installing remaining ComfyUI dependencies from mirror: ${PIP_INDEX_URL}"
  "${VENV_DIR}/bin/python" -m pip install --prefer-binary -r "${OUTPUT_REQUIREMENTS}"
  install_optional_templates
}

show_status() {
  configure_pip_mirror
  printf '%-28s %s\n' "requirements source" "${SOURCE_REQUIREMENTS}"
  printf '%-28s %s\n' "mirror requirements" "${OUTPUT_REQUIREMENTS}"
  printf '%-28s %s\n' "official requirements" "${VENDOR_REQUIREMENTS}"
  printf '%-28s %s\n' "Comfy package indexes" "${PACKAGE_INDEX_URL}"
  if [ "${PACKAGE_INDEX_URL}" = auto ]; then
    package_indexes | sed 's/^/  - /'
  fi
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
