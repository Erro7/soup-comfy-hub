#!/usr/bin/env bash

VENV_STATE_SCHEMA=1
VENV_STATE_DIR="${VENV_STATE_DIR:-${DATA_DIR}/state}"
VENV_STATE_FILE="${VENV_STATE_FILE:-${VENV_STATE_DIR}/venv.env}"

venv_realpath() {
  local candidate="$1"
  "${candidate}" -c 'import os,sys; print(os.path.realpath(sys.executable))'
}

venv_is_project_python() {
  local candidate="$1" resolved
  resolved="$(venv_realpath "${candidate}" 2>/dev/null || true)"
  case "${resolved}" in "${VENV_DIR}"/*) return 0 ;; *) return 1 ;; esac
}

venv_select_base_python() {
  local requested="${PYTHON_BIN:-}" candidate resolved fallback=""
  if [ -n "${requested}" ]; then
    resolved="$(command -v "${requested}" 2>/dev/null || true)"
    [ -n "${resolved}" ] || { echo "PYTHON_BIN is not executable: ${requested}" >&2; return 1; }
    venv_is_project_python "${resolved}" && {
      echo "PYTHON_BIN must point to the base interpreter, not ${VENV_DIR}." >&2
      return 1
    }
    printf '%s\n' "${resolved}"
    return
  fi
  for candidate in /opt/conda/bin/python python3 python; do
    resolved="$(command -v "${candidate}" 2>/dev/null || true)"
    [ -n "${resolved}" ] || continue
    venv_is_project_python "${resolved}" && continue
    [ -n "${fallback}" ] || fallback="${resolved}"
    if "${resolved}" -c 'import torch' >/dev/null 2>&1; then
      printf '%s\n' "${resolved}"
      return
    fi
  done
  [ -n "${fallback}" ] || { echo "No usable base Python interpreter was found." >&2; return 1; }
  printf '%s\n' "${fallback}"
}

venv_resolve_mode() {
  local python="$1" requested="${VENV_USE_SYSTEM_SITE_PACKAGES:-auto}" has_torch=0
  "${python}" -c 'import torch' >/dev/null 2>&1 && has_torch=1
  case "${requested}" in
    auto) printf '%s\n' "${has_torch}" ;;
    1|true|yes)
      [ "${has_torch}" = 1 ] || {
        echo "VENV_USE_SYSTEM_SITE_PACKAGES=1 but base Python cannot import torch: ${python}" >&2
        return 1
      }
      printf '1\n'
      ;;
    0|false|no) printf '0\n' ;;
    *) echo "VENV_USE_SYSTEM_SITE_PACKAGES must be auto, 1, or 0." >&2; return 2 ;;
  esac
}

venv_signature() {
  local python="$1" mode="$2" real version
  real="$(venv_realpath "${python}")"
  version="$("${python}" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
  printf 'schema=%s|python=%s|version=%s|system_site=%s' \
    "${VENV_STATE_SCHEMA}" "${real}" "${version}" "${mode}"
}

venv_read_signature() {
  [ -r "${VENV_STATE_FILE}" ] && sed -n 's/^SIGNATURE=//p' "${VENV_STATE_FILE}"
}

venv_write_state() {
  local python="$1" mode="$2" signature="$3" temporary
  mkdir -p "${VENV_STATE_DIR}"
  temporary="${VENV_STATE_FILE}.tmp.$$"
  cat > "${temporary}" <<EOF
SIGNATURE=${signature}
BASE_PYTHON=$(venv_realpath "${python}")
PYTHON_VERSION=$("${python}" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
SYSTEM_SITE_PACKAGES=${mode}
EOF
  mv -f "${temporary}" "${VENV_STATE_FILE}"
}

venv_ensure() {
  local base mode desired current reason="" args=()
  base="$(venv_select_base_python)"
  base="$(venv_realpath "${base}")"
  mode="$(venv_resolve_mode "${base}")"
  desired="$(venv_signature "${base}" "${mode}")"
  current="$(venv_read_signature || true)"

  if [ "${VENV_REBUILD:-0}" = 1 ]; then
    reason="explicit VENV_REBUILD=1"
  elif [ ! -x "${VENV_DIR}/bin/python" ]; then
    reason="environment is missing"
  elif [ "${current}" != "${desired}" ]; then
    reason="base Python contract changed"
  fi

  if [ -z "${reason}" ]; then
    echo "Reusing persistent Python environment: ${VENV_DIR}"
    return
  fi

  [ "${mode}" = 0 ] || args+=(--system-site-packages)
  mkdir -p "$(dirname "${VENV_DIR}")"
  echo "Creating persistent Python environment (${reason}): ${VENV_DIR}"
  "${base}" -m venv --clear "${args[@]}" "${VENV_DIR}"
  venv_write_state "${base}" "${mode}" "${desired}"
}

venv_status() {
  local base mode desired current
  printf '%-24s %s\n' "venv" "${VENV_DIR}"
  printf '%-24s %s\n' "state" "${VENV_STATE_FILE}"
  if [ -x "${VENV_DIR}/bin/python" ]; then
    echo "OK   persistent Python: $("${VENV_DIR}/bin/python" --version 2>&1)"
  else
    echo "MISS persistent Python"
  fi
  base="$(venv_select_base_python 2>/dev/null || true)"
  if [ -n "${base}" ]; then
    mode="$(venv_resolve_mode "${base}" 2>/dev/null || true)"
    desired="$(venv_signature "${base}" "${mode}" 2>/dev/null || true)"
    current="$(venv_read_signature || true)"
    printf '%-24s %s\n' "base Python" "$(venv_realpath "${base}")"
    printf '%-24s %s\n' "system site packages" "${mode}"
    [ "${current}" = "${desired}" ] && echo "OK   venv contract current" || echo "STALE venv contract"
  fi
}

venv_doctor() {
  [ -x "${VENV_DIR}/bin/python" ] || { echo "MISS ${VENV_DIR}/bin/python"; return 1; }
  "${VENV_DIR}/bin/python" -c 'import sys; print(f"OK   Python {sys.version.split()[0]} at {sys.executable}")'
  local base mode desired current
  base="$(venv_select_base_python)"
  mode="$(venv_resolve_mode "${base}")"
  desired="$(venv_signature "${base}" "${mode}")"
  current="$(venv_read_signature || true)"
  [ "${current}" = "${desired}" ] || {
    echo "STALE venv contract; run make venv-init." >&2
    return 1
  }
  echo "Persistent venv checks passed."
}
