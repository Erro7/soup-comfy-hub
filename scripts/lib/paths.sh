#!/usr/bin/env bash

# Shared writable path policy. This file is safe to source with or without set -u.
paths_project_dir() {
  if [ -n "${PROJECT_DIR:-}" ]; then
    printf '%s\n' "${PROJECT_DIR}"
  else
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
  fi
}

paths_can_use() {
  local candidate="$1" probe parent
  [ -n "${candidate}" ] || return 1
  if [ -d "${candidate}" ]; then
    [ -w "${candidate}" ]
    return
  fi
  parent="${candidate}"
  while [ ! -e "${parent}" ] && [ "${parent}" != "/" ]; do
    parent="$(dirname "${parent}")"
  done
  [ -d "${parent}" ] && [ -w "${parent}" ]
}

paths_resolve_data_dir() {
  local project workspace candidate
  project="$(paths_project_dir)"
  if [ -n "${DATA_DIR:-}" ]; then
    printf '%s\n' "${DATA_DIR}"
    return
  fi
  workspace="${WORKSPACE:-$(dirname "${project}")}"
  candidate="${workspace}/soup-comfy-data"
  if paths_can_use "${candidate}"; then
    printf '%s\n' "${candidate}"
    return
  fi
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    candidate="${XDG_DATA_HOME}/soup-comfy-hub"
  elif [ -n "${HOME:-}" ]; then
    candidate="${HOME}/.local/share/soup-comfy-hub"
  else
    candidate=""
  fi
  if paths_can_use "${candidate}"; then
    printf '%s\n' "${candidate}"
  else
    printf '%s\n' "${project}/.data"
  fi
}

paths_resolve_tools_home() {
  local project data candidate
  project="$(paths_project_dir)"
  if [ -n "${TOOLS_HOME:-}" ]; then
    printf '%s\n' "${TOOLS_HOME}"
    return
  fi
  data="${DATA_DIR:-$(paths_resolve_data_dir)}"
  candidate="${data}/tools"
  if paths_can_use "${candidate}"; then
    printf '%s\n' "${candidate}"
    return
  fi
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    candidate="${XDG_DATA_HOME}/soup-comfy-hub/tools"
  elif [ -n "${HOME:-}" ]; then
    candidate="${HOME}/.local/share/soup-comfy-hub/tools"
  else
    candidate=""
  fi
  if paths_can_use "${candidate}"; then
    printf '%s\n' "${candidate}"
  else
    printf '%s\n' "${project}/.tools"
  fi
}

paths_export_runtime() {
  PROJECT_DIR="$(paths_project_dir)"
  WORKSPACE="${WORKSPACE:-$(dirname "${PROJECT_DIR}")}"
  DATA_DIR="$(paths_resolve_data_dir)"
  TOOLS_HOME="$(paths_resolve_tools_home)"
  TOOLS_BIN_DIR="${TOOLS_BIN_DIR:-${TOOLS_HOME}/bin}"
  export PROJECT_DIR WORKSPACE DATA_DIR TOOLS_HOME TOOLS_BIN_DIR
}

paths_prepend() {
  local directory="$1"
  case ":${PATH:-}:" in
    *":${directory}:"*) ;;
    *) PATH="${directory}${PATH:+:${PATH}}" ;;
  esac
  export PATH
}
