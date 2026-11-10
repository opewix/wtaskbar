import AppKit

enum ClassicStyle {
    case xp, vista
}

/// «Пуск» XP и Vista. Слева — закреплённые программы и кнопка «Все программы»,
/// справа — папки и параметры, внизу — выход и выключение.
/// В XP строки поиска не было, но печатать можно и здесь: поле невидимо, а результаты
/// заменяют список слева. В Vista поле «Начать поиск» под списком, как в оригинале.
final class ClassicStartView: StartBaseView {
    private let style: ClassicStyle
    private let allButton: AllProgramsRow
    private var places: [NSView] = []
    private var footer: [FooterButton] = []
    private var showingAll = false

    private var listWidth: CGFloat { style == .xp ? 212 : 256 }

    init(style: ClassicStyle) {
        self.style = style
        allButton = AllProgramsRow(style: style)
        super.init(listStyle: style == .xp ? .xp : .vista)

        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.textColor = .black
        if style == .vista {
            searchField.placeholderAttributedString = NSAttributedString(
                string: L.t("Начать поиск", "Start Search"),
                attributes: [.foregroundColor: NSColor(hex: 0x7A7A7A),
                             .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)])
        } else {
            searchField.alphaValue = 0
        }
        addSubview(searchField)

        allButton.onClick = { [weak self] in
            guard let self else { return }
            self.showingAll.toggle()
            self.searchField.stringValue = ""
            self.refill()
            self.list.scroll(.zero)
        }
        addSubview(allButton)

        places = makePlaces()
        places.forEach(addSubview)
        footer = makeFooter()
        footer.forEach(addSubview)
        refill()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func reset() {
        showingAll = false
        super.reset()
    }

    override func showDefault() {
        if showingAll {
            list.show(AppCatalog.shared.entries, grouped: true, selectFirst: false)
        } else {
            list.show(TaskbarModel.shared.tiles.map { AppEntry(url: $0) }, grouped: false, selectFirst: false)
        }
        allButton.showingAll = showingAll
    }

    // MARK: Правая колонка и кнопки внизу

    private func makePlaces() -> [NSView] {
        let placeStyle: ListStyle = style == .xp
            ? ListStyle(text: NSColor(hex: 0x00136B), hoverFill: NSColor(hex: 0x316AC5), hoverText: .white, header: .black,
                        font: .systemFont(ofSize: 12), rowHeight: 30, iconSize: 24)
            : ListStyle(text: .white, hoverFill: NSColor(white: 1, alpha: 0.14), hoverBorder: NSColor(white: 1, alpha: 0.35),
                        hoverText: .white, header: .white, font: .systemFont(ofSize: 12), rowHeight: 28, iconSize: 0, cornerRadius: 3)
        let home = URL(fileURLWithPath: NSHomeDirectory())
        func place(_ title: String, _ url: URL, bold: Bool = false) -> NSView {
            PlaceRow(title: title, url: url, bold: bold, style: placeStyle)
        }
        let documents = place(L.t("Мои документы", "My Documents"), StartMenu.folder(.documentDirectory), bold: style == .xp)
        let pictures = place(L.t("Мои рисунки", "My Pictures"), StartMenu.folder(.picturesDirectory), bold: style == .xp)
        let music = place(L.t("Моя музыка", "My Music"), StartMenu.folder(.musicDirectory), bold: style == .xp)
        let downloads = place(L.t("Загрузки", "Downloads"), StartMenu.folder(.downloadsDirectory))
        let computer = place(L.t("Мой компьютер", "My Computer"), URL(fileURLWithPath: "/"), bold: style == .xp)
        let apps = place(L.t("Программы", "Applications"), URL(fileURLWithPath: "/Applications"))
        let settings = place(L.t("Панель управления", "Control Panel"), Launcher.systemSettings)
        switch style {
        case .xp:
            return [documents, pictures, music, computer, PlaceSeparator(style: style), apps, downloads,
                    PlaceSeparator(style: style), settings]
        case .vista:
            return [place(NSFullUserName(), home, bold: true), documents, pictures, music, downloads,
                    PlaceSeparator(style: style), computer, apps, settings]
        }
    }

