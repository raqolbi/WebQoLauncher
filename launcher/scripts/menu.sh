#!/usr/bin/env bash
# Interactive menu for WebQoLauncher

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/apps.sh"

LAUNCHER_SCRIPT="${SCRIPT_DIR}/launcher.sh"

banner() {
  local port
  port="$(env_get "${LAUNCHER_DIR}/.env" "LAUNCHER_PORT" "8080")"
  echo
  echo "╔══════════════════════════════════════╗"
  echo "║         WebQoLauncher Menu           ║"
  echo "╚══════════════════════════════════════╝"
  if launcher_is_running; then
    printf '  Launcher: RUNNING → http://localhost:%s\n' "${port}"
  else
    printf '  Launcher: STOPPED (port %s)\n' "${port}"
  fi
  echo
}

main_menu() {
  echo "  1) Run        — jalankan app (+ launcher)"
  echo "  2) Stop       — hentikan app / launcher"
  echo "  3) Restart    — restart app / launcher"
  echo "  4) Logs       — tail log docker compose"
  echo "  5) Apps       — daftar aplikasi"
  echo "  6) Setup      — buat / lengkapi .env per app"
  echo "  7) Status     — status container"
  echo "  8) Reload     — rescan + regenerate nginx"
  echo "  9) Exit"
  echo
  printf 'Pilih [1-9]: '
}

# Build list of configured apps (valid .env)
list_configured_apps() {
  local out=()
  local folder
  while IFS= read -r folder; do
    [[ -n "${folder}" ]] || continue
    app_env_complete "${folder}" && out+=("${folder}")
  done < <(app_list_folders)
  printf '%s\n' "${out[@]}"
}

list_running_apps() {
  local out=()
  local folder
  while IFS= read -r folder; do
    [[ -n "${folder}" ]] || continue
    app_is_running "${folder}" && out+=("${folder}")
  done < <(app_list_folders)
  printf '%s\n' "${out[@]}"
}

print_app_list() {
  local -n _folders=$1
  local show_port="${2:-true}"
  local i=1
  for folder in "${_folders[@]}"; do
    local status port_info=""
    status="$(app_status_label "${folder}")"
    if [[ "${show_port}" == "true" ]] && app_env_complete "${folder}"; then
      port_info=" :$(app_port "${folder}")"
    fi
    printf '  %d) %s (%s)%s [%s]\n' "${i}" "$(app_display_name "${folder}")" "${folder}" "${port_info}" "${status}"
    i=$((i + 1))
  done
}

