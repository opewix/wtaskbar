import AppKit

/// Палитра тёмной темы Windows 10 (её же используют «Пуск» и меню Windows 10)
/// и размеры панели выбранной темы.
enum Theme {
    static var skin: Skin {
        switch Settings.theme {
        case .win10: Win10Skin()
        case .vista: VistaSkin()
        case .xp: XPSkin()
        }
    }

    /// Высота панели в логических точках — в них идёт вся раскладка и отрисовка.
    static var barHeight: CGFloat { skin.barHeight }
    static var scale: CGFloat { CGFloat(Settings.scale) }
    /// Высота окна панели на экране — с учётом масштаба.
    static var barScreenHeight: CGFloat { (skin.barHeight * scale).rounded() }
    static var buttonWidth: CGFloat { skin.buttonWidth }
    static var iconSize: CGFloat { skin.iconSize }
    static let minButtonWidth: CGFloat = 32
    /// Уже этого кнопки с подписью не сжимаются в режиме «при заполнении» — дальше группировка.
    static let minLabeledWidth: CGFloat = 100
    static let searchWidth: CGFloat = 344
    static let indicatorHeight: CGFloat = 2
    /// Видимая полоска автоматически скрытой панели.
    static let hiddenBarSliver: CGFloat = 2

    static let barBackground = NSColor(white: 0.06, alpha: 0.82)
    static let hover = NSColor(white: 1, alpha: 0.10)
    static let pressed = NSColor(white: 1, alpha: 0.05)
    static let active = NSColor(white: 1, alpha: 0.16)
    static let activeHover = NSColor(white: 1, alpha: 0.22)
    static let text = NSColor(white: 1, alpha: 0.95)
    static let dimText = NSColor(white: 1, alpha: 0.55)
    static let flyoutBackground = NSColor(calibratedWhite: 0.12, alpha: 0.96)
    static let flyoutField = NSColor(calibratedWhite: 0.20, alpha: 1)
    static let separator = NSColor(white: 1, alpha: 0.12)

    static let searchBox = NSColor(calibratedWhite: 0.95, alpha: 1)
    static let searchBoxHover = NSColor.white
    static let searchText = NSColor(calibratedWhite: 0.40, alpha: 1)

    /// Акцентный цвет берём системный, как Windows берёт цвет из «Персонализации».
    static var accent: NSColor { NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue }
    /// Полоска под запущенной программой — светлый вариант акцента.
    static var indicator: NSColor { accent.blended(withFraction: 0.45, of: .white) ?? accent }
    static var tile: NSColor { accent.blended(withFraction: 0.25, of: .black) ?? accent }

    static var font: NSFont { Fonts.ui(12) }
    static var menuFont: NSFont { Fonts.ui(13) }
    static let darkAppearance = NSAppearance(named: .darkAqua)
}

/// Шрифт надписей панели, «Пуска» и всплывающих окон. Шрифтов Microsoft в программе нет: берём
/// те, что уже стоят в системе. Tahoma — шрифт интерфейса Windows XP — входит в macOS; Segoe UI
/// (Vista и Windows 10) используется, только если пользователь установил его сам.
enum Fonts {
    /// Какой шрифт сейчас в ходу — чтобы пересобрать то, что запомнило шрифт.
    static var signature: String { "\(Settings.windowsFont)|\(family ?? "system")" }

    private static var family: String? {
        guard Settings.windowsFont else { return nil }
        let wanted = Settings.theme == .xp ? ["Tahoma"] : ["Segoe UI", "Tahoma"]
        return wanted.first { available.contains($0) }
    }

    private static let available: Set<String> = Set(["Segoe UI", "Tahoma"].filter {
        NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 12) != nil
    })

    private static var cache: [String: NSFont] = [:]

    /// Шрифты спрашивают при каждой отрисовке — найденные запоминаем.
    static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let key = "\(family ?? "")|\(size)|\(weight.rawValue)"
        if let font = cache[key] { return font }
        let font = find(size, weight: weight)
        cache[key] = font
        return font
    }

    private static func find(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let family else { return system }
        // У Tahoma светлого начертания нет, а крупные светлые цифры (часы над календарём) обычным
        // начертанием выходят тяжёлыми — там остаётся системный шрифт.
        if weight.rawValue < NSFont.Weight.regular.rawValue, family == "Tahoma" { return system }
        let bold = weight.rawValue >= NSFont.Weight.semibold.rawValue
        let light = weight.rawValue < NSFont.Weight.regular.rawValue
        return NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [],
                                         weight: bold ? 9 : light ? 3 : 5, size: size) ?? system
    }

    /// Курсив; у шрифта без курсивного начертания (Tahoma) — наклон.
    static func italic(_ font: NSFont) -> NSFont {
        let converted = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        if NSFontManager.shared.traits(of: converted).contains(.italicFontMask) { return converted }
        let size = font.pointSize
        let skew = AffineTransform(m11: size, m12: 0, m21: size * 0.2, m22: size, tX: 0, tY: 0)
        return NSFont(descriptor: font.fontDescriptor.withMatrix(skew), size: size) ?? font
    }
}

extension NSImage {
    /// Перекрашивает силуэт значка (SF Symbols и свои глифы) в нужный цвет.
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }

    static func symbol(_ name: String, size: CGFloat, color: NSColor = Theme.text) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .tinted(color)
    }
}

extension NSMenuItem {
    /// Пункт меню с замыканием вместо пары target/action.
    static func action(_ title: String, checked: Bool = false, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

extension NSMenu {
    /// Меню в цветах темы: тёмное в Windows 10 и Vista, светлое в XP.
    static func themed() -> NSMenu {
        let menu = NSMenu()
        menu.appearance = Theme.skin.menuAppearance
        menu.autoenablesItems = false
        menu.font = Theme.menuFont
        return menu
    }
}
