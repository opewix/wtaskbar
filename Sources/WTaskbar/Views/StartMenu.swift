import AppKit

/// «Пуск» выбранной темы. Содержимое пересобирается при смене темы.
final class StartMenu: Flyout {
    static let shared = StartMenu()
    private var content: StartBaseView
    private var builtFor: ThemeKind

    private init() {
        builtFor = Settings.theme
        content = Self.makeContent(builtFor)
        super.init(size: Self.size(builtFor), content: content)
        setContent(content, size: Self.size(builtFor), cornerRadius: Self.cornerRadius(builtFor))
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.changed, object: nil)
    }

    static func makeContent(_ theme: ThemeKind) -> StartBaseView {
        switch theme {
        case .win10: Win10StartView()
        case .vista: ClassicStartView(style: .vista)
        case .xp: ClassicStartView(style: .xp)
        }
    }

    static func size(_ theme: ThemeKind) -> NSSize {
        switch theme {
        case .win10: NSSize(width: 664, height: 620)
        case .vista: NSSize(width: 430, height: 520)
        case .xp: NSSize(width: 420, height: 500)
        }
    }

    private static func cornerRadius(_ theme: ThemeKind) -> CGFloat {
        theme == .win10 ? 0 : 7
    }

    @objc private func settingsChanged() {
        guard Settings.theme != builtFor else { return }
        close()
        builtFor = Settings.theme
        content = Self.makeContent(builtFor)
        setContent(content, size: Self.size(builtFor), cornerRadius: Self.cornerRadius(builtFor))
    }

    func toggle(on screen: NSScreen?) {
        if isShown { close() } else { show(on: screen) }
    }

    func show(on screen: NSScreen?) {
        show(on: screen, alignRight: false)
    }

    override func willShow() {
        AppCatalog.shared.refresh()
        content.reset()
    }

    /// Запуск из «Пуска»: меню закрывается, программа выходит вперёд.
    static func launch(_ url: URL) {
        shared.close()
        Launcher.open(url)
    }

    static func open(_ url: URL) {
        shared.close()
        NSWorkspace.shared.open(url)
    }

    static func entryMenu(_ url: URL) -> NSMenu {
        let model = TaskbarModel.shared
        let menu = NSMenu.themed()
        menu.addItem(.action(model.isTile(url) ? L.t("Открепить от меню «Пуск»", "Unpin from Start")
                                               : L.t("Закрепить в меню «Пуск»", "Pin to Start")) {
            model.toggleTile(url)
        })
        menu.addItem(.action(model.isPinned(url) ? L.t("Открепить от панели задач", "Unpin from taskbar")
                                                 : L.t("Закрепить на панели задач", "Pin to taskbar")) {
            model.togglePin(url)
        })
        menu.addItem(.separator())
        menu.addItem(.action(L.t("Показать в Finder", "Show in Finder")) {
            shared.close()
            Launcher.showInFinder(url)
        })
        return menu
    }

    static func powerMenu() -> NSMenu {
        let menu = NSMenu.themed()
        menu.addItem(.action(L.t("Спящий режим", "Sleep")) { shared.close(); Power.sleep() })
        menu.addItem(.action(L.t("Завершение работы", "Shut down")) { shared.close(); Power.shutDown() })
        menu.addItem(.action(L.t("Перезагрузка", "Restart")) { shared.close(); Power.restart() })
        return menu
    }

    static func userMenu() -> NSMenu {
        let menu = NSMenu.themed()
        menu.addItem(.action(L.t("Заблокировать", "Lock")) { shared.close(); Power.lock() })
        menu.addItem(.action(L.t("Выход", "Sign out")) { shared.close(); Power.logOut() })
        return menu
    }

    static func folder(_ directory: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: directory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }
}

// MARK: - Общая основа: поле поиска и список программ

/// Поле поиска и список, общие для всех тем. Печатать можно сразу после открытия:
/// ввод заменяет список результатами, Enter запускает первый, Esc очищает или закрывает.
class StartBaseView: NSView, NSTextFieldDelegate {
    let searchField = NSTextField()
    let listScroll = NSScrollView()
    let list: AppListView

    override var isFlipped: Bool { true }

