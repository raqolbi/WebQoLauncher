#!/usr/bin/env bash
# Stop docker compose for every discovered application

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

stop_all_in_apps_dir() {
  if [[ ! -d "${APPS_DIR}" ]]; then
    return 0
  fi

  for app_dir in "${APPS_DIR}"/*/; do
    [[ -d "${app_dir}" ]] || continue
    [[ -f "${app_dir}/docker-compose.yml" ]] || continue

    folder="$(basename "${app_dir%/}")"
    log "Stopping ${folder}..."
    (cd "${app_dir}" && docker compose down) || warn "Failed to stop ${folder}"
  done
}

if [[ -f "${MANIFEST}" ]] && [[ -s "${MANIFEST}" ]]; then
  while IFS=$'\t' read -r folder _ _ _ _ _ _; do
    [[ -n "${folder}" ]] || continue
    app_dir="${APPS_DIR}/${folder}"
    if [[ -f "${app_dir}/docker-compose.yml" ]]; then
      log "Stopping ${folder}..."
      (cd "${app_dir}" && docker compose down) || warn "Failed to stop ${folder}"
    fi
  done < "${MANIFEST}"
else
  warn "Manifest empty or missing — stopping all compose projects in apps/"
  stop_all_in_apps_dir
fi

log "Stop apps complete"
