#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-enter}"
ZDOTDIR="${ZDOTDIR:-${SHELL_HOME}}"
OMZ_DIR="${OMZ_DIR:-${SHELL_HOME}/oh-my-zsh}"
MANAGED_RC="${SHELL_HOME}/soup-comfy.zsh"
ZSHRC="${ZDOTDIR}/.zshrc"

ensure_zsh() {
  if command -v zsh >/dev/null 2>&1; then
    return
  fi
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    echo "Installing zsh into the current base container..."
    apt-get update
    apt-get install -y --no-install-recommends zsh
    return
  fi
  echo "zsh is unavailable; install it in the base image or run shell-init as root." >&2
  exit 1
}

write_managed_rc() {
  mkdir -p "${SHELL_HOME}" "${ZDOTDIR}"
  cat > "${MANAGED_RC}" <<EOF
export PROJECT_DIR="${PROJECT_DIR}"
export DATA_DIR="${DATA_DIR}"
export COMFY_DIR="${COMFY_DIR}"
export VENV_DIR="${VENV_DIR}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR}"
export ZSH="${OMZ_DIR}"
export HISTFILE="${SHELL_HOME}/history"
export HISTSIZE=50000
export SAVEHIST=50000
ZSH_THEME="${OMZ_THEME:-robbyrussell}"
plugins=(git python pip)
[ ! -f "\$ZSH/oh-my-zsh.sh" ] || source "\$ZSH/oh-my-zsh.sh"
[ ! -f "\$VENV_DIR/bin/activate" ] || source "\$VENV_DIR/bin/activate"
cd "\$PROJECT_DIR"
EOF

  touch "${ZSHRC}" "${SHELL_HOME}/history"
  local source_line="source \"${MANAGED_RC}\""
  if ! grep -Fqx "${source_line}" "${ZSHRC}"; then
    printf '\n# soup-comfy-hub managed shell\n%s\n' "${source_line}" >> "${ZSHRC}"
  fi
}

init_shell() {
  runtime_require_venv
  ensure_zsh
  mkdir -p "${SHELL_HOME}"
  if [ ! -d "${OMZ_DIR}/.git" ]; then
    echo "Installing Oh My Zsh into persistent storage: ${OMZ_DIR}"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "${OMZ_DIR}"
  fi
  write_managed_rc
  echo "Persistent shell ready: ${SHELL_HOME}"
}

require_shell() {
  runtime_require_venv
  command -v zsh >/dev/null 2>&1 || {
    echo "zsh is missing; run 'make shell-init' once." >&2
    return 1
  }
  [ -f "${OMZ_DIR}/oh-my-zsh.sh" ] || {
    echo "Oh My Zsh is missing; run 'make shell-init' once." >&2
    return 1
  }
  [ -f "${MANAGED_RC}" ] || {
    echo "Managed shell config is missing; run 'make shell-init' once." >&2
    return 1
  }
}

show_env() {
  printf 'export PROJECT_DIR=%q\n' "${PROJECT_DIR}"
  printf 'export DATA_DIR=%q\n' "${DATA_DIR}"
  printf 'export COMFY_DIR=%q\n' "${COMFY_DIR}"
  printf 'export VENV_DIR=%q\n' "${VENV_DIR}"
  printf 'export PIP_CACHE_DIR=%q\n' "${PIP_CACHE_DIR}"
  printf 'export SHELL_HOME=%q\n' "${SHELL_HOME}"
  printf 'export ZDOTDIR=%q\n' "${ZDOTDIR}"
  printf 'export ZSH=%q\n' "${OMZ_DIR}"
}

show_status() {
  printf '%-22s %s\n' "persistent data" "${DATA_DIR}"
  printf '%-22s %s\n' "venv" "${VENV_DIR}"
  printf '%-22s %s\n' "shell home" "${SHELL_HOME}"
  [ -x "${VENV_DIR}/bin/python" ] && echo "OK   Python venv" || echo "MISS Python venv (make init)"
  [ -f "${COMFY_DIR}/main.py" ] && echo "OK   ComfyUI" || echo "MISS ComfyUI (make init)"
  command -v zsh >/dev/null 2>&1 && echo "OK   zsh: $(command -v zsh)" || echo "MISS zsh (make shell-init)"
  [ -f "${OMZ_DIR}/oh-my-zsh.sh" ] && echo "OK   Oh My Zsh" || echo "MISS Oh My Zsh (make shell-init)"
  [ -f "${MANAGED_RC}" ] && echo "OK   managed shell config" || echo "MISS managed shell config"
  [ -f "${DATA_DIR}/.runtime-ready" ] && echo "OK   runtime marker" || echo "MISS runtime marker (make init)"
}

case "${ACTION}" in
  init)
    init_shell
    ;;
  enter)
    require_shell
    exec env ZDOTDIR="${ZDOTDIR}" ZSH="${OMZ_DIR}" zsh -l
    ;;
  status)
    show_status
    ;;
  env)
    show_env
    ;;
  update)
    require_shell
    git -C "${OMZ_DIR}" pull --ff-only
    write_managed_rc
    ;;
  help|-h|--help)
    cat <<'EOF'
Usage: scripts/shell.sh [enter|init|status|env|update|help]

  enter   enter the persistent zsh and activate the one project venv
  init    explicitly install/configure zsh and Oh My Zsh
  status  inspect the shared runtime, venv, and shell paths
  env     print sourceable export statements for the resolved environment
  update  explicitly update the persistent Oh My Zsh checkout
EOF
    ;;
  *)
    echo "Unknown shell command: ${ACTION}" >&2
    echo "Run 'make shell-help' for available commands." >&2
    exit 2
    ;;
esac