    var query: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    init(listStyle: ListStyle) {
        list = AppListView(style: listStyle)
        super.init(frame: .zero)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.scrollerStyle = .overlay
        listScroll.autohidesScrollers = true
        listScroll.documentView = list
        addSubview(listScroll)
        NotificationCenter.default.addObserver(self, selector: #selector(refill), name: AppCatalog.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refill), name: TaskbarModel.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        searchField.stringValue = ""
        refill()
        list.scroll(.zero)
        window?.makeFirstResponder(searchField)
    }

    @objc func refill() {
        if query.isEmpty {
            showDefault()
        } else {
            // Сначала названия, которые начинаются с запроса, потом содержащие его.
            let q = query.lowercased()
            let found = AppCatalog.shared.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
            list.show(found.filter { $0.name.lowercased().hasPrefix(q) } + found.filter { !$0.name.lowercased().hasPrefix(q) },
                      grouped: false, selectFirst: true)
        }
    }

    /// Что в списке без поиска; у каждой темы своё.
    func showDefault() {
        list.show(AppCatalog.shared.entries, grouped: true, selectFirst: false)
    }

    func controlTextDidChange(_ obj: Notification) {
        refill()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            list.moveSelection(1)
        case #selector(NSResponder.moveUp(_:)):
            list.moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)):
            if let url = list.selectedURL { StartMenu.launch(url) }
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty {
                StartMenu.shared.close()
            } else {
                searchField.stringValue = ""
                refill()
            }
        default:
            return false
        }
        return true
    }
}

// MARK: - Windows 10

/// Узкая колонка слева (пользователь, папки, параметры, питание),
/// алфавитный список программ с поиском и закреплённые плитки справа.
final class Win10StartView: StartBaseView {
    private static let railWidth: CGFloat = 48
    private static let listWidth: CGFloat = 272

    private let searchBox = NSView()
    private let tilesScroll = NSScrollView()
    private let tiles = TilesView()
    private var railButtons: [RailButton] = []

    init() {
        super.init(listStyle: .win10)
        searchBox.wantsLayer = true
        searchBox.layer?.backgroundColor = Theme.flyoutField.cgColor
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = Theme.text
        searchField.placeholderAttributedString = NSAttributedString(
            string: L.t("Поиск программ", "Search apps"),
            attributes: [.foregroundColor: Theme.dimText, .font: NSFont.systemFont(ofSize: 13)])
        searchBox.addSubview(searchField)
        addSubview(searchBox)

        tilesScroll.drawsBackground = false
        tilesScroll.hasVerticalScroller = true
        tilesScroll.scrollerStyle = .overlay
        tilesScroll.autohidesScrollers = true
        tilesScroll.documentView = tiles
        addSubview(tilesScroll)

        railButtons = [
            RailButton(symbol: "power", tooltip: L.t("Выключение", "Power"), menu: StartMenu.powerMenu),
            RailButton(symbol: "gearshape", tooltip: L.t("Параметры", "Settings"), action: { StartMenu.launch(Launcher.systemSettings) }),
            RailButton(symbol: "photo", tooltip: L.t("Изображения", "Pictures"), action: { StartMenu.open(StartMenu.folder(.picturesDirectory)) }),
            RailButton(symbol: "doc", tooltip: L.t("Документы", "Documents"), action: { StartMenu.open(StartMenu.folder(.documentDirectory)) }),
            RailButton(symbol: "person.crop.circle", tooltip: NSFullUserName(), menu: StartMenu.userMenu),
        ]
        railButtons.forEach(addSubview)
        NotificationCenter.default.addObserver(self, selector: #selector(refillTiles), name: TaskbarModel.changed, object: nil)
        refill()
        refillTiles()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        let rail = Self.railWidth
        for (index, button) in railButtons.enumerated() {
            button.frame = NSRect(x: 0, y: h - CGFloat(index + 1) * 48 - 4, width: rail, height: 48)
        }
        searchBox.frame = NSRect(x: rail + 8, y: 10, width: Self.listWidth - 16, height: 32)
        searchField.frame = NSRect(x: 10, y: 7, width: searchBox.bounds.width - 20, height: 18)
        listScroll.frame = NSRect(x: rail, y: 50, width: Self.listWidth, height: h - 50)
        list.setWidth(listScroll.contentSize.width)
        let tilesX = rail + Self.listWidth
        tilesScroll.frame = NSRect(x: tilesX, y: 0, width: bounds.width - tilesX, height: h)
        tiles.setWidth(tilesScroll.contentSize.width)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.flyoutBackground.setFill()
        bounds.fill()
    }

    @objc private func refillTiles() {
        tiles.show(TaskbarModel.shared.tiles)
    }
}

/// Кнопка левой колонки «Пуска». С меню — открывает его по обычному щелчку.
final class RailButton: HoverButton {
    private let image: NSImage?

