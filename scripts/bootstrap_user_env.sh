#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime_env.sh"

REQUESTED_USER="${1:-${MODE_A_USER:-}}"
USER_CONFIG_FILE="${MODE_A_USER_FILE:-${WORKSPACE}/.current_user}"
UID_CONFIG_FILE="${MODE_A_UID_FILE:-${WORKSPACE}/.current_uid}"
BOOTSTRAP_LINK="${MODE_A_BOOTSTRAP_LINK:-${WORKSPACE}/bootstrap_env.sh}"
DEFAULT_USER="${MODE_A_DEFAULT_USER:-dev}"
REQUESTED_UID="${MODE_A_UID:-10001}"
MODE_A_AUTO_ENTER="${MODE_A_AUTO_ENTER:-1}"
MODE_A_PASSWORDLESS_SUDO="${MODE_A_PASSWORDLESS_SUDO:-1}"
TRAIN_ROOT="${TRAIN_ROOT:-${DATA_DIR}/training}"

[ "$(id -u)" -eq 0 ] || {
  echo "Mode-A user initialization requires root inside the container." >&2
  exit 1
}

if [ -n "${REQUESTED_USER}" ]; then
  USERNAME="${REQUESTED_USER}"
  printf '%s\n' "${USERNAME}" > "${USER_CONFIG_FILE}"
elif [ -s "${USER_CONFIG_FILE}" ]; then
  USERNAME="$(tr -d '[:space:]' < "${USER_CONFIG_FILE}")"
else
  USERNAME="${DEFAULT_USER}"
  printf '%s\n' "${USERNAME}" > "${USER_CONFIG_FILE}"
fi
case "${USERNAME}" in
  ""|*[!a-zA-Z0-9_-]*|[0-9]*)
    echo "Invalid Mode-A username: ${USERNAME}" >&2
    exit 2
    ;;
esac

USER_HOME="${MODE_A_HOME:-${WORKSPACE}/${USERNAME}}"

echo ">>> [1/7] Initializing Mode-A user: ${USERNAME} (HOME=${USER_HOME})"
missing_packages=()
for pair in "sudo:sudo" "zsh:zsh" "git:git" "curl:curl" "wget:wget" "tmux:tmux"; do
  command_name="${pair%%:*}"
  package_name="${pair#*:}"
  command -v "${command_name}" >/dev/null 2>&1 || missing_packages+=("${package_name}")
done
if [ "${#missing_packages[@]}" -gt 0 ]; then
  command -v apt-get >/dev/null 2>&1 || {
    echo "apt-get is required to restore Mode-A system tools in this container." >&2
    exit 1
  }
  echo "    Installing missing container packages: ${missing_packages[*]}"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing_packages[@]}"
fi

echo ">>> [2/7] Creating persistent user directories"
mkdir -p "${USER_HOME}"/{.cache,.local/bin,.npm-global,.ssh,.cc-switch,projects,models,datasets,outputs,logs}
mkdir -p "${PIP_CACHE_DIR}" "${MODELSCOPE_CACHE}" "${HF_HOME}" "${TORCH_HOME}" \
  "${NPM_CONFIG_CACHE}" "${TASK_OUTPUT_DIR}" "${COMFY_DIR}/models/loras" "${TRAIN_ROOT}"

echo ">>> [3/7] Restoring the container user and login shell"
if id -u "${USERNAME}" >/dev/null 2>&1; then
  USER_UID="$(id -u "${USERNAME}")"
  usermod -d "${USER_HOME}" -s "$(command -v zsh)" "${USERNAME}"
else
  if [ -s "${UID_CONFIG_FILE}" ]; then
    USER_UID="$(tr -d '[:space:]' < "${UID_CONFIG_FILE}")"
  else
    USER_UID="${REQUESTED_UID}"
  fi
  while getent passwd "${USER_UID}" >/dev/null 2>&1; do
    USER_UID=$((USER_UID + 1))
    [ "${USER_UID}" -le 19999 ] || {
      echo "No free UID found in the Mode-A allocation range." >&2
      exit 1
    }
  done
  useradd -u "${USER_UID}" -d "${USER_HOME}" -M -s "$(command -v zsh)" "${USERNAME}"
fi
printf '%s\n' "${USER_UID}" > "${UID_CONFIG_FILE}"
usermod -aG sudo "${USERNAME}"

if [ "${MODE_A_PASSWORDLESS_SUDO}" = 1 ]; then
  cat > "/etc/sudoers.d/${USERNAME}" <<EOF
