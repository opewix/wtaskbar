import AppKit

/// Как выглядит кнопка программы в данный момент.
struct ButtonLook {
    var hovered = false
    var pressed = false
    var active = false
    var running = false
    var labeled = false
    /// Сколько окон в кнопке программы; у кнопки отдельного окна — 1.
    var windows = 0
    var icon: NSImage
    var title: String
}

/// Цвета календаря над часами.
struct CalendarPalette {
    var background: NSColor
    var text: NSColor
    var dim: NSColor
    var accent: NSColor
    var date: NSColor
    var separator: NSColor
}

/// Оформление панели. Раскладку делает `TaskbarView`, тема только рисует и задаёт размеры.
protocol Skin {
    var barHeight: CGFloat { get }
    /// Кнопка без подписи: значок программы (в XP и Vista — как в «Быстром запуске»).
    var buttonWidth: CGFloat { get }
    var iconSize: CGFloat { get }
    var startWidth: CGFloat { get }
    /// В XP и Vista у запущенных программ всегда подписи; группировка лишь объединяет окна.
    var labelsAlways: Bool { get }
    /// Поле поиска, «Представление задач», дата под часами и маленькие кнопки — только в Windows 10.
    var isModern: Bool { get }
    var font: NSFont { get }
    var trayText: NSColor { get }
    var languageWidth: CGFloat { get }
    var menuAppearance: NSAppearance? { get }
    var calendar: CalendarPalette { get }

    func drawBar(_ bounds: NSRect, trayFrom: CGFloat)
    func drawStart(_ rect: NSRect, hovered: Bool, pressed: Bool)
    func drawTaskButton(_ rect: NSRect, _ look: ButtonLook)
    func drawTrayButton(_ rect: NSRect, hovered: Bool, pressed: Bool, active: Bool)
    func drawLanguage(_ rect: NSRect, _ source: InputSource.Source?, hovered: Bool, pressed: Bool)
}

extension Skin {
    var languageWidth: CGFloat { 30 }

    /// Подпись кнопки: в сгруппированной кнопке XP и Vista — число окон перед названием.
    func caption(_ look: ButtonLook) -> String {
        look.windows > 1 ? "\(look.windows) \(look.title)" : look.title
    }

    func drawCaption(_ text: String, in rect: NSRect, color: NSColor, shadow: Bool) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if shadow {
            let s = NSShadow()
            s.shadowOffset = NSSize(width: 1, height: -1)
            s.shadowBlurRadius = 1
            s.shadowColor = NSColor(white: 0, alpha: 0.6)
            attrs[.shadow] = s
        }
        let height = text.size(withAttributes: attrs).height
        text.draw(with: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    func drawIcon(_ icon: NSImage, at x: CGFloat, in rect: NSRect) {
        let s = iconSize
        icon.draw(in: NSRect(x: x, y: rect.midY - s / 2, width: s, height: s), from: .zero, operation: .sourceOver, fraction: 1)
    }

    func centeredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}

extension NSColor {
    /// Цвет из 0xRRGGBB — так их и записывают в описаниях тем Windows.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Вертикальный градиент сверху вниз по точкам (цвет, доля высоты от верха).
func verticalGradient(_ stops: [(NSColor, CGFloat)], in rect: NSRect, path: NSBezierPath? = nil) {
    guard let gradient = NSGradient(colors: stops.map(\.0), atLocations: stops.map(\.1), colorSpace: .sRGB) else { return }
    if let path { gradient.draw(in: path, angle: -90) } else { gradient.draw(in: rect, angle: -90) }
}

// MARK: - Windows 10

struct Win10Skin: Skin {
    var barHeight: CGFloat { Settings.smallButtons ? 30 : 40 }
    var buttonWidth: CGFloat { Settings.smallButtons ? 40 : 48 }
    var iconSize: CGFloat { Settings.smallButtons ? 16 : 24 }
    var startWidth: CGFloat { buttonWidth }
    let labelsAlways = false
    let isModern = true
    var font: NSFont { Theme.font }
    var trayText: NSColor { Theme.text }
    var languageWidth: CGFloat { 40 }
    var menuAppearance: NSAppearance? { Theme.darkAppearance }
    var calendar: CalendarPalette {
        CalendarPalette(background: Theme.flyoutBackground, text: Theme.text, dim: Theme.dimText,
                        accent: Theme.accent, date: Theme.indicator, separator: Theme.separator)
    }

