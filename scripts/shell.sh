#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

ACTION="${1:-enter}"
SHELL_HOME="${SHELL_HOME:-${DATA_DIR}/shell}"
ZDOTDIR="${ZDOTDIR:-${SHELL_HOME}}"
OMZ_DIR="${OMZ_DIR:-${SHELL_HOME}/oh-my-zsh}"
MANAGED_RC="${SHELL_HOME}/soup-comfy.zsh"
ZSHRC="${ZDOTDIR}/.zshrc"

ensure_zsh() {
  if command -v zsh >/dev/null 2>&1; then
    return
  fi
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    echo "Installing the zsh binary into the current container..."
    apt-get update
    apt-get install -y --no-install-recommends zsh
    return
  fi
  echo "zsh is unavailable. Install it in the base image or run shell-init as root." >&2
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
  ensure_zsh
  mkdir -p "${SHELL_HOME}"
  if [ ! -d "${OMZ_DIR}/.git" ]; then
    echo "Installing Oh My Zsh into persistent storage: ${OMZ_DIR}"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "${OMZ_DIR}"
  fi
  write_managed_rc
  echo "Persistent shell ready: ${SHELL_HOME}"
}

show_env() {
  printf 'PROJECT_DIR=%q\n' "${PROJECT_DIR}"
  printf 'DATA_DIR=%q\n' "${DATA_DIR}"
  printf 'COMFY_DIR=%q\n' "${COMFY_DIR}"
  printf 'VENV_DIR=%q\n' "${VENV_DIR}"
  printf 'PIP_CACHE_DIR=%q\n' "${PIP_CACHE_DIR}"
  printf 'SHELL_HOME=%q\n' "${SHELL_HOME}"
  printf 'ZDOTDIR=%q\n' "${ZDOTDIR}"
  printf 'ZSH=%q\n' "${OMZ_DIR}"
}

show_status() {
  printf '%-20s %s\n' "persistent data" "${DATA_DIR}"
  [ -x "${VENV_DIR}/bin/python" ] && echo "OK   Python venv" || echo "MISS Python venv (run make init)"
  [ -f "${COMFY_DIR}/main.py" ] && echo "OK   ComfyUI" || echo "MISS ComfyUI (run make init)"
  command -v zsh >/dev/null 2>&1 && echo "OK   zsh: $(command -v zsh)" || echo "MISS zsh binary"
  [ -f "${OMZ_DIR}/oh-my-zsh.sh" ] && echo "OK   Oh My Zsh" || echo "MISS Oh My Zsh (run make shell-init)"
  [ -f "${MANAGED_RC}" ] && echo "OK   managed shell environment" || echo "MISS managed shell environment"
  [ -f "${DATA_DIR}/.runtime-ready" ] && echo "OK   runtime marker" || echo "MISS runtime marker (run make init)"
}

case "${ACTION}" in
  init)
    init_shell
    ;;
  enter)
    init_shell
    exec env ZDOTDIR="${ZDOTDIR}" ZSH="${OMZ_DIR}" zsh -l
    ;;
  status)
    show_status
    ;;
  env)
    show_env
    ;;
  update)
    init_shell
    git -C "${OMZ_DIR}" pull --ff-only
    ;;
  help|-h|--help)
    cat <<'EOF'
Usage: scripts/shell.sh [enter|init|status|env|update|help]

  enter   initialize if needed, then enter zsh with the project venv active
  init    install/configure the persistent Oh My Zsh environment
  status  inspect persistent runtime and shell components
  env     print resolved runtime and shell paths
  update  update the persistent Oh My Zsh checkout
EOF
    ;;
  *)
    echo "Unknown shell command: ${ACTION}" >&2
    echo "Run 'make shell-help' for available commands." >&2
    exit 2
    ;;
esac
