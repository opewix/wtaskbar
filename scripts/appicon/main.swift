import AppKit

// Рисует значок программы во всех размерах для .iconset: тёмная плитка, внизу — панель задач
// с кнопкой «Пуск» и полоской запущенной программы.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.80, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.48, alpha: 1))!.draw(in: shape, angle: -90)
    shape.addClip()
    let bar = NSRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height * 0.24)
    NSColor(white: 0.07, alpha: 0.95).setFill()
    bar.fill()
    let unit = bar.height
    let glyph = NSRect(x: bar.minX + unit * 0.3, y: bar.minY, width: unit, height: unit)
    let pane = unit * 0.2, gap = unit * 0.05
    NSColor.white.setFill()
    for c in 0..<2 { for r in 0..<2 {
        NSRect(x: glyph.midX - pane - gap / 2 + CGFloat(c) * (pane + gap),
               y: glyph.midY - pane - gap / 2 + CGFloat(r) * (pane + gap), width: pane, height: pane).fill()
    } }
    let apps = [glyph.maxX + unit * 0.3, glyph.maxX + unit * 1.3]
    for (i, x) in apps.enumerated() {
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: bar.minY + unit * 0.25, width: unit * 0.5, height: unit * 0.5),
                     xRadius: unit * 0.1, yRadius: unit * 0.1).fill()
        NSColor(calibratedRed: 0.55, green: 0.78, blue: 0.97, alpha: 1).setFill()
        NSRect(x: x - unit * (i == 0 ? 0.2 : 0.1), y: bar.minY, width: unit * (i == 0 ? 0.9 : 0.7), height: max(1, unit * 0.06)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
