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
