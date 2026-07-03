#!/usr/bin/env bash
# Shared helpers for WebQoLauncher scripts.

set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_DIR="$(cd "${_LIB_DIR}/../.." && pwd)"
PROJECT_ROOT="$(cd "${LAUNCHER_DIR}/.." && pwd)"
APPS_DIR="${PROJECT_ROOT}/apps"
DATA_DIR="${LAUNCHER_DIR}/data"
MANIFEST="${DATA_DIR}/apps.manifest"
NGINX_CONF="${LAUNCHER_DIR}/nginx.conf"
HTML_DIR="${LAUNCHER_DIR}/html"

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
  value="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^["'\'']//;s/["'\'']$//')" || true
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${default}"
  fi
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
