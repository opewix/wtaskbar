import AppKit

/// Календарь по щелчку на часах: крупное время, дата и сетка месяца.
final class CalendarFlyout: Flyout {
    static let shared = CalendarFlyout()
    private let calendarView: CalendarView
    private var timer: Timer?

    private init() {
        let view = CalendarView()
        calendarView = view
        super.init(size: NSSize(width: 360, height: 430), content: view)
    }

    func toggle(on screen: NSScreen?) {
        if isShown { close() } else { show(on: screen, alignRight: true) }
    }

    override func willShow() {
        calendarView.month = Date()
        calendarView.needsDisplay = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.calendarView.needsDisplay = true
        }
    }

    override func didClose() {
        timer?.invalidate()
        timer = nil
    }
}

final class CalendarView: NSView {
    /// Любой день показываемого месяца.
    var month = Date()

    private let calendar = Calendar.current
    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    private let monthFormatter = DateFormatter()
    private static let cell = NSSize(width: 46, height: 40)
    private static let gridTop: CGFloat = 170

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        timeFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmmss", options: 0, locale: .current)
        dateFormatter.dateStyle = .full
        monthFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "LLLLyyyy", options: 0, locale: .current)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var gridLeft: CGFloat { (bounds.width - Self.cell.width * 7) / 2 }

    override func draw(_ dirtyRect: NSRect) {
        let palette = Theme.skin.calendar
        palette.background.setFill()
        bounds.fill()
        let now = Date()

        text(timeFormatter.string(from: now), at: NSPoint(x: 24, y: 18), size: 40, weight: .light, color: palette.text)
        text(dateFormatter.string(from: now), at: NSPoint(x: 24, y: 72), size: 13, color: palette.date)

        palette.separator.setFill()
        NSRect(x: 0, y: 104, width: bounds.width, height: 1).fill()

        // Заголовок месяца и стрелки.
        let title = monthFormatter.string(from: month)
        text(title.prefix(1).uppercased() + title.dropFirst(), at: NSPoint(x: 24, y: 120), size: 14, weight: .semibold, color: palette.text)
        text("▲", at: NSPoint(x: bounds.width - 70, y: 121), size: 11, color: palette.text)
        text("▼", at: NSPoint(x: bounds.width - 40, y: 121), size: 11, color: palette.text)

        // Дни недели — начиная с первого дня недели в настройках системы.
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        for column in 0..<7 {
            let symbol = String(symbols[(first + column) % 7].prefix(2))
            centered(symbol, in: cellRect(column: column, row: -1), size: 12, color: palette.text)
        }

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return }
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let currentMonth = calendar.component(.month, from: monthStart)
        for index in 0..<42 {
            guard let day = calendar.date(byAdding: .day, value: index - offset, to: monthStart) else { continue }
            let rect = cellRect(column: index % 7, row: index / 7)
            let inMonth = calendar.component(.month, from: day) == currentMonth
            if calendar.isDateInToday(day) {
                palette.accent.setFill()
                rect.insetBy(dx: 1, dy: 1).fill()
            }
            let today = calendar.isDateInToday(day)
            centered("\(calendar.component(.day, from: day))", in: rect, size: 13,
                     color: today ? .white : inMonth ? palette.text : palette.dim)
        }
    }

    private func cellRect(column: Int, row: Int) -> NSRect {
        NSRect(x: gridLeft + CGFloat(column) * Self.cell.width,
               y: Self.gridTop + CGFloat(row) * Self.cell.height + (row < 0 ? 12 : 0),
               width: Self.cell.width, height: Self.cell.height)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.y > 110, p.y < 150 else { return }
        if p.x > bounds.width - 80 && p.x < bounds.width - 52 { shiftMonth(-1) }
        if p.x > bounds.width - 50 && p.x < bounds.width - 20 { shiftMonth(1) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 2 else { return }
        shiftMonth(event.scrollingDeltaY > 0 ? -1 : 1)
    }

    private func shiftMonth(_ delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
        needsDisplay = true
    }

    private func text(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        string.draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    private func centered(_ string: String, in rect: NSRect, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
        let s = string.size(withAttributes: attrs)
        string.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: attrs)
    }
}
