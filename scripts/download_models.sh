#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${SCRIPT_DIR}/lib/download.sh"

MODEL_PROFILE="${MODEL_PROFILE:-all}"
WAN_REPO="${WAN_REPO:-Comfy-Org/Wan_2.1_ComfyUI_repackaged}"
WAN_MODEL="${WAN_MODEL:-split_files/diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors}"
MODEL_CACHE_ROOT="${COMFY_DIR}/models/.modelscope"

runtime_require_venv
runtime_require_comfy
mkdir -p "${MODEL_CACHE_ROOT}"

MS_PYTHON="${MODELSCOPE_PYTHON:-}"
if [ -n "${MS_PYTHON}" ]; then
  [ -x "${MS_PYTHON}" ] || { echo "MODELSCOPE_PYTHON is not executable: ${MS_PYTHON}" >&2; exit 1; }
  "${MS_PYTHON}" -c 'import modelscope' >/dev/null 2>&1 || {
    echo "MODELSCOPE_PYTHON cannot import modelscope: ${MS_PYTHON}" >&2
    exit 1
  }
fi

if [ -z "${MS_PYTHON}" ]; then
  for candidate in /opt/conda/bin/python /usr/local/bin/python python3 python; do
    resolved="$(command -v "${candidate}" 2>/dev/null || true)"
    [ -n "${resolved}" ] || continue
    if "${resolved}" -c 'import modelscope' >/dev/null 2>&1; then
      MS_PYTHON="${resolved}"
      echo "Using preinstalled ModelScope client: ${MS_PYTHON}"
      break
    fi
  done
fi

if [ -z "${MS_PYTHON}" ] && [ "${INSTALL_MODELSCOPE_CLIENT:-0}" = 1 ]; then
  runtime_activate_venv
  MODELSCOPE_PIP_INDEX_URL="${MODELSCOPE_PIP_INDEX_URL:-https://pypi.org/simple}"
  echo "Explicitly installing optional ModelScope client from ${MODELSCOPE_PIP_INDEX_URL}"
  python -m pip install --index-url "${MODELSCOPE_PIP_INDEX_URL}" modelscope
  MS_PYTHON="${VENV_DIR}/bin/python"
fi

if [ -z "${MS_PYTHON}" ]; then
  echo "No Python interpreter with the ModelScope library was found." >&2
  echo "Use the Notebook preinstalled client, set MODELSCOPE_PYTHON, or opt in with INSTALL_MODELSCOPE_CLIENT=1." >&2
  exit 1
fi

ms_snapshot() {
  local repo="$1" local_dir="$2"
  shift 2
  "${MS_PYTHON}" - "${repo}" "${local_dir}" "$@" <<'PY'
import os
import sys
from modelscope import snapshot_download

repo, local_dir, *patterns = sys.argv[1:]
kwargs = {
    "model_id": repo,
    "local_dir": local_dir,
}
revision = os.environ.get("MODEL_REVISION", "").strip()
if revision:
    kwargs["revision"] = revision
if patterns:
    kwargs["allow_patterns"] = patterns
snapshot_download(**kwargs)
PY
}

link_model() {
  local source="$1" target="$2"
  [ -f "${source}" ] || {
    echo "Downloaded model file was not found: ${source}" >&2
    return 1
  }
  mkdir -p "$(dirname "${target}")"
  ln -sfn "${source}" "${target}"
  echo "Linked $(basename "${target}") -> ${target}"
}

download_video_models() {
  local cache="${MODEL_CACHE_ROOT}/${WAN_REPO//\//--}"
  local vae="split_files/vae/wan_2.1_vae.safetensors"
  local text="split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
  local clip="split_files/clip_vision/clip_vision_h.safetensors"

  echo "Downloading video profile from ${WAN_REPO}"
  ms_snapshot "${WAN_REPO}" "${cache}" "${WAN_MODEL}" "${vae}" "${text}" "${clip}"

  link_model "${cache}/${WAN_MODEL}"     "${COMFY_DIR}/models/diffusion_models/$(basename "${WAN_MODEL}")"
  link_model "${cache}/${vae}"     "${COMFY_DIR}/models/vae/wan_2.1_vae.safetensors"
  link_model "${cache}/${text}"     "${COMFY_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
  link_model "${cache}/${clip}"     "${COMFY_DIR}/models/clip_vision/clip_vision_h.safetensors"
}

