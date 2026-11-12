// Рисует значок программы в .iconset для iconutil: синяя плитка, внизу крупная тёмная панель задач
// с кнопкой «Пуск» и двумя программами, у первой — полоска «запущена». См. scripts/bundle.sh.
import AppKit

// Плитка по сетке значков macOS: холст 1024, отступ 100, сторона 824, радиус 185,4. Только такую форму
// macOS 26 показывает во весь скруглённый квадрат; иную сажает на серую подложку и уменьшает.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185.4, yRadius: 185.4)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func withShadow(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: -dy)
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func startGlyph(centerX cx: CGFloat, centerY cy: CGFloat, size: CGFloat, color: NSColor) {
    let pane = size * 0.47, gap = size * 0.06
    color.setFill()
    for c in 0..<2 {
        for r in 0..<2 {
            rounded(cx - size / 2 + CGFloat(c) * (pane + gap), cy - size / 2 + CGFloat(r) * (pane + gap),
                    pane, pane, size * 0.04).fill()
        }
    }
}

func drawIcon() {
    gradient(tile, rgb(60, 140, 230), rgb(14, 60, 150))
    rgb(255, 255, 255, 0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: 200, y: 450, width: 620, height: 620)).fill()
    rgb(18, 22, 30, 0.97).setFill()
    NSRect(x: 100, y: 100, width: 824, height: 300).fill()
    rgb(60, 70, 90).setFill()
    rounded(170, 155, 190, 190, 36).fill()
    startGlyph(centerX: 265, centerY: 250, size: 120, color: rgb(120, 200, 255))
    rgb(220, 228, 240).setFill()
    for x in [410.0, 610.0] { rounded(x, 175, 150, 150, 30).fill() }
    rgb(120, 200, 255).setFill()
    rounded(440, 128, 90, 16, 8).fill()
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scaleTo = NSAffineTransform()
        scaleTo.scale(by: CGFloat(pixels) / 1024)
        scaleTo.concat()
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}

