#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

export PROJECT_DIR
export DATA_DIR="${TEMP_ROOT}/data"

core="$(COMFY_PROFILE=core bash "${PROJECT_DIR}/scripts/comfy_profile.sh" nodes)"
test -z "${core}"

image="$(COMFY_PROFILE=image bash "${PROJECT_DIR}/scripts/comfy_profile.sh" nodes)"
grep -q 'ComfyUI_InstantID' <<<"${image}"
grep -q 'ComfyUI_IPAdapter_plus' <<<"${image}"
! grep -q 'VideoHelperSuite' <<<"${image}"

video="$(COMFY_PROFILE=video bash "${PROJECT_DIR}/scripts/comfy_profile.sh" nodes)"
grep -q 'VideoHelperSuite' <<<"${video}"
grep -q 'ComfyUI-GGUF' <<<"${video}"
! grep -q 'InstantID' <<<"${video}"

all="$(COMFY_PROFILE=all bash "${PROJECT_DIR}/scripts/comfy_profile.sh" nodes)"
grep -q 'InstantID' <<<"${all}"
grep -q 'VideoHelperSuite' <<<"${all}"

COMFY_PROFILE=core bash "${PROJECT_DIR}/scripts/comfy_profile.sh" mark
test -f "${DATA_DIR}/state/comfy-profiles/core"
test ! -f "${DATA_DIR}/state/comfy-profiles/image"
COMFY_PROFILE=image bash "${PROJECT_DIR}/scripts/comfy_profile.sh" mark
test -f "${DATA_DIR}/state/comfy-profiles/core"
test -f "${DATA_DIR}/state/comfy-profiles/image"
test ! -f "${DATA_DIR}/state/comfy-profiles/video"

echo "ComfyUI profile regression: PASS"