${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL
Defaults:${USERNAME} !env_reset
Defaults:${USERNAME} !secure_path
EOF
  chmod 0440 "/etc/sudoers.d/${USERNAME}"
  visudo -cf "/etc/sudoers.d/${USERNAME}" >/dev/null
fi

echo ">>> [4/7] Installing persistent Oh My Zsh and plugins"
OMZ_DIR="${USER_HOME}/.oh-my-zsh"
ZSH_CUSTOM="${OMZ_DIR}/custom"
if [ ! -d "${OMZ_DIR}/.git" ]; then
  rm -rf "${OMZ_DIR}"
  git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "${OMZ_DIR}"
fi
mkdir -p "${ZSH_CUSTOM}/plugins"
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions/.git" ]; then
  rm -rf "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git \
    "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting/.git" ]; then
  rm -rf "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
fi

echo ">>> [5/7] Writing the persistent zsh profile"
cat > "${USER_HOME}/.zshrc" <<EOF
export HOME="${USER_HOME}"
export USER="${USERNAME}"
export PROJECT_DIR="${PROJECT_DIR}"
export DATA_DIR="${DATA_DIR}"
export COMFY_DIR="${COMFY_DIR}"
export VENV_DIR="${VENV_DIR}"
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="${MODE_A_OMZ_THEME:-robbyrussell}"
DISABLE_AUTO_UPDATE="true"
plugins=(git sudo extract z zsh-autosuggestions zsh-syntax-highlighting)
source "\$ZSH/oh-my-zsh.sh"

export PATH="\$HOME/venv/bin:\$HOME/.local/bin:\$HOME/.npm-global/bin:${TOOLS_BIN_DIR}:\$PATH"
export PIP_CACHE_DIR="${PIP_CACHE_DIR}"
export MODELSCOPE_CACHE="${MODELSCOPE_CACHE}"
export MODELSCOPE_CACHE_HOME="${MODELSCOPE_CACHE_HOME}"
export HF_HOME="${HF_HOME}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE}"
export TORCH_HOME="${TORCH_HOME}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE}"
export NPM_CONFIG_PREFIX="\$HOME/.npm-global"
export HISTFILE="\$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY

alias ll='ls -alF --color=auto'
alias la='ls -A'
alias gpu='watch -n 1 nvidia-smi'
alias cls='clear'
alias root='STAY_ROOT=1 sudo -i'
[ ! -f "\$HOME/.zshrc.local" ] || source "\$HOME/.zshrc.local"
cd "\$HOME"
EOF
touch "${USER_HOME}/.zsh_history" "${USER_HOME}/.zshrc_initialized"

echo ">>> [6/7] Linking the unified persistent project venv"
if [ ! -x "${VENV_DIR}/bin/python" ]; then
  bash "${PROJECT_DIR}/scripts/venv.sh" init
fi
if [ -e "${USER_HOME}/venv" ] && [ ! -L "${USER_HOME}/venv" ]; then
  echo "Existing non-symlink venv retained at ${USER_HOME}/venv; project venv is ${VENV_DIR}." >&2
else
  ln -sfn "${VENV_DIR}" "${USER_HOME}/venv"
fi

echo ">>> [7/7] Calibrating permissions and installing the Terminal recovery hook"
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}"
for writable in "${PIP_CACHE_DIR}" "${MODELSCOPE_CACHE}" "${HF_HOME}" "${TORCH_HOME}" \
  "${NPM_CONFIG_CACHE}" "${TASK_OUTPUT_DIR}" "${COMFY_DIR}/models/loras" "${TRAIN_ROOT}" "${VENV_DIR}"; do
  [ ! -e "${writable}" ] || chown -R "${USERNAME}:${USERNAME}" "${writable}"
done
chmod 700 "${USER_HOME}/.ssh" "${USER_HOME}/.cc-switch"

printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' \
  "${PROJECT_DIR}/scripts/bootstrap_user_env.sh" > "${BOOTSTRAP_LINK}"
chmod 0755 "${BOOTSTRAP_LINK}"
sed -i '/# === SOUP_MODE_A_START ===/,/# === SOUP_MODE_A_END ===/d' /root/.bashrc 2>/dev/null || true
if [ "${MODE_A_AUTO_ENTER}" = 1 ]; then
  cat >> /root/.bashrc <<'EOF'
# === SOUP_MODE_A_START ===
if [ -f /mnt/workspace/bootstrap_env.sh ]; then
  TARGET_USER="$(cat /mnt/workspace/.current_user 2>/dev/null || echo dev)"
  if ! id -u "$TARGET_USER" >/dev/null 2>&1 || ! command -v zsh >/dev/null 2>&1; then
    bash /mnt/workspace/bootstrap_env.sh "$TARGET_USER"
  fi
  if [ -t 1 ] && [ "$(id -u)" -eq 0 ] && [ -z "${STAY_ROOT:-}" ]; then
    exec su - "$TARGET_USER"
  fi
fi
# === SOUP_MODE_A_END ===
EOF
fi

echo "Mode-A ready: user=${USERNAME} uid=${USER_UID} home=${USER_HOME}"
echo "Open a new Terminal or run: exec su - ${USERNAME}"
