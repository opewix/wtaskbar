import AppKit

/// Кнопка панели задач: закреплённая программа (может быть не запущена), запущенная
/// программа целиком или — без группировки — одно её окно.
struct TaskItem {
    let key: String
    /// Программа в порядке кнопок: путь к ней или, если пути нет, номер процесса.
    let appID: String
    let url: URL?
    let app: NSRunningApplication?
    let pinned: Bool
    var window: WindowList.Window? = nil

    var name: String {
        if let title = window?.title, !title.isEmpty { return title }
        if let name = app?.localizedName { return name }
        if let url { return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        return "?"
    }

    var icon: NSImage {
        if let url { return Icons.app(url) }
        return app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Та же программа, но кнопка — на одно окно.
    func forWindow(_ window: WindowList.Window) -> TaskItem {
        TaskItem(key: "win:\(app?.processIdentifier ?? 0):\(window.id)", appID: appID, url: url, app: app, pinned: pinned, window: window)
    }
}

/// Что показывает панель: закреплённые программы, запущенные, их окна, активная.
/// Любое изменение рассылает `TaskbarModel.changed`.
final class TaskbarModel {
    static let shared = TaskbarModel()
    static let changed = Notification.Name("WTaskbarModelChanged")

    private(set) var pinned: [URL] = []
    private(set) var tiles: [URL] = []
    private(set) var frontmostPID: pid_t?
    /// Окна запущенных программ; пусто без разрешения «Универсальный доступ».
    private(set) var windows: [pid_t: [WindowList.Window]] = [:]
    private var windowsSignature = ""
    /// Порядок запуска: новые кнопки встают в конец в том порядке, в каком открывались программы.
    private var launchOrder: [pid_t] = []
    /// Порядок кнопок программ — закреплённых и запущенных вперемешку, его меняет перетаскивание.
    private var slots: [String] = []
    /// Порядок окон каждой программы: по времени появления, его тоже меняет перетаскивание.
    /// Система отдаёт окна «верхнее первым», и без этого кнопки окон прыгали бы при каждом переключении.
    private var windowOrder: [pid_t: [Int]] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func start() {
        pinned = (Settings.taskbarPins ?? Self.defaultPins).map { URL(fileURLWithPath: $0) }
        tiles = (Settings.startTiles ?? Self.defaultTiles).map { URL(fileURLWithPath: $0) }
        launchOrder = NSWorkspace.shared.runningApplications.filter(isTaskApp).map(\.processIdentifier)
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(self, selector: #selector(workspaceEvent(_:)), name: name, object: nil)
        }
        // Окна открываются, закрываются и переименовываются без уведомлений — опрашиваем.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshWindows() }
        refreshWindows()
    }

    /// Кнопки по программам в порядке `slots`. Закреплённая и запущенная программа — одна кнопка.
    var items: [TaskItem] {
        let running = runningIDs()
        let pins = Dictionary(pinned.map { (Self.identity($0), $0) }, uniquingKeysWith: { first, _ in first })
        syncSlots(pinned: pinned.map(Self.identity), running: running.map(\.id))
        let apps = Dictionary(running, uniquingKeysWith: { first, _ in first })
        return slots.compactMap { id in
            let app = apps[id]
            let pin = pins[id]
            guard app != nil || pin != nil else { return nil }
            return TaskItem(key: "app:" + id, appID: id, url: pin ?? app?.bundleURL, app: app, pinned: pin != nil)
        }
    }

    /// Новый порядок программ после перетаскивания. `ids` может быть частью кнопок
    /// (на втором дисплее видны не все) — тогда переставляются только они, на своих местах.
    func reorder(_ ids: [String]) {
        let moving = Set(ids)
        let positions = slots.indices.filter { moving.contains(slots[$0]) }
        guard positions.count == ids.count else { return }
        for (position, id) in zip(positions, ids) { slots[position] = id }
        // Закреплённые запоминаем в новом порядке — он переживает перезапуск.
        let order = Dictionary(slots.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        pinned.sort { (order[Self.identity($0)] ?? .max) < (order[Self.identity($1)] ?? .max) }
        Settings.taskbarPins = pinned.map(\.path)
        post()
    }

    /// Новый порядок окон программы после перетаскивания.
    func reorderWindows(of pid: pid_t, _ ids: [Int]) {
        guard var order = windowOrder[pid] else { return }
        let moving = Set(ids)
        let positions = order.indices.filter { moving.contains(order[$0]) }
        guard positions.count == ids.count else { return }
        for (position, id) in zip(positions, ids) { order[position] = id }
        windowOrder[pid] = order
        windows[pid] = sortedWindows(windows[pid] ?? [], pid: pid)
        post()
    }

    func windows(of item: TaskItem) -> [WindowList.Window] {
        item.app.map { windows[$0.processIdentifier] ?? [] } ?? []
    }

    /// Кнопка программы активна, когда программа впереди; кнопка окна — когда ещё и окно в фокусе.
    func isActive(_ item: TaskItem) -> Bool {
        guard let app = item.app, app.processIdentifier == frontmostPID, !app.isHidden else { return false }
        guard let window = item.window else { return true }
        return window.focused && !window.minimized
    }

    /// После своих действий с окнами не ждём очередного опроса.
    func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refreshWindows() }
    }

    // MARK: Закрепление

    func isPinned(_ url: URL) -> Bool { pinned.contains { Self.same($0, url) } }
    func isTile(_ url: URL) -> Bool { tiles.contains { Self.same($0, url) } }

    func togglePin(_ url: URL) {
        if isPinned(url) { pinned.removeAll { Self.same($0, url) } } else { pinned.append(url) }
        Settings.taskbarPins = pinned.map(\.path)
        post()
    }

    func toggleTile(_ url: URL) {
        if isTile(url) { tiles.removeAll { Self.same($0, url) } } else { tiles.append(url) }
        Settings.startTiles = tiles.map(\.path)
        post()
    }

    // MARK: Внутреннее

    @objc private func workspaceEvent(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        switch note.name {
        case NSWorkspace.didTerminateApplicationNotification:
            if let pid = app?.processIdentifier {
                launchOrder.removeAll { $0 == pid }
                windows[pid] = nil
                windowOrder[pid] = nil
            }
        case NSWorkspace.didActivateApplicationNotification:
            // Своё окно («Пуск», параметры) активной программой не считаем.
            if let pid = app?.processIdentifier, pid != ownPID { frontmostPID = pid }
            refreshSoon()
        default:
            break
        }
        post()
    }

    private func runningTaskApps() -> [NSRunningApplication] {
        // Политику программа может сменить после запуска, поэтому фильтруем каждый раз заново.
        let apps = NSWorkspace.shared.runningApplications.filter(isTaskApp)
        for app in apps where !launchOrder.contains(app.processIdentifier) {
            launchOrder.append(app.processIdentifier)
        }
        return apps.sorted {
            (launchOrder.firstIndex(of: $0.processIdentifier) ?? 0) < (launchOrder.firstIndex(of: $1.processIdentifier) ?? 0)
        }
    }

    /// Запущенные программы с их местом в порядке кнопок. Второй экземпляр той же программы
    /// получает своё место по номеру процесса.
    private func runningIDs() -> [(id: String, app: NSRunningApplication)] {
        var seen = Set<String>()
        return runningTaskApps().map { app in
            var id = app.bundleURL.map(Self.identity) ?? "pid:\(app.processIdentifier)"
            if !seen.insert(id).inserted { id = "pid:\(app.processIdentifier)" }
            return (id, app)
        }
    }

    /// Убирает места закрытых и откреплённых программ; новые — в конец.
    private func syncSlots(pinned: [String], running: [String]) {
        let alive = Set(pinned).union(running)
        slots.removeAll { !alive.contains($0) }
        for id in pinned + running where !slots.contains(id) {
            slots.append(id)
        }
    }

    private func sortedWindows(_ list: [WindowList.Window], pid: pid_t) -> [WindowList.Window] {
        let order = windowOrder[pid] ?? []
        let index = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return list.sorted { (index[$0.id] ?? .max) < (index[$1.id] ?? .max) }
    }

    static func identity(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func isTaskApp(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ownPID
    }

    private func refreshWindows() {
        guard WindowList.isTrusted else { return }
        var fresh: [pid_t: [WindowList.Window]] = [:]
        var signature = ""
        for app in runningTaskApps() {
            let pid = app.processIdentifier
            // Не ответила — оставляем прежние окна, а не показываем кнопку без них.
            let list = WindowList.windows(of: app, previous: windows[pid] ?? []) ?? windows[pid] ?? []
            // Новые окна — в конец, закрытые убираем.
            let ids = Set(list.map(\.id))
            var order = (windowOrder[pid] ?? []).filter(ids.contains)
            order += list.map(\.id).filter { !order.contains($0) }
            windowOrder[pid] = order
            fresh[pid] = sortedWindows(list, pid: pid)
            signature += "\(pid):" + (fresh[pid] ?? []).map(\.signature).joined(separator: ";") + "\n"
        }
        windows = fresh
        if signature != windowsSignature {
            windowsSignature = signature
            post()
        }
    }

    private func post() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    static func same(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        return a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static var defaultPins: [String] {
        ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app",
         "/System/Applications/Mail.app", "/System/Applications/System Settings.app"].filter(exists)
    }

    private static var defaultTiles: [String] {
        ["/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Calendar.app",
         "/System/Applications/Photos.app", "/System/Applications/Music.app", "/System/Applications/Notes.app",
         "/System/Applications/Maps.app", "/System/Applications/App Store.app",
         "/System/Applications/System Settings.app"].filter(exists)
    }

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
