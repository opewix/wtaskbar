import AppKit

/// Регулятор громкости по щелчку на динамике в области уведомлений.
/// Windows 10 — полоса над часами: устройство, динамик, ползунок, проценты.
/// XP и Vista — узкое окошко над значком с вертикальным ползунком и «Выкл. звук».
final class VolumeFlyout: Flyout {
    static let shared = VolumeFlyout()
    private var view = VolumeView(frame: .zero)
    private var theme: ThemeKind?

    private init() {
        super.init(size: VolumeView.size(Settings.theme), content: view)
    }

    /// `anchorX` — середина значка на экране: классическое окошко встаёт над ним.
    func toggle(on screen: NSScreen?, anchorX: CGFloat) {
        if isShown { close(); return }
        if theme != Settings.theme {
            theme = Settings.theme
            view = VolumeView(frame: .zero)
            setContent(view, size: VolumeView.size(Settings.theme))
        }
        if Settings.theme == .win10 {
            show(on: screen, alignRight: true)
        } else {
            show(on: screen, alignRight: true, centerX: anchorX)
        }
    }

    override func willShow() {
        view.needsDisplay = true
        panel.makeFirstResponder(view)
    }
}

final class VolumeView: NSView {
    static func size(_ theme: ThemeKind) -> NSSize {
        theme == .win10 ? NSSize(width: 360, height: 104) : NSSize(width: 96, height: 214)
    }

