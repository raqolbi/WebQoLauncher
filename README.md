# WebQoLauncher

Portal internal berbasis **Docker + Nginx** yang secara otomatis mendeteksi aplikasi di folder `apps/`, membaca konfigurasi dari `.env`, menjalankan Docker Compose per aplikasi, dan menyajikan reverse proxy plus halaman portal.

Mirip konsep [QoLauncher](https://github.com/raqolbi/QoLauncher), tetapi fokus pada **web apps** dengan reverse proxy Nginx — bukan supervisor binary Go.

## Struktur

```text
/
├── apps/                    # Satu folder = satu aplikasi
│   ├── pos/
│   │   ├── .env
│   │   ├── docker-compose.yml
│   │   └── public/
│   ├── dashboard/
│   └── inventory/
├── main/                    # Runtime portal (Nginx + scripts)
│   ├── docker-compose.yml   # Container Nginx reverse proxy
│   ├── nginx.conf           # Auto-generated (jangan edit manual)
│   ├── proxy_params_extra.conf
│   ├── html/index.html      # Auto-generated landing page
│   ├── data/apps.manifest   # Hasil scan
│   └── scripts/
│       ├── scan.sh
│       ├── generate-nginx.sh
│       ├── generate-html.sh
│       ├── start-apps.sh
│       ├── stop-apps.sh
│       ├── reload.sh
│       ├── setup.sh
│       ├── menu.sh
│       └── launcher.sh
├── launcher.sh              # Entry point
└── README.md
```

## Kontrak setiap aplikasi

Setiap folder di `apps/` **wajib** memiliki file `.env`:

```env
APP_NAME=Point Of Sale
PORT_APP=3101
```

Opsional:

```env
APP_DESCRIPTION=Kasir Superoti
APP_ICON=logo.png
APP_PATH=pos
APP_SPA=true
```

| Variabel | Wajib | Keterangan |
|----------|-------|------------|
| `APP_NAME` | Ya | Nama tampilan di portal |
| `PORT_APP` | Ya | Port host tempat app berjalan |
| `APP_PATH` | Tidak | Path URL proxy (default: nama folder) |
| `APP_DESCRIPTION` | Tidak | Deskripsi di card portal |
| `APP_ICON` | Tidak | Nama file ikon (metadata) |
| `APP_SPA` | Tidak | `false` untuk API murni; default `true` (Next.js / SPA fallback) |

Setiap aplikasi juga **wajib** punya `docker-compose.yml` yang mem-publish port sesuai `PORT_APP`.

## Cara kerja

Saat `./launcher.sh start`:

1. **Scan** — baca semua folder di `apps/` yang punya `.env`
2. **Generate** — buat `main/nginx.conf` dan landing page HTML
3. **Start apps** — `docker compose up -d` di setiap folder aplikasi
4. **Start portal** — jalankan container Nginx reverse proxy

### Reverse proxy

```text
/pos        → http://host.docker.internal:3101
/dashboard  → http://host.docker.internal:3102
/inventory  → http://host.docker.internal:3103
```

Nginx dilengkapi:

- WebSocket (`Upgrade` / `Connection`)
- HTTP/2
- Gzip
- Cache static asset (CSS, JS, gambar, font)
- Security headers (X-Frame-Options, CSP-related, dll.)
- SPA / Next.js fallback (default aktif) — refresh `/login`, `/dashboard` tidak 404

## Quick start

```bash
# Pastikan Docker & Docker Compose tersedia
chmod +x launcher.sh main/scripts/*.sh

# Menu interaktif (default)
./launcher.sh

# Atau jalankan semua sekaligus via CLI
./launcher.sh start
```

Buka **http://localhost:8080** — halaman portal menampilkan semua aplikasi yang terdeteksi.

## Menu interaktif

Jalankan tanpa argumen atau `./launcher.sh menu`:

| Menu | Fungsi |
|------|--------|
| **Run** | Pilih app (`all` / nomor / `1,3`), opsional jalankan nginx portal |
| **Stop** | Stop app yang running; `L` untuk nginx portal saja |
| **Restart** | Restart app terpilih |
| **Logs** | `docker compose logs -f` untuk satu app |
| **Apps** | Daftar semua folder di `apps/` + status |
| **Setup** | Wizard `.env` — tanya nama & port per app |
| **Status** | Status container portal + apps |
| **Reload** | Rescan + regenerate nginx |

### Setup wizard

Menu **Setup** menanyakan secara interaktif:

1. **Nama aplikasi** — tampilan di portal (wajib)
2. **Port aplikasi** — port host, disarankan otomatis & dicek bentrok (wajib)

Alur:

- Folder di `apps/` tanpa `.env` → pilih dari daftar (atau `0` untuk app baru)
- App baru → folder `apps/` dibuat otomatis dari nama (mis. `Point Of Sale` → `point-of-sale`)
- File `.env` dibuat otomatis (`APP_PATH` = nama folder)
- Opsional: scan + reload nginx di akhir

## Perintah CLI

| Perintah | Fungsi |
|----------|--------|
| `./launcher.sh` | Menu interaktif |
| `./launcher.sh menu` | Menu interaktif |
| `./launcher.sh setup` | Wizard setup `.env` |
| `./launcher.sh start` | Scan, generate, start semua app + nginx portal |
| `./launcher.sh stop` | Stop portal dan semua app |
| `./launcher.sh restart` | Stop lalu start ulang |
| `./launcher.sh reload` | Rescan, regenerate config, reload Nginx |
| `./launcher.sh scan` | Scan + generate config saja (tanpa start) |
| `./launcher.sh status` | Tampilkan status container |

## Menambah aplikasi baru

1. Buat folder baru di `apps/`, misalnya `apps/billing/`
2. Tambahkan `.env` dengan `APP_NAME`, `PORT_APP`, dan opsional lainnya
3. Tambahkan `docker-compose.yml` yang expose `PORT_APP`
4. Jalankan:

```bash
./launcher.sh reload
```

Tidak perlu edit manual `main/nginx.conf` atau `main/docker-compose.yml`.

## Konfigurasi portal

File `main/.env`:

```env
# Port portal Nginx — akses semua app via http://localhost:8080
LAUNCHER_PORT=8080
```

**Penting — dua jenis port:**

| Port | Fungsi | Contoh |
|------|--------|--------|
| **Portal** (`LAUNCHER_PORT`, default 8080) | Reverse proxy Nginx — satu pintu masuk semua app | `http://localhost:8080/pos` |
| **Port app** (`PORT_APP` di setiap `.env`) | Port docker compose per aplikasi | `http://localhost:3101` |

App diakses via portal (`/ho-fe`) atau langsung ke port app (`:3101`).

### Next.js static export

1. Build dengan `output: 'export'` di `next.config.js`
2. Salin isi folder `out/` ke `apps/<nama-app>/public/`
3. Pastikan `nginx.conf` ada di folder app (otomatis dari Setup/Run)
4. Set `APP_SPA=true` di `.env` (default) — portal & container app sudah pakai fallback `index.html`

```nginx
# Di container app (apps/<nama>/nginx.conf):
try_files $uri $uri.html $uri/ /index.html;
```

## Contoh aplikasi

Repo ini menyertakan 3 app demo (Nginx static):

| App | Port | URL |
|-----|------|-----|
| Point Of Sale | 3101 | `/pos` |
| Dashboard | 3102 | `/dashboard` |
| Inventory | 3103 | `/inventory` |

## Persyaratan

- Docker Engine 20.10+
- Docker Compose v2
- Bash 4+

## Lisensi

MIT
