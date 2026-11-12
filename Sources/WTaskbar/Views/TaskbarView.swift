import AppKit

/// Раскладка панели слева направо: «Пуск», поиск, «Представление задач», программы —
/// и справа область уведомлений: раскладка, часы, «Свернуть все окна».
final class TaskbarView: NSView {
    private let screen: NSScreen
    private let startButton = StartButton()
    private let searchBox = SearchBoxButton()
    private let searchIcon = GlyphButton(glyph: Glyphs.search, tooltip: L.t("Поиск", "Search"))
    private let taskViewButton = GlyphButton(glyph: Glyphs.taskView, tooltip: L.t("Представление задач", "Task View"))
    private let languageButton = LanguageButton()
    private let clockButton = ClockButton()
    private let desktopButton = ShowDesktopButton()
    private var taskButtons: [String: TaskButton] = [:]
    private var taskOrder: [String] = []
    private var labeled = false

    /// Перетаскиваемая кнопка: её ключ, порядок кнопок с ней на новом месте
    /// и в каком месте кнопки её схватили.
    private struct Drag {
        let key: String
        var order: [String]
        let grab: CGFloat
    }
    private var drag: Drag?

    /// Главная панель — на экране со строкой меню.
    private var isMain: Bool { screen == NSScreen.screens.first }

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: .zero)
        for view in [startButton, searchBox, searchIcon, taskViewButton, languageButton, clockButton, desktopButton] as [NSView] {
            addSubview(view)
        }
        taskViewButton.onClick = { Launcher.open(Launcher.missionControl) }
        searchIcon.closesFlyouts = false
        searchIcon.onClick = { [weak self] in
            CalendarFlyout.shared.close()
            StartMenu.shared.show(on: self?.window?.screen)
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reload), name: TaskbarModel.changed, object: nil)
        center.addObserver(self, selector: #selector(reload), name: Settings.changed, object: nil)
        center.addObserver(self, selector: #selector(flyoutsChanged), name: Flyouts.changed, object: nil)
        reload()
        // Стрелка над всей панелью, даже когда активна другая программа: см. ArrowCursor.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { ArrowCursor.set(over: window) }
    override func mouseMoved(with event: NSEvent) { ArrowCursor.set(over: window) }

    /// Окно панели — в экранных точках, раскладка — в логических: масштаб задают границы вида.
    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = bounds.width
        super.setFrameSize(newSize)
        applyScale()
        if bounds.width != oldWidth { reload() } else { needsLayout = true }
    }

    private func applyScale() {
        let scale = Theme.scale
        let logical = NSSize(width: frame.width / scale, height: frame.height / scale)
        if bounds.size != logical { setBoundsSize(logical) }
    }

    // MARK: Какие кнопки показать

    @objc private func reload() {
        applyScale()
        let model = TaskbarModel.shared
        let skin = Theme.skin
        let combined = model.items.filter(showsApp)
        let expanded = expand(combined)

        // «При заполнении» — без группировки, пока кнопки с подписями не уже минимальной ширины.
        // В XP и Vista подписи есть и у сгруппированных кнопок.
        let items: [TaskItem]
        switch Settings.combine {
        case .always:
            items = combined
            labeled = skin.labelsAlways
        case .never:
            items = expanded
            labeled = true
        case .whenFull:
            let needed = expanded.reduce(CGFloat(0)) { $0 + (isIconOnly($1) ? Theme.buttonWidth : Theme.minLabeledWidth) }
            let fits = needed <= taskArea().width
            items = fits ? expanded : combined
            labeled = fits || skin.labelsAlways
        }

        var fresh: [String: TaskButton] = [:]
        for item in items {
            let button = taskButtons[item.key] ?? makeTaskButton()
            let windowCount = item.window == nil ? windowsHere(item).count : 1
            button.update(item: item, active: model.isActive(item), windows: windowCount)
            button.labeled = labeled && !isIconOnly(item)
            if button.superview == nil { addSubview(button) }
            fresh[item.key] = button
        }
        for (key, button) in taskButtons where fresh[key] == nil {
            button.removeFromSuperview()
        }
        taskButtons = fresh
        taskOrder = items.map(\.key)
        if var current = drag {
            // Пока кнопку тащат, программы могут открываться и закрываться.
            if fresh[current.key] == nil {
                drag = nil
            } else {
                current.order = current.order.filter { fresh[$0] != nil } + taskOrder.filter { !current.order.contains($0) }
                drag = current
            }
        }

        // Поиск и «Представление задач» появились только в Windows 10.
        let small = Settings.smallButtons
        searchBox.isHidden = !skin.isModern || Settings.search != .box || small
        searchIcon.isHidden = !skin.isModern || !(Settings.search == .icon || (Settings.search == .box && small))
        taskViewButton.isHidden = !skin.isModern || !Settings.showTaskView
        languageButton.isHidden = !Settings.showLanguage
        desktopButton.isHidden = !Settings.showDesktopButton
        subviews.forEach { $0.needsDisplay = true }
        needsDisplay = true
        needsLayout = true
    }

    /// Кнопка «Пуск» и часы показывают, открыто ли их окно.
    @objc private func flyoutsChanged() {
        startButton.needsDisplay = true
        clockButton.needsDisplay = true
    }

    /// Закреплённая, но не запущенная программа и в Windows остаётся значком без подписи.
    private func isIconOnly(_ item: TaskItem) -> Bool {
        item.app == nil
    }

    /// Без группировки: кнопка на каждое окно; программа без окон — одной кнопкой.
    private func expand(_ items: [TaskItem]) -> [TaskItem] {
        items.flatMap { item -> [TaskItem] in
            guard item.app != nil else { return [item] }
            let windows = windowsHere(item)
            return windows.isEmpty ? [item] : windows.map(item.forWindow)
        }
    }

    /// Фильтр по дисплеям включается, только когда панелей несколько и окна видны.
    private var filtersByScreen: Bool {
        Settings.allDisplays && NSScreen.screens.count > 1 && Settings.buttonsOn != .all && WindowList.isTrusted
    }

    private func windowsHere(_ item: TaskItem) -> [WindowList.Window] {
        let windows = TaskbarModel.shared.windows(of: item)
        guard filtersByScreen, !(isMain && Settings.buttonsOn == .mainAndOpen) else { return windows }
        return windows.filter { $0.isOn(screen) }
    }

    private func showsApp(_ item: TaskItem) -> Bool {
        guard filtersByScreen, !(isMain && Settings.buttonsOn == .mainAndOpen) else { return true }
        let windows = TaskbarModel.shared.windows(of: item)
        // Закреплённые и программы без окон — на главной панели.
        if windows.isEmpty { return isMain }
        return windows.contains { $0.isOn(screen) }
    }

    // MARK: Раскладка

    /// Место между левыми кнопками и областью уведомлений.
    private func taskArea() -> (x: CGFloat, width: CGFloat) {
        let skin = Theme.skin
        var left = skin.startWidth + (skin.isModern ? 0 : 4)
        if skin.isModern {
            switch Settings.search {
            case .box where !Settings.smallButtons: left += searchBoxWidth
            case .box, .icon: left += Theme.buttonWidth
            case .hidden: break
            }
            if Settings.showTaskView { left += Theme.buttonWidth }
        }
        return (left, max(0, trayLeft - left))
    }

    private var searchBoxWidth: CGFloat {
        // На узком экране поле поиска уступает место программам.
        min(Theme.searchWidth, max(0, bounds.width * 0.22))
    }

    private var trayLeft: CGFloat {
        var right = bounds.width
        if Settings.showDesktopButton { right -= 6 + 4 }
        right -= clockButton.preferredWidth
        if Settings.showLanguage { right -= Theme.skin.languageWidth }
        return right - 8
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 0
        func place(_ view: NSView, _ width: CGFloat) {
            view.frame = NSRect(x: x, y: 0, width: width, height: h)
            x += width
        }

        // Справа налево: полоска «Свернуть все», часы, раскладка.
        var right = bounds.width
        if Settings.showDesktopButton {
            desktopButton.frame = NSRect(x: right - 6, y: 0, width: 6, height: h)
            right -= 6 + 4
        }
        let clockWidth = clockButton.preferredWidth
        clockButton.frame = NSRect(x: right - clockWidth, y: 0, width: clockWidth, height: h)
        right -= clockWidth
        let languageWidth = Theme.skin.languageWidth
        if Settings.showLanguage {
            languageButton.frame = NSRect(x: right - languageWidth, y: 0, width: languageWidth, height: h)
        }

        place(startButton, Theme.skin.startWidth)
        if !searchBox.isHidden { place(searchBox, searchBoxWidth) }
        if !searchIcon.isHidden { place(searchIcon, Theme.buttonWidth) }
        if !taskViewButton.isHidden { place(taskViewButton, Theme.buttonWidth) }

        layoutTasks(animated: false)
    }

    /// Места кнопок программ при данном порядке. Кнопки с подписью делят то, что осталось
    /// после значков, но не шире настройки.
    private func taskFrames(_ order: [String]) -> [(key: String, frame: NSRect)] {
        let area = taskArea()
        let buttons = order.compactMap { key in taskButtons[key].map { (key, $0) } }
        let iconOnly = buttons.filter { !$0.1.labeled }.count
        let withLabel = buttons.count - iconOnly
        var iconWidth = Theme.buttonWidth
        var labelWidth = CGFloat(Settings.maxButtonWidth)
        if withLabel > 0 {
            let rest = area.width - CGFloat(iconOnly) * iconWidth
            labelWidth = max(Theme.buttonWidth, min(labelWidth, floor(rest / CGFloat(withLabel))))
        } else if iconOnly > 0 {
            iconWidth = max(Theme.minButtonWidth, min(iconWidth, floor(area.width / CGFloat(iconOnly))))
        }
        var x = area.x
        return buttons.map { key, button in
            let width = button.labeled ? labelWidth : iconWidth
            defer { x += width }
            return (key, NSRect(x: x, y: 0, width: width, height: bounds.height))
        }
    }

    /// Расставляет кнопки программ; перетаскиваемую не трогает — она идёт за курсором.
    private func layoutTasks(animated: Bool) {
        let area = taskArea()
        let limit = area.x + area.width
        let frames = taskFrames(drag?.order ?? taskOrder)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            for (key, frame) in frames {
                guard let button = taskButtons[key] else { continue }
                button.isHidden = frame.maxX > limit + 0.5
                guard key != drag?.key else { continue }
                if animated { button.animator().frame = frame } else { button.frame = frame }
            }
        }
    }

    // MARK: Перетаскивание кнопок

    private func makeTaskButton() -> TaskButton {
        let button = TaskButton()
        button.dragHandler = { [weak self, weak button] phase, windowX in
            guard let self, let button else { return }
            self.handleDrag(button, phase, x: self.convert(NSPoint(x: windowX, y: 0), from: nil).x)
        }
        return button
    }

    /// Как в Windows: кнопка идёт за курсором, соседние расступаются, отпустил — порядок сохранён.
    private func handleDrag(_ button: TaskButton, _ phase: HoverButton.DragPhase, x: CGFloat) {
        switch phase {
        case .began:
            guard let key = taskButtons.first(where: { $0.value === button })?.key else { return }
            drag = Drag(key: key, order: taskOrder, grab: x - button.frame.minX)
            addSubview(button, positioned: .above, relativeTo: nil)
        case .moved:
            guard var current = drag else { return }
            let area = taskArea()
            var frame = button.frame
            frame.origin.x = min(max(x - current.grab, area.x), area.x + area.width - frame.width)
            button.frame = frame
            // Новое место — то, где середина кнопки ближе всего к середине её будущего места.
            let others = current.order.filter { $0 != current.key }
            var best = current.order
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for index in 0...others.count {
                var candidate = others
                candidate.insert(current.key, at: index)
                guard let slot = taskFrames(candidate).first(where: { $0.key == current.key })?.frame else { continue }
                let distance = abs(slot.midX - frame.midX)
                if distance < bestDistance {
                    bestDistance = distance
                    best = candidate
                }
            }
            if best != current.order {
                current.order = best
                drag = current
                layoutTasks(animated: true)
            }
        case .ended:
            guard let current = drag else { return }
            drag = nil
            taskOrder = current.order
            layoutTasks(animated: true)
            commit(current.order)
        }
    }

    /// Порядок кнопок — в модель: порядок программ и порядок окон внутри программы.
    private func commit(_ order: [String]) {
        let items = order.compactMap { taskButtons[$0]?.item }
        var apps: [String] = []
        var windows: [pid_t: [Int]] = [:]
        for item in items {
            if !apps.contains(item.appID) { apps.append(item.appID) }
            if let window = item.window, let pid = item.app?.processIdentifier {
                windows[pid, default: []].append(window.id)
            }
        }
        let model = TaskbarModel.shared
        model.reorder(apps)
        for (pid, ids) in windows { model.reorderWindows(of: pid, ids) }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.skin.drawBar(bounds, trayFrom: trayLeft + 2)
    }

    // MARK: Меню панели (правый щелчок по пустому месту)

    override func rightMouseDown(with event: NSEvent) {
        Flyouts.closeAll()
        NSMenu.popUpContextMenu(barMenu(), with: event, for: self)
    }

    private func barMenu() -> NSMenu {
        let menu = NSMenu.themed()

        let search = NSMenuItem(title: L.t("Поиск", "Search"), action: nil, keyEquivalent: "")
        let searchMenu = NSMenu.themed()
        for mode in SearchMode.allCases {
            searchMenu.addItem(.action(mode.title, checked: Settings.search == mode) { Settings.search = mode })
        }
        search.submenu = searchMenu
        menu.addItem(search)
        menu.addItem(.action(L.t("Показать кнопку «Представление задач»", "Show Task View button"), checked: Settings.showTaskView) {
            Settings.showTaskView.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(.action(L.t("Скрывать Dock", "Hide the Dock"), checked: Settings.hideDock) {
            Settings.hideDock.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(.action(L.t("Мониторинг системы", "Activity Monitor")) { Launcher.open(Launcher.activityMonitor) })
        menu.addItem(.separator())
        menu.addItem(.action(L.t("Параметры панели задач…", "Taskbar settings…")) { OptionsWindow.shared.show() })
        menu.addItem(.action(L.t("Выйти из WTaskbar", "Quit WTaskbar")) { NSApp.terminate(nil) })
        return menu
    }
}
