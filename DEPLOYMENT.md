# Drilex VPS – Deployment Guide

## Přehled architektury

```
Telefon (Android APK)
        ↓ HTTPS
Nginx (443) → FastAPI uvicorn (127.0.0.1:8000)
```

---

## 1. Příprava VPS (Ubuntu 22.04+)

```bash
# Aktualizace systému
sudo apt update && sudo apt upgrade -y

# Základní balíčky
sudo apt install -y python3 python3-pip python3-venv \
    nginx certbot python3-certbot-nginx \
    iptables net-tools ufw git
```

---

## 2. Vytvoření uživatele drilex

```bash
# Vytvoření uživatele bez login shellu (pro bezpečnost)
sudo useradd -r -m -d /opt/drilex-backend -s /bin/bash drilex

# Přidání do skupiny docker (pokud chcete Docker management)
sudo usermod -aG docker drilex
```

---

## 3. Nahrání backendu

```bash
# Zkopírujte složku backend/ na VPS (scp, rsync, git...)
scp -r ./backend/ user@your-vps:/tmp/drilex-backend

# Přesuňte na správné místo
sudo mv /tmp/drilex-backend /opt/drilex-backend
sudo chown -R drilex:drilex /opt/drilex-backend
```

---

## 4. Python virtuální prostředí

```bash
# Přepněte se na uživatele drilex
sudo -u drilex bash

# Vytvořte venv
cd /opt/drilex-backend
python3 -m venv venv

# Aktivujte a nainstalujte závislosti
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Otestujte spuštění
uvicorn main:app --host 127.0.0.1 --port 8000
# Ctrl+C pro ukončení

exit
```

---

## 5. Nastavení .env souboru

```bash
# Zkopírujte šablonu
sudo -u drilex cp /opt/drilex-backend/.env.example /opt/drilex-backend/.env

# Vygenerujte bezpečný API klíč
openssl rand -hex 32

# Nastavte API klíč
sudo -u drilex nano /opt/drilex-backend/.env
# Vyplňte: DRILEX_API_KEY=váš_vygenerovaný_klíč
```

---

## 6. Systemd service

```bash
# Zkopírujte service soubor
sudo cp /opt/drilex-backend/drilex.service /etc/systemd/system/drilex.service

# Povolte a spusťte
sudo systemctl daemon-reload
sudo systemctl enable drilex
sudo systemctl start drilex

# Zkontrolujte stav
sudo systemctl status drilex
sudo journalctl -u drilex -f
```

### Testování backendu
```bash
# Otestujte health endpoint (lokálně)
curl http://127.0.0.1:8000/api/health

# Otestujte autorizaci
curl -H "Authorization: Bearer váš_api_klíč" http://127.0.0.1:8000/api/system/overview
```

---

## 7. Nginx konfigurace

### SSL certifikát (Let's Encrypt)
```bash
# Nahraďte example.com vaší doménou
sudo certbot certonly --nginx -d your-domain.example.com
```

### Nginx konfigurace
```bash
# Zkopírujte nginx config
sudo cp /opt/drilex-backend/nginx.conf /etc/nginx/sites-available/drilex

# Upravte doménu v configu
sudo nano /etc/nginx/sites-available/drilex
# Nahraďte "your-domain.example.com" vaší doménou

# Aktivujte site
sudo ln -s /etc/nginx/sites-available/drilex /etc/nginx/sites-enabled/drilex

# Odstraňte default site
sudo rm -f /etc/nginx/sites-enabled/default

# Otestujte konfiguraci
sudo nginx -t

# Restartujte nginx
sudo systemctl restart nginx
sudo systemctl enable nginx
```

---

## 8. UFW Firewall

```bash
# Základní pravidla
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Povolte SSH (důležité – nepřijdete o přístup!)
sudo ufw allow OpenSSH

# Povolte HTTPS
sudo ufw allow 443/tcp

# Povolte HTTP (pro redirect na HTTPS)
sudo ufw allow 80/tcp

# Aktivujte UFW
sudo ufw enable

# Zkontrolujte
sudo ufw status verbose
```

