import AppKit

/// «Пуск» в виде выбранной темы: створки Windows 10, зелёная кнопка XP, шар Vista.
final class StartButton: HoverButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        closesFlyouts = false
        toolTip = L.t("Пуск", "Start")
        onClick = { [weak self] in
            CalendarFlyout.shared.close()
            VolumeFlyout.shared.close()
            StartMenu.shared.toggle(on: self?.window?.screen)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.skin.drawStart(bounds, hovered: hovered, pressed: pressed || StartMenu.shared.isShown)
    }
}

/// Светлое поле «Введите здесь текст для поиска». Сам ввод идёт в «Пуске».
final class SearchBoxButton: HoverButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        closesFlyouts = false
        onClick = { [weak self] in
            CalendarFlyout.shared.close()
            VolumeFlyout.shared.close()
            StartMenu.shared.show(on: self?.window?.screen)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (hovered ? Theme.searchBoxHover : Theme.searchBox).setFill()
        bounds.fill()
        Glyphs.search(in: NSRect(x: 8, y: 0, width: 24, height: bounds.height), color: NSColor(white: 0.1, alpha: 1))
        let placeholder = L.t("Введите здесь текст для поиска", "Type here to search")
        let attrs: [NSAttributedString.Key: Any] = [.font: Fonts.ui(13), .foregroundColor: Theme.searchText]
        let size = placeholder.size(withAttributes: attrs)
        let rect = NSRect(x: 42, y: (bounds.height - size.height) / 2, width: bounds.width - 50, height: size.height)
        placeholder.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}

/// Кнопка со своим глифом («Представление задач»).
final class GlyphButton: HoverButton {
    private let glyph: (NSRect, NSColor) -> Void

    init(glyph: @escaping (NSRect, NSColor) -> Void, tooltip: String) {
        self.glyph = glyph
        super.init(frame: .zero)
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        glyph(bounds, Theme.text)
    }
}

/// Кнопка программы или окна: значок (и подпись без группировки), полоска «запущена»,
/// подсветка активной, «стопка» справа, если в сгруппированной кнопке больше одного окна.
final class TaskButton: HoverButton {
    private(set) var item: TaskItem?
    private var active = false
    private var windows = 0
    /// С подписью — кнопка во всю ширину, как в Windows без группировки.
    var labeled = false { didSet { if labeled != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        onClick = { [weak self] in
            guard let self, let item = self.item else { return }
            // Shift и щелчок — ещё одно окно программы, как в Windows.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true, let url = item.url ?? item.app?.bundleURL {
                Launcher.openNew(url)
            } else if item.window == nil, let menu = TaskMenu.windowList(item) {
                // Сгруппированная кнопка с несколькими окнами: в Windows — выбор окна, а не одно из них наугад.
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.height), in: self)
            } else {
                Launcher.click(item)
            }
        }
        menuProvider = { [weak self] in self?.item.map(TaskMenu.make) }
        registerForDraggedTypes(Self.draggedTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Перетаскивание над кнопкой

    /// Всё, что обычно тащат из Finder, Проводника и других программ: файлы, ссылки, текст, картинки.
    private static let draggedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .string, .html, .rtf, .tiff, .png, .pdf,
         NSPasteboard.PasteboardType("NSFilenamesPboardType")]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    /// Сколько держать перетаскиваемое над кнопкой, чтобы окно вышло вперёд.
    private static let springDelay: TimeInterval = 0.5
    /// Через сколько над сгруппированной кнопкой показывается следующее её окно.
    private static let springCycle: TimeInterval = 1.5

    private var springTimer: Timer?
    private var springQueue: [WindowList.Window] = []
    private var springStep = 0
    private var dropHovered = false { didSet { if dropHovered != oldValue { needsDisplay = true } } }

    /// Как в Windows: бросить на кнопку нельзя, но задержался над ней — окно выходит вперёд,
    /// и перетаскиваемое бросают уже в него.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHovered = true
        springStep = 0
        scheduleSpring(after: Self.springDelay)
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { cancelSpring() }
    override func draggingEnded(_ sender: NSDraggingInfo) { cancelSpring() }

    private func scheduleSpring(after delay: TimeInterval) {
        springTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.spring() }
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }

    private func cancelSpring() {
        springTimer?.invalidate()
        springTimer = nil
        springQueue = []
        dropHovered = false
    }

    private func spring() {
        // Конец перетаскивания сюда может и не дойти — сверяемся с мышью сами.
        guard let item, let window, NSEvent.pressedMouseButtons & 1 != 0,
              bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else {
            cancelSpring()
            return
        }
        if springStep == 0 { springQueue = Launcher.windowsToBring(item) }
        if springQueue.isEmpty {
            // Окна не опрошены или доступа к ним нет — выводим программу целиком, один раз.
            item.app?.activate(options: [.activateIgnoringOtherApps])
            return
        }
        Launcher.focus(springQueue[springStep % springQueue.count])
        springStep += 1
        if springQueue.count > 1 { scheduleSpring(after: Self.springCycle) }
    }

    /// Щелчок колёсиком — тоже ещё одно окно программы, как в Windows.
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)),
              let url = item?.url ?? item?.app?.bundleURL else { return }
        Flyouts.closeAll()
        Launcher.openNew(url)
    }

    func update(item: TaskItem, active: Bool, windows: Int) {
        self.item = item
        self.active = active
        self.windows = windows
        toolTip = item.name
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        Theme.skin.drawTaskButton(bounds, ButtonLook(
            hovered: hovered || dropHovered, pressed: pressed, active: active, running: item.app != nil,
            labeled: labeled, windows: windows, icon: item.icon, title: item.name))
    }
}

