#!/usr/bin/env bash
# Start docker compose for every discovered application

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/apps.sh"

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

  app_sync_nginx_conf "${folder}" false || true
  app_ensure_nginx_mount "${folder}" || true

  if ! app_start "${folder}"; then
    failed=$((failed + 1))
    continue
  fi
  started=$((started + 1))
done < "${MANIFEST}"

log "Apps started: ${started}, failed: ${failed}"
