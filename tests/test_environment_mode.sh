#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_DIR}/scripts/lib/platform.sh"

SOUP_ENV_MODE=build
test "$(platform_kind)" = build
SOUP_ENV_MODE=docker
test "$(platform_kind)" = docker
SOUP_ENV_MODE=modelscope
test "$(platform_kind)" = modelscope
SOUP_ENV_MODE=linux
test "$(platform_kind)" = linux

SOUP_ENV_MODE=invalid
if platform_kind >/dev/null 2>&1; then
  echo "invalid environment mode was accepted" >&2
  exit 1
fi

echo "environment mode regression: PASS"
