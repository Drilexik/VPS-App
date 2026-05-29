# Drilex VPS

Aplikace pro správu Ubuntu VPS z mobilního telefonu.

```
Telefon (Android APK)
        ↓ HTTPS
Nginx (443) → FastAPI uvicorn (127.0.0.1:8000)
```

## Struktura

- [`backend/`](backend/) – FastAPI server (Python)
- [`web_app/`](web_app/) – Mobilní aplikace (Capacitor + HTML/CSS/JS)
- [`DEPLOYMENT.md`](DEPLOYMENT.md) – **Kompletní návod na nasazení**
- [`UPDATES.md`](UPDATES.md) – Changelog

## Funkce

- Dashboard se živými gauges (CPU/RAM/Disk) přes Server-Sent Events
- Top procesy + ukončování
- Souborový prohlížeč + editace textových souborů
- Síťové statistiky + ban/unban IP přes iptables
- Docker kontejnery (start/stop/restart + logy)
- Terminál s whitelistovanými příkazy
- Push notifikace pro CPU/RAM > 80 %, Disk > 90 %, SSH login

## Rychlý start

**VPS (Ubuntu 22.04+):**
```bash
curl -fsSL https://raw.githubusercontent.com/Drilexik/VPS-App/main/backend/redeploy-app -o redeploy-app \
  && chmod +x redeploy-app \
  && sudo ./redeploy-app
```

**Android APK (vývojové PC):**
```bash
cd web_app
npm install && npx cap add android
./build.sh        # nebo .\build.ps1 na Windows
```

Detaily v [DEPLOYMENT.md](DEPLOYMENT.md).
