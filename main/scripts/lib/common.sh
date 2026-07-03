#!/usr/bin/env bash
# Shared helpers for WebQoLauncher scripts.

set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_DIR="$(cd "${_LIB_DIR}/../.." && pwd)"
PROJECT_ROOT="$(cd "${MAIN_DIR}/.." && pwd)"
APPS_DIR="${PROJECT_ROOT}/apps"
DATA_DIR="${MAIN_DIR}/data"
MANIFEST="${DATA_DIR}/apps.manifest"
NGINX_CONF="${MAIN_DIR}/nginx.conf"
HTML_DIR="${MAIN_DIR}/html"

log()  { printf '[launcher] %s\n' "$*"; }
warn() { printf '[launcher] WARN: %s\n' "$*" >&2; }
die()  { printf '[launcher] ERROR: %s\n' "$*" >&2; exit 1; }

ensure_dirs() {
  mkdir -p "${DATA_DIR}" "${HTML_DIR}"
}

# Read a single KEY from an .env file (ignores comments and blank lines).
env_get() {
  local file="$1" key="$2" default="${3:-}"
  local value
  value="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^["'\'']//;s/["'\'']$//' | tr -d '\r')" || true
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${default}"
  fi
}

# Format nilai aman untuk ditulis ke .env
env_format() {
  local value="$1"
  if [[ "${value}" == *" "* || "${value}" == *\"* || "${value}" == *\\* ]]; then
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
  else
    printf '%s' "${value}"
  fi
}

# Escape string untuk dipakai di nginx location regex
nginx_regex_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//+/\\+}"
  s="${s//\*/\\*}"
  s="${s//\?/\\?}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  s="${s//\(/\\(}"
  s="${s//\)/\\)}"
  s="${s//\{/\\{}"
  s="${s//\}/\\}}"
  s="${s//\^/\\^}"
  s="${s//\$/\\$}"
  s="${s//\|/\\|}"
  printf '%s' "${s}"
}

# Baca input interaktif dari terminal (aman dipanggil dari subshell/menu)
read_tty() {
  local __out="$1" prompt="$2" default="${3:-}"
  local _input=""
  if [[ -n "${default}" ]]; then
    prompt="${prompt} [${default}]: "
  else
    prompt="${prompt}: "
  fi
  if [[ -r /dev/tty ]]; then
    printf '%s' "${prompt}" >/dev/tty
    IFS= read -r _input </dev/tty || _input=""
  else
    IFS= read -r -p "${prompt}" _input || _input=""
  fi
  if [[ -z "${_input}" && -n "${default}" ]]; then
    _input="${default}"
  fi
  printf -v "${__out}" '%s' "${_input}"
}

# Escape string for safe HTML embedding.
html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&#39;}"
  printf '%s' "${s}"
}
