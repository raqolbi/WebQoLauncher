#!/usr/bin/env bash
# Start docker compose for every discovered application

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

if [[ ! -f "${MANIFEST}" ]]; then
  die "Manifest not found. Run scan.sh first."
fi

if [[ ! -s "${MANIFEST}" ]]; then
  warn "No applications in manifest — nothing to start"
  exit 0
fi

started=0
failed=0

while IFS=$'\t' read -r folder app_name port_app app_path app_desc app_icon app_spa; do
  [[ -n "${folder}" ]] || continue

  app_dir="${APPS_DIR}/${folder}"
  compose_file="${app_dir}/docker-compose.yml"

  if [[ ! -f "${compose_file}" ]]; then
    warn "Skipping ${folder}: missing docker-compose.yml"
    failed=$((failed + 1))
    continue
  fi

  log "Starting ${app_name} (${folder})..."
  if (cd "${app_dir}" && docker compose up -d); then
    started=$((started + 1))
  else
    warn "Failed to start ${folder}"
    failed=$((failed + 1))
  fi
done < "${MANIFEST}"

log "Apps started: ${started}, failed: ${failed}"
