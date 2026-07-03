#!/usr/bin/env bash
# WebQoLauncher — main orchestration script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
WebQoLauncher — Docker + Nginx application portal

Usage: $(basename "$0") <command>

Commands:
  menu        Interactive menu (default when no command given)
  start       Scan apps, generate configs, start all apps + launcher nginx
  stop        Stop launcher nginx and all apps
  restart     stop then start
  reload      Rescan, regenerate configs, reload nginx (start new apps if needed)
  sync-nginx  Update nginx.conf semua app dari template + pastikan mount di compose
  setup       Interactive wizard to create .env per app
  scan        Scan apps/ and write manifest only
  status      Show running containers for launcher and apps
  help        Show this help

Examples:
  ./launcher.sh start
  ./launcher.sh reload
  ./launcher.sh stop
EOF
}

cmd_scan() {
  "${SCRIPT_DIR}/scan.sh"
  "${SCRIPT_DIR}/generate-nginx.sh"
  "${SCRIPT_DIR}/generate-html.sh"
}

cmd_start() {
  cmd_scan
  "${SCRIPT_DIR}/start-apps.sh"

  log "Starting launcher nginx..."
  docker compose -f "${MAIN_DIR}/docker-compose.yml" up -d --remove-orphans

  local port
  port="$(env_get "${MAIN_DIR}/.env" "LAUNCHER_PORT" "8080")"
  log "Launcher ready → http://localhost:${port}"
}

cmd_stop() {
  log "Stopping launcher nginx..."
  docker compose -f "${MAIN_DIR}/docker-compose.yml" down || true
  "${SCRIPT_DIR}/stop-apps.sh"
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_reload() {
  "${SCRIPT_DIR}/reload.sh"
  "${SCRIPT_DIR}/start-apps.sh"
}

cmd_sync_nginx() {
  source "${SCRIPT_DIR}/lib/apps.sh"
  local force="${1:-false}"
  if [[ "${force}" == "--force" ]]; then
    force=true
  else
    force=false
  fi
  app_sync_all_nginx "${force}"
  log "Selesai. Recreate container yang berjalan:"
  log "  cd apps/<nama> && docker compose up -d --force-recreate"
}

cmd_status() {
  source "${SCRIPT_DIR}/lib/apps.sh"
  print_full_status
}

main() {
  local cmd="${1:-menu}"
  shift || true

  case "${cmd}" in
    menu)    bash "${SCRIPT_DIR}/menu.sh" ;;
    start)   cmd_start "$@" ;;
    stop)    cmd_stop "$@" ;;
    restart) cmd_restart "$@" ;;
    reload)      cmd_reload "$@" ;;
    sync-nginx)  cmd_sync_nginx "$@" ;;
    scan)        cmd_scan "$@" ;;
    setup)   bash "${SCRIPT_DIR}/setup.sh" ;;
    status)  cmd_status "$@" ;;
    help|-h|--help) usage ;;
    *) die "Unknown command: ${cmd}. Run '$(basename "$0") help' for usage." ;;
  esac
}

main "$@"