    func drawBar(_ bounds: NSRect, trayFrom: CGFloat) {
        Theme.barBackground.setFill()
        bounds.fill()
    }

    func drawStart(_ rect: NSRect, hovered: Bool, pressed: Bool) {
        fill(rect, hovered: hovered, pressed: pressed, active: false)
        Glyphs.start(in: rect, color: hovered ? Theme.indicator : Theme.text)
    }

    func drawTaskButton(_ rect: NSRect, _ look: ButtonLook) {
        if look.labeled { drawLabeled(rect, look) } else { drawIconOnly(rect, look) }
    }

    func drawTrayButton(_ rect: NSRect, hovered: Bool, pressed: Bool, active: Bool) {
        fill(rect, hovered: hovered, pressed: pressed, active: active)
    }

    func drawLanguage(_ rect: NSRect, _ source: InputSource.Source?, hovered: Bool, pressed: Bool) {
        fill(rect, hovered: hovered, pressed: pressed, active: false)
        centeredText(source?.label ?? "", in: rect, font: font, color: trayText)
    }

    private func fill(_ rect: NSRect, hovered: Bool, pressed: Bool, active: Bool) {
        let color: NSColor?
        if active { color = hovered ? Theme.activeHover : Theme.active }
        else if pressed { color = Theme.pressed }
        else if hovered { color = Theme.hover }
        else { color = nil }
        color?.setFill()
        if color != nil { rect.fill() }
    }

    private func drawLabeled(_ rect: NSRect, _ look: ButtonLook) {
        if look.active || look.hovered || look.pressed {
            fill(rect, hovered: look.hovered, pressed: look.pressed, active: look.active)
        } else if look.running {
            Theme.running.setFill()
            rect.fill()
        }
        let pad: CGFloat = Settings.smallButtons ? 6 : 10
        drawIcon(look.icon, at: rect.minX + pad, in: rect)
        let textX = rect.minX + pad + iconSize + 8
        if rect.maxX - textX > 16 {
            drawCaption(look.title, in: NSRect(x: textX, y: rect.minY, width: rect.maxX - textX - 6, height: rect.height),
                        color: Theme.text, shadow: false)
        }
        if look.running {
            Theme.indicator.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: Theme.indicatorHeight).fill()
        }
    }

    /// Значок, полоска «запущена», «стопка» справа, если окон больше одного.
    private func drawIconOnly(_ rect: NSRect, _ look: ButtonLook) {
        let stacked = look.running && look.windows > 1
        var background: NSColor?
        if look.active { background = look.hovered ? Theme.activeHover : Theme.active }
        else if look.pressed { background = Theme.pressed }
        else if look.hovered { background = Theme.hover }
        if let background {
            background.setFill()
            // У «стопки» основная плашка короче, справа виден край второго окна.
            NSRect(x: rect.minX, y: rect.minY, width: rect.width - (stacked ? 3 : 0), height: rect.height).fill()
            if stacked {
                background.withAlphaComponent(background.alphaComponent * 0.6).setFill()
                NSRect(x: rect.maxX - 2, y: rect.minY, width: 2, height: rect.height).fill()
            }
        }
        drawIcon(look.icon, at: rect.midX - iconSize / 2, in: rect)
        if look.running {
            // Активная — полоска во всю ширину, фоновая — с отступами.
            let inset: CGFloat = look.active || look.hovered ? 0 : 6
            Theme.indicator.setFill()
            let width = rect.width - (stacked ? 3 : 0) - inset * 2
            NSRect(x: rect.minX + inset, y: rect.minY, width: width, height: Theme.indicatorHeight).fill()
            if stacked {
                NSRect(x: rect.maxX - 2, y: rect.minY, width: 2, height: Theme.indicatorHeight).fill()
            }
        }
    }
}

// MARK: - Windows XP (Luna, синяя)

struct XPSkin: Skin {
    let barHeight: CGFloat = 30
    let buttonWidth: CGFloat = 24
    let iconSize: CGFloat = 16
    let startWidth: CGFloat = 100
    let labelsAlways = true
    let isModern = false
    var font: NSFont { NSFont.systemFont(ofSize: 11) }
    var trayText: NSColor { .white }
    var languageWidth: CGFloat { 28 }
    var menuAppearance: NSAppearance? { NSAppearance(named: .aqua) }
    var calendar: CalendarPalette {
        CalendarPalette(background: NSColor(hex: 0xECE9D8), text: .black, dim: NSColor(hex: 0x8D8961),
                        accent: NSColor(hex: 0x316AC5), date: NSColor(hex: 0x0A246A), separator: NSColor(hex: 0xACA899))
    }

