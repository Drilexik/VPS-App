# Firebase Cloud Messaging (FCM) – Setup pro Drilex VPS

Push notifikace fungují i když je aplikace **úplně ukončená** (swipnutá z recents). Notifikace se zobrazí jako floating notifikace nahoře (Samsung "edge"/heads-up).

Setup zabere ~10 minut a vyžaduje 2 soubory:
- `google-services.json` → do **Android projektu**
- `firebase-key.json` → na **VPS**

---

## 1. Vytvoření Firebase projektu

1. Otevři https://console.firebase.google.com/
2. Klikni **Add project** → zadej název `Drilex VPS` → Continue → vypni Google Analytics (není potřeba) → Create
3. Po vytvoření klikni **Continue**

---

## 2. Přidání Android aplikace

1. Na hlavní stránce projektu klikni ikonu **Android** (Add app)
2. **Android package name:** `com.drilex.vps` (musí přesně sedět s `appId` v `capacitor.config.json`)
3. **App nickname:** `Drilex VPS`
4. **SHA-1:** přeskoč (není povinné pro FCM)
5. Klikni **Register app**
6. **Download `google-services.json`** ← tento soubor stáhni
7. Zkopíruj ho do:
   ```
   c:\Users\drile\Documents\VPS-App\VPS-App\web_app\android\app\google-services.json
   ```
8. Další 2 kroky průvodce ("Add Firebase SDK" a "Verify") **přeskoč** – Capacitor 8 to už má nakonfigurované automaticky

---

## 3. Service Account key (pro backend)

1. V Firebase Console klikni ozubené kolo (vlevo nahoře vedle "Project Overview") → **Project settings**
2. Karta **Service accounts**
3. Klikni **Generate new private key** → **Generate key**
4. Stáhne se JSON soubor (něco jako `drilex-vps-firebase-adminsdk-XXXXX.json`)
5. Přejmenuj na `firebase-key.json`
6. Nahraj na VPS:
   ```bash
   scp firebase-key.json root@api.vps.drilex.cz:/opt/drilex-backend/firebase-key.json
   ssh root@api.vps.drilex.cz "chmod 600 /opt/drilex-backend/firebase-key.json"
   ```

> ⚠️ Tento soubor je tajný – kdokoli ho má, může posílat push notifikace jménem tvé aplikace. **Nikdy ho necommituj do gitu.**

---

## 4. Rebuild + deploy

### Backend (VPS)

```bash
# Push změny na GitHub
git add . && git commit -m "Add FCM push notifications" && git push

# Na VPS:
sudo redeploy-app
# Skript nainstaluje firebase-admin do venv a restartuje službu.
# V logu uvidíš: [fcm] Firebase admin SDK initialized – push notifications enabled.
```

### APK (na vývojovém PC)

```powershell
cd web_app
.\build.ps1
# Nebo přes USB:
npx cap run android
```

> **První build s google-services.json** může trvat o ~30s déle (Gradle stáhne google-services plugin).

---

## 5. Test

1. Otevři aplikaci na telefonu (jednou – stačí 2 sekundy, aby se zaregistroval FCM token)
2. Zavři aplikaci úplně (swipe z recents)
3. Na VPS:
   ```bash
   sudo testnotifyapp
   ```
4. Měl bys dostat 5 push notifikací do 25 s – **fungují i při zavřené aplikaci**

V backend logu uvidíš:
```
[fcm] Firebase admin SDK initialized
```
A v odpovědi `/api/test/notify`:
```json
{"ok": true, "queued": "cpu", "queue_size": 1, "fcm_devices": 1}
```

`fcm_devices: 1` znamená že jeden telefon je zaregistrovaný a dostane push.

---

## 6. Troubleshooting

**`[fcm] Firebase key not found at /opt/drilex-backend/firebase-key.json`**  
→ Soubor chybí na VPS. Nahraj přes scp viz krok 3.

**`[push] registration error: GoogleApiAvailability failed`**  
→ Telefon nemá Google Play Services. FCM bez nich nefunguje (Huawei, čínský Android).

**Notifikace nepřijde ani v aplikaci v popředí**  
→ Zkontroluj že `google-services.json` má správný `package_name: "com.drilex.vps"`. Otevři ho a podívej se.

**Build padá s `google-services.json is missing`**  
→ Build skript je nastaven tak, aby `google-services` plugin aplikoval JEN pokud soubor existuje. Pokud build padá, zkontroluj že `google-services.json` je v `web_app/android/app/`.

**Notifikace dorazí, ale je to bílý čtvereček bez ikony**  
→ Restartuj telefon. Android někdy ikony cachuje špatně.

---

## Bez Firebase (fallback)

Aplikace funguje i bez Firebase setupu:
- Push notifikace přes FCM = vypnuto
- Místo toho fungují **in-app toasty** a **LocalNotifications** (heads-up, ale jen když je aplikace v paměti)
- Když je aplikace **ukončená**, alerty se kupí v backend queue a doručí se hromadně při otevření aplikace

FCM setup je tedy volitelný, ale doporučený.
