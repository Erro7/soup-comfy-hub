#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"
source "${SCRIPT_DIR}/pip_mirror.sh"

ACTION="${1:-enter}"
SHELL_KIND="${SHELL_KIND:-zsh}"
CACHE_KIND="${CACHE_KIND:-}"
OMZ_DIR="${OMZ_DIR:-${SHELL_HOME}/oh-my-zsh}"
SHARED_ENV="${SHELL_HOME}/env.sh"
BASH_RC="${SHELL_HOME}/bashrc"
ZDOTDIR="${ZDOTDIR:-${SHELL_HOME}/zsh}"
ZSH_RC="${ZDOTDIR}/.zshrc"
PLATFORM_FILE="${SHELL_STATE_DIR}/platform.env"
SHELL_CONFIG_DIR="${SHELL_CONFIG_DIR:-${SHELL_HOME}/config}"
PIP_CONFIG_FILE="${PIP_CONFIG_FILE:-${SHELL_CONFIG_DIR}/pip/pip.conf}"
NPM_CONFIG_USERCONFIG="${NPM_CONFIG_USERCONFIG:-${SHELL_CONFIG_DIR}/npm/npmrc}"

ensure_directories() {
  if [ -f "${SHELL_HISTORY_DIR}" ]; then
    local legacy="${SHELL_HOME}/history.legacy.$$"
    mv "${SHELL_HISTORY_DIR}" "${legacy}"
    mkdir -p "${SHELL_HISTORY_DIR}"
    mv "${legacy}" "${SHELL_HISTORY_DIR}/zsh_history"
  fi
  mkdir -p "${TOOLS_BIN_DIR}" "${SHELL_BIN_DIR}" "${SHELL_STATE_DIR}" \
    "${SHELL_HISTORY_DIR}" "${ZDOTDIR}" "${SHELL_CONFIG_DIR}/pip" \
    "${SHELL_CONFIG_DIR}/npm" "${PIP_CACHE_DIR}" "${UV_CACHE_DIR}" \
    "${MODELSCOPE_CACHE}" "${HUGGINGFACE_HUB_CACHE}" "${TORCH_HOME}" \
    "${NPM_CONFIG_CACHE}" "${XDG_CACHE_HOME}" "${CUDA_CACHE_PATH}"
}

detect_platform() {
  source "${SCRIPT_DIR}/lib/platform.sh"
  cat > "${PLATFORM_FILE}" <<EOF
PLATFORM=$(platform_kind)
OS=$(platform_os)
ARCH=$(platform_arch)
PROJECT_DIR=${PROJECT_DIR}
DATA_DIR=${DATA_DIR}
TOOLS_HOME=${TOOLS_HOME}
VENV_DIR=${VENV_DIR}
EOF
}

write_package_configs() {
  configure_pip_mirror
  cat > "${PIP_CONFIG_FILE}" <<EOF
[global]
index-url = ${PIP_INDEX_URL}
cache-dir = ${PIP_CACHE_DIR}
disable-pip-version-check = true
EOF
  cat > "${NPM_CONFIG_USERCONFIG}" <<EOF
cache=${NPM_CONFIG_CACHE}
fund=false
audit=false
update-notifier=false
EOF
}

write_shared_env() {
  cat > "${SHARED_ENV}" <<EOF
export PROJECT_DIR="${PROJECT_DIR}"
export DATA_DIR="${DATA_DIR}"
export COMFY_DIR="${COMFY_DIR}"
export VENV_DIR="${VENV_DIR}"
export TOOLS_HOME="${TOOLS_HOME}"
export TOOLS_BIN_DIR="${TOOLS_BIN_DIR}"
export CACHE_DIR="${CACHE_DIR}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR}"
export PIP_CONFIG_FILE="${PIP_CONFIG_FILE}"
export PIP_INDEX_URL="${PIP_INDEX_URL}"
export UV_CACHE_DIR="${UV_CACHE_DIR}"
export MODELSCOPE_CACHE="${MODELSCOPE_CACHE}"
export MODELSCOPE_CACHE_HOME="${MODELSCOPE_CACHE_HOME}"
export HF_HOME="${HF_HOME}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE}"
export TORCH_HOME="${TORCH_HOME}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}"
export NPM_CONFIG_USERCONFIG="${NPM_CONFIG_USERCONFIG}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME}"
export CUDA_CACHE_PATH="${CUDA_CACHE_PATH}"
export SHELL_HOME="${SHELL_HOME}"
export SHELL_BIN_DIR="${SHELL_BIN_DIR}"
export SHELL_STATE_DIR="${SHELL_STATE_DIR}"
export SHELL_HISTORY_DIR="${SHELL_HISTORY_DIR}"
export SHELL_CONFIG_DIR="${SHELL_CONFIG_DIR}"
for directory in "\$TOOLS_BIN_DIR" "\$SHELL_BIN_DIR"; do
  case ":\$PATH:" in *":\$directory:"*) ;; *) PATH="\$directory:\$PATH" ;; esac
