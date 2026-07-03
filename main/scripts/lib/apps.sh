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
  local env_file port_app
  env_file="$(app_dir_for "${folder}")/.env"
  [[ -f "${env_file}" ]] || return 1
  [[ -n "$(env_get "${env_file}" "APP_NAME")" ]] || return 1
  port_app="$(env_get "${env_file}" "PORT_APP")"
  [[ -n "${port_app}" ]] || return 1
  [[ "${port_app}" =~ ^[0-9]+$ ]] || return 1
  (( port_app >= 1 && port_app <= 65535 )) || return 1
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
  docker compose -f "${MAIN_DIR}/docker-compose.yml" ps --status running -q nginx 2>/dev/null | grep -q .
}

portal_port() {
  env_get "${MAIN_DIR}/.env" "LAUNCHER_PORT" "8080"
}

app_url_path() {
  local folder="$1"
  local env_file path
  env_file="$(app_dir_for "${folder}")/.env"
  if [[ -f "${env_file}" ]]; then
    path="$(env_get "${env_file}" "APP_PATH" "${folder}")"
  else
    path="${folder}"
  fi
  path="${path#/}"
  path="${path%/}"
  printf '/%s/' "${path}"
}

app_container_name() {
  local folder="$1"
  printf 'webqo-app-%s' "${folder//[^a-zA-Z0-9_.-]/-}"
}

app_write_nginx_conf() {
  local folder="$1"
  local app_dir nginx_conf template
  app_dir="$(app_dir_for "${folder}")"
  nginx_conf="${app_dir}/nginx.conf"
  template="${MAIN_DIR}/templates/app-nginx.conf"

  if [[ -f "${nginx_conf}" ]]; then
    return 0
  fi

  if [[ ! -f "${template}" ]]; then
    warn "Template tidak ditemukan: ${template}"
    return 1
  fi

  cp "${template}" "${nginx_conf}"
  chmod 644 "${nginx_conf}"
  log "Dibuat ${nginx_conf} (Next.js / SPA fallback)"
}

# Template docker-compose + public/ untuk app baru (bisa diganti user nanti)
app_write_compose_stub() {
  local folder="$1"
  local app_dir public_dir index_file cname
  app_dir="$(app_dir_for "${folder}")"
  public_dir="${app_dir}/public"
  index_file="${public_dir}/index.html"
  cname="$(app_container_name "${folder}")"

  mkdir -p "${public_dir}"

  if [[ ! -f "${index_file}" ]]; then
    cat > "${index_file}" <<EOF
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <title>$(app_display_name "${folder}")</title>
</head>
<body>
  <h1>$(app_display_name "${folder}")</h1>
  <p>Placeholder — salin hasil <code>next build</code> (folder <code>out/</code>) ke <code>public/</code>.</p>
</body>
</html>
EOF
    chmod 644 "${index_file}"
  fi

  app_write_nginx_conf "${folder}"

  if [[ -f "${app_dir}/docker-compose.yml" ]]; then
    return 0
  fi

  cat > "${app_dir}/docker-compose.yml" <<EOF
services:
  app:
    image: nginx:1.27-alpine
    container_name: ${cname}
    ports:
      - "\${PORT_APP}:80"
    volumes:
      - ./public:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    restart: unless-stopped
EOF
  chmod 644 "${app_dir}/docker-compose.yml"
  log "Dibuat ${app_dir}/docker-compose.yml (+ nginx.conf Next.js)"
}

app_ensure_compose() {
  local folder="$1"
  app_write_nginx_conf "${folder}" || true
  if app_has_compose "${folder}"; then
    return 0
  fi
  warn "App ${folder} belum punya docker-compose.yml — membuat template otomatis."
  app_write_compose_stub "${folder}"
}

app_compose_ps() {
  local folder="$1"
  local app_dir
  app_dir="$(app_dir_for "${folder}")"
  [[ -f "${app_dir}/docker-compose.yml" ]] || return 1
  (cd "${app_dir}" && docker compose ps 2>/dev/null)
}