    func drawBar(_ bounds: NSRect, trayFrom: CGFloat) {
        verticalGradient([(NSColor(hex: 0x3A81F3), 0), (NSColor(hex: 0x2D6BE4), 0.1), (NSColor(hex: 0x245EDB), 0.5),
                          (NSColor(hex: 0x2157D6), 0.9), (NSColor(hex: 0x1941A5), 1)], in: bounds)
        NSColor(hex: 0x5A95F6).setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        // Область уведомлений — голубая, с тёмной и светлой гранью слева.
        let tray = NSRect(x: trayFrom, y: bounds.minY, width: bounds.maxX - trayFrom, height: bounds.height - 1)
        verticalGradient([(NSColor(hex: 0x1C9AF0), 0), (NSColor(hex: 0x0F8BE9), 0.15), (NSColor(hex: 0x0C82DF), 0.6),
                          (NSColor(hex: 0x0A6FCB), 1)], in: tray)
        NSColor(hex: 0x1042AF).setFill()
        NSRect(x: tray.minX, y: tray.minY, width: 1, height: tray.height).fill()
        NSColor(hex: 0x19B9F3).setFill()
        NSRect(x: tray.minX + 1, y: tray.minY, width: 1, height: tray.height).fill()
    }

    /// Зелёная кнопка со скруглённым правым краем и надписью «пуск» курсивом.
    func drawStart(_ rect: NSRect, hovered: Bool, pressed: Bool) {
        let r = rect
        let radius = r.height * 0.42
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        path.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        path.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        path.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: r.minX, y: r.maxY))
        path.close()
        let base: [(UInt32, CGFloat)] = pressed
            ? [(0x2B7A2B, 0), (0x2F8A2F, 0.3), (0x358F35, 1)]
            : hovered
            ? [(0x7FCC7F, 0), (0x4DAE4D, 0.15), (0x45A345, 0.6), (0x358A35, 1)]
            : [(0x67BC67, 0), (0x3F9C3F, 0.15), (0x379437, 0.6), (0x2D7D2D, 1)]
        verticalGradient(base.map { (NSColor(hex: $0.0), $0.1) }, in: r, path: path)
        NSColor(hex: 0x1E5E1E, alpha: 0.6).setStroke()
        path.lineWidth = 1
        path.stroke()

