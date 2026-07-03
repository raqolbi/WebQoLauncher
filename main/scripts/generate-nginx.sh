#!/usr/bin/env bash
# Generate nginx.conf from apps.manifest

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ensure_dirs

if [[ ! -f "${MANIFEST}" ]]; then
  die "Manifest not found. Run scan.sh first."
fi

# Emit reverse-proxy locations for one app (Next.js / SPA-safe)
emit_app_proxy_locations() {
  local folder="$1" app_path="$2" app_spa="$3"
  local location_path="/${app_path}"
  local location_path_regex upstream_name safe_folder is_spa=false

  location_path_regex="$(nginx_regex_escape "${location_path}")"
  safe_folder="${folder//[^a-zA-Z0-9_]/_}"
  upstream_name="app_${safe_folder}"

  if [[ "${app_spa}" == "false" || "${app_spa}" == "0" || "${app_spa}" == "no" ]]; then
    is_spa=false
  else
    # Default: SPA/Next.js fallback ON (APP_SPA=true atau tidak diset)
    is_spa=true
  fi

  cat <<NGINX_APP_HEADER

        # ── App: ${folder} (path ${location_path}) ─────────────────────
        # Reverse proxy ke container app di host.docker.internal.
NGINX_APP_HEADER

  if [[ "${is_spa}" == "true" ]]; then
    cat <<NGINX_SPA

        # Tanpa trailing slash → redirect ke path/
        location = ${location_path} {
            return 301 ${location_path}/;
        }

        # Next.js build output — jangan pernah di-fallback ke index.html
        # GET /${app_path}/_next/static/... → file asli di upstream
        location ~* ^${location_path_regex}/_next/ {
            rewrite ^${location_path_regex}/(.*)\$ /\$1 break;
            proxy_pass http://${upstream_name};
            include /etc/nginx/proxy_params_extra.conf;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Asset statis (css, js, gambar, font) — file asli
        location ~* ^${location_path_regex}/(.+\.(?:css|js|mjs|map|jpg|jpeg|png|gif|ico|svg|webp|woff2?|ttf|eot))\$ {
            rewrite ^${location_path_regex}/(.*)\$ /\$1 break;
            proxy_pass http://${upstream_name};
            include /etc/nginx/proxy_params_extra.conf;
            expires 7d;
            add_header Cache-Control "public";
        }

        # Folder public/assets/
        location ${location_path}/assets/ {
            proxy_pass http://${upstream_name}/assets/;
            include /etc/nginx/proxy_params_extra.conf;
            expires 7d;
            add_header Cache-Control "public";
        }

        # Semua route lain (/login, /dashboard, ...) — SPA fallback
        # Upstream mengembalikan 404 → layani index.html
        location ${location_path}/ {
            proxy_pass http://${upstream_name}/;
            include /etc/nginx/proxy_params_extra.conf;
            proxy_intercept_errors on;
            error_page 404 = @${safe_folder}_spa_fallback;
        }

        location @${safe_folder}_spa_fallback {
            proxy_pass http://${upstream_name}/index.html;
            include /etc/nginx/proxy_params_extra.conf;
        }
NGINX_SPA
  else
    cat <<NGINX_API

        # Mode API (APP_SPA=false) — tanpa fallback index.html
        location = ${location_path} {
            return 301 ${location_path}/;
        }

        location ${location_path}/ {
            proxy_pass http://${upstream_name}/;
            include /etc/nginx/proxy_params_extra.conf;
            proxy_cache_bypass \$http_upgrade;
        }
NGINX_API
  fi
}

tmp_conf="$(mktemp)"
trap 'rm -f "${tmp_conf}"' EXIT

{
  cat <<'NGINX_HEADER'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    http2 on;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/xml
        image/svg+xml;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

NGINX_HEADER

  if [[ -s "${MANIFEST}" ]]; then
    while IFS=$'\t' read -r folder _ port_app _ _ _ _; do
      [[ -n "${folder}" ]] || continue
      safe_id="${folder//[^a-zA-Z0-9_]/_}"
      cat <<NGINX_UPSTREAM

    upstream app_${safe_id} {
        server host.docker.internal:${port_app};
        keepalive 32;
    }
NGINX_UPSTREAM
    done < "${MANIFEST}"
  fi

  cat <<'NGINX_SERVER'

    server {
        listen 80;
        server_name _;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

        # Portal launcher — halaman daftar aplikasi
        location = / {
            root /usr/share/nginx/html;
            try_files /index.html =404;
        }

        location /assets/ {
            root /usr/share/nginx/html;
            expires 7d;
            add_header Cache-Control "public, immutable";
        }

NGINX_SERVER

  if [[ ! -s "${MANIFEST}" ]]; then
    cat <<'NGINX_EMPTY'
        location / {
            default_type text/html;
            return 200 '<!DOCTYPE html><html><head><title>WebQoLauncher</title></head><body><h1>No applications found</h1></body></html>';
        }
NGINX_EMPTY
  else
    while IFS=$'\t' read -r folder _ _ app_path _ _ app_spa; do
      [[ -n "${folder}" ]] || continue
      emit_app_proxy_locations "${folder}" "${app_path}" "${app_spa}"
    done < "${MANIFEST}"
  fi

  cat <<'NGINX_FOOTER'
    }
}
NGINX_FOOTER

} > "${tmp_conf}"

mv "${tmp_conf}" "${NGINX_CONF}"
trap - EXIT
log "Generated nginx.conf → ${NGINX_CONF}"
