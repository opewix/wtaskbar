import AppKit

/// Стрелка над панелью.
///
/// Панель не делает WTaskbar активной программой, а курсором распоряжается активная.
/// Программа, поднятая щелчком по кнопке, ставит курсор по своим окнам, не зная о панели
/// поверх них: если рядом край её окна, над панелью остаётся курсор изменения размера.
/// Поэтому панель ставит стрелку сама — и сразу, и чуть позже, когда поднятая программа
/// уже выставит свой курсор.
enum ArrowCursor {
    /// Без этого свойства соединения система не даёт фоновой программе менять курсор.
    /// Закрытый интерфейс: ищем его при запуске, нет — обходимся без него.
    static func enableInBackground() {
        typealias MainConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let handle = dlopen(nil, RTLD_NOW)
        guard let mainSym = dlsym(handle, "_CGSDefaultConnection") ?? dlsym(handle, "CGSMainConnectionID"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(mainSym, to: MainConnection.self)()
        _ = unsafeBitCast(setSym, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    /// Ставит стрелку, если курсор над окном `window`.
    static func set(over window: NSWindow?) {
        guard let window, window.isVisible, !window.ignoresMouseEvents,
              NSMouseInRect(NSEvent.mouseLocation, window.frame, false) else { return }
        NSCursor.arrow.set()
    }

    /// После щелчка по кнопке: поднятая программа ставит курсор не сразу.
    static func reassert(over window: NSWindow?) {
        set(over: window)
        for delay in [0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in set(over: window) }
        }
    }
}
