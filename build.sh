#!/bin/sh
# Builds ~/Applications/Parrot.app (ad-hoc signed). The app registers itself as a login item on first launch.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Parrot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Icon: assets/icon.svg → AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
swiftc -O tools/svg2png.swift -o "$ICONSET/../svg2png"
for s in 16 32 128 256 512; do
  "$ICONSET/../svg2png" assets/icon.svg "$ICONSET/icon_${s}x${s}.png" $s
  "$ICONSET/../svg2png" assets/icon.svg "$ICONSET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14.0" Parrot.swift PopoverView.swift -o "$APP/Contents/MacOS/Parrot"
cp -R speakd.py models "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.brahim.parrot</string>
<key>CFBundleName</key><string>Parrot</string>
<key>CFBundleExecutable</key><string>Parrot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>Parrot</string>
  <key>CFBundleURLSchemes</key><array><string>parrot</string></array>
</dict></array>
</dict></plist>
PLIST
# Pin the designated requirement to the bundle id so rebuilds keep the Accessibility grant.
codesign --force --sign - -r='designated => identifier "dev.brahim.parrot"' "$APP"
echo "built $APP"