download_image_models() {
  local manifest="${IMAGE_MODEL_MANIFEST:-${PROJECT_DIR}/config/model-profiles/image.tsv}"
  [ -f "${manifest}" ] || { echo "Image model manifest is missing: ${manifest}" >&2; return 1; }
  echo "Downloading image profile from ${manifest}"

  local kind model_repo source target cache downloaded_dir archive_file extract_root expected_sha actual_sha
  while IFS='|' read -r kind model_repo source target; do
    [ -n "${kind}" ] || continue
    case "${kind}" in \#*) continue ;; esac
    cache="${MODEL_CACHE_ROOT}/${model_repo//\//--}"
    case "${kind}" in
      file)
        ms_snapshot "${model_repo}" "${cache}" "${source}"
        link_model "${cache}/${source}" "${COMFY_DIR}/models/${target}"
        ;;
      tree)
        # ModelScope glob semantics differ between client versions. Download the
        # repository snapshot for directory models, then locate the named tree.
        # Existing files in the persistent snapshot cache are reused/resumed.
        ms_snapshot "${model_repo}" "${cache}"
        downloaded_dir="$(find "${cache}" -type d -name "${source}" -print -quit)"
        [ -n "${downloaded_dir}" ] || {
          echo "Model directory ${source} was not found in ${model_repo}" >&2
          return 1
        }
        if ! find "${downloaded_dir}" -type f -name '*.onnx' -print -quit | grep -q .; then
          echo "Model directory ${source} contains no ONNX files: ${downloaded_dir}" >&2
          return 1
        fi
        mkdir -p "$(dirname "${COMFY_DIR}/models/${target}")"
        ln -sfnT "${downloaded_dir}" "${COMFY_DIR}/models/${target}"
        echo "Linked ${source} -> ${COMFY_DIR}/models/${target}"
        ;;
      archive)
        if [ -d "${COMFY_DIR}/models/${target}" ] &&
           find "${COMFY_DIR}/models/${target}" -type f -name '*.onnx' -print -quit | grep -q .; then
          echo "Reusing extracted model directory: ${COMFY_DIR}/models/${target}"
          continue
        fi
        archive_file="${CACHE_DIR}/model-archives/$(basename "${model_repo}")"
        expected_sha="${ANTELOPEV2_SHA256:-8e182f14fc6e80b3bfa375b33eb6cff7ee05d8ef7633e738d1c89021dcf0c5c5}"
        if [ -f "${archive_file}" ]; then
          actual_sha="$("${VENV_DIR}/bin/python" - "${archive_file}" <<'PY'
import hashlib
import sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
          if [ "${actual_sha}" != "${expected_sha}" ]; then
            echo "Cached archive checksum mismatch; downloading it again." >&2
            rm -f "${archive_file}"
          fi
        fi
        if [ ! -f "${archive_file}" ]; then
          download_atomic "${model_repo}" "${archive_file}" 0644
        fi
        actual_sha="$("${VENV_DIR}/bin/python" - "${archive_file}" <<'PY'
import hashlib
import sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
        [ "${actual_sha}" = "${expected_sha}" ] || {
          echo "Archive checksum mismatch: ${archive_file}" >&2
          return 1
        }
        extract_root="${MODEL_CACHE_ROOT}/archives/$(basename "${model_repo}" .zip)"
        rm -rf "${extract_root}.extracting"
        mkdir -p "${extract_root}.extracting"
        "${VENV_DIR}/bin/python" - "${archive_file}" "${extract_root}.extracting" <<'PY'
import sys
import zipfile
from pathlib import Path
archive, target = map(Path, sys.argv[1:])
root = target.resolve()
with zipfile.ZipFile(archive) as bundle:
    for member in bundle.infolist():
        destination = (target / member.filename).resolve()
        if root not in destination.parents and destination != root:
            raise SystemExit(f"unsafe archive member: {member.filename}")
    bundle.extractall(target)
PY
        rm -rf "${extract_root}"
        mv "${extract_root}.extracting" "${extract_root}"
        downloaded_dir="$(find "${extract_root}" -type d -name "${source}" -print -quit)"
        [ -n "${downloaded_dir}" ] || { echo "${source} was not found in archive" >&2; return 1; }
        find "${downloaded_dir}" -type f -name '*.onnx' -print -quit | grep -q . || {
          echo "${source} contains no ONNX files" >&2; return 1;
        }
        mkdir -p "$(dirname "${COMFY_DIR}/models/${target}")"
        ln -sfnT "${downloaded_dir}" "${COMFY_DIR}/models/${target}"
        echo "Extracted and linked ${source} -> ${COMFY_DIR}/models/${target}"
        ;;
      *) echo "Unsupported image manifest kind: ${kind}" >&2; return 2 ;;
    esac
  done < "${manifest}"
}

download_custom_model() {
  : "${MODEL_ID:?MODEL_ID is required for MODEL_PROFILE=custom}"
  : "${MODEL_FILE:?MODEL_FILE is required for MODEL_PROFILE=custom}"
  : "${MODEL_DIR:?MODEL_DIR is required for MODEL_PROFILE=custom}"
  case "${MODEL_DIR}" in
    /*|*..*) echo "MODEL_DIR must be a relative directory inside ComfyUI/models" >&2; return 2 ;;
  esac
  case "${MODEL_FILE}" in
    *\**|*\?*|*\[*)
      echo "MODEL_FILE must be one exact repository path, not a glob." >&2
      return 2
      ;;
  esac

  local cache="${MODEL_CACHE_ROOT}/custom-${MODEL_ID//\//--}"
  echo "Downloading custom model ${MODEL_ID}:${MODEL_FILE}"
  ms_snapshot "${MODEL_ID}" "${cache}" "${MODEL_FILE}"
  link_model "${cache}/${MODEL_FILE}"     "${COMFY_DIR}/models/${MODEL_DIR}/$(basename "${MODEL_FILE}")"
}

case "${MODEL_PROFILE}" in
  image)
    download_image_models
    ;;
  video)
    download_video_models
    ;;
  all)
    download_image_models
    download_video_models
    ;;
  custom)
    download_custom_model
    ;;
  *)
    echo "MODEL_PROFILE must be image, video, all, or custom" >&2
    exit 2
    ;;
esac

echo "Model profile '${MODEL_PROFILE}' is ready. Run: MODEL_PROFILE=${MODEL_PROFILE} make doctor"