---

## 9. Docker (volitelné)

Pokud chcete spravovat Docker kontejnery:

```bash
# Instalace Docker
curl -fsSL https://get.docker.com | sh

# Přidejte drilex do docker skupiny
sudo usermod -aG docker drilex

# Restartujte service aby se aplikovalo
sudo systemctl restart drilex
```

---

## 10. Sestavení Android APK

Mobilní aplikace je postavena na **Capacitor** (HTML/CSS/JS → nativní APK).

### Předpoklady (na vývojovém PC)
- **Node.js 18+** (`node --version`)
- **Java JDK 21** (`java -version`) — `winget install Microsoft.OpenJDK.21`
- **Android SDK** s platformou 35 + build-tools 35
- `ANDROID_HOME` musí být nastavena

Bez Android Studia stačí `cmdline-tools` + `platform-tools` + `platforms;android-35` + `build-tools;35.0.0` (viz `web_app/README.md` pro one-liner).

### Build (PowerShell – Windows)
```powershell
cd web_app

# První build:
npm install
npx cap add android
.\build.ps1            # debug APK

# Každý další build po změně www/:
.\build.ps1            # debug
.\build.ps1 release    # release (nepodepsaný)
```

### Build (bash – Linux/macOS)
```bash
cd web_app
npm install
npx cap add android
./build.sh             # debug
./build.sh release     # release
```

Skript spustí `npx cap sync android` (zkopíruje `www/` do Android projektu) a poté Gradle. Cesta k APK se vypíše na konci.

```
android/app/build/outputs/apk/debug/app-debug.apk
android/app/build/outputs/apk/release/app-release-unsigned.apk
```

### Instalace na telefon
```bash
# Přes USB (zapněte USB debugging)
npx cap run android

# Nebo manuálně:
# Přesuňte app-debug.apk na telefon a nainstalujte
# (povolte "Instalace z neznámých zdrojů")
```

### Editace UI/logiky
Veškerý zdrojový kód aplikace je v `web_app/www/` (HTML/CSS/JS). Po každé změně spusťte build skript – Capacitor automaticky synchronizuje soubory do Android projektu.

---

## 11. Nastavení aplikace

1. Otevřete aplikaci Drilex VPS
2. Zadejte **Backend URL**: `https://your-domain.example.com`
3. Zadejte **API Key**: váš klíč z `.env` souboru
4. Klikněte **Connect**

Credentials se uloží přes `@capacitor/preferences` (Android šifrované úložiště).

---

## 12. Iptables oprávnění pro uživatele drilex

Backend potřebuje oprávnění pro iptables (ban/unban IP). Systemd service používá `AmbientCapabilities=CAP_NET_ADMIN`, ale to nemusí fungovat na všech distribucích.

**Alternativa – sudoers (bezpečnější):**
```bash
# Nastavte NoNewPrivileges=false v drilex.service
# nebo přidejte sudoers pravidlo:

sudo visudo -f /etc/sudoers.d/drilex
```
Obsah souboru:
```
drilex ALL=(root) NOPASSWD: /sbin/iptables -I INPUT *, /sbin/iptables -D INPUT *, /sbin/iptables -L INPUT *
```

Potom upravte volání iptables v `main.py` – přidejte `"sudo"` jako první argument ve `subprocess.run`.

---

## 13. Redeployment

### 🚀 Auto-deploy z GitHubu (doporučeno)

Repo: **https://github.com/Drilexik/VPS-App**

Hotový skript [`backend/redeploy-app`](backend/redeploy-app) udělá veškerou práci – stačí ho jednou stáhnout a spustit.

#### První instalace na čisté VPS (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/Drilexik/VPS-App/main/backend/redeploy-app -o redeploy-app \
  && chmod +x redeploy-app \
  && sudo ./redeploy-app
