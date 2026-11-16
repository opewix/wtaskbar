import AppKit

/// Меню по правому щелчку на программе — аналог списка переходов Windows:
/// окна программы, запуск, закрепление, закрытие.
enum TaskMenu {
    static func make(_ item: TaskItem) -> NSMenu {
        let menu = NSMenu.themed()

        if let app = item.app {
            if WindowList.isTrusted {
                let windows = (WindowList.windows(of: app) ?? TaskbarModel.shared.allWindows(of: item)).filter(\.isShown)
                for window in windows {
                    var title = window.title.isEmpty ? item.name : window.title
                    if window.minimized { title += L.t("  (свёрнуто)", "  (minimized)") }
                    menu.addItem(.action(title) { WindowList.focus(window, of: app) })
                }
                if !windows.isEmpty { menu.addItem(.separator()) }
            } else {
                menu.addItem(.action(L.t("Показать окна…", "Show windows…")) { WindowList.requestAccess() })
                menu.addItem(.separator())
            }
        }

        if let url = item.url {
            let open = NSMenuItem.action(item.name) { Launcher.open(url) }
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
            menu.addItem(.separator())
            if app.isHidden {
                menu.addItem(.action(L.t("Показать", "Show")) { app.unhide() })
            } else {
                menu.addItem(.action(L.t("Скрыть", "Hide")) { app.hide() })
            }
            menu.addItem(.action(L.t("Завершить \(app.localizedName ?? "")", "Quit \(app.localizedName ?? "")")) {
                app.terminate()
            })
            // Как в Windows: «Закрыть» — самый нижний пункт и закрывает окна — то, что на кнопке, а не программу.
            // Кнопка окна — только его; кнопка группы — все её окна этого рабочего стола.
            let windows = item.window.map { [$0] } ?? closableWindows(of: app, item)
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

    private static func closableWindows(of app: NSRunningApplication, _ item: TaskItem) -> [WindowList.Window] {
        guard WindowList.isTrusted else { return [] }
        return (WindowList.windows(of: app) ?? TaskbarModel.shared.allWindows(of: item)).filter(\.isShown)
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
