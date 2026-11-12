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

TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT
STATE_FILE="${TEMP_ROOT}/index-state"
printf '%s\n' 'old-index-contract' > "${STATE_FILE}"
PIP_ENV_FLAVOR=persistent-test
PIP_INDEX_URL=https://new.example/simple
prepare_pip_cache "${STATE_FILE}"
test -f "${STATE_FILE}"
echo "pip mirror regression: PASS"
