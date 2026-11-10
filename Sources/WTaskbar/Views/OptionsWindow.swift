import AppKit
import ServiceManagement

/// «Параметры панели задач» — по образцу одноимённой страницы Windows 10.
/// Каждый переключатель сразу пишет в `Settings`, панель перестраивается на лету.
final class OptionsWindow: NSObject, NSWindowDelegate {
    static let shared = OptionsWindow()

    private var window: NSWindow?
    private var handlers: [ControlHandler] = []
    /// Элементы, доступность которых зависит от других настроек.
    private var widthRow: NSView?
    /// Что было только в Windows 10: в XP и Vista эти настройки недоступны.
    private var modernOnly: [NSView] = []
    private var buttonsOnRow: NSView?
    private var accessRow: NSView?

    func show() {
        Flyouts.closeAll()
        let window = self.window ?? makeWindow()
        self.window = window
        rebuild()
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// Содержимое окна без показа на экране — для `-snapshot`.
    func snapshotView() -> NSView {
        window = makeWindow()
        rebuild()
        return window!.contentView!
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L.t("Параметры панели задач", "Taskbar settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// Состояние «Универсального доступа» могло поменяться, пока окно было в фоне.
    func windowDidBecomeKey(_ notification: Notification) {
        rebuild()
    }

    // MARK: Содержимое

    private func rebuild() {
        guard let window else { return }
        handlers = []
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)

        modernOnly = []
        func modern<V: NSView>(_ view: V) -> V {
            modernOnly.append(view)
            return view
        }

        stack.addArrangedSubview(header(L.t("Оформление", "Appearance")))
        stack.addArrangedSubview(row(L.t("Тема:", "Theme:"),
                                     popup(ThemeKind.allCases, Settings.theme, \.title) { [weak self] in
                                         Settings.theme = $0
                                         // У каждой темы свой масштаб — показываем его. Не прямо из
                                         // обработчика: перестройка окна освобождает и его самого.
                                         DispatchQueue.main.async { self?.rebuild() }
                                     }))
        let scaleLabel = NSTextField(labelWithString: "")
        let scaleSlider = NSSlider(value: Settings.scale * 100, minValue: 70, maxValue: 200, target: nil, action: nil)
        scaleSlider.numberOfTickMarks = 14 // шаг 10 %
        scaleSlider.allowsTickMarkValuesOnly = true
        scaleSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        func showScale() { scaleLabel.stringValue = "\(Int(scaleSlider.doubleValue.rounded())) %" }
        showScale()
        bind(scaleSlider) {
            let value = scaleSlider.doubleValue.rounded() / 100
            showScale()
            if value != Settings.scale { Settings.scale = value }
        }
        stack.addArrangedSubview(row(L.t("Масштаб:", "Scale:"), scaleSlider, scaleLabel))
        stack.addArrangedSubview(note(L.t(
            "В XP и Vista у запущенных программ всегда есть подписи, а закреплённые показываются значками, как в «Быстром запуске». Поиска, «Представления задач» и даты под часами там не было.",
            "In XP and Vista running apps always have labels and pinned ones are shown as Quick Launch icons. There was no search, Task View or date under the clock.")))

        stack.addArrangedSubview(header(L.t("Панель задач", "Taskbar")))
        stack.addArrangedSubview(checkbox(L.t("Автоматически скрывать панель задач", "Automatically hide the taskbar"),
                                          Settings.autoHide) { Settings.autoHide = $0 })
        stack.addArrangedSubview(modern(checkbox(L.t("Использовать маленькие кнопки панели задач", "Use small taskbar buttons"),
                                                 Settings.smallButtons) { Settings.smallButtons = $0 }))
        stack.addArrangedSubview(row(L.t("Группировать кнопки на панели задач:", "Combine taskbar buttons:"),
                                     popup(CombineMode.allCases, Settings.combine, \.title) { [weak self] in
                                         Settings.combine = $0
                                         self?.updateEnabled()
                                     }))
        let widthLabel = NSTextField(labelWithString: "")
        let slider = NSSlider(value: Settings.maxButtonWidth, minValue: 100, maxValue: 320, target: nil, action: nil)
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        func showWidth() { widthLabel.stringValue = "\(Int(slider.doubleValue)) pt" }
        showWidth()
        bind(slider) {
            Settings.maxButtonWidth = slider.doubleValue.rounded()
            showWidth()
        }
        let widthRow = row(L.t("Ширина кнопки с подписью:", "Labeled button width:"), slider, widthLabel)
        self.widthRow = widthRow
        stack.addArrangedSubview(widthRow)
        stack.addArrangedSubview(row(L.t("Щелчок по активной программе:", "Clicking the active app:"),
                                     popup(ActiveClick.allCases, Settings.activeClick, \.title) { Settings.activeClick = $0 }))

        stack.addArrangedSubview(header(L.t("Кнопки и область уведомлений", "Buttons and notification area")))
        stack.addArrangedSubview(modern(row(L.t("Поиск:", "Search:"),
                                            popup(SearchMode.allCases, Settings.search, \.title) { Settings.search = $0 })))
        stack.addArrangedSubview(modern(checkbox(L.t("Показать кнопку «Представление задач»", "Show Task View button"),
                                                 Settings.showTaskView) { Settings.showTaskView = $0 }))
        stack.addArrangedSubview(checkbox(L.t("Показывать индикатор раскладки клавиатуры", "Show keyboard layout indicator"),
                                          Settings.showLanguage) { Settings.showLanguage = $0 })
        stack.addArrangedSubview(modern(checkbox(L.t("Показывать дату под часами", "Show the date under the clock"),
                                                 Settings.showDate) { Settings.showDate = $0 }))
        stack.addArrangedSubview(checkbox(L.t("Показывать секунды", "Show seconds"),
                                          Settings.showSeconds) { Settings.showSeconds = $0 })
        stack.addArrangedSubview(checkbox(L.t("Кнопка «Свернуть все окна» у правого края", "“Show desktop” button at the far right"),
                                          Settings.showDesktopButton) { Settings.showDesktopButton = $0 })

        stack.addArrangedSubview(header(L.t("Несколько дисплеев", "Multiple displays")))
        stack.addArrangedSubview(checkbox(L.t("Показать панель задач на всех дисплеях", "Show taskbar on all displays"),
                                          Settings.allDisplays) { [weak self] in
            Settings.allDisplays = $0
            self?.updateEnabled()
        })
        let buttonsOnRow = row(L.t("Показать кнопки панели задач:", "Show taskbar buttons on:"),
                               popup(ButtonsOn.allCases, Settings.buttonsOn, \.title) { Settings.buttonsOn = $0 })
        self.buttonsOnRow = buttonsOnRow
        stack.addArrangedSubview(buttonsOnRow)

        stack.addArrangedSubview(header(L.t("Система", "System")))
        stack.addArrangedSubview(checkbox(L.t("Скрывать Dock", "Hide the Dock"), Settings.hideDock) { Settings.hideDock = $0 })
        let pin = checkbox(L.t("Не сдвигать панель при переключении рабочих столов", "Keep the taskbar still when switching desktops"),
                           Settings.pinToAllSpaces) { Settings.pinToAllSpaces = $0 }
        pin.isEnabled = SpacePin.isAvailable
        stack.addArrangedSubview(pin)
        let login = SMAppService.mainApp
        stack.addArrangedSubview(checkbox(L.t("Запускать при входе в систему", "Start at login"), login.status == .enabled) { on in
            if on { try? login.register() } else { try? login.unregister() }
        })
        stack.addArrangedSubview(checkbox(L.t("Открывать «Пуск» по ⌃Esc", "Open Start with ⌃Esc"),
                                          Settings.startHotKey) { Settings.startHotKey = $0 })

        let trusted = WindowList.isTrusted
        let status = NSTextField(labelWithString: trusted ? L.t("Доступ к окнам разрешён", "Window access granted")
                                                          : L.t("Доступ к окнам не разрешён", "Window access not granted"))
        status.textColor = trusted ? .secondaryLabelColor : .systemOrange
        let access = NSButton(title: L.t("Разрешить…", "Allow…"), target: nil, action: nil)
        bind(access) { WindowList.requestAccess() }
        let reset = NSButton(title: L.t("Запросить заново", "Ask again"), target: nil, action: nil)
        bind(reset) { WindowList.resetAccess() }
        access.isHidden = trusted
        reset.isHidden = trusted
        let accessRow = NSStackView(views: [status, access, reset])
        accessRow.spacing = 8
        self.accessRow = accessRow
        stack.addArrangedSubview(accessRow)
        stack.addArrangedSubview(note(L.t(
            "Нужен для кнопок отдельных окон, «стопки», меню окон и кнопок по дисплеям. Без него — одна кнопка на программу.",
            "Needed for per-window buttons, the stacked look, the window list and per-display buttons. Without it, one button per app.")))
        if !trusted {
            stack.addArrangedSubview(note(L.t(
                "WTaskbar в списке «Универсального доступа» уже включена, а доступа нет? Значит, разрешение выдано прошлой сборке. Нажмите «Запросить заново»: старая запись удалится, и macOS спросит снова.",
                "WTaskbar is already switched on in the Accessibility list but access isn't granted? The permission belongs to a previous build. Click “Ask again”: the old entry is removed and macOS asks again.")))
        }

        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        updateEnabled()
    }

    private func updateEnabled() {
        setEnabled(widthRow, Settings.combine != .always || Settings.theme != .win10)
        setEnabled(buttonsOnRow, Settings.allDisplays && NSScreen.screens.count > 1)
        modernOnly.forEach { setEnabled($0, Settings.theme == .win10) }
    }

    // MARK: Элементы

    private func header(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let box = NSStackView(views: [label])
        box.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        return box
    }

    private func note(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 11)
        label.preferredMaxLayoutWidth = 460
        return label
    }

    private func checkbox(_ title: String, _ value: Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = value ? .on : .off
        bind(button) { set(button.state == .on) }
        return button
    }

    private func popup<T: Equatable>(_ cases: [T], _ value: T, _ title: KeyPath<T, String>, _ set: @escaping (T) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: cases.map { $0[keyPath: title] })
        popup.selectItem(at: cases.firstIndex(of: value) ?? 0)
        bind(popup) { set(cases[max(0, popup.indexOfSelectedItem)]) }
        return popup
    }

