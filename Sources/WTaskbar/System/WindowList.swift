import AppKit
import ApplicationServices

/// Окна чужих программ через Accessibility: список, положение, вывод вперёд, сворачивание.
/// Без разрешения «Универсальный доступ» ничего не возвращает.
enum WindowList {
    struct Window {
        let element: AXUIElement
        let id: Int
        let title: String
        let minimized: Bool
        /// Окно, в котором фокус у своей программы.
        let focused: Bool
        /// В координатах AppKit (начало — левый нижний угол главного экрана).
        let frame: NSRect

        /// Для сравнения: изменилось ли что-то, что видно на панели.
        var signature: String {
            "\(id)|\(title)|\(minimized)|\(focused)|\(Int(frame.midX)),\(Int(frame.midY))"
        }

        func isOn(_ screen: NSScreen) -> Bool {
            screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY))
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Показывает системный запрос и открывает нужный раздел настроек.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Разрешение, выданное прошлой сборке, macOS показывает включённым, но не применяет.
    /// Удаляем запись о WTaskbar и спрашиваем заново.
    static func resetAccess() {
        if let id = Bundle.main.bundleIdentifier {
            DockControl.run("/usr/bin/tccutil", ["reset", "Accessibility", id])
        }
        requestAccess()
    }

    /// nil — программа не ответила (занята дольше таймаута или ещё не готова). Это не «окон нет»:
    /// вызывающий оставляет прежний список, иначе кнопки на секунду теряют заголовок окна.
    /// Заголовок, который не удалось прочитать, берётся из `previous` — того же окна на прошлом опросе.
    static func windows(of app: NSRunningApplication, previous: [Window] = []) -> [Window]? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw) == .success else {
            return nil
        }
        let list = raw as? [AXUIElement] ?? []
        let focusedWindow: AXUIElement? = value(appElement, kAXFocusedWindowAttribute)
        return list.compactMap { element in
            // Обычные окна документов; палитры, всплывашки и прочее — мимо.
            let subrole: String? = value(element, kAXSubroleAttribute)
            guard subrole == kAXStandardWindowSubrole as String else { return nil }
            let id = Int(CFHash(element))
            let title: String? = value(element, kAXTitleAttribute)
            return Window(element: element,
                          id: id,
                          title: title ?? previous.first { $0.id == id }?.title ?? "",
                          minimized: value(element, kAXMinimizedAttribute) ?? false,
                          focused: focusedWindow.map { CFEqual($0, element) } ?? false,
                          frame: frame(of: element))
        }
    }

    static func focus(_ window: Window, of app: NSRunningApplication) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps])
    }

    static func minimize(_ window: Window) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func close(_ window: Window) {
        guard let button: AXUIElement = value(window.element, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    static func isStandard(_ window: AXUIElement) -> Bool {
        let subrole: String? = value(window, kAXSubroleAttribute)
        return subrole == kAXStandardWindowSubrole as String
    }

    /// Полноэкранное окно живёт на своём столе — его размер не трогаем.
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        value(window, "AXFullScreen") ?? false
    }

    static func setSize(_ window: AXUIElement, _ size: NSSize) {
        var cgSize = CGSize(width: size.width, height: size.height)
        guard let value = AXValueCreate(.cgSize, &cgSize) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    static func frame(of element: AXUIElement) -> NSRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &raw) == .success,
           let raw, CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &raw) == .success,
           let raw, CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgSize, &size)
        }
        // Accessibility считает от левого верхнего угла главного экрана, AppKit — от левого нижнего.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: origin.x, y: primaryHeight - origin.y - size.height, width: size.width, height: size.height)
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? T
    }
}
