#!/usr/bin/env bash
# Interactive setup wizard — buat .env per aplikasi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/apps.sh"

prompt_line() {
  local label="$1" default="${2:-}" answer
  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${label}" "${default}"
  else
    printf '%s: ' "${label}"
  fi
  IFS= read -r answer || answer=""
  if [[ -z "${answer}" && -n "${default}" ]]; then
    answer="${default}"
  fi
  printf '%s' "${answer}"
}

setup_one_app() {
  local folder="$1"
  local default_name default_port app_name port_app

  default_name="$(app_display_name "${folder}")"
  if [[ "${default_name}" == "${folder}" ]]; then
    default_name="${folder//-/ }"
    default_name="$(echo "${default_name}" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')"
  fi

  default_port="$(app_suggest_port 3101)"

  echo
  printf '── Setup: %s ──\n' "${folder}"

  app_name="$(prompt_line "APP_NAME" "${default_name}")"
  while [[ -z "${app_name}" ]]; do
    warn "APP_NAME wajib diisi"
    app_name="$(prompt_line "APP_NAME" "${default_name}")"
  done

  port_app="$(prompt_line "PORT_APP" "${default_port}")"
  while [[ -z "${port_app}" ]] || ! [[ "${port_app}" =~ ^[0-9]+$ ]]; do
    warn "PORT_APP harus angka"
    port_app="$(prompt_line "PORT_APP" "${default_port}")"
  done

  # Pastikan port unik
  while true; do
    local conflict=false
    while IFS= read -r other_folder; do
      [[ "${other_folder}" == "${folder}" ]] && continue
      other_env="$(app_dir_for "${other_folder}")/.env"
      [[ -f "${other_env}" ]] || continue
      other_port="$(env_get "${other_env}" "PORT_APP")"
      if [[ "${other_port}" == "${port_app}" ]]; then
        conflict=true
        break
      fi
    done < <(app_list_folders)

    if [[ "${conflict}" == "false" ]]; then
      break
    fi

    warn "Port ${port_app} sudah dipakai app lain"
    default_port="$(app_suggest_port $((port_app + 1)))"
    port_app="$(prompt_line "PORT_APP (unik)" "${default_port}")"
    while [[ -z "${port_app}" ]] || ! [[ "${port_app}" =~ ^[0-9]+$ ]]; do
      warn "PORT_APP harus angka"
      port_app="$(prompt_line "PORT_APP (unik)" "${default_port}")"
    done
  done

  app_write_env "${folder}" "${app_name}" "${port_app}"
}

cmd_setup_interactive() {
  local needs_setup=()
  local folder

  mkdir -p "${APPS_DIR}"

  while IFS= read -r folder; do
    [[ -n "${folder}" ]] || continue
    if ! app_env_complete "${folder}"; then
      needs_setup+=("${folder}")
    fi
  done < <(app_list_folders)

  if ((${#needs_setup[@]} == 0)); then
    log "Semua aplikasi di apps/ sudah punya .env lengkap."
    printf 'Buat folder baru di apps/ lalu jalankan Setup lagi, atau ketik nama folder baru: '
    local new_folder
    IFS= read -r new_folder || new_folder=""
    new_folder="$(echo "${new_folder}" | tr -d '[:space:]')"
    if [[ -z "${new_folder}" ]]; then
      return 0
    fi
    if [[ ! "${new_folder}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
      die "Nama folder tidak valid: ${new_folder}"
    fi
    needs_setup=("${new_folder}")
  fi

  echo
  echo "Aplikasi yang perlu setup:"
  local i=1
  for folder in "${needs_setup[@]}"; do
    local reason="belum ada .env"
    if app_has_env "${folder}"; then
      reason=".env tidak lengkap"
    fi
    printf '  %d) %s (%s)\n' "${i}" "${folder}" "${reason}"
    i=$((i + 1))
  done
  echo
  printf 'Pilih yang akan di-setup (all / nomor / 1,3): '
  local choice
  IFS= read -r choice || choice=""

  local selected=()
  app_parse_selection "${choice}" needs_setup selected || die "Pilihan tidak valid"

  for folder in "${selected[@]}"; do
    setup_one_app "${folder}"
  done

  echo
  log "Setup selesai untuk ${#selected[@]} aplikasi."
  printf 'Jalankan scan & reload launcher sekarang? [Y/n]: '
  local reload_choice
  IFS= read -r reload_choice || reload_choice=""
  if [[ -z "${reload_choice}" || "${reload_choice}" =~ ^[Yy] ]]; then
    "${SCRIPT_DIR}/scan.sh"
    "${SCRIPT_DIR}/generate-nginx.sh"
    "${SCRIPT_DIR}/generate-html.sh"
    if launcher_is_running; then
      docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" exec -T nginx nginx -s reload
      log "Nginx reloaded"
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd_setup_interactive
fi
