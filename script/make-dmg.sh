#!/bin/sh
# Package and notarize a Developer ID-signed macOS app.
# Usage: make-dmg.sh /path/App.app /path/App.dmg [--app-already-stapled]
set -eu

APP_DIR=$(cd "$(dirname "$1")" && pwd)
APP_FILE=$(basename "$1")
APP="$APP_DIR/$APP_FILE"
VOLUME=${APP_FILE%.app}
OUTPUT=$2
SIGN_ID=${DEVELOPER_ID_APPLICATION:-Developer ID Application: Scaling Adventures LLC (3G5832B4DA)}
KEY_ID=${NOTARY_KEY_ID:-3QL56ZM2UJ}
ISSUER=${NOTARY_ISSUER:-d4d04f18-e907-4b82-9a5f-bddffc3ea5b5}
KEY=${NOTARY_KEY_PATH:-"$HOME/.asc/keys/AuthKey_$KEY_ID.p8"}

command -v create-dmg >/dev/null || { echo "Install create-dmg with brew install create-dmg" >&2; exit 1; }
test -r "$KEY" || { echo "App Store Connect notarization key is unavailable" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
mkdir -p "$(dirname "$OUTPUT")"
WORK=$(mktemp -d "$(dirname "$OUTPUT")/.dmg.XXXXXXXX")
WORK=$(cd "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' HUP INT TERM

notarize() {
    xcrun notarytool submit "$1" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" \
        --wait --timeout 4m --output-format json >"$WORK/notary.json" || {
        cat "$WORK/notary.json" >&2
        return 1
    }
    cat "$WORK/notary.json"
    test "$(plutil -extract status raw -o - "$WORK/notary.json")" = Accepted
}

if [ "${3:-}" != --app-already-stapled ]; then
    ditto -c -k --keepParent "$APP" "$WORK/app.zip"
    notarize "$WORK/app.zip"
    xcrun stapler staple "$APP"
fi
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/$APP_FILE"

# Finder uses the 1x and 2x representations in a single TIFF.
cat >"$WORK/background.swift" <<'SWIFT'
import AppKit

let width = 600
let height = 400
for scale in [1, 2] {
    let canvas = CGContext(
        data: nil, width: width * scale, height: height * scale,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let context = NSGraphicsContext(cgContext: canvas, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 254, y: 233))
    arrow.line(to: NSPoint(x: 346, y: 233))
    arrow.move(to: NSPoint(x: 330, y: 249))
    arrow.line(to: NSPoint(x: 346, y: 233))
    arrow.line(to: NSPoint(x: 330, y: 217))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(srgbRed: 0.49, green: 0.54, blue: 0.60, alpha: 1).setStroke()
    arrow.stroke()

    let label = NSAttributedString(string: "Drag to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.31, green: 0.35, blue: 0.41, alpha: 1)
    ])
    label.draw(at: NSPoint(x: (CGFloat(width) - label.size().width) / 2, y: 123))

    NSGraphicsContext.restoreGraphicsState()
    let path = CommandLine.arguments[1] + "/background-\(scale)x.png"
    let bitmap = NSBitmapImageRep(cgImage: canvas.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
SWIFT
swift "$WORK/background.swift" "$WORK"
tiffutil -cathidpicheck "$WORK/background-1x.png" "$WORK/background-2x.png" -out "$WORK/background.tiff"

DMG="$WORK/$(basename "$OUTPUT")"
create-dmg --volname "$VOLUME" --background "$WORK/background.tiff" \
    --window-pos 200 120 --window-size 600 400 --text-size 14 --icon-size 112 \
    --icon "$APP_FILE" 155 167 --hide-extension "$APP_FILE" --app-drop-link 445 167 \
    --format UDZO --no-internet-enable "$DMG" "$WORK/stage"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --strict "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
mv -f "$DMG" "$OUTPUT"
echo "Built $OUTPUT"
