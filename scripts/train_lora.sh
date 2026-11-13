#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${SCRIPT_DIR}/pip_mirror.sh"

ACTION="${1:-status}"
TRAIN_ROOT="${TRAIN_ROOT:-${DATA_DIR}/training}"
TRAINER_DIR="${TRAINER_DIR:-${TRAIN_ROOT}/sd-scripts}"
TRAIN_VENV="${TRAIN_VENV:-${TRAIN_ROOT}/venv}"
TRAIN_STATE_DIR="${TRAIN_ROOT}/state"
TRAIN_DATASETS_DIR="${TRAIN_ROOT}/datasets"
TRAIN_CONFIG_DIR="${TRAIN_ROOT}/config"
TRAIN_LOG_DIR="${TRAIN_ROOT}/logs"
TRAIN_OUTPUT_DIR="${TRAIN_OUTPUT_DIR:-${COMFY_DIR}/models/loras}"
TRAIN_NAME="${TRAIN_NAME:-ai-pose}"
TRAIN_TRIGGER="${TRAIN_TRIGGER:-ai_pose}"
TRAIN_EPOCHS="${TRAIN_EPOCHS:-10}"
TRAIN_REPEATS="${TRAIN_REPEATS:-10}"
TRAIN_DIM="${TRAIN_DIM:-16}"
TRAIN_ALPHA="${TRAIN_ALPHA:-16}"
TRAIN_LR="${TRAIN_LR:-1e-4}"
TRAIN_RESOLUTION="${TRAIN_RESOLUTION:-1024}"
TRAIN_BATCH_SIZE="${TRAIN_BATCH_SIZE:-1}"
TRAIN_MIXED_PRECISION="${TRAIN_MIXED_PRECISION:-bf16}"
TRAIN_BASE_MODEL="${TRAIN_BASE_MODEL:-${COMFY_DIR}/models/checkpoints/sd_xl_base_1.0.safetensors}"
TRAINER_REPOSITORY="${TRAINER_REPOSITORY:-https://github.com/kohya-ss/sd-scripts.git}"
TRAINER_REVISION="${TRAINER_REVISION:-main}"
TRAIN_DATA="${TRAIN_DATA:-}"
TRAIN_CONFIG="${TRAIN_CONFIG_DIR}/${TRAIN_NAME}.toml"
PREPARED_DATA="${TRAIN_DATASETS_DIR}/${TRAIN_NAME}"

ensure_dirs() {
  mkdir -p "${TRAIN_ROOT}" "${TRAIN_STATE_DIR}" "${TRAIN_DATASETS_DIR}" \
    "${TRAIN_CONFIG_DIR}" "${TRAIN_LOG_DIR}" "${TRAIN_OUTPUT_DIR}"
}

find_base_python() {
  local candidate resolved
  for candidate in "${PYTHON_BIN:-}" /usr/local/bin/python3 /opt/conda/bin/python python3 python; do
    [ -n "${candidate}" ] || continue
    resolved="$(command -v "${candidate}" 2>/dev/null || true)"
    [ -n "${resolved}" ] || continue
    "${resolved}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null || continue
    printf '%s\n' "${resolved}"
    return 0
  done
  echo "Python 3.10+ is required." >&2
  return 1
}

init_trainer() {
  ensure_dirs
  local base_python
  base_python="$(find_base_python)"

  if [ ! -d "${TRAINER_DIR}/.git" ]; then
    [ ! -e "${TRAINER_DIR}" ] || {
      echo "Refusing to replace non-git trainer directory: ${TRAINER_DIR}" >&2
      return 1
    }
    echo "Cloning persistent SDXL trainer..."
    git clone --depth 1 --branch "${TRAINER_REVISION}" "${TRAINER_REPOSITORY}" "${TRAINER_DIR}"
  else
    echo "Reusing persistent trainer checkout: ${TRAINER_DIR}"
  fi

  if [ ! -x "${TRAIN_VENV}/bin/python" ]; then
    echo "Creating isolated training venv with platform Torch access..."
    "${base_python}" -m venv --system-site-packages "${TRAIN_VENV}"
  fi

  # shellcheck disable=SC1091
  source "${TRAIN_VENV}/bin/activate"
  configure_pip_mirror
  export PIP_ENV_FLAVOR="training:${base_python}:system-site=1"
  echo "Installing trainer dependencies without replacing platform Torch..."
  pip_install_with_fallback --upgrade-strategy only-if-needed -r "${TRAINER_DIR}/requirements.txt"
  "${TRAIN_VENV}/bin/python" - <<'PY'
import torch
print(f"Trainer runtime: torch={torch.__version__} cuda={torch.version.cuda} path={torch.__file__}")
if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available to the training environment")
PY
  touch "${TRAIN_STATE_DIR}/ready"
  echo "Image LoRA trainer ready: ${TRAIN_ROOT}"
}

