import AppKit

/// Основа всех кнопок: подсветка под курсором, нажатие, щелчок, контекстное меню
/// и, если задан `dragHandler`, перетаскивание по горизонтали.
class HoverButton: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    /// Нажатие закрывает открытые «Пуск» и календарь. Кнопкам внутри них это не нужно.
    var closesFlyouts = true
    /// Получает начало, движение и конец перетаскивания; координата — x курсора в окне.
    var dragHandler: ((DragPhase, CGFloat) -> Void)?

    enum DragPhase { case began, moved, ended }

    /// Сдвиг, после которого нажатие считается перетаскиванием, а не щелчком.
    private static let dragThreshold: CGFloat = 5
    private var downX: CGFloat?
    private(set) var dragging = false

    private(set) var hovered = false { didSet { needsDisplay = true } }
    private(set) var pressed = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        downX = event.locationInWindow.x
        if closesFlyouts { Flyouts.closeAll() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragHandler, let downX else { return }
        let x = event.locationInWindow.x
        if !dragging {
            guard abs(x - downX) >= Self.dragThreshold else { return }
            dragging = true
            dragHandler(.began, downX)
        }
        dragHandler(.moved, x)
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        downX = nil
        if dragging {
            // Перетаскивание — не щелчок: программу не открываем.
            dragging = false
            dragHandler?(.ended, event.locationInWindow.x)
            return
        }
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
            ArrowCursor.reassert(over: window)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if closesFlyouts { Flyouts.closeAll() }
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        hovered = false
    }

    /// Фон кнопки по состоянию; наследники рисуют поверх свой значок или текст.
    func backgroundColor(active: Bool = false) -> NSColor? {
        if active { return hovered ? Theme.activeHover : Theme.active }
        if pressed { return Theme.pressed }
        if hovered { return Theme.hover }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if let color = backgroundColor() {
            color.setFill()
            bounds.fill()
        }
    }
}
