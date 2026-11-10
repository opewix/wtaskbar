import AppKit

/// Свои глифы панели: рисуем сами, графики Microsoft в программе нет.
enum Glyphs {
    /// Кнопка «Пуск»: окно из четырёх створок.
    static func start(in rect: NSRect, color: NSColor, size: CGFloat = 16) {
        let gap: CGFloat = max(1, size * 0.09)
        let pane = (size - gap) / 2
        let origin = NSPoint(x: rect.midX - size / 2, y: rect.midY - size / 2)
        color.setFill()
        for col in 0..<2 {
            for row in 0..<2 {
                NSRect(x: origin.x + CGFloat(col) * (pane + gap),
                       y: origin.y + CGFloat(row) * (pane + gap),
                       width: pane, height: pane).fill()
            }
        }
    }

    /// Лупа ручкой влево вниз, как в поле поиска Windows 10.
    static func search(in rect: NSRect, color: NSColor) {
        let radius: CGFloat = 5.5
        // В перевёрнутом виде «вниз» — это рост y; ручка должна смотреть вниз в обоих случаях.
        let down: CGFloat = NSGraphicsContext.current?.isFlipped == true ? -1 : 1
        let center = NSPoint(x: rect.midX + 2, y: rect.midY + 2 * down)
        color.setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        circle.lineWidth = 1.2
        circle.stroke()
        let handle = NSBezierPath()
        let d = radius * 0.7071
        handle.move(to: NSPoint(x: center.x - d, y: center.y - d * down))
        handle.line(to: NSPoint(x: center.x - d - 5, y: center.y - (d + 5) * down))
        handle.lineWidth = 1.4
        handle.stroke()
    }

    /// «Представление задач»: окно в центре и края соседних по бокам.
    static func taskView(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let main = NSRect(x: rect.midX - 6.5, y: rect.midY - 5, width: 13, height: 10)
        let frame = NSBezierPath(rect: main.insetBy(dx: 0.5, dy: 0.5))
        frame.lineWidth = 1
        frame.stroke()
        color.setFill()
        NSRect(x: main.minX - 4, y: main.minY + 1, width: 1, height: main.height - 2).fill()
        NSRect(x: main.maxX + 3, y: main.minY + 1, width: 1, height: main.height - 2).fill()
    }
}