    private func makeFooter() -> [FooterButton] {
        switch style {
        case .xp:
            return [
                FooterButton(symbol: "rectangle.portrait.and.arrow.right", title: L.t("Выход из системы", "Log Off"),
                             color: NSColor(hex: 0xE39A2F), round: false, menu: StartMenu.userMenu),
                FooterButton(symbol: "power", title: L.t("Выключение", "Turn Off Computer"),
                             color: NSColor(hex: 0xD8402F), round: false, menu: StartMenu.powerMenu),
            ]
        case .vista:
            let all = { () -> NSMenu in
                let menu = StartMenu.userMenu()
                menu.addItem(.separator())
                StartMenu.powerMenu().items.forEach { item in
                    item.menu?.removeItem(item)
                    menu.addItem(item)
                }
                return menu
            }
            return [
                FooterButton(symbol: "power", title: nil, color: NSColor(hex: 0xD9822B), round: true,
                             tooltip: L.t("Спящий режим", "Sleep"), action: { StartMenu.shared.close(); Power.sleep() }),
                FooterButton(symbol: "lock.fill", title: nil, color: NSColor(hex: 0x8C969F), round: true,
                             tooltip: L.t("Заблокировать", "Lock"), action: { StartMenu.shared.close(); Power.lock() }),
                FooterButton(symbol: "chevron.right", title: nil, color: NSColor(hex: 0x56616B), round: false,
                             tooltip: L.t("Завершение работы", "Shut down options"), menu: all),
            ]
        }
    }

