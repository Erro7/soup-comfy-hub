#!/usr/bin/env bash

download_atomic() {
  local url="$1" destination="$2" mode="${3:-0644}" temporary
  mkdir -p "$(dirname "${destination}")"
  temporary="${destination}.download.$$"
  rm -f "${temporary}"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --retry-all-errors --connect-timeout 15 \
      --output "${temporary}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=3 --timeout=15 --output-document="${temporary}" "${url}"
  else
    echo "curl or wget is required to download ${url}" >&2
    return 1
  fi
  chmod "${mode}" "${temporary}"
  mv -f "${temporary}" "${destination}"
}

download_version() {
  local binary="$1"
  "${binary}" --version 2>/dev/null | head -n 1
}
