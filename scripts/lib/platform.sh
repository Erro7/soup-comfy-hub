#!/usr/bin/env bash

platform_os() {
  case "$(uname -s 2>/dev/null || true)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

platform_arch() {
  case "$(uname -m 2>/dev/null || true)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

platform_kind() {
  case "${SOUP_ENV_MODE:-auto}" in
    build|docker|modelscope|linux)
      printf '%s\n' "${SOUP_ENV_MODE}"
      return
      ;;
    auto|"") ;;
    *)
      echo "Unsupported SOUP_ENV_MODE=${SOUP_ENV_MODE}; use auto, build, docker, modelscope, or linux." >&2
      return 2
      ;;
  esac
  if [ -n "${MODELSCOPE_ENVIRONMENT:-}" ] || [ -n "${MODELSCOPE_NOTEBOOK:-}" ] || [ -d /mnt/workspace ]; then
    printf 'modelscope\n'
  elif [ -f /.dockerenv ]; then
    printf 'docker\n'
  else
    printf 'linux\n'
  fi
}

platform_has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

platform_require_supported_binary() {
  local os arch
  os="$(platform_os)"
  arch="$(platform_arch)"
  [ "${os}" != unsupported ] && [ "${arch}" != unsupported ] || {
    echo "Unsupported platform: os=${os} arch=${arch}" >&2
    return 1
  }
}
