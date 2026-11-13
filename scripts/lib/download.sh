#!/usr/bin/env bash

download_timezone() {
  local timezone="${TZ:-}"
  if [ -z "${timezone}" ] && [ -r /etc/timezone ]; then
    timezone="$(tr -d '[:space:]' < /etc/timezone)"
  fi
  printf '%s\n' "${timezone}"
}

download_is_cn_timezone() {
  case "$(download_timezone)" in
    Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi) return 0 ;;
    *) return 1 ;;
  esac
}

download_resolve_url() {
  local url="$1" prefix="${GITHUB_FILE_MIRROR_PREFIX:-auto}"
  case "${prefix}" in
    auto)
      if download_is_cn_timezone; then
        prefix="${GITHUB_FILE_MIRROR_CN:-https://ghfast.top/}"
      else
        prefix=""
      fi
      ;;
    off|direct|none) prefix="" ;;
  esac
  case "${url}" in
    https://github.com/*)
      printf '%s%s\n' "${prefix}" "${url}"
      ;;
    *) printf '%s\n' "${url}" ;;
  esac
}

download_fetch() {
  local url="$1" destination="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --retry-all-errors --connect-timeout 15 \
      --output "${destination}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=3 --timeout=15 --output-document="${destination}" "${url}"
  else
    echo "curl or wget is required to download ${url}" >&2
    return 1
  fi
}

download_atomic() {
  local url="$1" destination="$2" mode="${3:-0644}" temporary resolved
  mkdir -p "$(dirname "${destination}")"
  temporary="${destination}.download.$$"
  resolved="$(download_resolve_url "${url}")"
  rm -f "${temporary}"

  if [ "${resolved}" != "${url}" ]; then
    echo "Using GitHub single-file accelerator: ${resolved}"
  fi
  if ! download_fetch "${resolved}" "${temporary}"; then
    rm -f "${temporary}"
    if [ "${resolved}" = "${url}" ]; then
      return 1
    fi
    echo "Single-file accelerator failed; retrying direct: ${url}" >&2
    download_fetch "${url}" "${temporary}"
  fi

  chmod "${mode}" "${temporary}"
  mv -f "${temporary}" "${destination}"
}

download_version() {
  local binary="$1"
  "${binary}" --version 2>/dev/null | head -n 1
}
