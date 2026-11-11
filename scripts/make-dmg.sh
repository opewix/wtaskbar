#!/bin/zsh
# Собирает установочный образ build/wtaskbar-<версия>.dmg: приложение + ярлык «Программы».
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-0.9}"
./scripts/bundle.sh

STAGE=build/dmg
DMG="build/wtaskbar-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/WTaskbar.app" "$STAGE/"
ln -s /Applications "$STAGE/Программы"

hdiutil create -volname "WTaskbar $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Установщик: $DMG"