    init(symbol: String, tooltip: String, menu: (() -> NSMenu)? = nil, action: (() -> Void)? = nil) {
        image = NSImage.symbol(symbol, size: 15)
        super.init(frame: .zero)
        closesFlyouts = false
        toolTip = tooltip
        if let menu {
            onClick = { [weak self] in
                guard let self else { return }
                menu().popUp(positioning: nil, at: NSPoint(x: self.bounds.width, y: self.bounds.height), in: self)
            }
        } else {
            onClick = action
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        image.draw(in: NSRect(x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                              width: image.size.width, height: image.size.height))
    }
}

// MARK: - Список программ

/// Цвета и размеры строк списка программ у каждой темы.
struct ListStyle {
    var text: NSColor
    var hoverFill: NSColor
    var hoverBorder: NSColor?
    var hoverText: NSColor
    var header: NSColor
    var font: NSFont
    var rowHeight: CGFloat
    var iconSize: CGFloat
    var cornerRadius: CGFloat = 0

    static let win10 = ListStyle(text: Theme.text, hoverFill: Theme.hover, hoverText: Theme.text, header: Theme.text,
                                 font: .systemFont(ofSize: 13), rowHeight: 36, iconSize: 26)
    static let xp = ListStyle(text: .black, hoverFill: NSColor(hex: 0x316AC5), hoverText: .white, header: NSColor(hex: 0x6F6F6F),
                              font: .systemFont(ofSize: 12), rowHeight: 34, iconSize: 24)
    static let vista = ListStyle(text: NSColor(hex: 0x1E1E1E), hoverFill: NSColor(hex: 0xDCEBFC), hoverBorder: NSColor(hex: 0x7DA2CE),
                                 hoverText: NSColor(hex: 0x1E1E1E), header: NSColor(hex: 0x6D6D6D),
                                 font: .systemFont(ofSize: 12), rowHeight: 30, iconSize: 22, cornerRadius: 3)
}

final class AppListView: NSView {
    let style: ListStyle
    private var rows: [AppRow] = []
    private var selected: Int?

    override var isFlipped: Bool { true }

    var selectedURL: URL? { selected.map { rows[$0].entry.url } }

    init(style: ListStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ entries: [AppEntry], grouped: Bool, selectFirst: Bool) {
        subviews.forEach { $0.removeFromSuperview() }
        rows = []
        selected = nil
        var y: CGFloat = 0
        var letter: String?
        for entry in entries {
            if grouped {
                let first = Self.letter(entry.name)
                if first != letter {
                    letter = first
                    let header = NSTextField(labelWithString: first)
                    header.font = style.font
                    header.textColor = style.header
                    header.frame = NSRect(x: 14, y: y + (style.rowHeight - 18) / 2 + 1, width: 40, height: 18)
                    addSubview(header)
                    y += style.rowHeight
                }
            }
            let row = AppRow(entry: entry, style: style)
            row.frame = NSRect(x: 0, y: y, width: frame.width, height: style.rowHeight)
            row.autoresizingMask = [.width]
            addSubview(row)
            rows.append(row)
            y += style.rowHeight
        }
        setFrameSize(NSSize(width: frame.width, height: y + 8))
        // При поиске Enter запускает первый результат, как в Windows.
        if selectFirst && !rows.isEmpty { select(0) }
    }

    func setWidth(_ width: CGFloat) {
        setFrameSize(NSSize(width: width, height: frame.height))
    }

    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let next = selected.map { $0 + delta } ?? (delta > 0 ? 0 : rows.count - 1)
        select(min(max(next, 0), rows.count - 1))
    }