        let glyphRect = NSRect(x: r.minX + 8, y: r.minY, width: 20, height: r.height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 1
        shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        shadow.set()
        Glyphs.start(in: glyphRect, color: .white, size: 14)
        let title = L.t("пуск", "start")
        let font = NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize: 17), toHaveTrait: .italicFontMask)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: glyphRect.maxX + 5, y: r.midY - size.height / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawTaskButton(_ rect: NSRect, _ look: ButtonLook) {
        guard look.labeled else {
            // Значок «Быстрого запуска».
            if look.hovered || look.pressed {
                let box = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 4), xRadius: 2, yRadius: 2)
                NSColor(white: 1, alpha: look.pressed ? 0.1 : 0.2).setFill()
                box.fill()
                NSColor(white: 1, alpha: 0.4).setStroke()
                box.stroke()
            }
            drawIcon(look.icon, at: rect.midX - iconSize / 2, in: rect)
            return
        }
        let box = NSRect(x: rect.minX + 1, y: rect.minY + 2, width: rect.width - 2, height: rect.height - 5)
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        let stops: [(UInt32, CGFloat)]
        if look.active || look.pressed {
            stops = [(0x1A43A7, 0), (0x1E4DB9, 0.2), (0x2155C4, 1)]
        } else if look.hovered {
            stops = [(0x6BB3FF, 0), (0x4D97FA, 0.2), (0x3F87F3, 1)]
        } else {
            stops = [(0x5AA2FF, 0), (0x3C8BF8, 0.2), (0x3480F2, 1)]
        }
        verticalGradient(stops.map { (NSColor(hex: $0.0), $0.1) }, in: box, path: path)
        NSColor(hex: look.active ? 0x113796 : 0x1F56C9).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawIcon(look.icon, at: box.minX + 5, in: box)
        let textX = box.minX + 5 + iconSize + 5
        var textWidth = box.maxX - textX - 4
        if look.windows > 1 {
            // Треугольник: в сгруппированной кнопке — список окон.
            textWidth -= 10
            let tri = NSBezierPath()
            let cx = box.maxX - 9, cy = box.midY
            tri.move(to: NSPoint(x: cx - 3, y: cy + 2))
            tri.line(to: NSPoint(x: cx + 3, y: cy + 2))
            tri.line(to: NSPoint(x: cx, y: cy - 2))
            tri.close()
            NSColor.white.setFill()
            tri.fill()
        }
        if textWidth > 10 {
            let font = look.active ? NSFont.boldSystemFont(ofSize: 11) : self.font
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 1, height: -1)
            shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
            attrs[.shadow] = shadow
            let text = caption(look)
            let height = text.size(withAttributes: attrs).height
            text.draw(with: NSRect(x: textX, y: box.midY - height / 2, width: textWidth, height: height),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        }
    }

    func drawTrayButton(_ rect: NSRect, hovered: Bool, pressed: Bool, active: Bool) {
        guard hovered || pressed || active else { return }
        NSColor(white: 1, alpha: pressed || active ? 0.08 : 0.14).setFill()
        rect.fill()
    }

    /// Синий квадратик «RU / EN» языковой панели.
    func drawLanguage(_ rect: NSRect, _ source: InputSource.Source?, hovered: Bool, pressed: Bool) {
        let box = NSRect(x: rect.midX - 10, y: rect.midY - 8, width: 20, height: 16)
        let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
        NSColor(hex: hovered ? 0x3A78E0 : 0x2A5FCF).setFill()
        path.fill()
        NSColor(hex: 0x8FC1FF, alpha: 0.7).setStroke()
        path.stroke()
        centeredText(source?.code ?? "", in: box, font: NSFont.boldSystemFont(ofSize: 9), color: .white)
    }
}

// MARK: - Windows Vista (Aero, чёрное стекло)

struct VistaSkin: Skin {
    let barHeight: CGFloat = 30
    let buttonWidth: CGFloat = 26
    let iconSize: CGFloat = 16
    let startWidth: CGFloat = 50
    let labelsAlways = true
    let isModern = false
    var font: NSFont { NSFont.systemFont(ofSize: 11) }
    var trayText: NSColor { .white }
    var menuAppearance: NSAppearance? { Theme.darkAppearance }
    var calendar: CalendarPalette {
        CalendarPalette(background: NSColor(hex: 0x16202B, alpha: 0.97), text: .white, dim: NSColor(white: 1, alpha: 0.45),
                        accent: NSColor(hex: 0x3B8FE0), date: NSColor(hex: 0x9ACBF5), separator: NSColor(white: 1, alpha: 0.15))
    }

    func drawBar(_ bounds: NSRect, trayFrom: CGFloat) {
        // Верхняя половина светлее нижней — блик стекла.
        verticalGradient([(NSColor(hex: 0x5A6168, alpha: 0.80), 0), (NSColor(hex: 0x2A2F34, alpha: 0.84), 0.48),
                          (NSColor(hex: 0x0D1012, alpha: 0.90), 0.52), (NSColor(hex: 0x000000, alpha: 0.94), 1)], in: bounds)
        NSColor(white: 1, alpha: 0.35).setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        // Граница области уведомлений.
        NSColor(white: 0, alpha: 0.6).setFill()
        NSRect(x: trayFrom, y: bounds.minY + 3, width: 1, height: bounds.height - 6).fill()
        NSColor(white: 1, alpha: 0.18).setFill()
        NSRect(x: trayFrom + 1, y: bounds.minY + 3, width: 1, height: bounds.height - 6).fill()
    }

