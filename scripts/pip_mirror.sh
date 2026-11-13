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
    if [[ -n "${MODELSCOPE_ENVIRONMENT:-}" || -n "${MODELSCOPE_NOTEBOOK:-}" || -d /mnt/workspace ]]; then
      mirror="modelscope"
    else
      case "${timezone}" in
        Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi) mirror="tsinghua" ;;
        *) mirror="pypi" ;;
      esac
    fi
  fi

  case "${mirror}" in
    modelscope|aliyun-internal|alicloud) export PIP_INDEX_URL="https://mirrors.cloud.aliyuncs.com/pypi/simple" ;;
    tsinghua|tuna) export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple" ;;
    aliyun|alibaba) export PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/" ;;
    pypi|official|off) export PIP_INDEX_URL="https://pypi.org/simple" ;;
    *)
      echo "Unsupported PIP_MIRROR=${mirror}; use auto, modelscope, tsinghua, aliyun, or pypi" >&2
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


pip_index_fallback_enabled() {
  case "${PIP_INDEX_FALLBACK:-auto}" in
    1|true|yes|on) return 0 ;;
    0|false|no|off) return 1 ;;
    auto)
      [[ "${PIP_INDEX_URL:-}" == "https://mirrors.cloud.aliyuncs.com/pypi/simple"* ]]
      ;;
    *)
      echo "PIP_INDEX_FALLBACK must be auto, 1, or 0." >&2
      return 2
      ;;
  esac
}

# Retry the same pip operation against independent indexes when the ModelScope
# internal mirror is unreachable, has a TLS mismatch, or lacks a package.
# The shared pip cache is retained, and the selected primary index is unchanged.
pip_install_with_fallback() {
  local primary_index="${PIP_INDEX_URL:-https://pypi.org/simple}"
  if python -m pip install "$@"; then
    return 0
  fi
  pip_index_fallback_enabled || return 1

  local fallback_index
  echo "Primary pip index failed: ${primary_index}" >&2
  for fallback_index in ${PIP_FALLBACK_INDEX_URLS:-https://mirrors.aliyun.com/pypi/simple/ https://pypi.org/simple}; do
    [ "${fallback_index}" != "${primary_index}" ] || continue
    echo "Retrying pip install with fallback index: ${fallback_index}" >&2
    if PIP_INDEX_URL="${fallback_index}" python -m pip install "$@"; then
      return 0
    fi
  done
  echo "All configured pip indexes failed." >&2
  return 1
}
