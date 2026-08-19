#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/android"
APK="$ANDROID/android/app/build/outputs/apk/release/app-release.apk"
KEYCHAIN_STORE="KEY_STORE_PASSWORD__/Users/mac/release-key.jks"
KEYCHAIN_KEY="KEY_PASSWORD__/Users/mac/release-key.jks__key888"

# ── 0. Проверка инструментов ──────────────────────────────────────────────
command -v adb >/dev/null || { echo "adb не найден" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "Телефон не подключён (adb get-state)" >&2; exit 1; }
command -v npx >/dev/null || { echo "node/npx не найден" >&2; exit 1; }

# ── 1. Пароли keystore из macOS Keychain (в git их нет) ───────────────────
# NOTE: `security -g` prints the secret to stderr; stderr must be captured.
PF_STORE_PASSWORD="$(security find-generic-password -a "$KEYCHAIN_STORE" -g 2>&1 | grep '^password:' | sed 's/^password: //; s/^"//; s/"$//')"
PF_KEY_PASSWORD="$(security find-generic-password -a "$KEYCHAIN_KEY" -g 2>&1 | grep '^password:' | sed 's/^password: //; s/^"//; s/"$//')"
if [[ -z "$PF_STORE_PASSWORD" || -z "$PF_KEY_PASSWORD" ]]; then
  echo "Не удалось получить пароли keystore из Keychain" >&2
  exit 1
fi
export PF_STORE_PASSWORD PF_KEY_PASSWORD
echo "  Пароли keystore прочитаны из Keychain (не из git)"

# SDK location (machine-specific; not stored in the repo)
if [[ -z "${ANDROID_HOME:-}" && -d "$HOME/Library/Android/sdk" ]]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
fi
if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo "ANDROID_HOME не задан и Android SDK не найден в $HOME/Library/Android/sdk" >&2
  exit 1
fi
echo "  ANDROID_HOME=$ANDROID_HOME"

# ── 2. Синхронизация веб-версии в мобильную сборку ────────────────────────
bash "$ROOT/scripts/mobile-sync.sh"

# ── 3. Capacitor sync ─────────────────────────────────────────────────────
cd "$ANDROID"
if [[ ! -d node_modules ]]; then
  echo "  Установка node_modules..."
  npm install --no-audit --no-fund >/dev/null
fi
npx cap sync android

# ── 4. Release-сборка ─────────────────────────────────────────────────────
cd "$ANDROID/android"
./gradlew assembleRelease

# ── 5. Установка на телефон ───────────────────────────────────────────────
if [[ ! -f "$APK" ]]; then
  echo "APK не собран: $APK" >&2
  exit 1
fi
echo "  Установка $(basename "$APK") ($(du -h "$APK" | cut -f1))..."
adb install -r "$APK"

echo "Готово. APK установлен и готов к запуску."
echo "  Запуск: adb shell monkey -p com.paperflight.cardboardskies -c android.intent.category.LAUNCHER 1"
