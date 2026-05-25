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

## 10. Sestavení Flutter APK

### Předpoklady (na vašem vývojovém počítači)
- Flutter SDK ≥ 3.16 (`flutter --version`)
- Android SDK / Android Studio
- Java 17+

### Vytvoření Flutter projektu
```bash
# Pokud ještě nemáte projekt vytvořený
flutter create drilex_vps
cd drilex_vps

# Zkopírujte naše soubory
# (přepište obsah lib/ a pubspec.yaml z tohoto repozitáře)
cp -r /path/to/VPS-App/flutter_app/lib ./
cp /path/to/VPS-App/flutter_app/pubspec.yaml ./

# Nahraďte AndroidManifest.xml
cp /path/to/VPS-App/flutter_app/android/app/src/main/AndroidManifest.xml \
   ./android/app/src/main/AndroidManifest.xml
```

### Úprava android/app/build.gradle
```groovy
android {
    defaultConfig {
        minSdkVersion 21    // Vyžadováno pro flutter_secure_storage
        targetSdkVersion 34
    }
}
```

### Build
```bash
# Závislosti
flutter pub get

# Debug APK (pro testování)
flutter build apk --debug

# Release APK (bez podpisu – pro osobní použití)
flutter build apk --release

# APK bude v:
# build/app/outputs/flutter-apk/app-release.apk
```

### Instalace na telefon
```bash
# Přes USB (zapněte USB debugging)
flutter install

# Nebo zkopírujte APK na telefon přes USB/email a nainstalujte ručně
# (musíte povolit "Instalace z neznámých zdrojů" v nastavení telefonu)
```

---

## 11. Nastavení aplikace

1. Otevřete aplikaci Drilex VPS
2. Zadejte **Backend URL**: `https://your-domain.example.com`
3. Zadejte **API Key**: váš klíč z `.env` souboru
4. Klikněte **Connect**

Credentials se bezpečně uloží do Android Keystore (přes flutter_secure_storage).

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

### Backend – aktualizace kódu

Po každé změně `main.py` nebo `requirements.txt` stačí:

```bash
# 1. Nahrajte změněné soubory na VPS
scp ./backend/main.py drilex@your-vps:/opt/drilex-backend/main.py

# Pokud změníte requirements.txt, aktualizujte i balíčky
scp ./backend/requirements.txt drilex@your-vps:/opt/drilex-backend/requirements.txt
sudo -u drilex bash -c "cd /opt/drilex-backend && source venv/bin/activate && pip install -r requirements.txt"

# 2. Restartujte service
sudo systemctl restart drilex

# 3. Ověřte stav
sudo systemctl status drilex
curl http://127.0.0.1:8000/api/health
```

Pro hromadnou synchronizaci celého adresáře (doporučeno):
```bash
# rsync přeskočí nezměněné soubory
rsync -av --exclude='venv/' --exclude='.env' \
    ./backend/ drilex@your-vps:/opt/drilex-backend/

# Poté restartujte
ssh user@your-vps "sudo systemctl restart drilex"
```

> **Pozor:** Soubor `.env` nikdy nepřepisujte rsync/scp – obsahuje váš API klíč. Používejte `--exclude='.env'`.

---

### Backend – aktualizace systemd service nebo nginx

Pokud změníte `drilex.service`:
```bash
scp ./backend/drilex.service drilex@your-vps:/tmp/drilex.service
ssh user@your-vps "sudo cp /tmp/drilex.service /etc/systemd/system/drilex.service && sudo systemctl daemon-reload && sudo systemctl restart drilex"
```

Pokud změníte `nginx.conf`:
```bash
scp ./backend/nginx.conf user@your-vps:/tmp/nginx-drilex.conf
ssh user@your-vps "sudo cp /tmp/nginx-drilex.conf /etc/nginx/sites-available/drilex && sudo nginx -t && sudo systemctl reload nginx"
```

> `nginx -t` ověří konfiguraci před reloadem – pokud selže, nginx se nepřestane.

---

### Flutter app – nový build a instalace APK

Po každé změně Flutter kódu:

```bash
# Přejděte do složky flutter_app
cd flutter_app

# Pokud jste změnili pubspec.yaml (nové balíčky)
flutter pub get

# Sestavte release APK
flutter build apk --release

# APK se nachází v:
# build/app/outputs/flutter-apk/app-release.apk
```

**Instalace přes USB (nejrychlejší):**
```bash
# Telefon musí mít zapnutý USB debugging
flutter install --release
```

**Instalace ručně (bez USB debugging):**
```bash
# Zkopírujte APK na telefon
adb push build/app/outputs/flutter-apk/app-release.apk /sdcard/Download/drilex.apk

# Nebo přes Windows – zkopírujte APK do sdíleného úložiště telefonu
# a nainstalujte v telefonu (Soubory → Stažené → drilex.apk)
# Musíte povolit "Instalace z neznámých zdrojů" v Nastavení → Zabezpečení
```

> Při přechodu z debug na release APK, nebo při změně `applicationId`, může být nutné nejprve odinstalovat starou verzi.

---

## 14. Monitoring a údržba

```bash
# Logy backendu
sudo journalctl -u drilex -f --since "1 hour ago"

# Logy nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Restart backendu po úpravě kódu
sudo systemctl restart drilex

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
│   └── nginx.conf           # Nginx konfigurace
├── flutter_app/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart                    # Entry point, routing
│   │   ├── theme/app_theme.dart         # Design systém
│   │   ├── models/models.dart           # Datové modely
│   │   ├── services/api_service.dart    # HTTP klient
│   │   ├── providers/auth_provider.dart # Auth state
│   │   ├── widgets/
│   │   │   ├── gauge_widget.dart        # Kruhové gauge
│   │   │   ├── stat_card.dart           # Info karty
│   │   │   └── app_drawer.dart          # Navigační drawer
│   │   └── screens/
│   │       ├── setup_screen.dart        # Přihlášení
│   │       ├── home_screen.dart         # Dashboard
│   │       ├── stats_screen.dart        # Statistiky
│   │       ├── processes_screen.dart    # CPU/RAM procesy
│   │       ├── disk_screen.dart         # Správa souborů
│   │       ├── network_screen.dart      # Síť + IP ban
│   │       ├── docker_screen.dart       # Docker kontejnery
│   │       ├── docker_logs_screen.dart  # Logy kontejnerů
│   │       └── terminal_screen.dart     # Terminál
│   └── android/
│       └── app/src/main/AndroidManifest.xml
└── DEPLOYMENT.md            # Tento soubor
```
