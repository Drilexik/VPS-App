# Drilex VPS – Web App (Capacitor)

Vanilla HTML/CSS/JS aplikace zabalená přes [Capacitor](https://capacitorjs.com/) do nativního Android APK. Build je jeden CLI příkaz.

---

## Předpoklady (na vývojovém PC)

| Nástroj | Verze | Kde získat |
|---------|-------|------------|
| **Node.js** | 18+ | https://nodejs.org/ |
| **Java JDK** | **21** | `winget install Microsoft.OpenJDK.21` |
| **Android SDK** | Platform 35 + Build-tools 35 | viz níže |
| **ANDROID_HOME** | env var | typicky `%LOCALAPPDATA%\Android\Sdk` |

### Rychlá instalace SDK (bez Android Studia)

```powershell
# 1. Stáhnout cmdline-tools
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
Invoke-WebRequest "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile "$env:TEMP\cmd.zip"
Expand-Archive "$env:TEMP\cmd.zip" "$sdk\cmdline-tools" -Force
Move-Item "$sdk\cmdline-tools\cmdline-tools" "$sdk\cmdline-tools\latest" -Force

# 2. Nastavit env vars (persistentně)
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdk, "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdk, "User")
$env:ANDROID_HOME = $sdk; $env:Path = "$sdk\cmdline-tools\latest\bin;$sdk\platform-tools;$env:Path"

# 3. Přijmout licence + nainstalovat balíčky
echo y | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

> Bez Android Studia stačí `cmdline-tools` + `platform-tools` + `build-tools;34.0.0`.

---

## První build – krok za krokem

```powershell
cd web_app

# 1. Instalace npm balíčků (jen poprvé)
npm install

# 2. Vygenerování Android projektu (jen poprvé)
npx cap add android

# 3. Sync + build debug APK
.\build.ps1           # Windows
./build.sh            # Linux/macOS
```

APK najdete v:  
`web_app/android/app/build/outputs/apk/debug/app-debug.apk`

---

## Každý další build (po změně www/)

```powershell
.\build.ps1           # debug
.\build.ps1 release   # release (nepodepsaný, pro osobní použití)
```

Skript:
1. spustí `npx cap sync android` (zkopíruje `www/` → Android assets)
2. zavolá Gradle `assembleDebug`/`assembleRelease`
3. vypíše cestu k vytvořenému APK

---

## Instalace na telefon

### Přes USB (rychlé)
```powershell
# Zapněte USB debugging v telefonu
npx cap run android
```

### Ručně
1. Přeneste `app-debug.apk` na telefon (USB / email / cloud)
2. Otevřete na telefonu → povolte "Instalace z neznámých zdrojů"
3. Při prvním spuštění aplikace vás požádá o oprávnění notifikací

---

## Struktura projektu

```
web_app/
├── package.json              # npm závislosti (Capacitor + pluginy)
├── capacitor.config.json     # Konfigurace appId, Background Runner
├── build.ps1 / build.sh      # CLI build skripty
├── www/                      # ⬅ tady upravujte zdrojový kód!
│   ├── index.html            # Single-page HTML s wrappery obrazovek
│   ├── style.css             # Dark téma, gauges, drawer, ...
│   ├── api.js                # Fetch klient pro /api/* endpointy
│   ├── monitor.js            # SSE stream + LocalNotifications
│   ├── app.js                # Routing + všechny screeny
│   └── capacitor.js          # Stub (nahrazen runtime po cap sync)
└── android/                  # ⬅ vygenerováno přes `cap add android`,
                                ručně neupravujte (přepíše se při sync)
```

### Když měníte UI/logiku
Editujte soubory v `www/`. Pak `.\build.ps1` → instalace.

### Když chcete přidat Capacitor plugin
```powershell
npm install @capacitor/název-pluginu
npx cap sync android
```

---

## Konfigurace aplikace

Po prvním spuštění aplikace:
1. Zadejte **Backend URL** (`https://your-vps.com`)
2. Zadejte **API Key** (ze souboru `.env` na VPS)
3. Klikněte **Connect**

Credentials se uloží přes `@capacitor/preferences` (na Androidu šifrované úložiště).

---

## Funkce

- **Dashboard** – 3 živé gauges (CPU/RAM/Disk) + uptime + top procesy, real-time přes SSE
- **Statistics** – top CPU/RAM/disk/network
- **CPU/RAM Monitor** – seznam procesů s možností Kill
- **Disk Manager** – procházení, mkdir, mazání, **prohlížení a editace textových souborů**
- **Network** – stats rozhraní + ban/unban IP přes iptables
- **Docker** – seznam, start/stop/restart, logy
- **Terminal** – whitelisted příkazy
- **Push notifikace** – CPU/RAM > 80 %, Disk > 90 %, SSH login (fungují když je app v paměti)

---

## Troubleshooting

**`gradlew.bat: command not found`**  
→ Spusťte nejdřív `npx cap add android` (vygeneruje Android projekt včetně `gradlew`).

**`SDK location not found`**  
→ Nastavte `ANDROID_HOME` na cestu k Android SDK (typicky `C:\Users\<vy>\AppData\Local\Android\Sdk`).

**`Java version not supported` / `invalid source release: 21`**  
→ Capacitor 8 vyžaduje **JDK 21**. Zkontrolujte: `java -version`. Pokud máte 17, doinstalujte přes `winget install Microsoft.OpenJDK.21`.

**Real-time gauges se neaktualizují**  
→ Backend musí mít endpoint `/api/events/stream` (přidán ve v1.1). Zkontrolujte taky nginx config – musí být `proxy_buffering off` na `/api/events/`.

**Notifikace nefungují na pozadí**  
→ V Androidu 13+ povolte `POST_NOTIFICATIONS` ručně v Nastavení → Aplikace → Drilex VPS → Oprávnění.

**Po `cap sync` jsou změny v `www/` ignorovány**  
→ Vždy musíte spustit znovu build (`.\build.ps1`). Samotný cap sync jen zkopíruje soubory do Android projektu.