    /// Круглая стеклянная кнопка: тёмный шар, голубое свечение снизу, блик сверху.
    func drawStart(_ rect: NSRect, hovered: Bool, pressed: Bool) {
        let d = min(rect.height - 2, 28)
        let orb = NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
        let circle = NSBezierPath(ovalIn: orb)

        NSGradient(starting: NSColor(hex: 0x2E353D), ending: NSColor(hex: 0x050709))?
            .draw(in: circle, relativeCenterPosition: NSPoint(x: 0, y: 0.3))
        let glow = NSGradient(colors: [NSColor(hex: pressed ? 0x2F8FD8 : hovered ? 0x6FD0FF : 0x45B4F5, alpha: hovered ? 0.95 : 0.8),
                                       NSColor(hex: 0x1B6FB8, alpha: 0)])
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        glow?.draw(in: circle, relativeCenterPosition: NSPoint(x: 0, y: -0.9))
        // Блик — эллипс в верхней половине.
        let shine = NSBezierPath(ovalIn: NSRect(x: orb.minX + d * 0.14, y: orb.midY - d * 0.02, width: d * 0.72, height: d * 0.48))
        NSGradient(starting: NSColor(white: 1, alpha: 0.55), ending: NSColor(white: 1, alpha: 0.04))?.draw(in: shine, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.45).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        Glyphs.start(in: orb, color: .white, size: d * 0.42)
    }

    func drawTaskButton(_ rect: NSRect, _ look: ButtonLook) {
        guard look.labeled else {
            if look.hovered || look.pressed { glass(rect.insetBy(dx: 1, dy: 3), level: look.pressed ? 0.2 : 0.3, tint: true) }
            drawIcon(look.icon, at: rect.midX - iconSize / 2, in: rect)
            return
        }
        let box = NSRect(x: rect.minX + 1, y: rect.minY + 2, width: rect.width - 2, height: rect.height - 4)
        if look.active { glass(box, level: 0.36, tint: look.hovered) }
        else if look.hovered || look.pressed { glass(box, level: look.pressed ? 0.18 : 0.26, tint: true) }
        else { glass(box, level: 0.16, tint: false) }
        drawIcon(look.icon, at: box.minX + 6, in: box)
        let textX = box.minX + 6 + iconSize + 6
        if box.maxX - textX > 10 {
            drawCaption(caption(look), in: NSRect(x: textX, y: box.minY, width: box.maxX - textX - 5, height: box.height),
                        color: .white, shadow: true)
        }
    }

    /// Стеклянная плашка: светлая верхняя половина, рамка, голубой оттенок под курсором.
    private func glass(_ box: NSRect, level: CGFloat, tint: Bool) {
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        let top = tint ? NSColor(hex: 0x9BD3FF, alpha: level + 0.05) : NSColor(white: 1, alpha: level)
        let bottom = tint ? NSColor(hex: 0x2F7FC6, alpha: level * 0.7) : NSColor(white: 1, alpha: level * 0.25)
        verticalGradient([(top, 0), (top.withAlphaComponent(top.alphaComponent * 0.6), 0.48),
                          (bottom.withAlphaComponent(bottom.alphaComponent * 0.6), 0.52), (bottom, 1)], in: box, path: path)
        NSColor(white: 0, alpha: 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSColor(white: 1, alpha: 0.28 + level * 0.3).setStroke()
        NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).stroke()
    }

    func drawTrayButton(_ rect: NSRect, hovered: Bool, pressed: Bool, active: Bool) {
        guard hovered || pressed || active else { return }
        glass(rect.insetBy(dx: 1, dy: 3), level: pressed || active ? 0.2 : 0.14, tint: false)
    }

    func drawLanguage(_ rect: NSRect, _ source: InputSource.Source?, hovered: Bool, pressed: Bool) {
        drawTrayButton(rect, hovered: hovered, pressed: pressed, active: false)
        centeredText(source?.code ?? "", in: rect, font: font, color: trayText)
    }
}
