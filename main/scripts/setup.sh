#!/usr/bin/env bash
# Interactive setup wizard — tanya nama app & port ke user, buat .env otomatis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/apps.sh"

# $3 = nama variabel output (jangan pakai nama yang sama dengan variabel lokal di sini)
prompt_required() {
  local label="$1" default="${2:-}" __out="$3"
  local prompt _input=""
  while [[ -z "${_input}" ]]; do
    if [[ -n "${default}" ]]; then
      prompt="${label} [${default}]: "
    else
      prompt="${label}: "
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
    if [[ -z "${_input}" ]]; then
      warn "Wajib diisi."
    fi
  done
  printf -v "${__out}" '%s' "${_input}"
}

prompt_port() {
  local label="$1" default="$2" __out="$3" _val=""
  local tries=0
  while true; do
    prompt_required "${label}" "${default}" _val
    _val="${_val//[[:space:]]/}"
    if [[ "${_val}" =~ ^[0-9]+$ ]] && (( 10#${_val} >= 1 && 10#${_val} <= 65535 )); then
      printf -v "${__out}" '%s' "${_val}"
      return 0
    fi
    tries=$((tries + 1))
    if (( tries >= 20 )); then
      die "Terlalu banyak percobaan input port."
    fi
    warn "Port harus angka 1–65535."
  done
}

port_is_taken() {
  local port="$1" exclude_folder="${2:-}"
  local other_folder other_env other_port
  port="${port//[[:space:]]/}"
  while IFS= read -r other_folder; do
    [[ "${other_folder}" == "${exclude_folder}" ]] && continue
    other_env="$(app_dir_for "${other_folder}")/.env"
    [[ -f "${other_env}" ]] || continue
    other_port="$(env_get "${other_env}" "PORT_APP")"
    other_port="${other_port//[[:space:]]/}"
    [[ "${other_port}" == "${port}" ]] && return 0
  done < <(app_list_folders)
  return 1
}

# $1 = variabel output port, $2 = folder yang dikecualikan (opsional)
ask_unique_port() {
  local __out="$1" exclude_folder="${2:-}" suggested port tries=0
  suggested="$(app_suggest_port 3101)"
  while (( tries < 20 )); do
    prompt_port "Port aplikasi" "${suggested}" port
    if port_is_taken "${port}" "${exclude_folder}"; then
      warn "Port ${port} sudah dipakai aplikasi lain. Pilih port lain."
      suggested="$(app_suggest_port $((port + 1)))"
      tries=$((tries + 1))
    else
      printf -v "${__out}" '%s' "${port}"
      return 0
    fi
  done
  die "Terlalu banyak percobaan — port masih bentrok."
}

setup_one_app() {
  local folder="$1"
  local default_name app_name port_app

  default_name="$(app_display_name "${folder}")"
  if [[ "${default_name}" == "${folder}" ]]; then
    default_name="$(app_title_from_folder "${folder}")"
  fi

  echo
  echo "══════════════════════════════════════"
  printf '  Setup aplikasi: %s\n' "${folder}"
  echo "══════════════════════════════════════"
  echo "  Isi nama dan port aplikasi di bawah."
  echo

  prompt_required "Nama aplikasi" "${default_name}" app_name
  ask_unique_port port_app "${folder}"

  app_write_env "${folder}" "${app_name}" "${port_app}"
  app_write_compose_stub "${folder}"

  echo
  log "✓ ${app_name} → apps/${folder}/, port app ${port_app}"
}

setup_new_app() {
  local app_name port_app folder

  echo
  echo "══════════════════════════════════════"
  echo "  Tambah Aplikasi Baru"
  echo "══════════════════════════════════════"
  echo "  Isi nama dan port aplikasi. Folder di apps/ dibuat otomatis."
  echo

  prompt_required "Nama aplikasi" "" app_name
  ask_unique_port port_app
  folder="$(app_folder_from_name "${app_name}")"

  app_write_env "${folder}" "${app_name}" "${port_app}"
  app_write_compose_stub "${folder}"

  echo
  log "✓ ${app_name} → apps/${folder}/, port app ${port_app}"
}

offer_reload() {
  echo
  local reload_choice
  read_tty reload_choice "Jalankan scan & reload launcher sekarang? [Y/n]" ""
  if [[ -z "${reload_choice}" || "${reload_choice}" =~ ^[Yy] ]]; then
    "${SCRIPT_DIR}/scan.sh"
    "${SCRIPT_DIR}/generate-nginx.sh"
    "${SCRIPT_DIR}/generate-html.sh"
    if launcher_is_running; then
      docker compose -f "${MAIN_DIR}/docker-compose.yml" exec -T nginx nginx -s reload
      log "Nginx reloaded"
    fi
  fi
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

  echo
  echo "╔══════════════════════════════════════╗"
  echo "║         Setup Aplikasi               ║"
  echo "╚══════════════════════════════════════╝"
  echo
  echo "  Setiap aplikasi akan ditanyakan:"
  echo "    • Nama aplikasi"
  echo "    • Port aplikasi"
  echo

  if ((${#needs_setup[@]} == 0)); then
    echo "  Semua folder di apps/ sudah punya .env lengkap."
    echo
    local add_new
    read_tty add_new "  Tambah aplikasi baru? [Y/n]" ""
    if [[ -z "${add_new}" || "${add_new}" =~ ^[Yy] ]]; then
      setup_new_app
      offer_reload
    fi
    return 0
  fi

  echo "  0) + Tambah aplikasi baru"
  local i=1
  for folder in "${needs_setup[@]}"; do
    local reason="belum ada .env"
    if app_has_env "${folder}"; then
      reason=".env belum lengkap"
    fi
    printf '  %d) %s — %s\n' "${i}" "${folder}" "${reason}"
    i=$((i + 1))
  done
  echo
  printf 'Pilih (0=baru / all=semua / nomor / 1,3): '
  local choice
  read_tty choice "" ""

  if [[ -z "${choice}" ]]; then
    warn "Dibatalkan — tidak ada pilihan."
    return 0
  fi

  if [[ "${choice}" == "0" ]]; then
    setup_new_app
    offer_reload
    return 0
  fi

  local selected=()
  if ! app_parse_selection "${choice}" needs_setup selected; then
    warn "Pilihan tidak valid."
    return 0
  fi

  for folder in "${selected[@]}"; do
    setup_one_app "${folder}"
  done

  echo
  log "Setup selesai untuk ${#selected[@]} aplikasi."
  offer_reload
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd_setup_interactive
fi