done
if [ -x "\$VENV_DIR/bin/python" ]; then
  case ":\$PATH:" in *":\$VENV_DIR/bin:"*) ;; *) PATH="\$VENV_DIR/bin:\$PATH" ;; esac
  [ ! -f "\$VENV_DIR/bin/activate" ] || source "\$VENV_DIR/bin/activate"
fi
export PATH
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
ZSH_THEME="${OMZ_THEME:-clean}"
plugins=(git python pip npm)
[ ! -f "\$ZSH/oh-my-zsh.sh" ] || source "\$ZSH/oh-my-zsh.sh"
[ ! -f "${SHELL_HOME}/zshrc.local" ] || source "${SHELL_HOME}/zshrc.local"
EOF
  touch "${SHELL_HISTORY_DIR}/bash_history" "${SHELL_HISTORY_DIR}/zsh_history"
}

install_omz() {
  [ "${INSTALL_OMZ:-1}" = 1 ] || return
  command -v zsh >/dev/null 2>&1 || {
    echo "WARN zsh is unavailable; Bash is ready. Install zsh, then rerun make shell-init." >&2
    return
  }
  command -v git >/dev/null 2>&1 || {
    echo "WARN git is unavailable; skipping Oh My Zsh installation." >&2
    return
  }
  if [ ! -d "${OMZ_DIR}/.git" ]; then
    echo "Installing Oh My Zsh into persistent storage: ${OMZ_DIR}"
    git clone --depth 1 "${OMZ_GIT_URL:-https://github.com/ohmyzsh/ohmyzsh.git}" "${OMZ_DIR}"
  fi
}

init_shell() {
  command -v bash >/dev/null || { echo "bash is required" >&2; exit 1; }
  ensure_directories
  detect_platform
  write_package_configs
  write_shared_env
  write_profiles
  install_omz
  echo "Unified shell ready: ${SHELL_HOME}"
  [ -x "${VENV_DIR}/bin/python" ] || echo "INFO project venv is not installed yet; shell remains usable."
}

require_shell() {
  [ -f "${SHARED_ENV}" ] || {
    echo "Unified shell is not initialized; run 'make shell-init' once." >&2
    return 1
  }
}

select_shell() {
  local selected="${SHELL_KIND}"
  if [ "${selected}" = auto ]; then
    if command -v zsh >/dev/null 2>&1; then selected=zsh; else selected=bash; fi
  fi
  printf '%s\n' "${selected}"
}

enter_shell() {
  require_shell
  case "$(select_shell)" in
    bash) exec bash --rcfile "${BASH_RC}" -i ;;
    zsh)
      command -v zsh >/dev/null 2>&1 || {
        echo "zsh is unavailable; use 'make shell SHELL_KIND=bash'." >&2
        exit 1
      }
      exec env ZDOTDIR="${ZDOTDIR}" ZSH="${OMZ_DIR}" zsh -i
      ;;
    *) echo "SHELL_KIND must be auto, bash, or zsh." >&2; exit 2 ;;
  esac
}

run_command() {
  require_shell
  [ -n "${SHELL_COMMAND:-}" ] || {
    echo "SHELL_COMMAND is required, for example: make shell CMD=run SHELL_COMMAND='python --version'" >&2
    exit 2
  }
  case "$(select_shell)" in
    zsh)
      command -v zsh >/dev/null 2>&1 || { echo "zsh is unavailable." >&2; exit 1; }
      exec env ZDOTDIR="${ZDOTDIR}" ZSH="${OMZ_DIR}" zsh -ic "${SHELL_COMMAND}"
      ;;
    bash) exec bash --rcfile "${BASH_RC}" -ic "${SHELL_COMMAND}" ;;
    *) echo "SHELL_KIND must be auto, bash, or zsh." >&2; exit 2 ;;
  esac
}

show_env() {
  local names=(PROJECT_DIR DATA_DIR COMFY_DIR VENV_DIR TOOLS_HOME TOOLS_BIN_DIR
    CACHE_DIR PIP_CACHE_DIR PIP_CONFIG_FILE PIP_INDEX_URL UV_CACHE_DIR
    MODELSCOPE_CACHE MODELSCOPE_CACHE_HOME HF_HOME HUGGINGFACE_HUB_CACHE
    TORCH_HOME NPM_CONFIG_CACHE NPM_CONFIG_USERCONFIG XDG_CACHE_HOME
    CUDA_CACHE_PATH SHELL_HOME SHELL_BIN_DIR SHELL_CONFIG_DIR
    SHELL_STATE_DIR SHELL_HISTORY_DIR)
  local name
  for name in "${names[@]}"; do printf 'export %s=%q\n' "${name}" "${!name:-}"; done
}

