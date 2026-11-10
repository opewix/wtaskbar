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
    /// Фон запущенной кнопки с подписью — в Windows она чуть светлее панели.
    static let running = NSColor(white: 1, alpha: 0.05)
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

    static let font = NSFont.systemFont(ofSize: 12)
    static let menuFont = NSFont.systemFont(ofSize: 13)
    static let darkAppearance = NSAppearance(named: .darkAqua)
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
