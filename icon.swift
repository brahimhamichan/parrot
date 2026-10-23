// Renders AppIcon.png (1024²): violet squircle, a highlighted "selected text" line, and a waveform rising out of it.
import AppKit

let S: CGFloat = 1024
// Draw into an exact 1024² RGBA bitmap so the corners stay transparent.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle body with Apple's ~10% margin and soft drop shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); path.fill()
ctx.restoreGState()
path.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.11, blue: 0.52, alpha: 1),
                    NSColor(srgbRed: 0.45, green: 0.25, blue: 0.95, alpha: 1),
                    NSColor(srgbRed: 0.93, green: 0.42, blue: 0.85, alpha: 1)])!
    .draw(in: body, angle: 60)
// Gentle top sheen.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

// "Text lines" with the middle one selected.
func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
    c.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: min(w, h) / 2, yRadius: min(w, h) / 2).fill()
}
bar(230, 320, 420, 34, NSColor.white.withAlphaComponent(0.35))
let sel = NSRect(x: 210, y: 210, width: 604, height: 70)
NSColor.white.withAlphaComponent(0.28).setFill()
NSBezierPath(roundedRect: sel, xRadius: 16, yRadius: 16).fill()
bar(240, 230, 544, 30, NSColor.white.withAlphaComponent(0.95))
// Selection handles.
for x in [sel.minX, sel.maxX] {
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: x - 5, y: sel.minY - 6, width: 10, height: sel.height + 12)).fill()
    NSBezierPath(ovalIn: NSRect(x: x - 18, y: x == sel.minX ? sel.maxY + 2 : sel.minY - 38, width: 36, height: 36)).fill()
}

// Waveform rising above the selection.
let heights: [CGFloat] = [120, 230, 340, 430, 340, 230, 120]
let w: CGFloat = 54, gap: CGFloat = 30
let total = CGFloat(heights.count) * w + CGFloat(heights.count - 1) * gap
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: NSColor.white.withAlphaComponent(0.55).cgColor)
for (i, h) in heights.enumerated() {
    bar((S - total) / 2 + CGFloat(i) * (w + gap), 650 - h / 2, w, h, .white)
}
ctx.restoreGState()
NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