```

Skript:
1. Naklonuje repo do `/opt/drilex-repo`
2. Vytvoří uživatele `drilex` + skupinu `docker` (pokud existuje)
3. Nainstaluje Python venv + balíčky z `requirements.txt`
4. **Vygeneruje `.env` s náhodným 64-znakovým API klíčem a vypíše ho** ← uložte do aplikace
5. Nainstaluje systemd unit + nginx config
6. Spustí službu a ověří `/api/health`
7. **Sám se zkopíruje do `/usr/local/bin/redeploy-app`** → příště stačí volat odkudkoli

#### Každý další redeploy (po push na GitHub)

```bash
sudo redeploy-app
```

Skript:
- `git pull` – pokud žádný nový commit, **okamžitě skončí bez restartu**
- `rsync` změněných souborů (ignoruje `.env`, `venv/`, `__pycache__/`)
- `pip install` pouze pokud se změnil `requirements.txt`
- reload systemd/nginx pouze pokud se změnily (s `nginx -t` validací a rollbackem)
- `systemctl restart drilex` + health check

#### Plně automatický deploy přes cron

```bash
sudo crontab -e
# Přidejte řádek:
*/5 * * * * /usr/local/bin/redeploy-app >> /var/log/drilex-deploy.log 2>&1
```

Každých 5 minut zkontroluje GitHub. Idempotentní – beze změn na repu nic nedělá.

#### Workflow při vývoji

```bash
# Na vývojovém PC:
git add . && git commit -m "fix XYZ" && git push

# Na VPS (manuálně):
sudo redeploy-app

# Nebo počkat 5 min na cron
```

---

### Android app – nový build APK

Po změně v `web_app/www/` spusťte build skript znovu (viz [sekce 10](#10-sestavení-android-apk)):

```powershell
cd web_app
.\build.ps1            # debug
.\build.ps1 release    # release
```

Poté `npx cap run android` (USB) nebo zkopírovat APK ručně.

---

## 14. Monitoring a údržba

```bash
# Logy backendu
sudo journalctl -u drilex -f --since "1 hour ago"

# Logy nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Logy auto-deploye (pokud používáte cron)
sudo tail -f /var/log/drilex-deploy.log

# Obnova SSL certifikátu (automaticky přes cron)
sudo certbot renew --dry-run
```

---

## 15. Bezpečnostní doporučení

- Používejte silný API klíč (minimálně 32 znaků, hex)
- Nikdy nesdílejte API klíč
- Nastavte UFW / fail2ban pro ochranu SSH
- Pravidelně aktualizujte systém: `sudo apt update && sudo apt upgrade`
- Sledujte logy pro podezřelou aktivitu
- Zvažte omezení přístupu k portu 443 pouze na vaši IP: `sudo ufw allow from YOUR_IP to any port 443`

---

## 16. Struktura projektu

```
VPS-App/
├── backend/
│   ├── main.py              # FastAPI backend
│   ├── requirements.txt     # Python závislosti
│   ├── .env.example         # Šablona env proměnných
│   ├── drilex.service       # Systemd service
│   ├── nginx.conf           # Nginx konfigurace
│   └── redeploy-app         # Auto-deploy skript (klonuje z GitHubu)
├── web_app/                 # Aplikace (Capacitor + vanilla JS)
│   ├── package.json         # npm závislosti
│   ├── capacitor.config.json
│   ├── build.ps1 / build.sh # CLI build skripty
│   ├── www/                 # Zdrojový kód (HTML/CSS/JS)
│   │   ├── index.html       # SPA struktura
│   │   ├── style.css        # Dark téma
│   │   ├── api.js           # Fetch API klient
│   │   ├── monitor.js       # SSE + notifikace
│   │   └── app.js           # Routing + obrazovky
│   └── android/             # Vygenerováno přes `cap add android`
└── DEPLOYMENT.md            # Tento soubor
```
