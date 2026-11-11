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
