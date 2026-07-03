#!/usr/bin/env bash
# Generate landing page (html/index.html) from apps.manifest

set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ensure_dirs

index_file="${HTML_DIR}/index.html"
tmp_html="$(mktemp)"
trap 'rm -f "${tmp_html}"' EXIT

{
  cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>WebQoLauncher</title>
  <style>
    :root {
      --bg: #0f1419;
      --surface: #1a2332;
      --border: #2d3a4f;
      --text: #e7ecf3;
      --muted: #8b9cb3;
      --accent: #3b82f6;
      --accent-hover: #2563eb;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
      line-height: 1.5;
    }
    header {
      padding: 2.5rem 1.5rem 1.5rem;
      text-align: center;
      border-bottom: 1px solid var(--border);
      background: linear-gradient(180deg, #152030 0%, var(--bg) 100%);
    }
    header h1 { font-size: 1.75rem; font-weight: 700; letter-spacing: -0.02em; }
    header p { color: var(--muted); margin-top: 0.5rem; font-size: 0.95rem; }
    main {
      max-width: 1100px;
      margin: 0 auto;
      padding: 2rem 1.5rem 3rem;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 1.25rem;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.25rem 1.35rem;
      transition: border-color 0.15s, transform 0.15s;
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }
    .card:hover {
      border-color: var(--accent);
      transform: translateY(-2px);
    }
    .card-header {
      display: flex;
      align-items: flex-start;
      gap: 0.75rem;
    }
    .card-icon {
      font-size: 1.75rem;
      line-height: 1;
      flex-shrink: 0;
    }
    .card-title { font-size: 1.1rem; font-weight: 600; }
    .card-desc { color: var(--muted); font-size: 0.875rem; margin-top: 0.15rem; }
    .meta {
      display: grid;
      gap: 0.35rem;
      font-size: 0.875rem;
      color: var(--muted);
    }
    .meta strong { color: var(--text); font-weight: 500; }
    .card a.btn {
      display: inline-block;
      margin-top: auto;
      padding: 0.55rem 1rem;
      background: var(--accent);
      color: #fff;
      text-decoration: none;
      border-radius: 8px;
      font-size: 0.875rem;
      font-weight: 500;
      text-align: center;
      transition: background 0.15s;
    }
    .card a.btn:hover { background: var(--accent-hover); }
    .empty {
      text-align: center;
      padding: 3rem 1rem;
      color: var(--muted);
    }
    .empty code {
      background: var(--surface);
      padding: 0.15rem 0.4rem;
      border-radius: 4px;
      font-size: 0.85em;
    }
    footer {
      text-align: center;
      padding: 1.5rem;
      color: var(--muted);
      font-size: 0.8rem;
      border-top: 1px solid var(--border);
    }
  </style>
</head>
<body>
  <header>
    <h1>WebQoLauncher</h1>
    <p>Portal internal — aplikasi terdeteksi otomatis dari folder <code>apps/</code></p>
  </header>
  <main>
HTML_HEAD

  if [[ ! -s "${MANIFEST}" ]]; then
    cat <<'HTML_EMPTY'
    <div class="empty">
      <p>Belum ada aplikasi yang terdeteksi.</p>
      <p style="margin-top:1rem;">Tambahkan folder di <code>apps/</code> beserta <code>.env</code> dan <code>docker-compose.yml</code>, lalu jalankan launcher.</p>
    </div>
HTML_EMPTY
  else
    echo '    <div class="grid">'

    while IFS=$'\t' read -r folder app_name port_app app_path app_desc app_icon app_spa; do
      [[ -n "${folder}" ]] || continue

      name_esc="$(html_escape "${app_name}")"
      desc_esc="$(html_escape "${app_desc}")"
      path_esc="$(html_escape "/${app_path}/")"
      port_esc="$(html_escape "${port_app}")"

      icon="📦"
      if [[ -n "${app_icon}" ]]; then
        icon="🖼️"
      fi

      cat <<HTML_CARD
      <article class="card">
        <div class="card-header">
          <span class="card-icon" aria-hidden="true">${icon}</span>
          <div>
            <div class="card-title">${name_esc}</div>
HTML_CARD

      if [[ -n "${app_desc}" ]]; then
        echo "            <div class=\"card-desc\">${desc_esc}</div>"
      fi

      cat <<HTML_CARD2
          </div>
        </div>
        <div class="meta">
          <div><strong>Port</strong> : ${port_esc}</div>
          <div><strong>URL</strong> : ${path_esc}</div>
        </div>
        <a class="btn" href="${path_esc}">Buka aplikasi</a>
      </article>
HTML_CARD2
    done < "${MANIFEST}"

    echo '    </div>'
  fi

  cat <<'HTML_FOOT'
  </main>
  <footer>WebQoLauncher — generated automatically</footer>
</body>
</html>
HTML_FOOT

} > "${tmp_html}"

mv "${tmp_html}" "${index_file}"
chmod 644 "${index_file}"
trap - EXIT
log "Generated landing page → ${index_file}"