    private func row(_ title: String, _ controls: NSView...) -> NSView {
        let label = NSTextField(labelWithString: title)
        let row = NSStackView(views: [label] + controls)
        row.spacing = 8
        return row
    }

    private func setEnabled(_ view: NSView?, _ enabled: Bool) {
        guard let view else { return }
        (view as? NSControl)?.isEnabled = enabled
        for sub in view.subviews {
            (sub as? NSControl)?.isEnabled = enabled
            if let label = sub as? NSTextField, !label.isEditable {
                label.textColor = enabled ? .labelColor : .disabledControlTextColor
            }
        }
    }

    private func bind(_ control: NSControl, _ action: @escaping () -> Void) {
        let handler = ControlHandler(action)
        control.target = handler
        control.action = #selector(ControlHandler.fire)
        handlers.append(handler)
    }
}

private final class ControlHandler: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

// MARK: Подписи вариантов

extension ThemeKind {
    var title: String {
        switch self {
        case .win10: "Windows 10"
        case .vista: "Windows Vista"
        case .xp: "Windows XP"
        }
    }
}

extension CombineMode {
    var title: String {
        switch self {
        case .always: L.t("Всегда, скрывать метки", "Always, hide labels")
        case .whenFull: L.t("При заполнении панели задач", "When taskbar is full")
        case .never: L.t("Никогда", "Never")
        }
    }
}

extension SearchMode {
    var title: String {
        switch self {
        case .hidden: L.t("Скрыто", "Hidden")
        case .icon: L.t("Показать значок поиска", "Show search icon")
        case .box: L.t("Показать поле поиска", "Show search box")
        }
    }
}

extension ButtonsOn {
    var title: String {
        switch self {
        case .all: L.t("На всех панелях задач", "All taskbars")
        case .mainAndOpen: L.t("На главной панели и панели, где открыто окно", "Main taskbar and taskbar where window is open")
        case .whereOpen: L.t("На панели, где открыто окно", "Taskbar where window is open")
        }
    }
}

extension ActiveClick {
    var title: String {
        switch self {
        case .hide: L.t("Скрыть программу", "Hide the app")
        case .minimize: L.t("Свернуть окно", "Minimize the window")
        case .nothing: L.t("Ничего не делать", "Do nothing")
        }
    }
}
