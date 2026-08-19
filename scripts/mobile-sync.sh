#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/android"
WWW="$ANDROID/www"

if [[ ! -f "$ROOT/index.html" ]]; then
  echo "Ошибка: $ROOT/index.html не найден" >&2
  exit 1
fi

echo "Синхронизация веб-версии -> мобильная сборка (android/www)..."

# 1. Базовый index.html из корня репозитория
cp "$ROOT/index.html" "$WWW/index.html"

# 2. Строгий CSP для WebView: никаких внешних SDK / unsafe-eval
python3 - "$WWW/index.html" <<'PY'
import re, sys
path = sys.argv[1]
html = open(path, encoding='utf-8').read()
mobile_csp = (
    "default-src 'self'; script-src 'self' 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; "
    "connect-src https://uqnendfdguugtcguceei.supabase.co; "
    "img-src 'self' data: https:; font-src 'self' data:; "
    "media-src 'none'; object-src 'none'; frame-src 'none'; "
    "base-uri 'none'; form-action 'self'"
)
html = re.sub(
    r'<meta http-equiv="Content-Security-Policy"[^>]*>',
    f'<meta http-equiv="Content-Security-Policy" content="{mobile_csp}">',
    html,
)
open(path, 'w', encoding='utf-8').write(html)
print("  CSP заменён на мобильный (без рекламных доменов)")
PY

# 3. Удалить загрузку рекламных SDK и их адаптеров
python3 - "$WWW/index.html" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path, encoding='utf-8').read().split('\n')
keep = []
removed = 0
for line in lines:
    if 'playgama-bridge.js' in line or 'crazygames-sdk-v3.js' in line or 'html5.api.gamedistribution.com' in line:
        removed += 1
        continue
    if ('yt-playables-adapter.js' in line or 'crazygames-adapter.js' in line or 'gamedistribution-adapter.js' in line) and '<script' in line:
        removed += 1
        continue
    keep.append(line)
open(path, 'w', encoding='utf-8').write('\n'.join(keep))
print(f"  Удалено рекламных SDK-подключений: {removed}")
PY

# 4. Веб-адаптер (надмножество: без Bridge работает на localStorage)
cp "$ROOT/mobile-adapter.js" "$WWW/mobile-adapter.js"

# 5. Общие ассеты
cp "$ROOT/mobile.css" "$WWW/mobile.css"
cp "$ROOT/public-config.js" "$WWW/public-config.js"
cp "$ROOT/privacy.html" "$WWW/privacy.html"
cp "$ROOT/sw.js" "$WWW/sw.js"
# Убрать из mobile-версии sw.js ссылки на веб-адаптеры, которых нет в сборке
python3 - "$WWW/sw.js" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path, encoding='utf-8').read().split('\n')
         if 'gamedistribution-adapter.js' not in l]
open(path, 'w', encoding='utf-8').write('\n'.join(lines))
PY

# 6. Проверка: никаких внешних SDK-подключений в мобильной сборке
# (упоминания в JS-guard'ах вида typeof window.CrazyGames допустимы)
if grep -qE "document\.write\('<script|src=\"https?://(bridge\.playgama|sdk\.crazygames|html5\.api\.gamedistribution)" "$WWW/index.html"; then
  echo "Ошибка: в мобильной сборке остались загрузки рекламных SDK!" >&2
  exit 1
fi

# 7. Проверка синтаксиса главного скрипта
python3 - "$WWW/index.html" <<'PY'
import re, sys
html = open(sys.argv[1], encoding='utf-8').read()
scripts = re.findall(r'<script>(.*?)</script>', html, re.S)
open('/tmp/mobile-sync-check.js', 'w').write(scripts[-1] if scripts else '')
print(f"  Главный скрипт: {len(scripts)} блок(ов), извлечён для node --check")
PY
if ! node --check /tmp/mobile-sync-check.js; then
  echo "Ошибка: синтаксис скрипта сломан" >&2
  exit 1
fi
echo "  Синтаксис главного скрипта OK"

echo "Готово. android/www синхронизирован."
