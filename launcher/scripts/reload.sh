#!/usr/bin/env bash
# Rescan apps, regenerate configs, reload nginx without full restart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

"${SCRIPT_DIR}/scan.sh"
"${SCRIPT_DIR}/generate-nginx.sh"
"${SCRIPT_DIR}/generate-html.sh"

if docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" ps --status running -q nginx 2>/dev/null | grep -q .; then
  log "Reloading nginx configuration..."
  docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" exec -T nginx nginx -s reload
  log "Nginx reloaded"
else
  warn "Launcher nginx is not running — start with: ./launcher.sh start"
fi
