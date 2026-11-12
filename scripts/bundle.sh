#!/bin/zsh
# Собирает «WTaskbar.app» в build/ (без Xcode, только SwiftPM).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/WTaskbar.app"
VERSION="${VERSION:-0.10}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ru.lproj" "$APP/Contents/Resources/en.lproj"
cp .build/release/WTaskbar "$APP/Contents/MacOS/WTaskbar"

# Иконка: рисуем сами и собираем .icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc -O -o build/appicon scripts/appicon/main.swift
build/appicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WTaskbar</string>
<key>CFBundleDisplayName</key><string>WTaskbar</string>
<key>CFBundleIdentifier</key><string>dev.oleg.wtaskbar</string>
<key>CFBundleExecutable</key><string>WTaskbar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>WTaskbar просит систему показать окно выключения, перезагрузки или выхода.</string>
</dict></plist>
PLIST
# Подпись без сертификата, но с требованием «этот идентификатор», а не «этот отпечаток сборки»:
# иначе после каждой пересборки macOS считает программу новой, и выданный ей «Универсальный
# доступ» молча перестаёт действовать, хотя переключатель в настройках включён.
codesign --force --sign - -r='designated => identifier "dev.oleg.wtaskbar"' "$APP" >/dev/null
echo "Готово: $APP"
