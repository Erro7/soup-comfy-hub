#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-enter}"
SHELL_KIND="${SHELL_KIND:-auto}"
CACHE_KIND="${CACHE_KIND:-}"
OMZ_DIR="${OMZ_DIR:-${SHELL_HOME}/oh-my-zsh}"
SHARED_ENV="${SHELL_HOME}/env.sh"
BASH_RC="${SHELL_HOME}/bashrc"
ZDOTDIR="${ZDOTDIR:-${SHELL_HOME}/zsh}"
ZSH_RC="${ZDOTDIR}/.zshrc"
PLATFORM_FILE="${SHELL_STATE_DIR}/platform.env"

ensure_directories() {
  mkdir -p     "${SHELL_BIN_DIR}" "${SHELL_STATE_DIR}" "${SHELL_HISTORY_DIR}" "${ZDOTDIR}"     "${PIP_CACHE_DIR}" "${UV_CACHE_DIR}" "${MODELSCOPE_CACHE}"     "${HUGGINGFACE_HUB_CACHE}" "${TORCH_HOME}" "${NPM_CONFIG_CACHE}"     "${XDG_CACHE_HOME}" "${CUDA_CACHE_PATH}"
}

detect_platform() {
  local platform="linux"
  if [ -f /.dockerenv ]; then
    platform="docker"
  elif [[ "${PROJECT_DIR}" == /mnt/workspace/* ]] || [ -d /mnt/workspace ]; then
    platform="modelscope-notebook"
  fi
  cat > "${PLATFORM_FILE}" <<EOF
PLATFORM=${platform}
OS=$(uname -s)
ARCH=$(uname -m)
PROJECT_DIR=${PROJECT_DIR}
DATA_DIR=${DATA_DIR}
VENV_DIR=${VENV_DIR}
EOF
}

write_shared_env() {
  cat > "${SHARED_ENV}" <<EOF
export PROJECT_DIR="${PROJECT_DIR}"
export DATA_DIR="${DATA_DIR}"
export COMFY_DIR="${COMFY_DIR}"
export VENV_DIR="${VENV_DIR}"
export CACHE_DIR="${CACHE_DIR}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR}"
export UV_CACHE_DIR="${UV_CACHE_DIR}"
export MODELSCOPE_CACHE="${MODELSCOPE_CACHE}"
export MODELSCOPE_CACHE_HOME="${MODELSCOPE_CACHE_HOME}"
export HF_HOME="${HF_HOME}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE}"
export TORCH_HOME="${TORCH_HOME}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME}"
export CUDA_CACHE_PATH="${CUDA_CACHE_PATH}"
export SHELL_HOME="${SHELL_HOME}"
export SHELL_BIN_DIR="${SHELL_BIN_DIR}"
export SHELL_STATE_DIR="${SHELL_STATE_DIR}"
export SHELL_HISTORY_DIR="${SHELL_HISTORY_DIR}"
case ":\$PATH:" in
  *":\$VENV_DIR/bin:"*) ;;
  *) export PATH="\$VENV_DIR/bin:\$SHELL_BIN_DIR:\$PATH" ;;
esac
[ ! -f "\$VENV_DIR/bin/activate" ] || source "\$VENV_DIR/bin/activate"
cd "\$PROJECT_DIR"
EOF
}

write_profiles() {
  cat > "${BASH_RC}" <<EOF
source "${SHARED_ENV}"
export HISTFILE="${SHELL_HISTORY_DIR}/bash_history"
export HISTSIZE=50000
export HISTFILESIZE=50000
[ ! -f "${SHELL_HOME}/bashrc.local" ] || source "${SHELL_HOME}/bashrc.local"
EOF

  cat > "${ZSH_RC}" <<EOF
source "${SHARED_ENV}"
export ZSH="${OMZ_DIR}"
export HISTFILE="${SHELL_HISTORY_DIR}/zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
ZSH_THEME="${OMZ_THEME:-robbyrussell}"
plugins=(git python pip)
[ ! -f "\$ZSH/oh-my-zsh.sh" ] || source "\$ZSH/oh-my-zsh.sh"
[ ! -f "${SHELL_HOME}/zshrc.local" ] || source "${SHELL_HOME}/zshrc.local"
EOF
  touch "${SHELL_HISTORY_DIR}/bash_history" "${SHELL_HISTORY_DIR}/zsh_history"
}

ensure_zsh_for_init() {
  command -v zsh >/dev/null 2>&1 && return
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    echo "Installing zsh into the current base environment..."
    apt-get update
    apt-get install -y --no-install-recommends zsh
    return
  fi
  echo "zsh is unavailable; install it in the base image or run shell-init as root." >&2
  return 1
}

init_shell() {
  runtime_require_venv
  command -v bash >/dev/null || { echo "bash is required" >&2; exit 1; }
  ensure_directories
  detect_platform
  write_shared_env
  write_profiles
  ensure_zsh_for_init
  if [ ! -d "${OMZ_DIR}/.git" ]; then
    echo "Installing Oh My Zsh into persistent storage: ${OMZ_DIR}"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "${OMZ_DIR}"
  fi
  echo "Unified shell ready: ${SHELL_HOME}"
}

require_shell() {
  runtime_require_venv
  [ -f "${SHARED_ENV}" ] || {
    echo "Unified shell is not initialized; run 'make shell-init' once." >&2
    return 1
  }
}

enter_shell() {
  require_shell
  local selected="${SHELL_KIND}"
  if [ "${selected}" = "auto" ]; then
    if command -v zsh >/dev/null 2>&1 && [ -f "${OMZ_DIR}/oh-my-zsh.sh" ]; then
      selected="zsh"
    else
      selected="bash"
    fi
  fi
  case "${selected}" in
    bash)
      exec bash --rcfile "${BASH_RC}" -i
      ;;
    zsh)
      command -v zsh >/dev/null 2>&1 || {
        echo "zsh is unavailable; use SHELL_KIND=bash or run make shell-init." >&2
        exit 1
      }
      exec env ZDOTDIR="${ZDOTDIR}" ZSH="${OMZ_DIR}" zsh -i
      ;;
    *)
      echo "Unsupported SHELL_KIND=${selected}; use auto, bash, or zsh." >&2
      exit 2
      ;;
  esac
}

show_env() {
  local names=(
    PROJECT_DIR DATA_DIR COMFY_DIR VENV_DIR CACHE_DIR PIP_CACHE_DIR UV_CACHE_DIR
    MODELSCOPE_CACHE MODELSCOPE_CACHE_HOME HF_HOME HUGGINGFACE_HUB_CACHE TORCH_HOME
    NPM_CONFIG_CACHE XDG_CACHE_HOME CUDA_CACHE_PATH SHELL_HOME SHELL_BIN_DIR
    SHELL_STATE_DIR SHELL_HISTORY_DIR
  )
  local name
  for name in "${names[@]}"; do
    printf 'export %s=%q\n' "${name}" "${!name}"
  done
}

show_status() {
  local platform="uninitialized"
  [ ! -r "${PLATFORM_FILE}" ] || platform="$(sed -n 's/^PLATFORM=//p' "${PLATFORM_FILE}")"
  printf '%-22s %s\n' "platform" "${platform}"
  printf '%-22s %s\n' "persistent data" "${DATA_DIR}"
  printf '%-22s %s\n' "venv" "${VENV_DIR}"
  printf '%-22s %s\n' "shell home" "${SHELL_HOME}"
  printf '%-22s %s\n' "cache root" "${CACHE_DIR}"
  [ -x "${VENV_DIR}/bin/python" ] && echo "OK   shared Python venv" || echo "MISS shared Python venv (make init)"
  [ -f "${SHARED_ENV}" ] && echo "OK   shared Bash/zsh environment" || echo "MISS shared environment (make shell-init)"
  command -v bash >/dev/null 2>&1 && echo "OK   bash: $(command -v bash)" || echo "MISS bash"
  command -v zsh >/dev/null 2>&1 && echo "OK   zsh: $(command -v zsh)" || echo "MISS zsh"
  [ -f "${OMZ_DIR}/oh-my-zsh.sh" ] && echo "OK   Oh My Zsh" || echo "MISS Oh My Zsh"
}

show_cache() {
  ensure_directories
  local path
  for path in     "${PIP_CACHE_DIR}" "${UV_CACHE_DIR}" "${MODELSCOPE_CACHE}"     "${HF_HOME}" "${TORCH_HOME}" "${NPM_CONFIG_CACHE}"     "${XDG_CACHE_HOME}" "${CUDA_CACHE_PATH}"; do
    du -sh "${path}" 2>/dev/null || true
  done
}

cache_target() {
  case "$1" in
    pip) printf '%s' "${PIP_CACHE_DIR}" ;;
    uv) printf '%s' "${UV_CACHE_DIR}" ;;
    modelscope) printf '%s' "${MODELSCOPE_CACHE}" ;;
    huggingface|hf) printf '%s' "${HF_HOME}" ;;
    torch) printf '%s' "${TORCH_HOME}" ;;
    npm) printf '%s' "${NPM_CONFIG_CACHE}" ;;
    xdg) printf '%s' "${XDG_CACHE_HOME}" ;;
    cuda) printf '%s' "${CUDA_CACHE_PATH}" ;;
    all) printf '%s' "${CACHE_DIR}" ;;
    *) return 1 ;;
  esac
}

clean_cache() {
  [ -n "${CACHE_KIND}" ] || {
    echo "CACHE_KIND is required: pip|uv|modelscope|huggingface|torch|npm|xdg|cuda|all" >&2
    exit 2
  }
  local target
  target="$(cache_target "${CACHE_KIND}")" || {
    echo "Unsupported CACHE_KIND=${CACHE_KIND}" >&2
    exit 2
  }
  case "${target}" in
    "${CACHE_DIR}"|"${CACHE_DIR}/"*) ;;
    *) echo "Refusing to clean path outside CACHE_DIR: ${target}" >&2; exit 1 ;;
  esac
  mkdir -p "${target}"
  find "${target}" -mindepth 1 -delete
  ensure_directories
  echo "Cleared cache: ${target}"
}

shell_doctor() {
  local fail=0 path
  runtime_require_venv || fail=1
  for path in "${DATA_DIR}" "${CACHE_DIR}" "${SHELL_HOME}"; do
    mkdir -p "${path}"
    [ -w "${path}" ] && echo "OK   writable: ${path}" || { echo "FAIL not writable: ${path}"; fail=1; }
  done
  [ "${VENV_DIR}" != "${SHELL_HOME}" ] || { echo "FAIL venv and shell home must be separate"; fail=1; }
  [ "${CACHE_DIR}" != "${VENV_DIR}" ] || { echo "FAIL cache and venv must be separate"; fail=1; }
  command -v bash >/dev/null 2>&1 || { echo "FAIL bash missing"; fail=1; }
  [ -f "${SHARED_ENV}" ] || { echo "FAIL run make shell-init"; fail=1; }
  return "${fail}"
}

case "${ACTION}" in
  init) init_shell ;;
  enter) enter_shell ;;
  status) show_status ;;
  env) show_env ;;
  cache) show_cache ;;
  cache-clean) clean_cache ;;
  doctor) shell_doctor ;;
  update)
    require_shell
    [ -d "${OMZ_DIR}/.git" ] || { echo "Oh My Zsh is not initialized." >&2; exit 1; }
    git -C "${OMZ_DIR}" pull --ff-only
    ;;
  help|-h|--help)
    cat <<'EOF'
Usage: scripts/shell.sh [enter|init|status|env|cache|cache-clean|doctor|update|help]

Environment:
  SHELL_KIND=auto|bash|zsh
  CACHE_KIND=pip|uv|modelscope|huggingface|torch|npm|xdg|cuda|all

Examples:
  make shell
  make shell SHELL_KIND=bash
  make shell CMD=status
  make shell CMD=cache
  make shell CMD=cache-clean CACHE_KIND=pip
  make shell CMD=doctor
EOF
    ;;
  *)
    echo "Unknown shell command: ${ACTION}" >&2
    exit 2
    ;;
esac
