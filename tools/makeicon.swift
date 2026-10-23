// Fits a square artwork into the macOS icon grid (824² squircle on a 1024² transparent canvas, soft shadow).
// Usage: makeicon <source.png> <out.png> <pixels>
import AppKit

let src = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let px = Int(CommandLine.arguments[3])!
let s = CGFloat(px) / 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
let ctx = NSGraphicsContext.current!.cgContext
let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.restoreGState()
shape.addClip()
// The artwork has its own rounded tile; overscan slightly so its corners fall outside our clip.
src.draw(in: body.insetBy(dx: -24 * s, dy: -24 * s))
NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
