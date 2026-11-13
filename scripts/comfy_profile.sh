#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-status}"
PROFILE="${COMFY_PROFILE:-core}"
STATE_DIR="${DATA_DIR}/state/comfy-profiles"

validate_profile() {
  case "${PROFILE}" in core|image|video|all) ;; *)
    echo "COMFY_PROFILE must be core, image, video, or all." >&2
    return 2
  esac
}

has_feature() {
  local feature="$1"
  case "${PROFILE}:${feature}" in
    core:core|image:core|video:core|all:core) return 0 ;;
    image:image|all:image) return 0 ;;
    video:video|all:video) return 0 ;;
    *) return 1 ;;
  esac
}

print_nodes() {
  validate_profile
  if has_feature image; then
    printf '%s|%s\n' https://github.com/cubiq/ComfyUI_InstantID.git ComfyUI_InstantID
    printf '%s|%s\n' https://github.com/cubiq/ComfyUI_IPAdapter_plus.git ComfyUI_IPAdapter_plus
    if [ "${INSTALL_POSE_GALLERY:-0}" = 1 ]; then
      printf '%s|%s\n' https://github.com/anhao/ai-pose-gallery-zh.git ai-pose-gallery-zh
    fi
  fi
  if has_feature video; then
    printf '%s|%s\n' https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite
    printf '%s|%s\n' https://github.com/city96/ComfyUI-GGUF.git ComfyUI-GGUF
  fi
}

mark_installed() {
  validate_profile
  mkdir -p "${STATE_DIR}"
  touch "${STATE_DIR}/core"
  has_feature image && touch "${STATE_DIR}/image"
  has_feature video && touch "${STATE_DIR}/video"
  printf '%s\n' "${PROFILE}" > "${STATE_DIR}/last-requested"
}

show_status() {
  validate_profile
  printf '%-24s %s\n' "requested profile" "${PROFILE}"
  printf '%-24s %s\n' "profile state" "${STATE_DIR}"
  local feature
  for feature in core image video; do
    if [ -f "${STATE_DIR}/${feature}" ]; then
      echo "OK   installed profile: ${feature}"
    elif has_feature "${feature}"; then
      echo "MISS requested profile: ${feature}"
    else
      echo "SKIP optional profile: ${feature}"
    fi
  done
}

case "${ACTION}" in
  nodes) print_nodes ;;
  mark) mark_installed ;;
  status) show_status ;;
  has) validate_profile; has_feature "${2:?feature is required}" ;;
  help|-h|--help) echo "Usage: scripts/comfy_profile.sh [nodes|mark|status|has FEATURE]" ;;
  *) echo "Unsupported action: ${ACTION}" >&2; exit 2 ;;
esac
