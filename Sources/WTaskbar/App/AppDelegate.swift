import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bars: [TaskbarPanel] = []
    private var barsOnAllDisplays: Bool?
    private var barsPinned: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = Snapshot.directory {
            Snapshot.run(into: directory)
            return
        }
        TaskbarModel.shared.start()
        AppCatalog.shared.refresh()
        Flyouts.trackMenus()
        rebuildBars()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildBars),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.changed, object: nil)

        if !Settings.hideDock && !Settings.askedAboutDock {
            askAboutDock()
        }
        settingsChanged()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Без панели задач Mac остался бы без Dock — возвращаем его.
        DockControl.restore()
    }

    /// Настройки, которые меняют не вид панели, а систему: Dock, горячая клавиша, число панелей.
    @objc private func settingsChanged() {
        if Settings.hideDock { DockControl.hide() } else { DockControl.restore() }
        // ⌃Esc открывает «Пуск», как в Windows.
        HotKey.setEnabled(Settings.startHotKey) { StartMenu.shared.toggle(on: NSScreen.underMouse) }
        if barsOnAllDisplays != Settings.allDisplays || barsPinned != Settings.pinToAllSpaces { rebuildBars() }
    }

    @objc private func rebuildBars() {
        barsOnAllDisplays = Settings.allDisplays
        barsPinned = Settings.pinToAllSpaces
        bars.forEach { $0.orderOut(nil) }
        let screens = Settings.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        bars = screens.map { TaskbarPanel(screen: $0) }
        bars.forEach {
            $0.orderFrontRegardless()
            SpacePin.pin($0)
        }
    }

    private func askAboutDock() {
        Settings.askedAboutDock = true
        let alert = NSAlert()
        alert.messageText = L.t("Скрыть Dock?", "Hide the Dock?")
        alert.informativeText = L.t(
            "WTaskbar заменяет Dock. Его можно вернуть в любой момент: щёлкните правой кнопкой по панели задач и снимите флажок «Скрывать Dock».",
            "WTaskbar replaces the Dock. You can bring it back at any time: right-click the taskbar and uncheck “Hide the Dock”.")
        alert.addButton(withTitle: L.t("Скрыть", "Hide"))
        alert.addButton(withTitle: L.t("Оставить", "Keep"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Settings.hideDock = true
        }
    }
}

extension NSScreen {
    /// Экран под курсором — туда и открываем «Пуск» по горячей клавише.
    static var underMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main
    }
}
