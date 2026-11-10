import AppKit

/// Окно панели задач вдоль нижнего края экрана, на уровне Dock, на всех рабочих столах.
/// Щелчок по нему не делает WTaskbar активной программой — иначе нельзя понять,
/// какую программу «свернуть» повторным щелчком.
final class TaskbarPanel: NSPanel {
    private let targetScreen: NSScreen
    /// Для автоскрытия: панель выдвинута.
    private var revealed = true
    private var leftAt: Date?
    private var autoHideTimer: Timer?

    init(screen: NSScreen) {
        targetScreen = screen
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        appearance = Theme.darkAppearance

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let bar = TaskbarView(screen: screen)
        bar.autoresizingMask = [.width, .height]
        blur.addSubview(bar)
        contentView = blur
        applySettings()
        bar.frame = blur.bounds

        NotificationCenter.default.addObserver(self, selector: #selector(applySettings), name: Settings.changed, object: nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Автоскрытая панель уходит за край экрана — не даём системе вернуть её обратно.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    @objc private func applySettings() {
        if Settings.autoHide {
            if autoHideTimer == nil {
                revealed = false
                autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.trackMouse() }
            }
        } else {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
            revealed = true
        }
        updateFrame(animated: false)
    }

    private func updateFrame(animated: Bool) {
        let screen = targetScreen.frame
        let height = Theme.barScreenHeight
        var frame = NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: height)
        if !revealed { frame.origin.y -= height - Theme.hiddenBarSliver }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }

    /// Автоскрытие как в Windows: выезжает, когда курсор у нижнего края, прячется, когда ушёл,
    /// но не пока открыт «Пуск», календарь или меню.
    private func trackMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = targetScreen.frame
        let zone = revealed ? Theme.barScreenHeight : Theme.hiddenBarSliver + 1
        let inside = NSMouseInRect(mouse, screen, false) && mouse.y <= screen.minY + zone
        let busy = StartMenu.shared.isShown || CalendarFlyout.shared.isShown || Flyouts.menuOpen

        if inside || busy {
            leftAt = nil
            if !revealed {
                revealed = true
                updateFrame(animated: true)
            }
        } else if revealed {
            // Небольшая задержка, чтобы панель не дёргалась от случайного движения.
            if let leftAt {
                if Date().timeIntervalSince(leftAt) > 0.6 {
                    revealed = false
                    self.leftAt = nil
                    updateFrame(animated: true)
                }
            } else {
                leftAt = Date()
            }
        }
    }
}
