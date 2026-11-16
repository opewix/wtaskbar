import AppKit

/// Переход между рабочими столами свайпом по трекпаду и клавишами (⌃← / ⌃→, ⌃1…⌃9). macOS меняет текущий стол только в конце анимации
/// перехода (около секунды), а о самом жесте сообщает сразу: событие Dock типа 30. По его концу
/// панель показывает кнопки стола назначения, не дожидаясь анимации (`Desktops.predict`).
/// Для клавиш слушаем нажатия и сверяем с системными сочетаниями Mission Control.
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
        let mask = CGEventMask(1) << 30 | CGEventMask(1) << CGEventType.keyDown.rawValue
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
        } else if type == .keyDown {
            DesktopSwipe.handleKey(event)
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

    // MARK: Клавиши

    private enum Move { case step(Int), desktop(Int) }
    private static let modifierMask: UInt64 = 0x1E0000   // Shift, Control, Option, Command
    private static var hotKeys: [(key: Int64, modifiers: UInt64, move: Move)] = []
    private static var hotKeysRead = Date.distantPast

    /// Нажатие сверяется только по коду клавиши и модификаторам; что набирают — не смотрим и не храним.
    private static func handleKey(_ event: CGEvent) {
        let modifiers = event.flags.rawValue & modifierMask
        // Без модификатора сочетаний нет; повтор при удержании столы не листает.
        guard modifiers != 0, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        if Date().timeIntervalSince(hotKeysRead) > 10 {
            hotKeys = readHotKeys()
            hotKeysRead = Date()
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard let move = hotKeys.first(where: { $0.key == key && $0.modifiers == modifiers })?.move else { return }
        DispatchQueue.main.async {
            switch move {
            case .step(let direction): TaskbarModel.shared.desktopSwiped(direction)
            case .desktop(let index): TaskbarModel.shared.desktopChosen(index)
            }
        }
    }

    /// Системные сочетания Mission Control из `com.apple.symbolichotkeys`: 79 и 81 — стол левее и правее
    /// (без записи — включены, ⌃← и ⌃→), 118… — «Переключиться на рабочий стол N» (без записи — выключены,
    /// ⌃1…⌃9). В `parameters` — символ, код клавиши, модификаторы.
    private static func readHotKeys() -> [(key: Int64, modifiers: UInt64, move: Move)] {
        let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        func hotKey(_ id: Int, defaultKey: Int64, enabledByDefault: Bool) -> (Int64, UInt64)? {
            let entry = all["\(id)"] as? [String: Any]
            let enabled = (entry?["enabled"] as? NSNumber)?.boolValue ?? enabledByDefault
            guard enabled else { return nil }
            let parameters = ((entry?["value"] as? [String: Any])?["parameters"] as? [NSNumber]) ?? []
            guard parameters.count >= 3 else { return (defaultKey, 0x40000) }
            return (parameters[1].int64Value, parameters[2].uint64Value & modifierMask)
        }
        var result: [(key: Int64, modifiers: UInt64, move: Move)] = []
        if let left = hotKey(79, defaultKey: 123, enabledByDefault: true) { result.append((left.0, left.1, .step(-1))) }
        if let right = hotKey(81, defaultKey: 124, enabledByDefault: true) { result.append((right.0, right.1, .step(1))) }
        let digits: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (index, key) in digits.enumerated() {
            if let chosen = hotKey(118 + index, defaultKey: key, enabledByDefault: false) {
                result.append((chosen.0, chosen.1, .desktop(index)))
            }
        }
        return result
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