    // MARK: Раскладка

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        switch style {
        case .xp:
            let bodyTop: CGFloat = 60, footerTop = h - 42
            listScroll.frame = NSRect(x: 0, y: bodyTop + 6, width: listWidth, height: footerTop - bodyTop - 50)
            allButton.frame = NSRect(x: 6, y: footerTop - 38, width: listWidth - 12, height: 32)
            searchField.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
            var y = bodyTop + 8
            for place in places {
                place.frame = NSRect(x: listWidth + 4, y: y, width: w - listWidth - 8, height: placeHeight(place))
                y += placeHeight(place)
            }
            var x = w - 8
            for button in footer.reversed() {
                let width = button.preferredWidth
                x -= width
                button.frame = NSRect(x: x, y: footerTop + 5, width: width, height: 32)
                x -= 6
            }
        case .vista:
            let panel = vistaPanel
            listScroll.frame = NSRect(x: panel.minX + 1, y: panel.minY + 4, width: panel.width - 2, height: panel.height - 44)
            allButton.frame = NSRect(x: panel.minX + 2, y: panel.maxY - 36, width: panel.width - 4, height: 32)
            let search = vistaSearch
            searchField.frame = NSRect(x: search.minX + 8, y: search.minY + 5, width: search.width - 36, height: 18)
            var y: CGFloat = 78
            let x = panel.maxX + 8
            for place in places {
                place.frame = NSRect(x: x, y: y, width: w - x - 8, height: placeHeight(place))
                y += placeHeight(place)
            }
            var bx = x + 4
            for button in footer {
                let width = button.preferredWidth
                button.frame = NSRect(x: bx, y: h - 40, width: width, height: 30)
                bx += width + 4
            }
        }
        list.setWidth(listScroll.contentSize.width)
    }

    private func placeHeight(_ view: NSView) -> CGFloat {
        view is PlaceSeparator ? 11 : (style == .xp ? 30 : 28)
    }

    private var vistaPanel: NSRect { NSRect(x: 6, y: 6, width: listWidth, height: bounds.height - 6 - 46) }
    private var vistaSearch: NSRect { NSRect(x: 6, y: bounds.height - 36, width: listWidth, height: 28) }

    // MARK: Отрисовка

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .xp: drawXP()
        case .vista: drawVista()
        }
    }

    private func drawXP() {
        let w = bounds.width, h = bounds.height
        let header = NSRect(x: 0, y: 0, width: w, height: 58)
        // Вид перевёрнут: верх — меньшие y, поэтому градиент идёт «вниз» с углом 90.
        flippedGradient([(0x4C8EF4, 0), (0x2167E4, 0.12), (0x1A5ED8, 0.8), (0x1550C8, 1)], in: header)
        drawUserPicture(in: NSRect(x: 8, y: 8, width: 42, height: 42), frame: .white)
        text(NSFullUserName(), at: NSPoint(x: 58, y: 19), font: .boldSystemFont(ofSize: 14), color: .white, shadow: true)

        let orange = NSGradient(colors: [NSColor(hex: 0xF0A242, alpha: 0), NSColor(hex: 0xF0A242), NSColor(hex: 0xF0A242, alpha: 0)])
        orange?.draw(in: NSRect(x: 0, y: 58, width: w, height: 2), angle: 0)

        NSColor.white.setFill()
        NSRect(x: 0, y: 60, width: listWidth, height: h - 102).fill()
        NSColor(hex: 0xD3E5FA).setFill()
        NSRect(x: listWidth, y: 60, width: w - listWidth, height: h - 102).fill()
        NSColor(hex: 0x95BDEE).setFill()
        NSRect(x: listWidth, y: 60, width: 1, height: h - 102).fill()
        let line = NSGradient(colors: [NSColor(hex: 0xD5D5D5, alpha: 0), NSColor(hex: 0xC5C5C5), NSColor(hex: 0xD5D5D5, alpha: 0)])
        line?.draw(in: NSRect(x: 8, y: h - 84, width: listWidth - 16, height: 1), angle: 0)

        flippedGradient([(0x3A81F3, 0), (0x2464DD, 0.15), (0x1D5BD6, 0.7), (0x1849BB, 1)],
                        in: NSRect(x: 0, y: h - 42, width: w, height: 42))
    }

    private func drawVista() {
        let all = bounds
        let glass = NSBezierPath(roundedRect: all.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSGradient(colors: [NSColor(hex: 0x3B4C5E, alpha: 0.82), NSColor(hex: 0x16222F, alpha: 0.88),
                            NSColor(hex: 0x0A1119, alpha: 0.92)])?.draw(in: glass, angle: 90)
        NSColor(white: 1, alpha: 0.3).setStroke()
        glass.stroke()

        let panel = NSBezierPath(roundedRect: vistaPanel, xRadius: 3, yRadius: 3)
        NSColor.white.setFill()
        panel.fill()
        NSColor(hex: 0x8A9AAD).setStroke()
        panel.stroke()
        NSColor(hex: 0xD6DCE3).setFill()
        NSRect(x: vistaPanel.minX + 8, y: vistaPanel.maxY - 40, width: vistaPanel.width - 16, height: 1).fill()

        let search = NSBezierPath(roundedRect: vistaSearch, xRadius: 3, yRadius: 3)
        NSColor.white.setFill()
        search.fill()
        NSColor(hex: 0x8A9AAD).setStroke()
        search.stroke()
        Glyphs.search(in: NSRect(x: vistaSearch.maxX - 26, y: vistaSearch.minY, width: 24, height: vistaSearch.height),
                      color: NSColor(hex: 0x3C4A5A))

        let pictureSide: CGFloat = 54
        let column = NSRect(x: vistaPanel.maxX + 8, y: 0, width: bounds.width - vistaPanel.maxX - 16, height: 0)
        drawUserPicture(in: NSRect(x: column.midX - pictureSide / 2, y: 12, width: pictureSide, height: pictureSide),
                        frame: NSColor(white: 1, alpha: 0.7))
    }

    private func drawUserPicture(in rect: NSRect, frame: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        frame.setFill()
        path.fill()
        let inner = rect.insetBy(dx: 3, dy: 3)
        NSColor(hex: 0x7FA8D9).setFill()
        NSBezierPath(roundedRect: inner, xRadius: 2, yRadius: 2).fill()
        if let image = NSImage(named: NSImage.userName) {
            image.draw(in: inner.insetBy(dx: 3, dy: 3), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func flippedGradient(_ stops: [(UInt32, CGFloat)], in rect: NSRect) {
        NSGradient(colors: stops.map { NSColor(hex: $0.0) }, atLocations: stops.map(\.1), colorSpace: .sRGB)?.draw(in: rect, angle: 90)
    }

    private func text(_ string: String, at point: NSPoint, font: NSFont, color: NSColor, shadow: Bool) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if shadow {
            let s = NSShadow()
            s.shadowOffset = NSSize(width: 1, height: -1)
            s.shadowBlurRadius = 1
            s.shadowColor = NSColor(white: 0, alpha: 0.5)
            attrs[.shadow] = s
        }
        string.draw(at: point, withAttributes: attrs)
    }
}

// MARK: - Строки и кнопки

/// «Все программы ▶» / «◀ Назад» под списком закреплённых.
final class AllProgramsRow: HoverButton {
    private let style: ClassicStyle
    var showingAll = false { didSet { needsDisplay = true } }

    init(style: ClassicStyle) {
        self.style = style
        super.init(frame: .zero)
        closesFlyouts = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let listStyle: ListStyle = style == .xp ? .xp : .vista
        if hovered { StyledRow.drawHighlight(bounds, style: listStyle, pressed: pressed) }
        let title = showingAll ? L.t("Назад", "Back") : L.t("Все программы", "All Programs")
        let color = hovered ? listStyle.hoverText : listStyle.text
        let font = NSFont.boldSystemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = title.size(withAttributes: attrs)
        let arrowSide: CGFloat = 14
        switch style {
        case .xp:
            // По центру: надпись и зелёный квадрат со стрелкой.
            let total = size.width + 8 + arrowSide
            let x = (bounds.width - total) / 2
            title.draw(at: NSPoint(x: showingAll ? x + arrowSide + 8 : x, y: bounds.midY - size.height / 2), withAttributes: attrs)
            let box = NSRect(x: showingAll ? x : x + size.width + 8, y: bounds.midY - arrowSide / 2, width: arrowSide, height: arrowSide)
            let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            NSGradient(starting: NSColor(hex: 0x5DB85D), ending: NSColor(hex: 0x2E8B2E))?.draw(in: path, angle: -90)
            arrow(in: box, left: showingAll, color: .white)
        case .vista:
            let box = NSRect(x: 12, y: bounds.midY - arrowSide / 2, width: arrowSide, height: arrowSide)
            arrow(in: box, left: showingAll, color: NSColor(hex: 0x2A5B9A))
            title.draw(at: NSPoint(x: box.maxX + 8, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }

    private func arrow(in box: NSRect, left: Bool, color: NSColor) {
        let path = NSBezierPath()
        let cx = box.midX, cy = box.midY
        if left {
            path.move(to: NSPoint(x: cx + 3, y: cy - 4))
            path.line(to: NSPoint(x: cx + 3, y: cy + 4))
            path.line(to: NSPoint(x: cx - 3, y: cy))
        } else {
            path.move(to: NSPoint(x: cx - 3, y: cy - 4))
            path.line(to: NSPoint(x: cx - 3, y: cy + 4))
            path.line(to: NSPoint(x: cx + 3, y: cy))
        }
        path.close()
        color.setFill()
        path.fill()
    }
}

/// Папка или программа в правой колонке.
final class PlaceRow: HoverButton {
    private let title: String
    private let url: URL
    private let bold: Bool
    private let style: ListStyle

    init(title: String, url: URL, bold: Bool, style: ListStyle) {
        self.title = title
        self.url = url
        self.bold = bold
        self.style = style
        super.init(frame: .zero)
        closesFlyouts = false
        onClick = {
            if url.pathExtension == "app" { StartMenu.launch(url) } else { StartMenu.open(url) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if hovered { StyledRow.drawHighlight(bounds, style: style, pressed: pressed) }
        var x: CGFloat = 10
        if style.iconSize > 0 {
            let s = style.iconSize
            NSWorkspace.shared.icon(forFile: url.path).draw(in: NSRect(x: 6, y: (bounds.height - s) / 2, width: s, height: s))
            x = 6 + s + 8
        }
        let font = bold ? NSFont.boldSystemFont(ofSize: style.font.pointSize) : style.font
        StyledRow.drawTitle(title, x: x, in: bounds, font: font, color: hovered ? style.hoverText : style.text)
    }
}

final class PlaceSeparator: NSView {
    private let style: ClassicStyle

    init(style: ClassicStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (style == .xp ? NSColor(hex: 0xA7C5EE) : NSColor(white: 1, alpha: 0.2)).setFill()
        NSRect(x: 8, y: bounds.midY, width: bounds.width - 16, height: 1).fill()
    }
}

/// Кнопки выхода и выключения: в XP — значок в цветном квадрате с подписью,
/// в Vista — круглые кнопки и стрелка с меню.
final class FooterButton: HoverButton {
    private let image: NSImage?
    private let title: String?
    private let color: NSColor
    private let round: Bool

    init(symbol: String, title: String?, color: NSColor, round: Bool, tooltip: String? = nil,
         action: (() -> Void)? = nil, menu: (() -> NSMenu)? = nil) {
        image = NSImage.symbol(symbol, size: 12, color: .white)
        self.title = title
        self.color = color
        self.round = round
        super.init(frame: .zero)
        closesFlyouts = false
        toolTip = tooltip ?? title
        if let menu {
            onClick = { [weak self] in
                guard let self else { return }
                menu().popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.height), in: self)
            }
        } else {
            onClick = action
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredWidth: CGFloat {
        guard let title else { return round ? 30 : 22 }
        return 22 + 6 + ceil(title.size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width) + 6
    }

    override func draw(_ dirtyRect: NSRect) {
        let side: CGFloat = title == nil ? (round ? 26 : 18) : 22
        let box = NSRect(x: title == nil ? (bounds.width - side) / 2 : 0, y: (bounds.height - side) / 2, width: side, height: side)
        let path = round ? NSBezierPath(ovalIn: box) : NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        let base = hovered ? (color.blended(withFraction: 0.25, of: .white) ?? color) : color
        NSGradient(starting: base.blended(withFraction: 0.35, of: .white) ?? base,
                   ending: base.blended(withFraction: 0.2, of: .black) ?? base)?.draw(in: path, angle: -90)
        NSColor(white: 1, alpha: 0.6).setStroke()
        path.stroke()
        if let image {
            image.draw(in: NSRect(x: box.midX - image.size.width / 2, y: box.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let title {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white]
            let size = title.size(withAttributes: attrs)
            title.draw(at: NSPoint(x: box.maxX + 6, y: bounds.midY - size.height / 2), withAttributes: attrs)
            if hovered {
                NSColor(white: 1, alpha: 0.5).setFill()
                NSRect(x: box.maxX + 6, y: bounds.midY - size.height / 2 + 1, width: size.width, height: 1).fill()
            }
        }
    }
}
