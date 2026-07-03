#!/usr/bin/env bash
# Scan apps/ for .env files and write launcher/data/apps.manifest

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ensure_dirs

: > "${MANIFEST}"

found=0

if [[ ! -d "${APPS_DIR}" ]]; then
  warn "Directory apps/ not found at ${APPS_DIR}"
  log "Wrote empty manifest → ${MANIFEST}"
  exit 0
fi

for app_dir in "${APPS_DIR}"/*/; do
  [[ -d "${app_dir}" ]] || continue

  folder="$(basename "${app_dir%/}")"
  env_file="${app_dir}/.env"

  if [[ ! -f "${env_file}" ]]; then
    warn "Skipping ${folder}: missing .env"
    continue
  fi

  app_name="$(env_get "${env_file}" "APP_NAME")"
  port_app="$(env_get "${env_file}" "PORT_APP")"
  app_path="$(env_get "${env_file}" "APP_PATH" "${folder}")"
  app_desc="$(env_get "${env_file}" "APP_DESCRIPTION")"
  app_icon="$(env_get "${env_file}" "APP_ICON")"
  app_spa="$(env_get "${env_file}" "APP_SPA" "false")"

  if [[ -z "${app_name}" ]]; then
    warn "Skipping ${folder}: APP_NAME is required"
    continue
  fi

  if [[ -z "${port_app}" ]]; then
    warn "Skipping ${folder}: PORT_APP is required"
    continue
  fi

  if ! [[ "${port_app}" =~ ^[0-9]+$ ]]; then
    warn "Skipping ${folder}: PORT_APP must be numeric (got: ${port_app})"
    continue
  fi

  # Normalize path: strip leading/trailing slashes
  app_path="${app_path#/}"
  app_path="${app_path%/}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${folder}" "${app_name}" "${port_app}" "${app_path}" "${app_desc}" "${app_icon}" "${app_spa}" \
    >> "${MANIFEST}"

  found=$((found + 1))
  log "Found: ${app_name} (${folder}) → /${app_path} :${port_app}"
done

log "Scan complete: ${found} application(s) → ${MANIFEST}"
