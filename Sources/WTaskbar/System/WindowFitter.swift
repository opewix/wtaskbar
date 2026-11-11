import AppKit
import ApplicationServices

/// Развёрнутые окна не заходят под панель, как в Windows.
///
/// macOS о панели не знает: при скрытом Dock система считает свободным экран почти до низа
/// и разворачивает окна туда же. Место под стороннюю панель не зарезервировать, поэтому окно,
/// чей нижний край после изменения размера оказался в полосе панели, подрезаем снизу через
/// Accessibility. Окно, утащенное мышью ниже края экрана, не трогаем — в Windows оно тоже
/// может заходить под панель.
final class WindowFitter {
    static let shared = WindowFitter()
    private var observers: [pid_t: AXObserver] = [:]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        // Разрешение могут выдать позже — тогда и подписываемся.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.observeAll() }
        observeAll()
    }

    private func observeAll() {
        guard WindowList.isTrusted else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard WindowList.isTrusted, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observe(app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
              let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, _ in
            WindowFitter.shared.fit(element)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        // Только изменение размера и новые окна: на перемещение не реагируем,
        // иначе окно подрезалось бы прямо во время перетаскивания.
        for name in [kAXWindowResizedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(observer, appElement, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    fileprivate func fit(_ window: AXUIElement) {
        guard Settings.fitMaximized, !Settings.autoHide,
              WindowList.isStandard(window), !WindowList.isFullScreen(window) else { return }
        let frame = WindowList.frame(of: window)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }),
              Settings.allDisplays || screen == NSScreen.screens.first else { return }
        let barTop = screen.frame.minY + Theme.barScreenHeight
        // Нижний край — в полосе панели: так ложатся развёрнутые и прикреплённые к краю окна.
        guard frame.minY >= screen.frame.minY - 2, frame.minY < barTop - 1, frame.maxY > barTop + 100 else { return }
        // Верхний край остаётся на месте: Accessibility отсчитывает положение от верха.
        WindowList.setSize(window, NSSize(width: frame.width, height: frame.maxY - barTop))
    }
}
