import AppKit

/// Запуск программ и действия кнопок панели.
enum Launcher {
    static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    static let activityMonitor = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
    static let systemSettings = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    /// Запускает программу или, если она уже работает, делает то же, что щелчок по значку в Dock:
    /// выводит вперёд и разворачивает свёрнутое окно (или открывает новое, если окон нет).
    static func open(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
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
        if model.isActive(item) {
            switch Settings.activeClick {
            case .hide:
                app.hide()
            case .minimize:
                // Без доступа к окнам свернуть нечего — скрываем программу.
                if let window = item.window ?? model.windows(of: item).first(where: { $0.focused }) {
                    WindowList.minimize(window)
                } else {
                    app.hide()
                }
            case .nothing:
                break
            }
        } else if let window = item.window {
            WindowList.focus(window, of: app)
        } else if let url = app.bundleURL {
            app.unhide()
            open(url)
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
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