prompt_app_selection() {
  local -n _available=$1
  local -n _selected=$2
  local prompt_msg="${3:-Pilih aplikasi (all / nomor / 1,3): }"

  if ((${#_available[@]} == 0)); then
    warn "Tidak ada aplikasi tersedia."
    return 1
  fi

  echo
  print_app_list _available
  echo
  printf '%s' "${prompt_msg}"
  local choice
  IFS= read -r choice || choice=""
  app_parse_selection "${choice}" _available _selected
}

ask_launcher_too() {
  printf 'Sertakan launcher nginx? [Y/n]: '
  local ans
  IFS= read -r ans || ans=""
  [[ -z "${ans}" || "${ans}" =~ ^[Yy] ]]
}

regenerate_if_needed() {
  "${SCRIPT_DIR}/scan.sh"
  "${SCRIPT_DIR}/generate-nginx.sh"
  "${SCRIPT_DIR}/generate-html.sh"
  if launcher_is_running; then
    docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" exec -T nginx nginx -s reload 2>/dev/null || true
  fi
}

menu_run() {
  local configured=()
  mapfile -t configured < <(list_configured_apps)

  if ((${#configured[@]} == 0)); then
    warn "Belum ada app terkonfigurasi. Gunakan menu Setup dulu."
    return
  fi

  local selected=()
  prompt_app_selection configured selected "Pilih app yang dijalankan (all / nomor / 1,3): " || return

  regenerate_if_needed

  local folder
  for folder in "${selected[@]}"; do
    app_start "${folder}" || warn "Gagal start ${folder}"
  done

  if ask_launcher_too; then
    log "Starting launcher nginx..."
    docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" up -d --remove-orphans
    local port
    port="$(env_get "${LAUNCHER_DIR}/.env" "LAUNCHER_PORT" "8080")"
    log "Launcher → http://localhost:${port}"
  fi
}

menu_stop() {
  local running=()
  mapfile -t running < <(list_running_apps)

  echo
  echo "App yang sedang running:"
  if ((${#running[@]} == 0)); then
    echo "  (tidak ada)"
  else
    print_app_list running
  fi

  if launcher_is_running; then
    echo
    echo "  Launcher nginx: [running]"
  fi

  echo
  printf 'Pilih (all=semua app / nomor / 1,3 / L=launcher saja / q=batal): '
  local choice
  IFS= read -r choice || choice="q"

  if [[ "${choice}" =~ ^[Qq]$ ]]; then
    return
  fi

  if [[ "${choice}" =~ ^[Ll]$ ]]; then
    log "Stopping launcher nginx..."
    docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" down || true
    return
  fi

  local selected=()
  if [[ "${choice}" == "all" ]]; then
    selected=("${running[@]}")
  elif [[ -n "${choice}" ]]; then
    app_parse_selection "${choice}" running selected || { warn "Pilihan tidak valid"; return; }
  else
    return
  fi

  local folder
  for folder in "${selected[@]}"; do
    app_stop "${folder}" || true
  done

  if [[ "${choice}" == "all" ]] && launcher_is_running; then
    printf 'Stop launcher nginx juga? [y/N]: '
    local ans
    IFS= read -r ans || ans=""
    if [[ "${ans}" =~ ^[Yy]$ ]]; then
      docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" down || true
    fi
  fi
}

menu_restart() {
  local running=()
  mapfile -t running < <(list_running_apps)

  # Untuk restart, izinkan juga app configured yang stopped
  local configured=()
  mapfile -t configured < <(list_configured_apps)

  if ((${#configured[@]} == 0)); then
    warn "Belum ada app terkonfigurasi."
    return
  fi

  local selected=()
  prompt_app_selection configured selected "Pilih app untuk di-restart (all / nomor / 1,3): " || return

  regenerate_if_needed

  local folder
  for folder in "${selected[@]}"; do
    app_restart "${folder}" || warn "Gagal restart ${folder}"
  done

  if ask_launcher_too; then
    docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" up -d --remove-orphans
    if launcher_is_running; then
      docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" exec -T nginx nginx -s reload
    fi
  fi
}

menu_logs() {
  local running=()
  mapfile -t running < <(list_running_apps)

  if ((${#running[@]} == 0)); then
    warn "Tidak ada app yang sedang running."
    return
  fi

  local selected=()
  prompt_app_selection running selected "Pilih app untuk logs (nomor): " || return

  if ((${#selected[@]} != 1)); then
    warn "Logs hanya untuk satu app. Pilih satu nomor."
    return
  fi

  app_logs "${selected[0]}"
}

menu_apps() {
  local folders=()
  mapfile -t folders < <(app_list_folders)

  echo
  if ((${#folders[@]} == 0)); then
    echo "  Folder apps/ masih kosong."
    return
  fi

  print_app_list folders
  echo
}

menu_setup() {
  "${SCRIPT_DIR}/setup.sh"
}

menu_status() {
  bash "${LAUNCHER_SCRIPT}" status
}

menu_reload() {
  bash "${LAUNCHER_SCRIPT}" reload
}

run_menu() {
  while true; do
    banner
    main_menu
    local choice
    IFS= read -r choice || choice="9"

    case "${choice}" in
      1) menu_run ;;
      2) menu_stop ;;
      3) menu_restart ;;
      4) menu_logs ;;
      5) menu_apps ;;
      6) menu_setup ;;
      7) menu_status ;;
      8) menu_reload ;;
      9|q|Q|exit) echo "Bye."; exit 0 ;;
      *) warn "Pilihan tidak valid." ;;
    esac

    echo
    printf 'Tekan Enter untuk kembali ke menu...'
    IFS= read -r _
  done
}

run_menu
