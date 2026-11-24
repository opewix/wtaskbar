import AppKit

/// Запуск программ и действия кнопок панели.
enum Launcher {
    static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    static let activityMonitor = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
    static let systemSettings = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    /// Запускает программу или, если она уже работает, делает то же, что щелчок по значку в Dock:
    /// выводит вперёд и разворачивает свёрнутое окно (или открывает новое, если окон нет).
    static func open(_ url: URL) {
        let model = TaskbarModel.shared
        let instances = runningApps(at: url)
        // Окно на этом столе уже есть — его и выводим вперёд. Не программу через NSWorkspace: экземпляров
        // может быть несколько, и macOS выбрала бы любой — хоть с другого стола — и перешла бы туда.
        if focusWindowHere(of: instances) { return }
        // Запущена, но окон на этом столе нет — новое окно здесь, как в Windows, а не прыжок на чужой стол.
        if !instances.isEmpty, !instances.contains(where: model.hasWindowsHere), openNewWindow(in: instances) { return }
        launch(url)
    }

    /// Ещё одно окно программы — Shift и щелчок по кнопке или пункт с её именем в меню кнопки.
    /// Не запущена или «Нового окна» в её меню нет — как обычный щелчок.
    static func openNew(_ url: URL) {
        let instances = runningApps(at: url)
        if !instances.isEmpty, openNewWindow(in: instances) { return }
        open(url)
    }

    static func focus(_ window: WindowList.Window) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        app.unhide()
        WindowList.focus(window, of: app)
        TaskbarModel.shared.refreshSoon()
    }

    /// Окна кнопки в том порядке, в каком их выводить вперёд, когда над ней держат перетаскиваемое:
    /// у кнопки окна — оно одно; у программы — сначала то, что вывел бы щелчок, потом остальные.
    /// Пусто — программа не запущена или её окна не опрошены.
    static func windowsToBring(_ item: TaskItem) -> [WindowList.Window] {
        guard WindowList.isTrusted, let app = item.app else { return [] }
        if let window = item.window {
            return [WindowList.windows(of: app)?.first { $0.id == window.id } ?? window]
        }
        var windows = TaskbarModel.shared.windows(of: item)
        if let first = windows.firstIndex(where: { $0.focused && !$0.minimized })
            ?? windows.firstIndex(where: { !$0.minimized }) {
            windows.insert(windows.remove(at: first), at: 0)
        }
        return windows
    }

    private static func launch(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Выводит вперёд окно этих программ на текущем столе: то, что в фокусе, иначе любое не свёрнутое,
    /// иначе разворачивает свёрнутое. false — окон здесь нет или они не опрошены.
    @discardableResult
    private static func focusWindowHere(of apps: [NSRunningApplication]) -> Bool {
        guard WindowList.isTrusted else { return false }
        let windows = apps.flatMap(TaskbarModel.shared.windowsHere)
        guard let window = windows.first(where: { $0.focused && !$0.minimized })
                ?? windows.first(where: { !$0.minimized }) ?? windows.first else { return false }
        focus(window)
        return true
    }

    /// Нажимает «Новое окно» в меню программы и выводит вперёд появившееся окно. Просим экземпляр
    /// с окнами здесь, если такой есть. false — пункта нет или программа не ответила.
    private static func openNewWindow(in instances: [NSRunningApplication]) -> Bool {
        guard WindowList.isTrusted, let url = instances.first?.bundleURL else { return false }
        let model = TaskbarModel.shared
        let app = instances.first { !model.windowsHere(of: $0).isEmpty } ?? instances[0]
        let known = Set(instances.flatMap { WindowList.windows(of: $0) ?? model.windowsHere(of: $0) }.compactMap(\.number))
        guard WindowList.openNewWindow(of: app) else { return false }
        focusNewWindow(at: url, known: known, attempts: 10)
        return true
    }

    /// Щелчок по кнопке, как в Windows: не запущена — запустить, активна — то, что выбрано
    /// в параметрах (скрыть, свернуть окно, ничего), иначе — вывести вперёд.
    static func click(_ item: TaskItem) {
        let model = TaskbarModel.shared
        guard let app = item.app else {
            if let url = item.url { open(url) }
            return
        }
        defer { model.refreshSoon() }
        // Кнопка помнит окно по последнему опросу (до секунды назад): в фокусе ли оно и свёрнуто ли,
        // спрашиваем заново — иначе повторный щелчок по только что выбранному окну его не свернёт.
        var item = item
        if let window = item.window, let fresh = WindowList.windows(of: app)?.first(where: { $0.id == window.id }) {
            item.window = fresh
        }
        if model.isActive(item), let front = model.frontApp(of: item) {
            switch Settings.activeClick {
            case .hide:
                front.hide()
            case .minimize:
                // Без доступа к окнам свернуть нечего — скрываем программу.
                let focused = (WindowList.windows(of: front) ?? model.windowsHere(of: front))
                    .first { $0.focused && !$0.minimized && $0.onCurrentDesktop }
                if let window = item.window ?? focused {
                    WindowList.minimize(window)
                } else {
                    front.hide()
                }
            case .nothing:
                break
            }
        } else if let window = item.window {
            WindowList.focus(window, of: app)
        } else if focusWindowHere(of: item.apps) {
            // Окно этого стола, а не программа целиком: у неё могут быть окна и на других столах.
        } else if let url = app.bundleURL {
            app.unhide()
            launch(url)
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func runningApps(at url: URL) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { TaskbarModel.same($0.bundleURL, url) }
    }

    /// Выводит вперёд новое окно программы, когда оно появится. Не саму программу: её главное
    /// окно может быть на другом столе, и macOS перешла бы туда. Окно может открыть и другой экземпляр
    /// (WExplorer с отдельной иконкой на окно), поэтому смотрим все. Новое — то, которого не было
    /// в `known` (номера окон до нажатия).
    private static func focusNewWindow(at url: URL, known: Set<CGWindowID>, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for app in runningApps(at: url) {
                let fresh = WindowList.windows(of: app)?.first {
                    $0.onCurrentDesktop && !$0.minimized && !($0.number.map(known.contains) ?? false)
                }
                if let fresh {
                    WindowList.focus(fresh, of: app)
                    TaskbarModel.shared.refreshSoon()
                    return
                }
            }
            if attempts > 1 { focusNewWindow(at: url, known: known, attempts: attempts - 1) }
        }
    }

    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: «Свернуть все окна» — узкая полоска справа

    private static var hiddenForDesktop: [NSRunningApplication] = []

    /// Первый щелчок скрывает все программы, второй возвращает скрытые этим щелчком.
    static func toggleDesktop() {
        if !hiddenForDesktop.isEmpty {
            hiddenForDesktop.forEach { $0.unhide() }
            hiddenForDesktop = []
            return
        }
        hiddenForDesktop = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        hiddenForDesktop.forEach { $0.hide() }
    }
}

/// Сон, блокировка, выход, перезагрузка, выключение.
enum Power {
    static func sleep() {
        DockControl.run("/usr/bin/pmset", ["sleepnow"])
    }

    static func lock() {
        // Тот же вызов, что у пункта «Заблокировать экран» в меню Apple.
        typealias LockFunction = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(symbol, to: LockFunction.self)()
        } else {
            DockControl.run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    // Системные окна подтверждения из loginwindow — как у пунктов меню Apple.
    static func logOut() { loginwindow("logo") }
    static func restart() { loginwindow("rrst") }
    static func shutDown() { loginwindow("rsdn") }

    private static func loginwindow(_ code: String) {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevt\(code)»")?.executeAndReturnError(&error)
    }
}
