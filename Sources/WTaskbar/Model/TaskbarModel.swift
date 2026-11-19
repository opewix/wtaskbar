import AppKit

/// Кнопка панели задач: закреплённая программа (может быть не запущена), запущенная
/// программа целиком или — без группировки — одно её окно.
struct TaskItem {
    let key: String
    /// Программа в порядке кнопок: путь к ней или, если пути нет, номер процесса.
    let appID: String
    let url: URL?
    /// Экземпляр, от которого имя и значок; у кнопки окна — его процесс.
    let app: NSRunningApplication?
    /// Все экземпляры программы с окнами здесь: как в Windows, они — одна кнопка (WExplorer
    /// с отдельным процессом на окно, программа, запущенная дважды). Пусто — не запущена.
    var apps: [NSRunningApplication] = []
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
        let owner = apps.first { $0.processIdentifier == window.pid } ?? app
        return TaskItem(key: "win:\(window.pid):\(window.id)", appID: appID, url: url, app: owner,
                        apps: owner.map { [$0] } ?? [], pinned: pinned, window: window)
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
    /// Упреждение при смене стола: окно, которое macOS выведет вперёд на столе назначения. Активную
    /// программу она меняет только в конце анимации — до того активной была бы кнопка прежней.
    private var predictedFront: (number: CGWindowID, pid: pid_t)?
    /// Окна запущенных программ; пусто без разрешения «Универсальный доступ».
    private(set) var windows: [pid_t: [WindowList.Window]] = [:]
    private var windowsSignature = ""
    /// Столы окон каждой программы по WindowServer (см. `WindowList.serverWindows`).
    private var appDesktops: [pid_t: Set<UInt64>] = [:]
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
        // Сменился рабочий стол — кнопки окон другие, не ждём опроса.
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshWindows()
            self?.refreshSoon()
        }
        // Окна открываются, закрываются и переименовываются без уведомлений — опрашиваем.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshWindows() }
        refreshWindows()
    }

    /// Кнопки по программам в порядке `slots`. Закреплённая и запущенная программа — одна кнопка,
    /// сколько бы её экземпляров ни работало.
    var items: [TaskItem] {
        let running = runningIDs()
        let pins = Dictionary(pinned.map { (Self.identity($0), $0) }, uniquingKeysWith: { first, _ in first })
        syncSlots(pinned: pinned.map(Self.identity), running: running.map(\.id))
        let instances = Dictionary(grouping: running, by: \.id).mapValues { $0.map(\.app) }
        return slots.compactMap { id in
            let pin = pins[id]
            // Экземпляр, все окна которого на других столах, для этого стола не запущен.
            let here = (instances[id] ?? []).filter(hasWindowsHere)
            if let app = here.first {
                return TaskItem(key: "app:" + id, appID: id, url: pin ?? app.bundleURL, app: app, apps: here, pinned: pin != nil)
            }
            // Окон здесь нет: незакреплённой программы на панели нет, закреплённая — просто значком,
            // будто не запущена, как в Windows.
            guard let pin else { return nil }
            return TaskItem(key: "app:" + id, appID: id, url: pin, app: nil, pinned: true)
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

    /// Новый порядок экземпляров одной программы после перетаскивания кнопок их окон.
    func reorderInstances(_ pids: [pid_t]) {
        let moving = Set(pids)
        let positions = launchOrder.indices.filter { moving.contains(launchOrder[$0]) }
        guard pids.count > 1, positions.count == pids.count else { return }
        for (position, pid) in zip(positions, pids) { launchOrder[position] = pid }
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

    /// Окна программы, кнопки которых видны: без окон других рабочих столов.
    func windows(of item: TaskItem) -> [WindowList.Window] {
        allWindows(of: item).filter(\.isShown)
    }

    func allWindows(of item: TaskItem) -> [WindowList.Window] {
        item.apps.flatMap { windows[$0.processIdentifier] ?? [] }
    }

    /// Окна программы на этом столе по последнему опросу.
    func windowsHere(of app: NSRunningApplication) -> [WindowList.Window] {
        (windows[app.processIdentifier] ?? []).filter(\.onCurrentDesktop)
    }

    /// Есть ли у программы окна здесь. Без окон на этом столе — их нет вовсе или они на других
    /// столах — программа, как в Windows, на панели не запущена: закреплённая — значком, иначе её нет.
    /// Пока окна не опрошены или нет доступа к ним — считаем, что есть.
    func hasWindowsHere(_ app: NSRunningApplication) -> Bool {
        guard WindowList.isTrusted, let list = windows[app.processIdentifier] else { return true }
        if list.contains(where: \.isShown) { return true }
        let desktops = appDesktops[app.processIdentifier] ?? []
        // Окна других столов Accessibility не отдаёт: при показе всех столов программа с ними остаётся.
        if !Settings.currentDesktopOnly { return !desktops.isEmpty }
        // Окно на столе, куда только что перешли, а Accessibility его ещё не отдала.
        return desktops.contains { Desktops.current.contains($0) }
    }

    /// Кнопка программы активна, когда программа впереди; кнопка окна — когда ещё и окно в фокусе.
    func isActive(_ item: TaskItem) -> Bool {
        if let predictedFront {
            guard item.apps.contains(where: { $0.processIdentifier == predictedFront.pid }) else { return false }
            return item.window.map { $0.number == predictedFront.number } ?? true
        }
        guard frontApp(of: item) != nil else { return false }
        guard let window = item.window else { return true }
        return window.focused && !window.minimized
    }

    /// Экземпляр кнопки, который сейчас впереди.
    func frontApp(of item: TaskItem) -> NSRunningApplication? {
        item.apps.first { $0.processIdentifier == frontmostPID && !$0.isHidden }
    }

    /// Свайп между столами закончен (`DesktopSwipe`): кнопки стола назначения — сразу, не дожидаясь
    /// анимации. Не подтвердит macOS смену стола — вернём прежние.
    func desktopSwiped(_ direction: Int) {
        guard Settings.currentDesktopOnly, Desktops.predict(direction) else { return }
        showPredictedDesktop()
    }

    /// Клавишами выбран рабочий стол по номеру (с нуля).
    func desktopChosen(_ index: Int) {
        guard Settings.currentDesktopOnly, Desktops.predict(desktop: index) else { return }
        showPredictedDesktop()
    }

    private func showPredictedDesktop() {
        predictedFront = Desktops.predictedTarget.flatMap(frontWindow(on:))
        refreshWindows()
        let wait: TimeInterval = 2
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.05) { [weak self] in
            guard let self else { return }
            Desktops.update()
            let expired = Desktops.expirePrediction(after: wait)
            // Та же программа впереди и на новом столе — macOS об активации не сообщит, снимаем сами.
            if Desktops.predictedTarget == nil, self.predictedFront != nil {
                self.predictedFront = nil
                self.post()
            }
            if expired { self.refreshWindows() }
        }
    }

    /// Верхнее окно стола среди окон программ с панели: его macOS и выведет вперёд, придя на стол.
    /// Свёрнутые окна и окна скрытых программ не в счёт. nil — окон там нет или их не узнать.
    private func frontWindow(on space: UInt64) -> (number: CGWindowID, pid: pid_t)? {
        let apps = Dictionary(runningTaskApps().map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return WindowList.stack(on: space).first { entry in
            guard let app = apps[entry.pid], !app.isHidden else { return false }
            return !(windows[entry.pid] ?? []).contains { $0.number == entry.number && $0.minimized }
        }
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
            if let pid = app?.processIdentifier, pid != ownPID {
                frontmostPID = pid
                predictedFront = nil
            }
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

    /// Запущенные программы с их местом в порядке кнопок. У экземпляров одной программы место общее.
    private func runningIDs() -> [(id: String, app: NSRunningApplication)] {
        runningTaskApps().map { app in
            (app.bundleURL.map(Self.identity) ?? "pid:\(app.processIdentifier)", app)
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
        DesktopSwipe.startIfNeeded()
        Desktops.update()
        // Пришли на стол, и впереди та же программа, что была: об активации macOS не сообщит.
        if let predictedFront, Desktops.predictedTarget == nil, predictedFront.pid == frontmostPID {
            self.predictedFront = nil
        }
        let server = WindowList.serverWindows()
        var fresh: [pid_t: [WindowList.Window]] = [:]
        var signature = ""
        for app in runningTaskApps() {
            let pid = app.processIdentifier
            let previous = windows[pid] ?? []
            // Не ответила — оставляем прежние окна, а не показываем кнопку без них.
            var list = WindowList.windows(of: app, previous: previous) ?? previous
            // Окна других столов Accessibility не отдаёт — помним их с прошлых раз, пока окно живо
            // и стоит на другом столе: при переходе туда кнопки появятся сразу, без опроса.
            let seen = Set(list.compactMap(\.number))
            for var old in previous {
                guard let number = old.number, !seen.contains(number), let spaces = server.desktops[number],
                      !spaces.contains(where: Desktops.actual.contains) else { continue }
                old.desktops = spaces
                list.append(old)
            }
            // Новые окна — в конец, закрытые убираем.
            let ids = Set(list.map(\.id))
            var order = (windowOrder[pid] ?? []).filter(ids.contains)
            order += list.map(\.id).filter { !order.contains($0) }
            windowOrder[pid] = order
            fresh[pid] = sortedWindows(list, pid: pid)
            signature += "\(pid):" + (fresh[pid] ?? []).map(\.signature).joined(separator: ";") + "\n"
        }
        windows = fresh
        appDesktops = server.apps
        // Сменился только текущий стол — список окон с запомненными окнами других столов тот же,
        // а кнопки уже другие.
        signature += "current:\(Desktops.current.sorted()) fullScreen:\(Desktops.fullScreen.sorted())\n"
        signature += "front:\(predictedFront.map { "\($0.number)" } ?? "-")\n"
        signature += "desktops:" + appDesktops.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.sorted())" }.joined(separator: ",")
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
