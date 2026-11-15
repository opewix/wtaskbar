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

    /// Динамик контуром и волны по громкости: ни одной у тишины, до трёх у громкого звука.
    /// Без звука — крестик вместо волн. Рисунок симметричен по вертикали, перевёрнутость вида не важна.
    static func speaker(in rect: NSRect, color: NSColor, level: Float, muted: Bool, size: CGFloat = 16) {
        let u = size / 16
        let left = rect.midX - 8 * u
        let mid = rect.midY
        color.setStroke()
        let body = NSBezierPath()
        body.move(to: NSPoint(x: left + 0.5 * u, y: mid - 2.5 * u))
        body.line(to: NSPoint(x: left + 3.5 * u, y: mid - 2.5 * u))
        body.line(to: NSPoint(x: left + 7.5 * u, y: mid - 6 * u))
        body.line(to: NSPoint(x: left + 7.5 * u, y: mid + 6 * u))
        body.line(to: NSPoint(x: left + 3.5 * u, y: mid + 2.5 * u))
        body.line(to: NSPoint(x: left + 0.5 * u, y: mid + 2.5 * u))
        body.close()
        body.lineWidth = max(1, u)
        body.lineJoinStyle = .round
        body.stroke()

        let center = NSPoint(x: left + 7.5 * u, y: mid)
        if muted {
            let cross = NSBezierPath()
            let c = NSPoint(x: left + 12.5 * u, y: mid)
            let d = 2.5 * u
            cross.move(to: NSPoint(x: c.x - d, y: c.y - d))
            cross.line(to: NSPoint(x: c.x + d, y: c.y + d))
            cross.move(to: NSPoint(x: c.x - d, y: c.y + d))
            cross.line(to: NSPoint(x: c.x + d, y: c.y - d))
            cross.lineWidth = max(1, u)
            cross.stroke()
            return
        }
        let waves = level <= 0 ? 0 : level < 0.34 ? 1 : level < 0.67 ? 2 : 3
        for wave in 0..<waves {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: (2.5 + CGFloat(wave) * 2.5) * u, startAngle: -50, endAngle: 50)
            arc.lineWidth = max(1, u)
            arc.lineCapStyle = .round
            arc.stroke()
        }
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