show_status() {
  local platform=uninitialized
  [ ! -r "${PLATFORM_FILE}" ] || platform="$(sed -n 's/^PLATFORM=//p' "${PLATFORM_FILE}")"
  printf '%-22s %s\n' platform "${platform}"
  printf '%-22s %s\n' "persistent data" "${DATA_DIR}"
  printf '%-22s %s\n' "tools home" "${TOOLS_HOME}"
  printf '%-22s %s\n' "venv" "${VENV_DIR}"
  printf '%-22s %s\n' "shell home" "${SHELL_HOME}"
  printf '%-22s %s\n' "cache root" "${CACHE_DIR}"
  [ -x "${VENV_DIR}/bin/python" ] && echo "OK   project Python venv" || echo "INFO project venv not initialized"
  [ -f "${SHARED_ENV}" ] && echo "OK   shared Bash/zsh environment" || echo "MISS shared environment"
  [ -f "${PIP_CONFIG_FILE}" ] && echo "OK   persistent pip config" || echo "MISS persistent pip config"
  [ -f "${NPM_CONFIG_USERCONFIG}" ] && echo "OK   persistent npm config" || echo "MISS persistent npm config"
  command -v bash >/dev/null 2>&1 && echo "OK   bash: $(command -v bash)" || echo "MISS bash"
  command -v zsh >/dev/null 2>&1 && echo "OK   zsh: $(command -v zsh)" || echo "MISS zsh"
  [ -f "${OMZ_DIR}/oh-my-zsh.sh" ] && echo "OK   Oh My Zsh" || echo "INFO Oh My Zsh not installed"
}

show_cache() {
  ensure_directories
  local path
  for path in "${PIP_CACHE_DIR}" "${UV_CACHE_DIR}" "${MODELSCOPE_CACHE}" \
    "${HF_HOME}" "${TORCH_HOME}" "${NPM_CONFIG_CACHE}" "${XDG_CACHE_HOME}" \
    "${CUDA_CACHE_PATH}"; do du -sh "${path}" 2>/dev/null || true; done
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
  target="$(cache_target "${CACHE_KIND}")" || { echo "Unsupported CACHE_KIND=${CACHE_KIND}" >&2; exit 2; }
  case "${target}" in "${DATA_DIR}"/*) ;; *) echo "Refusing unsafe cache path: ${target}" >&2; exit 1 ;; esac
  find "${target}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  echo "Cleaned ${CACHE_KIND} cache: ${target}"
}

doctor() {
  local failed=0
  [ -w "${DATA_DIR}" ] || { echo "MISS writable data directory: ${DATA_DIR}"; failed=1; }
  [ -w "${TOOLS_HOME}" ] || { echo "MISS writable tools directory: ${TOOLS_HOME}"; failed=1; }
  [ -f "${SHARED_ENV}" ] || { echo "MISS shared environment; run make shell-init"; failed=1; }
  [ -f "${PIP_CONFIG_FILE}" ] || { echo "MISS pip config"; failed=1; }
  [ -f "${NPM_CONFIG_USERCONFIG}" ] || { echo "MISS npm config"; failed=1; }
  command -v bash >/dev/null || { echo "MISS bash"; failed=1; }
  command -v zsh >/dev/null || echo "WARN zsh missing; Bash mode remains available"
  command -v git >/dev/null || echo "WARN git missing; OMZ update/install unavailable"
  [ -x "${VENV_DIR}/bin/python" ] || echo "INFO project venv not initialized"
  [ "${failed}" -eq 0 ] && echo "Shell environment checks passed."
  return "${failed}"
}

update_omz() {
  [ -d "${OMZ_DIR}/.git" ] || { echo "Oh My Zsh is not installed." >&2; exit 1; }
  git -C "${OMZ_DIR}" pull --ff-only
}

help() {
  cat <<'EOF'
Usage: scripts/shell.sh ACTION

Actions:
  enter        Enter zsh by default (or SHELL_KIND=bash)
  init         Create persistent environment/configs; venv is optional
  run          Run SHELL_COMMAND inside the managed interactive environment
  status       Show resolved platform, paths and components
  env          Print sourceable exports
  cache        Show package/model cache sizes
  cache-clean  Clean only CACHE_KIND
  doctor       Validate the flattened shell environment
  update       Explicitly update Oh My Zsh
  help
EOF
}

case "${ACTION}" in
  enter) enter_shell ;;
  init) init_shell ;;
  run|command|exec) run_command ;;
  status) show_status ;;
  env) show_env ;;
  cache) show_cache ;;
  cache-clean) clean_cache ;;
  doctor) doctor ;;
  update) update_omz ;;
  help|-h|--help) help ;;
  *) help >&2; exit 2 ;;
esac
