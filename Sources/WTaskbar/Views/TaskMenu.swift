import AppKit

/// Меню по правому щелчку на программе — аналог списка переходов Windows:
/// окна программы, запуск, закрепление, закрытие.
enum TaskMenu {
    static func make(_ item: TaskItem) -> NSMenu {
        let menu = NSMenu.themed()

        if !item.apps.isEmpty {
            if WindowList.isTrusted {
                let windows = shownWindows(item)
                for window in windows {
                    var title = window.title.isEmpty ? item.name : window.title
                    if window.minimized { title += L.t("  (свёрнуто)", "  (minimized)") }
                    menu.addItem(.action(title) { Launcher.focus(window) })
                }
                if !windows.isEmpty { menu.addItem(.separator()) }
            } else {
                menu.addItem(.action(L.t("Показать окна…", "Show windows…")) { WindowList.requestAccess() })
                menu.addItem(.separator())
            }
        }

        if let url = item.url {
            // Как в Windows: пункт с именем программы открывает ещё одно её окно.
            let open = NSMenuItem.action(item.name) { Launcher.openNew(url) }
            open.image = item.icon.resized(16)
            menu.addItem(open)
            let pinned = TaskbarModel.shared.isPinned(url)
            menu.addItem(.action(pinned ? L.t("Открепить от панели задач", "Unpin from taskbar")
                                        : L.t("Закрепить на панели задач", "Pin to taskbar")) {
                TaskbarModel.shared.togglePin(url)
            })
            menu.addItem(.action(L.t("Показать в Finder", "Show in Finder")) { Launcher.showInFinder(url) })
        }

        if let app = item.app {
            let apps = item.apps
            menu.addItem(.separator())
            if apps.allSatisfy(\.isHidden) {
                menu.addItem(.action(L.t("Показать", "Show")) { apps.forEach { $0.unhide() } })
            } else {
                menu.addItem(.action(L.t("Скрыть", "Hide")) { apps.forEach { $0.hide() } })
            }
            menu.addItem(.action(L.t("Завершить \(app.localizedName ?? "")", "Quit \(app.localizedName ?? "")")) {
                apps.forEach { $0.terminate() }
            })
            // Как в Windows: «Закрыть» — самый нижний пункт и закрывает окна — то, что на кнопке, а не программу.
            // Кнопка окна — только его; кнопка группы — все её окна этого рабочего стола.
            let windows = item.window.map { [$0] } ?? (WindowList.isTrusted ? shownWindows(item) : [])
            if !windows.isEmpty {
                let title = windows.count == 1 ? L.t("Закрыть окно", "Close window")
                                               : L.t("Закрыть все окна", "Close all windows")
                menu.addItem(.action(title) {
                    windows.forEach(WindowList.close)
                    TaskbarModel.shared.refreshSoon()
                })
            }
        }
        return menu
    }

    /// Список окон сгруппированной кнопки для выбора щелчком. nil — окон здесь меньше двух.
    static func windowList(_ item: TaskItem) -> NSMenu? {
        guard WindowList.isTrusted, !item.apps.isEmpty else { return nil }
        let windows = TaskbarModel.shared.windows(of: item)
        guard windows.count > 1 else { return nil }
        let menu = NSMenu.themed()
        let icon = item.icon.resized(16)
        for window in windows {
            var title = window.title.isEmpty ? item.name : window.title
            if window.minimized { title += L.t("  (свёрнуто)", "  (minimized)") }
            let entry = NSMenuItem.action(title, checked: window.focused && TaskbarModel.shared.isActive(item)) { Launcher.focus(window) }
            entry.image = icon
            menu.addItem(entry)
        }
        return menu
    }

    /// Окна кнопки, спрошенные заново: меню не ждёт очередного опроса. Не ответила — по последнему опросу.
    private static func shownWindows(_ item: TaskItem) -> [WindowList.Window] {
        let model = TaskbarModel.shared
        return item.apps.flatMap { app in
            WindowList.windows(of: app) ?? model.allWindows(of: item).filter { $0.pid == app.processIdentifier }
        }.filter(\.isShown)
    }
}

extension NSImage {
    func resized(_ side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            self.draw(in: rect)
            return true
        }
    }
}
