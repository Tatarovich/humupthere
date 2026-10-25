#!/usr/bin/env bash
# Сборка Hum Up There и упаковка в .app-бандл (Xcode не нужен, хватает CommandLineTools).
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
CONFIG="release"
APP="dist/HumUpThere.app"

echo "==> Сборка ($CONFIG, $ARCH)"
swift build -c "$CONFIG" --arch "$ARCH"

BIN_DIR="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"
BIN="$BIN_DIR/HumUpThere"

if [[ ! -x "$BIN" ]]; then
    echo "Не найден исполняемый файл: $BIN" >&2
    exit 1
fi

echo "==> Сборка бандла $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HumUpThere"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Иконка для Finder и «Объектов входа», звук — для уведомлений.
cp Resources/HumUpThere.icns "$APP/Contents/Resources/HumUpThere.icns"
cp Resources/hum.aiff "$APP/Contents/Resources/hum.aiff"
cp Resources/airport.aiff "$APP/Contents/Resources/airport.aiff"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Подпись (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "подпись пропущена (не критично для локального запуска)"

echo "==> Готово: $APP"
echo "Запуск: open \"$APP\""
