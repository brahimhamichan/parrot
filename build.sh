#!/bin/sh
# Builds ~/Applications/Parrot.app for local use.
# Use ./build.sh release to build a notarized DMG with first-launch runtime setup.
set -eu
cd "$(dirname "$0")"
APP="$HOME/Applications/Parrot.app"
if [ "${1:-}" = release ]; then APP=dist/Parrot.app; fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Icon: assets/icon-source.png → AppIcon.icns
ICONSET="$WORK/AppIcon.iconset"; mkdir -p "$ICONSET"
swiftc -O tools/makeicon.swift -o "$ICONSET/../makeicon"
for s in 16 32 128 256 512; do
  "$ICONSET/../makeicon" assets/icon-source.png "$ICONSET/icon_${s}x${s}.png" $s
  "$ICONSET/../makeicon" assets/icon-source.png "$ICONSET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
if [ "${1:-}" = release ]; then
  for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$arch-apple-macos14.0" Parrot.swift PopoverView.swift -o "$WORK/$arch"
  done
  lipo -create "$WORK/arm64" "$WORK/x86_64" -output "$APP/Contents/MacOS/Parrot"
else
  swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14.0" Parrot.swift PopoverView.swift -o "$APP/Contents/MacOS/Parrot"
fi
cp -R speakd.py models "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.brahim.parrot</string>
<key>CFBundleName</key><string>Parrot</string>
<key>CFBundleExecutable</key><string>Parrot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>Parrot</string>
  <key>CFBundleURLSchemes</key><array><string>parrot</string></array>
</dict></array>
</dict></plist>
PLIST
if [ "${1:-}" = release ]; then
  SIGN_ID=${DEVELOPER_ID_APPLICATION:-Developer ID Application: Scaling Adventures LLC (3G5832B4DA)}
  mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/licenses"
  cp script/bootstrap-runtime.sh requirements-macos.lock "$APP/Contents/Resources/"
  cp LICENSE NOTICE.md licenses/uv-LICENSE-* "$APP/Contents/Resources/licenses/"
  ./script/fetch-uv.sh "$WORK" "$APP/Contents/Helpers/uv"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/Helpers/uv"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  ./script/make-dmg.sh "$APP" dist/Parrot.dmg
else
  # Preserve the Accessibility grant on local rebuilds.
  codesign --force --sign - -r='designated => identifier "dev.brahim.parrot"' "$APP"
  echo "built $APP"
fi