/// Индикатор раскладки «РУС / ENG» (в XP и Vista — «RU / EN»); щелчок — список раскладок.
final class LanguageButton: HoverButton {
    private var source = InputSource.current

    override init(frame: NSRect) {
        super.init(frame: frame)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sourceChanged), name: InputSource.changed, object: nil)
        onClick = { [weak self] in self?.showMenu() }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func sourceChanged() {
        source = InputSource.current
        toolTip = source?.name
        needsDisplay = true
    }

    private func showMenu() {
        let menu = NSMenu.themed()
        let currentID = InputSource.current?.id
        for source in InputSource.enabled {
            menu.addItem(.action("\(source.label)    \(source.name)", checked: source.id == currentID) {
                InputSource.select(source)
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.skin.drawLanguage(bounds, source, hovered: hovered, pressed: pressed)
    }
}

/// Динамик в области уведомлений: щелчок — регулятор громкости, колёсико — громче и тише,
/// правый щелчок — устройства вывода и параметры звука.
final class VolumeButton: HoverButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        closesFlyouts = false
        onClick = { [weak self] in
            guard let self, let window = self.window else { return }
            StartMenu.shared.close()
            CalendarFlyout.shared.close()
            let anchor = window.convertToScreen(self.convert(self.bounds, to: nil)).midX
            VolumeFlyout.shared.toggle(on: window.screen, anchorX: anchor)
        }
        menuProvider = { VolumeView.trayMenu() }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Audio.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Flyouts.changed, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() {
        let name = Audio.current?.name ?? L.t("Динамики", "Speakers")
        toolTip = Audio.isMuted ? "\(name): \(L.t("без звука", "muted"))" : "\(name): \(Audio.percent)%"
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        VolumeView.nudge(by: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let skin = Theme.skin
        skin.drawTrayButton(bounds, hovered: hovered, pressed: pressed, active: VolumeFlyout.shared.isShown)
        Glyphs.speaker(in: bounds, color: skin.trayText, level: Audio.volume, muted: Audio.isMuted)
    }
}

/// Часы: в Windows 10 — время и дата в две строки, в XP и Vista — только время. Щелчок — календарь.
final class ClockButton: HoverButton {
    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    private var timer: Timer?
    private var lines: [String] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        closesFlyouts = false
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        onClick = { [weak self] in
            StartMenu.shared.close()
            VolumeFlyout.shared.close()
            CalendarFlyout.shared.toggle(on: self?.window?.screen)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(configure), name: Settings.changed, object: nil)
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func configure() {
        let time = Settings.showSeconds ? "jmmss" : "jmm"
        timeFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: time, options: 0, locale: .current)
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: .current)
        lines = []
        tick()
    }

    private func tick() {
        let now = Date()
        // На маленьких кнопках дата не помещается второй строкой — как в Windows, остаётся только время.
        var fresh = [timeFormatter.string(from: now)]
        if Settings.showDate && !Settings.smallButtons && Theme.skin.isModern { fresh.append(dateFormatter.string(from: now)) }
        if fresh != lines {
            let widthChanged = fresh.count != lines.count || fresh.map(\.count) != lines.map(\.count)
            lines = fresh
            toolTip = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .none)
            if widthChanged { superview?.needsLayout = true }
        }
        // Подсветка зависит ещё и от того, открыт ли календарь.
        needsDisplay = true
    }

    var preferredWidth: CGFloat {
        let width = lines.map { $0.size(withAttributes: [.font: Theme.skin.font]).width }.max() ?? 0
        return ceil(width) + 16
    }

    override func draw(_ dirtyRect: NSRect) {
        let skin = Theme.skin
        skin.drawTrayButton(bounds, hovered: hovered, pressed: pressed, active: CalendarFlyout.shared.isShown)
        let attrs: [NSAttributedString.Key: Any] = [.font: skin.font, .foregroundColor: skin.trayText]
        let lineHeight = ("0" as NSString).size(withAttributes: attrs).height
        var y = bounds.midY + CGFloat(lines.count) * lineHeight / 2 - lineHeight
        for line in lines {
            let size = line.size(withAttributes: attrs)
            line.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attrs)
            y -= lineHeight - 2
        }
    }
}

/// Узкая полоска у правого края: скрыть все окна и показать рабочий стол.
final class ShowDesktopButton: HoverButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = L.t("Свернуть все окна", "Show desktop")
        onClick = { Launcher.toggleDesktop() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.skin.drawTrayButton(bounds, hovered: hovered, pressed: pressed, active: false)
        NSColor(white: 1, alpha: 0.35).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
}
