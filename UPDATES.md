# Drilex VPS – Changelog

---

## v1.2 – Migrace Flutter → Capacitor (vanilla web app)

Flutter aplikace se stále plně nepodařilo zprovoznit (build problémy, runtime crashe). Kompletně přepsáno na **Capacitor + vanilla HTML/CSS/JS** – jednodušší build (jeden PowerShell skript), žádné Dart závislosti, stejná funkčnost včetně push notifikací na pozadí.

### Nová složka `web_app/`

| Soubor | Účel |
|--------|------|
| `package.json` | npm závislosti: `@capacitor/core`, `@capacitor/android`, `@capacitor/local-notifications`, `@capacitor/preferences`, `@capacitor/background-runner`, `@capacitor/app` |
| `capacitor.config.json` | `appId`, `appName`, registrace Background Runner pro heartbeat (15 min interval, autoStart) |
| `build.ps1` / `build.sh` | One-command build: kontrola tooling → `npm install` → `npx cap sync android` → Gradle `assembleDebug`/`assembleRelease` |
| `.gitignore` | Ignoruje `node_modules/` a `android/` (regenerovatelné) |
| `README.md` | Návod na build, troubleshooting, struktura |
| `www/index.html` | Single-page HTML – setup obrazovka + main app s drawer navigací |
| `www/style.css` | Dark téma (#0E0E14 bg, #8B5CF6 primary, #06D6A0 accent), responsivní layout, gauges přes inline SVG, drawer, toasty, modální dialogy |
| `www/api.js` | `ApiClient` třída – fetch wrapper s Bearer auth, JSON parsing, timeouty, pokrývá všechny `/api/*` endpointy |
| `www/monitor.js` | `MonitorService` – SSE stream přes `fetch()` + `ReadableStream` (umožňuje pass Authorization header, co `EventSource` neumí); auto-reconnect po 12 s; per-kind cooldown alertů. `notify` modul – wrapper kolem `@capacitor/local-notifications` s fallback na in-app toasty |
| `www/app.js` | Všechny obrazovky: Dashboard (gauges + top procesy), Statistics, CPU/RAM Monitor (kill procesů), Disk Manager (browser + file viewer/editor), Network (interfaces + ban/unban IP), Docker (start/stop/restart + logy), Terminal. Storage abstrakce přes `@capacitor/preferences` (na webu fallback na `localStorage`) |
| `www/background.js` | Background Runner script – běží mimo WebView každých 15 min; checkuje `/api/health`, pošle notifikaci přes `CapacitorNotifications` pokud server nedostupný. Anti-spam: skip pokud byla app na popředí v posledních 5 min nebo už alert vyšel v posledních 30 min |
| `www/capacitor.js` | Stub – nahrazen reálným runtime po `cap sync` |

### Funkce identické s Flutter verzí

- 3 živé gauges (CPU/RAM/Disk) přes SSE
- Top procesy + kill
- Disk browser, mkdir, smazání, čtení/editace textových souborů
- Network stats, ban/unban IP
- Docker containers + logy
- Terminal s whitelistovanými příkazy
- Push notifikace (CPU/RAM > 80 %, Disk > 90 %, SSH login, heartbeat lost)
- Smart heartbeat anti-spam (foreground tracking + cooldown)

### Backend – beze změn

Backend zůstává identický. Capacitor app používá stejné `/api/*` endpointy včetně `/api/events/stream` (SSE) přidaného ve v1.1.

### Dokumentace

| Soubor | Změna |
|--------|-------|
| `DEPLOYMENT.md` | Sekce 10 přepsána z Flutter buildu na Capacitor (`build.ps1` / `build.sh`); sekce 13 (Redeployment) aktualizována; struktura projektu (sekce 16) reflektuje novou složku `web_app/` |
| `web_app/README.md` | Nový – kompletní průvodce buildem a strukturou |

### Stará Flutter aplikace

Složka `flutter_app/` byla smazána – Capacitor verze funguje, build úspěšný.

### Build verifikace (2026-05-29)

První úspěšný build proběhl s těmito verzemi:
- Microsoft OpenJDK 21.0.11 (Capacitor 8 vyžaduje JDK 21, ne 17)
- Android SDK Platform 35 + Build-tools 35.0.0
- Node.js 24.14.0
- APK velikost: ~4 MB
- `@capacitor/background-runner` musel být odebrán – jeho `android-js-engine-release.aar` se z npm nestahuje, build selhával. Background heartbeat lze v budoucnu doplnit přes `@capawesome/capacitor-background-task` nebo native WorkManager plugin.

---

## v1.1 – Opravy chyb + real-time monitoring + notifikace

### Backend

| Soubor | Změna |
|--------|-------|
| `backend/main.py` | Oprava type erroru na Statistics (`int(size_str.strip())`); rozšíření `WHITELISTED_PATHS` o `/etc/nginx`, `/etc/systemd/system`, `/etc/letsencrypt`, `/etc/cron.d`, `/root`; oprava ban/unban IP (iptables ukládá pravidla jako `IP/32` – nyní se zkouší obě varianty); nový endpoint `GET /api/disk/read` (čtení textových souborů do 2 MB); nový endpoint `POST /api/disk/write` (zápis textových souborů); nový SSE endpoint `GET /api/events/stream` – streamuje stats každých 5 s + threshold alerty (CPU/RAM > 80 %, Disk > 90 %, SSH přihlášení přes journald) |
| `backend/nginx.conf` | Přidán samostatný location blok `/api/events/` před `/api/` s `proxy_buffering off`, `proxy_cache off` a 600s timeouty (nutné pro SSE); prodloužen timeout hlavního `/api/` bloku na 300 s |
| `backend/drilex.service` | Odstraněn `/tmp/drilex` z `ReadWritePaths` – způsoboval chybu `226/NAMESPACE` při startu (`PrivateTmp=true` vyžaduje, aby cesta existovala) |

### Flutter – nové soubory

| Soubor | Popis |
|--------|-------|
| `lib/services/monitor_service.dart` | Singleton `ChangeNotifier` napojený na SSE stream; uchovává live hodnoty `cpuPercent`, `ramPercent`, `diskPercent`, `isConnected`; auto-reconnect po 12 s; vysílá alert eventy přes broadcast `Stream` |
| `lib/services/notification_service.dart` | Lokální push notifikace (`flutter_local_notifications`); per-kind cooldown (zabrání spamu); `shouldHeartbeatAlert()` kontroluje `lastForeground` timestamp – neupozorňuje pokud je app na popředí nebo byl telefon vypnutý |

### Flutter – upravené soubory

| Soubor | Změna |
|--------|-------|
| `pubspec.yaml` | Přidány balíčky: `http ^1.2.1`, `flutter_local_notifications ^17.2.2`, `workmanager ^0.5.2` |
| `lib/models/models.dart` | Přidány helpery `_toInt()` a `_toDouble()` pro bezpečné parsování JSON (zabraňuje `type string is not a subtype of int`); aplikovány na všechny `fromJson` konstruktory |
| `lib/services/api_service.dart` | Přidány metody `readFile(path)` → `GET /api/disk/read` a `writeFile(path, content)` → `POST /api/disk/write` |
| `lib/providers/auth_provider.dart` | `save()` a `clear()` nyní zrcadlí credentials do `SharedPreferences` (klíče `bg_api_url`, `bg_api_key`) – nutné pro WorkManager background isolate |
| `lib/main.dart` | Top-level `callbackDispatcher()` pro WorkManager (heartbeat check `/api/health` každých 15 min); inicializace `NotificationService` a `Workmanager` při startu; `MainScreen` sleduje lifecycle (`WidgetsBindingObserver`) – zastavuje SSE při přechodu do pozadí; in-app SnackBar bannery pro alert eventy; `_LiveBadge` nyní ukazuje "LIVE" (zelená) nebo "SYNC" (šedá) podle stavu SSE |
| `lib/screens/disk_screen.dart` | Přidána třída `FileViewerScreen` – zobrazuje obsah textového souboru ve scrollovatelném monospace view; tlačítko pro editaci přepne do `TextField`; uložení přes `api.writeFile()`; opraveno tapnutí na soubor (dříve `null`) |
| `android/app/src/main/AndroidManifest.xml` | Přidána oprávnění `POST_NOTIFICATIONS` (Android 13+), `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`; přidán `RescheduleReceiver` pro WorkManager (obnoví periodické tasky po rebootu) |

### Dokumentace

| Soubor | Změna |
|--------|-------|
| `DEPLOYMENT.md` | Přidána sekce **13 – Redeployment** s pokyny pro aktualizaci backendu (scp/rsync + systemctl restart), aktualizaci nginx/service souborů a nový build + instalaci Flutter APK |

---

## v1.0 – Počáteční implementace

Kompletní implementace projektu od základu.

### Backend (`backend/`)

| Soubor | Obsah |
|--------|-------|
| `main.py` | FastAPI server (~430 řádků); Bearer token autentizace; slowapi rate limiting; endpointy: system overview, top CPU/RAM/disk procesy, process kill, disk list/mkdir/delete, network stats, IP ban/unban přes iptables, Docker list/action/logs, terminál s whitelistem příkazů |
| `requirements.txt` | fastapi, uvicorn, psutil, slowapi, docker, pydantic, python-dotenv |
| `.env.example` | Šablona s `DRILEX_API_KEY` |
| `drilex.service` | Systemd unit; user=drilex; `AmbientCapabilities=CAP_NET_ADMIN CAP_KILL`; hardening (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`) |
| `nginx.conf` | HTTPS s Let's Encrypt; security headers; rate limiting zóna; proxy pouze na `/api/` |

### Flutter (`flutter_app/lib/`)

| Soubor | Obsah |
|--------|-------|
| `main.dart` | Entry point; MaterialApp s dark témou; routing mezi SetupScreen a MainScreen |
| `theme/app_theme.dart` | Barevná paleta (primary `#8B5CF6`, accent `#06D6A0`); SpaceGrotesk font; sdílené styly |
| `models/models.dart` | Datové modely: `SystemOverview`, `TopProcess`, `DiskEntry`, `DiskFolder`, `NetworkInterface`, `BannedIp`, `DockerContainer`, `ProcessInfo` |
| `services/api_service.dart` | Dio HTTP klient s Bearer interceptorem; obaluje všechny API volání |
| `providers/auth_provider.dart` | `ChangeNotifier` ukládající URL + API klíč do `flutter_secure_storage` |
| `widgets/gauge_widget.dart` | Kruhový gauge pro CPU/RAM/Disk |
| `widgets/stat_card.dart` | Informační karta pro dashboard |
| `widgets/app_drawer.dart` | Navigační drawer s 8 položkami |
| `screens/setup_screen.dart` | Přihlašovací obrazovka (URL + API klíč) |
| `screens/home_screen.dart` | Dashboard se 3 gaugy a přehledem systému |
| `screens/stats_screen.dart` | Statistiky – top CPU/RAM/disk procesy |
| `screens/processes_screen.dart` | Seznam procesů s řazením a kill akcí |
| `screens/disk_screen.dart` | Souborový prohlížeč s navigací, vytvořením složky a smazáním |
| `screens/network_screen.dart` | Síťové statistiky + ban/unban IP adres |
| `screens/docker_screen.dart` | Seznam Docker kontejnerů se start/stop/restart |
| `screens/docker_logs_screen.dart` | Logy Docker kontejneru |
| `screens/terminal_screen.dart` | Terminál s historií příkazů (whitelist) |
