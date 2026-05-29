#!/usr/bin/env bash
# Drilex VPS – Build APK (Linux / macOS)
# Usage:  ./build.sh           -> debug APK
#         ./build.sh release   -> release APK

set -e

BUILD_TYPE="${1:-debug}"

echo "==> Drilex VPS build"

# 1. Check tooling
command -v node >/dev/null 2>&1 || { echo "ERROR: Node.js not installed."; exit 1; }
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
  echo "WARNING: ANDROID_HOME not set."
fi

# 2. Install deps
[ -d node_modules ] || { echo "==> Installing dependencies..."; npm install; }

# 3. Add Android platform if needed
[ -d android ] || { echo "==> Adding Android platform..."; npx cap add android; }

# 4. Sync www -> android
echo "==> Syncing web assets..."
npx cap sync android

# 5. Build APK
cd android
if [ "$BUILD_TYPE" = "release" ]; then
  echo "==> Building RELEASE APK..."
  ./gradlew assembleRelease
  APK="app/build/outputs/apk/release/app-release-unsigned.apk"
else
  echo "==> Building DEBUG APK..."
  ./gradlew assembleDebug
  APK="app/build/outputs/apk/debug/app-debug.apk"
fi
cd ..

echo ""
echo "==> SUCCESS"
echo "APK: android/$APK"
echo ""
echo "Install on connected device:  npx cap run android"