prepare_dataset() {
  ensure_dirs
  [ -n "${TRAIN_DATA}" ] || {
    echo "TRAIN_DATA is required: make train TRAIN_DATA=/path/to/images" >&2
    return 2
  }
  [ -d "${TRAIN_DATA}" ] || { echo "Training data directory not found: ${TRAIN_DATA}" >&2; return 1; }
  [ -f "${TRAIN_BASE_MODEL}" ] || {
    echo "SDXL base model not found: ${TRAIN_BASE_MODEL}" >&2
    echo "The training fast path needs only this checkpoint; antelopev2 is not required." >&2
    return 1
  }

  rm -rf "${PREPARED_DATA}.preparing"
  mkdir -p "${PREPARED_DATA}.preparing"
  local image stem caption count=0
  while IFS= read -r -d '' image; do
    stem="$(basename "${image}")"
    stem="${stem%.*}"
    ln -s "${image}" "${PREPARED_DATA}.preparing/$(basename "${image}")"
    caption="${TRAIN_DATA}/${stem}.txt"
    if [ -f "${caption}" ]; then
      cp "${caption}" "${PREPARED_DATA}.preparing/${stem}.txt"
    else
      printf '%s\n' "${TRAIN_TRIGGER}" > "${PREPARED_DATA}.preparing/${stem}.txt"
    fi
    count=$((count + 1))
  done < <(find "${TRAIN_DATA}" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

  [ "${count}" -gt 0 ] || { echo "No PNG/JPEG/WebP images found in ${TRAIN_DATA}" >&2; return 1; }
  rm -rf "${PREPARED_DATA}"
  mv "${PREPARED_DATA}.preparing" "${PREPARED_DATA}"

  cat > "${TRAIN_CONFIG}" <<EOF
[general]
caption_extension = ".txt"
shuffle_caption = true
keep_tokens = 1

[[datasets]]
resolution = ${TRAIN_RESOLUTION}
batch_size = ${TRAIN_BATCH_SIZE}
enable_bucket = true
bucket_no_upscale = true
bucket_reso_steps = 32

  [[datasets.subsets]]
  image_dir = "${PREPARED_DATA}"
  num_repeats = ${TRAIN_REPEATS}
EOF
  echo "Prepared ${count} images: ${PREPARED_DATA}"
  echo "Dataset config: ${TRAIN_CONFIG}"
}

run_training() {
  [ -f "${TRAIN_STATE_DIR}/ready" ] && [ -x "${TRAIN_VENV}/bin/accelerate" ] || {
    echo "Trainer is not initialized. Run: make train-init" >&2
    return 1
  }
  prepare_dataset
  local log_file="${TRAIN_LOG_DIR}/${TRAIN_NAME}-$(date +%Y%m%d-%H%M%S).log"
  echo "Starting SDXL LoRA training; log: ${log_file}"
  cd "${TRAINER_DIR}"
  "${TRAIN_VENV}/bin/accelerate" launch --num_cpu_threads_per_process 2 \
    sdxl_train_network.py \
    --pretrained_model_name_or_path="${TRAIN_BASE_MODEL}" \
    --dataset_config="${TRAIN_CONFIG}" \
    --output_dir="${TRAIN_OUTPUT_DIR}" \
    --output_name="${TRAIN_NAME}" \
    --save_model_as=safetensors \
    --network_module=networks.lora \
    --network_dim="${TRAIN_DIM}" \
    --network_alpha="${TRAIN_ALPHA}" \
    --network_train_unet_only \
    --learning_rate="${TRAIN_LR}" \
    --optimizer_type=AdamW \
    --lr_scheduler=cosine \
    --max_train_epochs="${TRAIN_EPOCHS}" \
    --save_every_n_epochs=1 \
    --mixed_precision="${TRAIN_MIXED_PRECISION}" \
    --save_precision="${TRAIN_MIXED_PRECISION}" \
    --gradient_checkpointing \
    --cache_latents \
    --cache_latents_to_disk \
    --cache_text_encoder_outputs \
    --cache_text_encoder_outputs_to_disk \
    --sdpa \
    --seed=42 2>&1 | tee "${log_file}"
  echo "Training complete. LoRA files: ${TRAIN_OUTPUT_DIR}/${TRAIN_NAME}*.safetensors"
}

show_status() {
  printf '%-24s %s\n' "training root" "${TRAIN_ROOT}"
  printf '%-24s %s\n' "trainer" "${TRAINER_DIR}"
  printf '%-24s %s\n' "training venv" "${TRAIN_VENV}"
  printf '%-24s %s\n' "base model" "${TRAIN_BASE_MODEL}"
  printf '%-24s %s\n' "LoRA output" "${TRAIN_OUTPUT_DIR}"
  [ -f "${TRAIN_STATE_DIR}/ready" ] && echo "OK   trainer initialized" || echo "MISS trainer initialization"
  [ -f "${TRAIN_BASE_MODEL}" ] && echo "OK   SDXL base checkpoint" || echo "MISS SDXL base checkpoint"
}

case "${ACTION}" in
  init) init_trainer ;;
  prepare) prepare_dataset ;;
  run) run_training ;;
  status) show_status ;;
  *) echo "Usage: scripts/train_lora.sh [init|prepare|run|status]" >&2; exit 2 ;;
esac
