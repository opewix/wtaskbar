import AppKit

/// Окна над панелью задач: «Пуск» и календарь. Открыто не больше одного.
enum Flyouts {
    /// «Пуск» или календарь открылись либо закрылись.
    static let changed = Notification.Name("WTaskbarFlyoutsChanged")

    /// Открыто контекстное меню — автоскрытая панель не прячется под ним.
    private(set) static var menuOpen = false
    private static var observers: [NSObjectProtocol] = []

    static func trackMenus() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in menuOpen = true },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in menuOpen = false },
        ]
    }

    static func closeAll() {
        StartMenu.shared.close()
        CalendarFlyout.shared.close()
    }
}

/// Панель, которая принимает клавиатуру, не делая WTaskbar активной программой:
/// активной остаётся та, в которой работал пользователь.
final class FlyoutPanel: NSPanel {
    var onResign: (() -> Void)?
    var onEscape: (() -> Void)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = Theme.darkAppearance
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Показ и скрытие панели: щелчок в любой другой программе закрывает её.
class Flyout {
    let panel: FlyoutPanel
    private var monitor: Any?
    /// Содержимое и его размер в логических точках; на экране — с учётом масштаба.
    private var content: NSView?
    private var logicalSize = NSSize.zero

    var isShown: Bool { panel.isVisible }

    init(size: NSSize, content: NSView) {
        panel = FlyoutPanel(size: size)
        setContent(content, size: size)
        panel.onResign = { [weak self] in self?.close() }
        panel.onEscape = { [weak self] in self?.close() }
    }

    /// Ставит панель над панелью задач экрана `screen`: к левому краю или к правому.
    func show(on screen: NSScreen?, alignRight: Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        let scale = Theme.scale
        var size = NSSize(width: (logicalSize.width * scale).rounded(), height: (logicalSize.height * scale).rounded())
        size.height = min(size.height, screen.frame.height - Theme.barScreenHeight - 40)
        let x = alignRight ? screen.frame.maxX - size.width : screen.frame.minX
        panel.setFrame(NSRect(x: x, y: screen.frame.minY + Theme.barScreenHeight, width: size.width, height: size.height), display: true)
        // Содержимое раскладывается в логических точках, масштаб даёт разница рамки и границ.
        if let content, let background = panel.contentView {
            content.frame = background.bounds
            content.setBoundsSize(NSSize(width: size.width / scale, height: size.height / scale))
        }
        willShow()
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: Flyouts.changed, object: nil)
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.close()
            }
        }
    }

    func close() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        didClose()
        NotificationCenter.default.post(name: Flyouts.changed, object: nil)
    }

    /// Новое содержимое — при смене темы. Под ним размытие фона: стекло Vista и Windows 10.
    func setContent(_ content: NSView, size: NSSize, cornerRadius: CGFloat = 0) {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.masksToBounds = cornerRadius > 0
        content.frame = background.bounds
        background.addSubview(content)
        panel.contentView = background
        panel.setContentSize(size)
        self.content = content
        logicalSize = size
        panel.invalidateShadow()
    }

    func willShow() {}
    func didClose() {}
}
