# Drilex VPS – Build APK (Windows / PowerShell)
# Usage:  .\build.ps1            -> debug APK
#         .\build.ps1 release    -> release APK

param([string]$BuildType = "debug")

$ErrorActionPreference = "Stop"

Write-Host "==> Drilex VPS build" -ForegroundColor Cyan
Write-Host ""

# 1. Check tooling
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "ERROR: Node.js not installed.  Get it from https://nodejs.org/" -ForegroundColor Red
  exit 1
}
if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
  Write-Host "WARNING: ANDROID_HOME not set.  Capacitor may fail to find SDK." -ForegroundColor Yellow
}

# 2. Install deps
if (-not (Test-Path node_modules)) {
  Write-Host "==> Installing dependencies..." -ForegroundColor Cyan
  npm install
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

# 3. Add Android platform if needed
if (-not (Test-Path "android")) {
  Write-Host "==> Adding Android platform..." -ForegroundColor Cyan
  npx cap add android
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

# 4. Sync www -> android
Write-Host "==> Syncing web assets..." -ForegroundColor Cyan
npx cap sync android
if ($LASTEXITCODE -ne 0) { exit 1 }

# 5. Build APK
Push-Location android
try {
  if ($BuildType -eq "release") {
    Write-Host "==> Building RELEASE APK..." -ForegroundColor Cyan
    .\gradlew.bat assembleRelease
  } else {
    Write-Host "==> Building DEBUG APK..." -ForegroundColor Cyan
    .\gradlew.bat assembleDebug
  }
  if ($LASTEXITCODE -ne 0) { exit 1 }
} finally {
  Pop-Location
}

# 6. Show output path
$apkPath = if ($BuildType -eq "release") {
  "android\app\build\outputs\apk\release\app-release-unsigned.apk"
} else {
  "android\app\build\outputs\apk\debug\app-debug.apk"
}
Write-Host ""
Write-Host "==> SUCCESS" -ForegroundColor Green
Write-Host "APK: $apkPath"
Write-Host ""
Write-Host "Install on connected device:  npx cap run android"
