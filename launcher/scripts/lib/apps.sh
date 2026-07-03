#!/usr/bin/env bash
# Per-application operations for WebQoLauncher.

# List folder names under apps/ (sorted).
app_list_folders() {
  local folders=()
  if [[ -d "${APPS_DIR}" ]]; then
    local d
    for d in "${APPS_DIR}"/*/; do
      [[ -d "${d}" ]] || continue
      folders+=("$(basename "${d%/}")")
    done
  fi
  if ((${#folders[@]} > 0)); then
    printf '%s\n' "${folders[@]}" | sort
  fi
}

app_dir_for() {
  printf '%s' "${APPS_DIR}/$1"
}

app_has_env() {
  [[ -f "$(app_dir_for "$1")/.env" ]]
}

app_has_compose() {
  [[ -f "$(app_dir_for "$1")/docker-compose.yml" ]]
}

app_env_complete() {
  local folder="$1"
  local env_file
  env_file="$(app_dir_for "${folder}")/.env"
  [[ -f "${env_file}" ]] || return 1
  [[ -n "$(env_get "${env_file}" "APP_NAME")" ]] || return 1
  [[ -n "$(env_get "${env_file}" "PORT_APP")" ]] || return 1
  return 0
}

app_is_running() {
  local folder="$1"
  local app_dir
  app_dir="$(app_dir_for "${folder}")"
  [[ -f "${app_dir}/docker-compose.yml" ]] || return 1
  docker compose -f "${app_dir}/docker-compose.yml" ps --status running -q 2>/dev/null | grep -q .
}

launcher_is_running() {
  docker compose -f "${LAUNCHER_DIR}/docker-compose.yml" ps --status running -q nginx 2>/dev/null | grep -q .
}

# Collect PORT_APP values already used in apps/.
app_used_ports() {
  local folder env_file port
  while IFS= read -r folder; do
    [[ -n "${folder}" ]] || continue
    env_file="$(app_dir_for "${folder}")/.env"
    [[ -f "${env_file}" ]] || continue
    port="$(env_get "${env_file}" "PORT_APP")"
    [[ -n "${port}" ]] && printf '%s\n' "${port}"
  done < <(app_list_folders)
}

app_suggest_port() {
  local base="${1:-3101}"
  local used port="${base}"
  local used_ports
  mapfile -t used_ports < <(app_used_ports | sort -n | uniq)

  while true; do
    local taken=false
    for u in "${used_ports[@]}"; do
      if [[ "${u}" == "${port}" ]]; then
        taken=true
        break
      fi
    done
    if [[ "${taken}" == "false" ]]; then
      printf '%s' "${port}"
      return 0
    fi
    port=$((port + 1))
  done
}

app_display_name() {
  local folder="$1"
  local env_file
  env_file="$(app_dir_for "${folder}")/.env"
  if [[ -f "${env_file}" ]]; then
    local name
    name="$(env_get "${env_file}" "APP_NAME")"
    [[ -n "${name}" ]] && printf '%s' "${name}" && return 0
  fi
  printf '%s' "${folder}"
}

app_port() {
  local folder="$1"
  local env_file
  env_file="$(app_dir_for "${folder}")/.env"
  env_get "${env_file}" "PORT_APP"
}

app_status_label() {
  local folder="$1"
  if ! app_env_complete "${folder}"; then
    printf 'belum setup'
    return
  fi
  if ! app_has_compose "${folder}"; then
    printf 'no compose'
    return
  fi
  if app_is_running "${folder}"; then
    printf 'running'
  else
    printf 'stopped'
  fi
}

app_start() {
  local folder="$1"
  local app_dir
  app_dir="$(app_dir_for "${folder}")"

  app_env_complete "${folder}" || die "App ${folder} belum dikonfigurasi (.env)"
  app_has_compose "${folder}" || die "App ${folder} tidak punya docker-compose.yml"

  log "Starting $(app_display_name "${folder}") (${folder})..."
  (cd "${app_dir}" && docker compose up -d)
}

app_stop() {
  local folder="$1"
  local app_dir
  app_dir="$(app_dir_for "${folder}")"

  app_has_compose "${folder}" || die "App ${folder} tidak punya docker-compose.yml"

  log "Stopping $(app_display_name "${folder}") (${folder})..."
  (cd "${app_dir}" && docker compose down) || warn "Gagal stop ${folder}"
}

app_restart() {
  local folder="$1"
  app_stop "${folder}"
  app_start "${folder}"
}

app_logs() {
  local folder="$1"
  local app_dir
  app_dir="$(app_dir_for "${folder}")"

  app_has_compose "${folder}" || die "App ${folder} tidak punya docker-compose.yml"

  log "Logs $(app_display_name "${folder}") — Ctrl+C untuk keluar"
  (cd "${app_dir}" && docker compose logs -f --tail=100)
}

app_write_env() {
  local folder="$1" app_name="$2" port_app="$3"
  local app_dir env_file
  app_dir="$(app_dir_for "${folder}")"
  env_file="${app_dir}/.env"

  mkdir -p "${app_dir}"
  cat > "${env_file}" <<EOF
APP_NAME=${app_name}
PORT_APP=${port_app}
APP_PATH=${folder}
EOF
  chmod 644 "${env_file}"
  log "Dibuat ${env_file}"
}

# Parse selection: "all", "1", "1,3", "1 3"
# $1=input  $2=name of array variable for folder names (must be pre-filled list)
app_parse_selection() {
  local input="$1"
  local -n _items=$2
  local -n _out=$3
  _out=()

  input="$(echo "${input}" | tr -d '[:space:]' | tr ',' ' ')"

  if [[ -z "${input}" ]]; then
    return 1
  fi

  if [[ "${input}" == "all" || "${input}" == "*" ]]; then
    _out=("${_items[@]}")
    return 0
  fi

  local token idx
  for token in ${input}; do
    if ! [[ "${token}" =~ ^[0-9]+$ ]]; then
      warn "Pilihan tidak valid: ${token}"
      return 1
    fi
    idx=$((token - 1))
    if (( idx < 0 || idx >= ${#_items[@]} )); then
      warn "Nomor di luar range: ${token}"
      return 1
    fi
    _out+=("${_items[idx]}")
  done

  ((${#_out[@]} > 0))
}