    private func select(_ index: Int?) {
        if let selected, selected < rows.count { rows[selected].selected = false }
        selected = index
        if let index {
            rows[index].selected = true
            rows[index].scrollToVisible(rows[index].bounds)
        }
    }

    private static func letter(_ name: String) -> String {
        guard let first = name.first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }
}

final class AppRow: HoverButton {
    let entry: AppEntry
    let style: ListStyle
    var selected = false { didSet { needsDisplay = true } }

    init(entry: AppEntry, style: ListStyle) {
        self.entry = entry
        self.style = style
        super.init(frame: .zero)
        closesFlyouts = false
        onClick = { StartMenu.launch(entry.url) }
        menuProvider = { StartMenu.entryMenu(entry.url) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let lit = selected || hovered
        if lit { StyledRow.drawHighlight(bounds, style: style, pressed: pressed) }
        let s = style.iconSize
        Icons.app(entry.url).draw(in: NSRect(x: 12, y: (bounds.height - s) / 2, width: s, height: s))
        StyledRow.drawTitle(entry.name, x: 12 + s + 10, in: bounds, font: style.font, color: lit ? style.hoverText : style.text)
    }
}

/// Подсветка и подпись строк «Пуска» — у списка программ и у правой колонки XP и Vista.
enum StyledRow {
    static func drawHighlight(_ rect: NSRect, style: ListStyle, pressed: Bool) {
        let box = style.hoverBorder == nil ? rect : rect.insetBy(dx: 3, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        (pressed ? style.hoverFill.blended(withFraction: 0.15, of: .black) ?? style.hoverFill : style.hoverFill).setFill()
        path.fill()
        if let border = style.hoverBorder {
            border.setStroke()
            NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: style.cornerRadius, yRadius: style.cornerRadius).stroke()
        }
    }

    static func drawTitle(_ title: String, x: CGFloat, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let height = title.size(withAttributes: attrs).height
        title.draw(with: NSRect(x: x, y: (rect.height - height) / 2, width: rect.width - x - 8, height: height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}

// MARK: - Плитки Windows 10

final class TilesView: NSView {
    private static let tile: CGFloat = 100
    private static let gap: CGFloat = 4
    private static let columns = 3
    private let header = NSTextField(labelWithString: L.t("Закреплено", "Pinned"))
    private var buttons: [TileButton] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        header.font = NSFont.systemFont(ofSize: 12)
        header.textColor = Theme.text
        addSubview(header)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ urls: [URL]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = urls.map(TileButton.init)
        buttons.forEach(addSubview)
        relayout()
    }

    func setWidth(_ width: CGFloat) {
        setFrameSize(NSSize(width: width, height: frame.height))
        relayout()
    }

    private func relayout() {
        header.frame = NSRect(x: 20, y: 14, width: 200, height: 18)
        let step = Self.tile + Self.gap
        for (index, button) in buttons.enumerated() {
            let col = CGFloat(index % Self.columns)
            let row = CGFloat(index / Self.columns)
            button.frame = NSRect(x: 20 + col * step, y: 44 + row * step, width: Self.tile, height: Self.tile)
        }
        let rows = CGFloat((buttons.count + Self.columns - 1) / Self.columns)
        setFrameSize(NSSize(width: frame.width, height: 44 + rows * step + 16))
    }
}

/// Средняя плитка: акцентный фон, значок по центру, название внизу слева.
final class TileButton: HoverButton {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        closesFlyouts = false
        toolTip = AppEntry.name(of: url)
        onClick = { StartMenu.launch(url) }
        menuProvider = { StartMenu.entryMenu(url) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (pressed ? (Theme.tile.blended(withFraction: 0.15, of: .black) ?? Theme.tile) : Theme.tile).setFill()
        bounds.fill()
        if hovered {
            NSColor(white: 1, alpha: 0.45).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
        }
        let s: CGFloat = 44
        Icons.app(url).draw(in: NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2 + 6, width: s, height: s))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.text]
        let name = AppEntry.name(of: url)
        let height = name.size(withAttributes: attrs).height
        name.draw(with: NSRect(x: 8, y: 6, width: bounds.width - 16, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}
