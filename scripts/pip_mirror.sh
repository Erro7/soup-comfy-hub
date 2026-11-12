#!/usr/bin/env bash

# Select a PyPI index without changing the user's global pip configuration.
# Index changes never rebuild the venv and never erase reusable package caches.
# Precedence: explicit PIP_MIRROR > existing PIP_INDEX_URL > detected timezone.
configure_pip_mirror() {
  local mirror="${PIP_MIRROR:-auto}"
  local timezone="${TZ:-}"

  if [[ "${mirror}" == "auto" && -n "${PIP_INDEX_URL:-}" ]]; then
    echo "Using existing PIP_INDEX_URL=${PIP_INDEX_URL}"
    return
  fi

  if [[ -z "${timezone}" && -r /etc/timezone ]]; then
    timezone="$(tr -d '[:space:]' < /etc/timezone)"
  fi

  if [[ "${mirror}" == "auto" ]]; then
    case "${timezone}" in
      Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi) mirror="tsinghua" ;;
      *) mirror="pypi" ;;
    esac
  fi

  case "${mirror}" in
    tsinghua|tuna) export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple" ;;
    aliyun|alibaba) export PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/" ;;
    pypi|official|off) export PIP_INDEX_URL="https://pypi.org/simple" ;;
    *)
      echo "Unsupported PIP_MIRROR=${mirror}; use auto, tsinghua, aliyun, or pypi" >&2
      return 2
      ;;
  esac
  echo "Selected pip index: ${PIP_INDEX_URL} (timezone=${timezone:-unknown})"
}

pip_environment_signature() {
  printf 'venv-v3:%s:%s' "${PIP_INDEX_URL}" "${PIP_ENV_FLAVOR:-isolated}"
}

pip_index_changed() {
  local state_file="${1:?pip mirror state file is required}"
  local previous=""
  [[ -r "${state_file}" ]] && previous="$(<"${state_file}")"
  [[ "${previous}" != "$(pip_environment_signature)" ]]
}

prepare_pip_cache() {
  local state_file="${1:?pip mirror state file is required}"
  if pip_index_changed "${state_file}"; then
    echo "Package index changed; keeping the existing venv and shared pip cache."
  fi
}

record_pip_environment() {
  local state_file="${1:?pip mirror state file is required}"
  mkdir -p "$(dirname "${state_file}")"
  printf '%s\n' "$(pip_environment_signature)" > "${state_file}"
}
