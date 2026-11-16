import AppKit

/// Свайп по трекпаду между рабочими столами. macOS меняет текущий стол только в конце анимации
/// перехода (около секунды), а о самом жесте сообщает сразу: событие Dock типа 30. По его концу
/// панель показывает кнопки стола назначения, не дожидаясь анимации (`Desktops.predict`).
///
/// Поля события — закрытые, разобраны по записи `reference/swipe-gestures-2026-11-16.txt`:
/// 110 — вид жеста (23 — свайп Dock), 123 — ось (1 — горизонтальная), 132 — фаза (1 начало,
/// 2 движение, 4 конец, 8 отмена), 124 — пройденная доля пути (плюс — к следующему столу),
/// 129 — скорость в конце.
enum DesktopSwipe {
    private static var tap: CFMachPort?
    /// Как слушаем жесты: "listen", "default" или "none" — для `-dumpWindows`.
    private(set) static var mode = "none"

    /// Нужен «Универсальный доступ»; пока его нет, вызов повторяют.
    static func startIfNeeded() {
        guard tap == nil, WindowList.isTrusted else { return }
        let mask = CGEventMask(1) << 30
        // Только слушать можно с разрешением «Мониторинг ввода»; без него — обычный перехват
        // (ему хватает «Универсального доступа»), события отдаём как есть.
        let listen = CGPreflightListenEventAccess()
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                              options: listen ? .listenOnly : .defaultTap,
                                              eventsOfInterest: mask, callback: callback, userInfo: nil) else { return }
        tap = created
        mode = listen ? "listen" : "default"
        // В своём потоке: главный бывает занят опросом окон, а жест через перехват должен пройти без задержки.
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            CFRunLoopRun()
        }
        thread.name = "DesktopSwipe"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = DesktopSwipe.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        } else if type.rawValue == 30 {
            DesktopSwipe.handle(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private static func field(_ number: UInt32) -> CGEventField { CGEventField(rawValue: number)! }

    private static func handle(_ event: CGEvent) {
        guard event.getIntegerValueField(field(110)) == 23, event.getIntegerValueField(field(123)) == 1,
              event.getIntegerValueField(field(132)) == 4 else { return }
        let progress = event.getDoubleValueField(field(124))
        let speed = event.getDoubleValueField(field(129))
        guard let direction = direction(progress: progress, speed: speed) else { return }
        DispatchQueue.main.async { TaskbarModel.shared.desktopSwiped(direction) }
    }

    /// Куда уйдёт стол после отпускания: +1 — к следующему, −1 — к предыдущему, nil — останется.
    /// Быстрый жест решает скорость (в записи 3–4,5), медленный — пройдена ли половина пути.
    /// Пороги подобраны на глаз: ошибку исправит настоящая смена стола или её отсутствие.
    static func direction(progress: Double, speed: Double) -> Int? {
        guard progress != 0 else { return nil }
        let forward = progress > 0 ? 1 : -1
        if abs(speed) >= 0.5 { return (speed > 0) == (progress > 0) ? forward : nil }
        return abs(progress) >= 0.5 ? forward : nil
    }
}
