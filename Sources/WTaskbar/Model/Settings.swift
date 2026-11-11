import Foundation

/// Оформление панели, «Пуска» и календаря.
enum ThemeKind: String, CaseIterable {
    case win10, vista, xp
}

/// Группировка кнопок, как в Windows 10.
enum CombineMode: String, CaseIterable {
    /// Одна кнопка на программу, без подписей.
    case always
    /// Окна — отдельными кнопками с подписями, пока помещаются; потом как `always`.
    case whenFull
    /// Окна — всегда отдельными кнопками с подписями.
    case never
}

enum SearchMode: String, CaseIterable {
    case hidden, icon, box
}

/// На каких панелях показывать кнопки, когда панель есть на каждом дисплее.
enum ButtonsOn: String, CaseIterable {
    case all
    case mainAndOpen
    case whereOpen
}

/// Что делает щелчок по уже активной программе или окну.
enum ActiveClick: String, CaseIterable {
    case hide, minimize, nothing
}

/// Настройки панели. Любое изменение рассылает `Settings.changed`.
enum Settings {
    static let changed = Notification.Name("WTaskbarSettingsChanged")
    private static let defaults = UserDefaults.standard

    // MARK: Панель

    static var theme: ThemeKind {
        get { choice("theme", default: .win10) }
        set { store(newValue.rawValue, "theme") }
    }

    /// Масштаб панели, «Пуска» и календаря. Свой у каждой темы: XP и Vista изначально
    /// заметно меньше Windows 10.
    static var scale: Double {
        get {
            let key = "scale." + theme.rawValue
            let value = defaults.object(forKey: key) == nil ? 1 : defaults.double(forKey: key)
            return min(max(value, 0.7), 2)
        }
        set { store(newValue, "scale." + theme.rawValue) }
    }

    static var autoHide: Bool {
        get { bool("autoHide", default: false) }
        set { store(newValue, "autoHide") }
    }

    /// Развёрнутые окна не заходят под панель (нужен «Универсальный доступ»).
    static var fitMaximized: Bool {
        get { bool("fitMaximized", default: true) }
        set { store(newValue, "fitMaximized") }
    }

    static var smallButtons: Bool {
        get { bool("smallButtons", default: false) }
        set { store(newValue, "smallButtons") }
    }

    static var combine: CombineMode {
        get { choice("combine", default: .always) }
        set { store(newValue.rawValue, "combine") }
    }

    /// Ширина кнопки с подписью, пока на панели хватает места.
    static var maxButtonWidth: Double {
        get { defaults.object(forKey: "maxButtonWidth") == nil ? 180 : defaults.double(forKey: "maxButtonWidth") }
        set { store(newValue, "maxButtonWidth") }
    }

    static var activeClick: ActiveClick {
        get { choice("activeClick", default: .hide) }
        set { store(newValue.rawValue, "activeClick") }
    }

    // MARK: Кнопки и область уведомлений

    static var search: SearchMode {
        get {
            // До окна параметров было только «показать поле поиска: да/нет».
            return choice("search", default: bool("showSearch", default: true) ? .box : .hidden)
        }
        set { store(newValue.rawValue, "search") }
    }

    static var showTaskView: Bool {
        get { bool("showTaskView", default: true) }
        set { store(newValue, "showTaskView") }
    }

    static var showLanguage: Bool {
        get { bool("showLanguage", default: true) }
        set { store(newValue, "showLanguage") }
    }

    static var showDate: Bool {
        get { bool("showDate", default: true) }
        set { store(newValue, "showDate") }
    }

    static var showSeconds: Bool {
        get { bool("showSeconds", default: false) }
        set { store(newValue, "showSeconds") }
    }

    static var showDesktopButton: Bool {
        get { bool("showDesktopButton", default: true) }
        set { store(newValue, "showDesktopButton") }
    }

    // MARK: Несколько дисплеев

    static var allDisplays: Bool {
        get { bool("allDisplays", default: true) }
        set { store(newValue, "allDisplays") }
    }

    static var buttonsOn: ButtonsOn {
        get { choice("buttonsOn", default: .all) }
        set { store(newValue.rawValue, "buttonsOn") }
    }

    // MARK: Система

    static var hideDock: Bool {
        get { bool("hideDock", default: false) }
        set { store(newValue, "hideDock") }
    }

    /// Панель не уезжает при переключении рабочих столов (закрытый API macOS, см. `SpacePin`).
    static var pinToAllSpaces: Bool {
        get { bool("pinToAllSpaces", default: true) }
        set { store(newValue, "pinToAllSpaces") }
    }

    static var startHotKey: Bool {
        get { bool("startHotKey", default: true) }
        set { store(newValue, "startHotKey") }
    }

    static var askedAboutDock: Bool {
        get { bool("askedAboutDock", default: false) }
        set { defaults.set(newValue, forKey: "askedAboutDock") }
    }

    static var taskbarPins: [String]? {
        get { defaults.stringArray(forKey: "taskbarPins") }
        set { defaults.set(newValue, forKey: "taskbarPins") }
    }

    static var startTiles: [String]? {
        get { defaults.stringArray(forKey: "startTiles") }
        set { defaults.set(newValue, forKey: "startTiles") }
    }

    // bool(forKey:) понимает и «YES» из аргументов запуска, `as? Bool` — нет.
    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    private static func choice<T: RawRepresentable>(_ key: String, default value: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? value
    }

    private static func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
