#!/usr/bin/env bash

# Select a PyPI index without changing the user's global pip configuration.
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
      Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi)
        mirror="tsinghua"
        ;;
      *)
        mirror="pypi"
        ;;
    esac
  fi

  case "${mirror}" in
    tsinghua|tuna)
      export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
      ;;
    aliyun|alibaba)
      export PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"
      ;;
    pypi|official|off)
      export PIP_INDEX_URL="https://pypi.org/simple"
      ;;
    *)
      echo "Unsupported PIP_MIRROR=${mirror}; use auto, tsinghua, aliyun, or pypi" >&2
      return 2
      ;;
  esac
  echo "Selected pip index: ${PIP_INDEX_URL} (timezone=${timezone:-unknown})"
}

# pip's cache is shared across indexes. Purge it only on the first managed run
# or when the selected index changes, so cached responses/artifacts from one
# cloud mirror cannot affect another.
prepare_pip_cache() {
  local state_file="${1:?pip mirror state file is required}"
  local previous_index=""

  if [[ -r "${state_file}" ]]; then
    previous_index="$(<"${state_file}")"
  fi

  if [[ "${previous_index}" != "${PIP_INDEX_URL}" ]]; then
    if [[ -n "${previous_index}" ]]; then
      echo "pip index changed: ${previous_index} -> ${PIP_INDEX_URL}"
    else
      echo "Initializing pip index state for ${PIP_INDEX_URL}"
    fi
    echo "Clearing pip cache before using the selected index..."
    python -m pip cache purge >/dev/null 2>&1 || true
  fi

  mkdir -p "$(dirname "${state_file}")"
  printf '%s\n' "${PIP_INDEX_URL}" > "${state_file}"
}
