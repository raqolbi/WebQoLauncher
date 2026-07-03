#!/usr/bin/env bash
# Generate host-level SSL vhost for domain → PORT_APP (di luar Docker)
# Usage: generate-host-vhost.sh <app-folder> <domain>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/apps.sh"

folder="${1:-}"
domain="${2:-}"

if [[ -z "${folder}" || -z "${domain}" ]]; then
  cat <<EOF
Usage: $(basename "$0") <app-folder> <domain>

Contoh:
  $(basename "$0") ho-fe ho.superoti.tuas.my.id

Menulis apps/<folder>/host-nginx.conf — salin ke server SSL (nginx di host).
EOF
  exit 1
fi

app_env_complete "${folder}" || die "App ${folder} belum dikonfigurasi"

port="$(app_port "${folder}")"
template="${MAIN_DIR}/templates/host-vhost-ssl.conf"
out="$(app_dir_for "${folder}")/host-nginx.conf"

[[ -f "${template}" ]] || die "Template tidak ditemukan: ${template}"

sed \
  -e "s/__DOMAIN__/${domain}/g" \
  -e "s/__PORT_APP__/${port}/g" \
  "${template}" > "${out}"
chmod 644 "${out}"

log "Generated ${out}"
log "Domain: https://${domain}/ → 127.0.0.1:${port}"
echo
echo "Langkah di server production:"
echo "  1. cd apps/${folder} && docker compose up -d --force-recreate"
echo "  2. Salin host-nginx.conf ke /etc/nginx/sites-available/${domain}"
echo "  3. Sesuaikan ssl_certificate & ssl_certificate_key"
echo "  4. nginx -t && systemctl reload nginx"