    private var modern: Bool { Settings.theme == .win10 }
    private var dragging = false
    private var thumbHovered = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Audio.changed, object: nil)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() { needsDisplay = true }

    // MARK: Раскладка

    /// Ход ползунка: от тишины до полной громкости.
    private var track: (from: NSPoint, to: NSPoint) {
        if modern {
            let y: CGFloat = 74
            return (NSPoint(x: 64, y: y), NSPoint(x: bounds.width - 70, y: y))
        }
        let x = bounds.midX
        return (NSPoint(x: x, y: 166), NSPoint(x: x, y: 44))
    }

    private var speakerRect: NSRect { NSRect(x: 12, y: 54, width: 40, height: 40) }
    private var deviceRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: 44) }
    private var muteRect: NSRect { NSRect(x: 8, y: 180, width: bounds.width - 16, height: 24) }

    private func point(for value: Float) -> NSPoint {
        let (a, b) = track
        let t = CGFloat(value)
        return NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func value(at p: NSPoint) -> Float {
        let (a, b) = track
        let t = modern ? (p.x - a.x) / (b.x - a.x) : (p.y - a.y) / (b.y - a.y)
        return Float(min(max(t, 0), 1))
    }

    private var thumbRect: NSRect {
        let c = point(for: Audio.volume)
        return modern ? NSRect(x: c.x - 4, y: c.y - 12, width: 8, height: 24)
                      : NSRect(x: c.x - 11, y: c.y - 5, width: 22, height: 10)
    }

    /// Где хватать ползунок: полоса вокруг хода, а не только сам бегунок.
    private var grabRect: NSRect {
        let (a, b) = track
        return modern ? NSRect(x: a.x - 8, y: a.y - 16, width: b.x - a.x + 16, height: 32)
                      : NSRect(x: a.x - 18, y: b.y - 10, width: 36, height: a.y - b.y + 20)
    }

    // MARK: Отрисовка

    override func draw(_ dirtyRect: NSRect) {
        let palette = Theme.skin.calendar
        palette.background.setFill()
        bounds.fill()
        let enabled = Audio.hasVolume
        let volume = Audio.volume
        let muted = Audio.isMuted

        if modern {
            let name = Audio.current?.name ?? L.t("Нет устройства вывода", "No output device")
            text(name, in: NSRect(x: 20, y: 14, width: bounds.width - 60, height: 18), size: 13, color: palette.text)
            text("⌃", in: NSRect(x: bounds.width - 34, y: 14, width: 16, height: 18), size: 13, color: palette.text)
            Glyphs.speaker(in: speakerRect, color: palette.text, level: volume, muted: muted, size: 20)
            text("\(Audio.percent)", in: NSRect(x: bounds.width - 62, y: 60, width: 50, height: 28),
                 size: 22, weight: .light, color: palette.text, centered: true)
        } else {
            text(L.t("Громкость", "Volume"), in: NSRect(x: 0, y: 12, width: bounds.width, height: 18),
                 size: 12, color: palette.text, centered: true)
            drawCheckbox(checked: muted, palette: palette)
        }

        // Ход: пройденная часть — акцентом, оставшаяся — блёкло.
        let (a, b) = track
        let c = point(for: volume)
        let rest = NSBezierPath()
        rest.move(to: c)
        rest.line(to: b)
        rest.lineWidth = 2
        palette.dim.setStroke()
        rest.stroke()
        let done = NSBezierPath()
        done.move(to: a)
        done.line(to: c)
        done.lineWidth = 2
        (enabled ? palette.accent : palette.dim).setStroke()
        done.stroke()

        let thumb = NSBezierPath(roundedRect: thumbRect, xRadius: modern ? 4 : 2, yRadius: modern ? 4 : 2)
        let thumbColor: NSColor = !enabled ? palette.dim : (thumbHovered || dragging) ? palette.text : palette.accent
        thumbColor.setFill()
        thumb.fill()
        if !modern {
            palette.text.withAlphaComponent(0.5).setStroke()
            thumb.lineWidth = 1
            thumb.stroke()
        }
    }

    private func drawCheckbox(checked: Bool, palette: CalendarPalette) {
        let box = NSRect(x: muteRect.minX + 4, y: muteRect.midY - 6, width: 12, height: 12)
        palette.text.withAlphaComponent(0.7).setStroke()
        NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()
        if checked {
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 2.5, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + 5, y: box.maxY - 2.5))
            tick.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 2.5))
            tick.lineWidth = 1.5
            palette.text.setStroke()
            tick.stroke()
        }
        text(L.t("Выкл. звук", "Mute"), in: NSRect(x: box.maxX + 6, y: muteRect.minY + 4, width: muteRect.width - 22, height: 16),
             size: 11, color: palette.text)
    }

    private func text(_ string: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, centered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                    .foregroundColor: color, .paragraphStyle: style]
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    // MARK: Мышь и клавиатура

    override func mouseMoved(with event: NSEvent) {
        let hovered = thumbRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        if hovered != thumbHovered {
            thumbHovered = hovered
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        thumbHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if Audio.hasVolume && grabRect.contains(p) {
            dragging = true
            Audio.volume = value(at: p)
        } else if modern && speakerRect.contains(p) || !modern && muteRect.contains(p) {
            Audio.isMuted.toggle()
        } else if modern && deviceRect.contains(p) {
            deviceMenu().popUp(positioning: nil, at: NSPoint(x: 20, y: deviceRect.maxY), in: self)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        Audio.volume = value(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        VolumeView.nudge(by: event)
    }

    override func keyDown(with event: NSEvent) {
        let step: Float
        switch Int(event.keyCode) {
        case 123, 125: step = -0.02           // ← ↓
        case 124, 126: step = 0.02            // → ↑
        case 121: step = -0.1                 // Page Down
        case 116: step = 0.1                  // Page Up
        case 49: Audio.isMuted.toggle(); return // пробел
        default: super.keyDown(with: event); return
        }
        Audio.volume += step
    }

    /// Колёсико над регулятором или над значком: шаг 2 %, как в Windows.
    static func nudge(by event: NSEvent) {
        guard Audio.hasVolume else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 40 : event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return }
        Audio.volume += Float(delta) * 0.02
    }

    private func deviceMenu() -> NSMenu {
        let menu = NSMenu.themed()
        let current = Audio.defaultDevice
        for device in Audio.outputDevices {
            menu.addItem(.action(device.name, checked: device.id == current) { Audio.select(device) })
        }
        return menu
    }

    /// Меню значка: устройства вывода и параметры звука macOS.
    static func trayMenu() -> NSMenu {
        let menu = NSMenu.themed()
        let current = Audio.defaultDevice
        for device in Audio.outputDevices {
            menu.addItem(.action(device.name, checked: device.id == current) { Audio.select(device) })
        }
        menu.addItem(.separator())
        menu.addItem(.action(L.t("Выключить звук", "Mute"), checked: Audio.isMuted) { Audio.isMuted.toggle() })
        menu.addItem(.action(L.t("Параметры звука", "Sound settings")) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        })
        return menu
    }
}
