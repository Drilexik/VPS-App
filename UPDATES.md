# Drilex VPS – Changelog

## v1.0 – Initial release (2026-05-29)

První funkční verze projektu.

### Backend (`backend/`)

| Soubor | Účel |
|--------|------|
| `main.py` | FastAPI server (~430 řádků); Bearer auth + slowapi rate limiting; endpointy pro system overview, procesy (list/kill), disk (list/mkdir/delete/read/write), network stats + IP ban/unban přes iptables, Docker (list/action/logs), terminál s whitelistovanými příkazy, SSE stream `/api/events/stream` (live stats + threshold alerty) |
| `requirements.txt` | fastapi, uvicorn, psutil, slowapi, docker, pydantic, python-dotenv |
| `.env.example` | Šablona pro `DRILEX_API_KEY` |
| `drilex.service` | Systemd unit (user=drilex, `AmbientCapabilities=CAP_NET_ADMIN CAP_KILL`, hardening) |
| `nginx.conf` | HTTPS + security headers + rate limiting; samostatný blok pro `/api/events/` (SSE musí mít `proxy_buffering off`) |
| `redeploy-app` | Auto-deploy skript: klonuje/pulluje z GitHubu, syncuje kód (zachová .env + venv), reloadne systemd/nginx, health check |

### Mobilní aplikace (`web_app/`) – Capacitor + vanilla JS

| Soubor | Účel |
|--------|------|
| `package.json` | `@capacitor/core`, `@capacitor/android`, `@capacitor/local-notifications`, `@capacitor/preferences`, `@capacitor/app` |
| `capacitor.config.json` | `appId=com.drilex.vps`, konfigurace notifikací |
| `build.ps1` / `build.sh` | One-command build: `npm install` → `cap sync` → Gradle assemble |
| `www/index.html` | Single-page HTML – setup obrazovka + main app s drawer navigací |
| `www/style.css` | Dark téma (#0E0E14 bg, #8B5CF6 primary, #06D6A0 accent); gauges přes inline SVG |
| `www/api.js` | `ApiClient` třída – fetch wrapper s Bearer auth, mapuje 1:1 na backend endpointy |
| `www/monitor.js` | `MonitorService` – SSE stream přes `fetch()` + `ReadableStream` (umožňuje Bearer header); auto-reconnect; `notify` modul s `@capacitor/local-notifications` + fallback toasty |
| `www/app.js` | Všechny obrazovky: Dashboard, Statistics, CPU/RAM Monitor, Disk Manager (browser + file viewer/editor), Network, Docker, Terminal; Storage abstrakce přes `@capacitor/preferences` |

### Funkce

- Dashboard se živými gauges (CPU/RAM/Disk) přes SSE, real-time bez polling
- Top procesy + ukončování (SIGTERM/SIGKILL)
- Disk browser, mkdir, mazání, čtení/editace textových souborů (do 2 MB)
- Network stats + ban/unban IP přes iptables
- Docker containers + start/stop/restart + logy
- Terminal s whitelistovanými shell příkazy
- Push notifikace (CPU/RAM > 80 %, Disk > 90 %, SSH login, ztracený heartbeat) – fungují když je app v paměti

### Build verifikace

První úspěšný build (2026-05-29):
- Microsoft OpenJDK 21.0.11 (Capacitor 8 vyžaduje JDK 21)
- Android SDK Platform 35 + Build-tools 35.0.0
- Node.js 24.14.0
- APK: ~4 MB (debug)
