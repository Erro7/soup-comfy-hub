#!/usr/bin/env bash
set -Eeuo pipefail

source scripts/pip_mirror.sh

unset PIP_INDEX_URL
TZ=Asia/Shanghai
PIP_MIRROR=auto
configure_pip_mirror
[[ "${PIP_INDEX_URL}" == "https://pypi.tuna.tsinghua.edu.cn/simple" ]]

unset PIP_INDEX_URL
TZ=Etc/UTC
PIP_MIRROR=auto
configure_pip_mirror
[[ "${PIP_INDEX_URL}" == "https://pypi.org/simple" ]]

PIP_INDEX_URL=https://custom.example/simple
TZ=Asia/Shanghai
PIP_MIRROR=auto
configure_pip_mirror
[[ "${PIP_INDEX_URL}" == "https://custom.example/simple" ]]

PIP_INDEX_URL=https://custom.example/simple
PIP_MIRROR=aliyun
configure_pip_mirror
[[ "${PIP_INDEX_URL}" == "https://mirrors.aliyun.com/pypi/simple/" ]]

unset PIP_INDEX_URL
MODELSCOPE_ENVIRONMENT=1
export MODELSCOPE_ENVIRONMENT
TZ=Asia/Shanghai
PIP_MIRROR=auto
configure_pip_mirror
[[ "${PIP_INDEX_URL}" == "https://mirrors.cloud.aliyuncs.com/pypi/simple" ]]
unset MODELSCOPE_ENVIRONMENT

ATTEMPTS_FILE="$(mktemp)"
python() {
  printf '%s\n' "${PIP_INDEX_URL:-}" >> "${ATTEMPTS_FILE}"
  [[ "${PIP_INDEX_URL:-}" == "https://mirrors.aliyun.com/pypi/simple/" ]]
}
export -f python
PIP_INDEX_URL=https://mirrors.cloud.aliyuncs.com/pypi/simple
PIP_INDEX_FALLBACK=auto
PIP_FALLBACK_INDEX_URLS="https://mirrors.aliyun.com/pypi/simple/ https://pypi.org/simple"
pip_install_with_fallback insightface
mapfile -t attempts < "${ATTEMPTS_FILE}"
[[ "${attempts[0]}" == "https://mirrors.cloud.aliyuncs.com/pypi/simple" ]]
[[ "${attempts[1]}" == "https://mirrors.aliyun.com/pypi/simple/" ]]
[[ "${#attempts[@]}" -eq 2 ]]
unset -f python
rm -f "${ATTEMPTS_FILE}"
unset PIP_INDEX_FALLBACK PIP_FALLBACK_INDEX_URLS

TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT
STATE_FILE="${TEMP_ROOT}/index-state"
printf '%s\n' 'old-index-contract' > "${STATE_FILE}"
PIP_ENV_FLAVOR=persistent-test
PIP_INDEX_URL=https://new.example/simple
prepare_pip_cache "${STATE_FILE}"
test -f "${STATE_FILE}"
echo "pip mirror regression: PASS"