app_print_info() {
  local folder="$1"
  local app_dir port path
  app_dir="$(app_dir_for "${folder}")"
  port="$(app_port "${folder}")"
  path="$(app_url_path "${folder}")"
  local portal
  portal="$(portal_port)"

  printf '  Nama     : %s\n' "$(app_display_name "${folder}")"
  printf '  Folder   : apps/%s/\n' "${folder}"
  printf '  Port app : %s  (docker compose, bukan portal)\n' "${port:-?}"
  printf '  URL app  : http://localhost:%s\n' "${port:-?}"
  if launcher_is_running; then
    printf '  URL proxy: http://localhost:%s%s\n' "${portal}" "${path}"
  else
    printf '  URL proxy: (portal nginx belum jalan — port %s)\n' "${portal}"
  fi
  printf '  Compose  : %s\n' "${app_dir}/docker-compose.yml"
  printf '  Status   : %s\n' "$(app_status_label "${folder}")"
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

  while (( port <= 65535 )); do
    local taken=false
    for u in "${used_ports[@]}"; do
      u="${u//[[:space:]]/}"
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
  die "Semua port 3101–65535 sudah terpakai"
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
  app_ensure_compose "${folder}"

  log "Starting $(app_display_name "${folder}") (${folder})..."
  if ! (cd "${app_dir}" && docker compose up -d); then
    warn "Gagal start ${folder} — cek: cd apps/${folder} && docker compose up -d"
    return 1
  fi
  log "App berjalan di http://localhost:$(app_port "${folder}")"
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
  local follow="${2:-true}"
  local app_dir
  app_dir="$(app_dir_for "${folder}")"

  app_has_compose "${folder}" || die "App ${folder} tidak punya docker-compose.yml"

  echo
  echo "══════════════════════════════════════"
  printf '  Docker logs: %s\n' "$(app_display_name "${folder}")"
  echo "══════════════════════════════════════"
  app_print_info "${folder}"
  echo
  echo "── Container ──"
  if ! app_compose_ps "${folder}"; then
    warn "Tidak ada container (app belum pernah dijalankan?)"
  fi
  echo
  echo "── Log output (Ctrl+C untuk keluar) ──"
  if [[ "${follow}" == "true" ]]; then
    (cd "${app_dir}" && docker compose logs -f --tail=100)
  else
    (cd "${app_dir}" && docker compose logs --tail=100)
  fi
}

portal_logs() {
  echo
  echo "══════════════════════════════════════"
  echo "  Docker logs: Portal Nginx"
  echo "══════════════════════════════════════"
  printf '  Port portal : %s\n' "$(portal_port)"
  printf '  Compose     : %s/docker-compose.yml\n' "${MAIN_DIR}"
  echo
  echo "── Container ──"
  docker compose -f "${MAIN_DIR}/docker-compose.yml" ps 2>/dev/null || warn "Portal tidak berjalan"
  echo
  echo "── Log output (Ctrl+C untuk keluar) ──"
  docker compose -f "${MAIN_DIR}/docker-compose.yml" logs -f --tail=100
}

print_full_status() {
  local portal folder
  portal="$(portal_port)"

  echo
  log "Portal Nginx (reverse proxy):"
  if launcher_is_running; then
    printf '  Status : RUNNING\n'
    printf '  URL    : http://localhost:%s\n' "${portal}"
    printf '  Port   : %s  ← ini port portal, BUKAN port app\n' "${portal}"
    docker compose -f "${MAIN_DIR}/docker-compose.yml" ps 2>/dev/null | sed 's/^/  /' || true
  else
    printf '  Status : STOPPED\n'
    printf '  URL    : http://localhost:%s (belum aktif)\n' "${portal}"
    printf '  Port   : %s  ← jalankan menu Run + pilih portal, atau ./launcher.sh start\n' "${portal}"
  fi

  echo
  log "Aplikasi:"
  local found=0
  while IFS= read -r folder; do
    [[ -n "${folder}" ]] || continue
    app_env_complete "${folder}" || continue
    found=1
    echo
    app_print_info "${folder}"
    if app_has_compose "${folder}"; then
      echo "  Container:"
      app_compose_ps "${folder}" | sed 's/^/    /' || echo "    (belum ada container)"
    else
      echo "  Container: (belum ada docker-compose.yml)"
    fi
  done < <(app_list_folders)

  if (( found == 0 )); then
    echo "  (belum ada app terkonfigurasi — gunakan menu Setup)"
  fi
  echo
}

app_write_env() {
  local folder="$1" app_name="$2" port_app="$3"
  local app_dir env_file
  app_dir="$(app_dir_for "${folder}")"
  env_file="${app_dir}/.env"

  mkdir -p "${app_dir}"
  {
    printf 'APP_NAME=%s\n' "$(env_format "${app_name}")"
    printf 'PORT_APP=%s\n' "${port_app}"
    printf 'APP_PATH=%s\n' "$(env_format "${folder}")"
  } > "${env_file}"
  chmod 644 "${env_file}"
  log "Dibuat ${env_file}"
}

# Slug untuk nama folder dari nama aplikasi, mis. "Point Of Sale" → "point-of-sale"
app_slug_from_name() {
  local s="$1"
  s="$(printf '%s' "${s}" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "${s}" | sed 's/[^a-z0-9_-]/-/g; s/-\+/-/g; s/^-//; s/-$//')"
  printf '%s' "${s}"
}

app_title_from_folder() {
  local folder="$1"
  printf '%s' "${folder}" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}'
}

# Folder otomatis dari nama aplikasi; tambah suffix jika sudah ada & terkonfigurasi
app_folder_from_name() {
  local app_name="$1"
  local base folder n=2

  base="$(app_slug_from_name "${app_name}")"
  [[ -n "${base}" ]] || base="app"

  folder="${base}"
  while [[ -d "$(app_dir_for "${folder}")" ]] && app_env_complete "${folder}"; do
    folder="${base}-${n}"
    n=$((n + 1))
  done

  printf '%s' "${folder}"
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

  local token idx seen=""
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
    # Hindari duplikat (mis. input "1,1")
    if [[ " ${seen} " != *" ${idx} "* ]]; then
      _out+=("${_items[idx]}")
      seen+="${idx} "
    fi
  done

  ((${#_out[@]} > 0))
}
