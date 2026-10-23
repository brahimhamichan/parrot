// Renders assets/social-preview.png (1280×640) for GitHub's social preview and the landing page.
import AppKit

let W = 1280, H = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.08, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.09, green: 0.16, blue: 0.42, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 30)
NSImage(contentsOfFile: CommandLine.arguments[1])!.draw(in: NSRect(x: 70, y: 150, width: 340, height: 340))

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, _ y: CGFloat) {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 6
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
        .draw(in: NSRect(x: 460, y: y, width: 760, height: 200))
}
text("Parrot", 92, .heavy, .white, 300)
text("Free offline text-to-speech for Mac", 40, .semibold, NSColor(srgbRed: 0.53, green: 0.94, blue: 0.67, alpha: 1), 190)
text("Select any text, press ⌥Esc, hear it read aloud in a natural AI voice. Private, open source, no subscription.", 28, .regular, NSColor.white.withAlphaComponent(0.8), 120)
text("github.com/brahimhamichan/parrot", 24, .medium, NSColor.white.withAlphaComponent(0.55), 10)
NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
