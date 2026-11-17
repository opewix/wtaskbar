import AppKit
import ApplicationServices

/// Окна чужих программ через Accessibility: список, положение, вывод вперёд, сворачивание.
/// Без разрешения «Универсальный доступ» ничего не возвращает.
enum WindowList {
    struct Window {
        let element: AXUIElement
        /// Процесс окна: у кнопки программы окна могут быть от нескольких её экземпляров.
        let pid: pid_t
        let id: Int
        let title: String
        let minimized: Bool
        /// Окно, в котором фокус у своей программы.
        let focused: Bool
        /// В координатах AppKit (начало — левый нижний угол главного экрана).
        let frame: NSRect
        /// Номер окна WindowServer; nil — не узнать.
        let number: CGWindowID?
        /// Столы окна; пусто — не узнать.
        var desktops: [UInt64]

        /// На текущем рабочем столе. Свёрнутое окно остаётся на своём столе, как в Windows: WindowServer
        /// и для него отдаёт стол, а Accessibility — само окно с любого стола. Полноэкранные и окна,
        /// чей стол не узнать, — везде.
        var onCurrentDesktop: Bool { Desktops.contains(desktops) }

        /// Видна ли кнопка окна: в Windows 10 по умолчанию — только окна текущего рабочего стола.
        var isShown: Bool { onCurrentDesktop || !Settings.currentDesktopOnly }

        /// Для сравнения: изменилось ли что-то, что видно на панели.
        var signature: String {
            "\(id)|\(title)|\(minimized)|\(focused)|\(desktops)|\(Int(frame.midX)),\(Int(frame.midY))"
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
            guard isStandard(element) else { return nil }
            let id = Int(CFHash(element))
            let title: String? = value(element, kAXTitleAttribute)
            let number = windowNumber(element)
            return Window(element: element,
                          pid: app.processIdentifier,
                          id: id,
                          title: title ?? previous.first { $0.id == id }?.title ?? "",
                          minimized: value(element, kAXMinimizedAttribute) ?? false,
                          focused: focusedWindow.map { CFEqual($0, element) } ?? false,
                          frame: frame(of: element),
                          number: number,
                          desktops: number.map(SpacePin.desktops(ofWindow:)) ?? [])
        }
    }

    /// Окна WindowServer обычного уровня размером с окно документа — без служебных полосок и всплывашек.
    static func isDocumentSized(_ info: [String: Any]) -> Bool {
        guard (info[kCGWindowLayer as String] as? Int) == 0,
              let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else {
            return false
        }
        return bounds.width >= 150 && bounds.height >= 150
    }

    /// Окна WindowServer на всех столах: номер → столы, и столы окон каждой программы.
    /// Accessibility окон других столов не отдаёт — для неё программа там выглядит как оставшаяся
    /// без окон, — поэтому смотрим сюда. Мелочь (служебные полоски, всплывашки) не считаем.
    static func serverWindows() -> (desktops: [CGWindowID: [UInt64]], apps: [pid_t: Set<UInt64>]) {
        var desktops: [CGWindowID: [UInt64]] = [:]
        var apps: [pid_t: Set<UInt64>] = [:]
        for info in CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [] {
            guard isDocumentSized(info),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let spaces = SpacePin.desktops(ofWindow: number)
            guard !spaces.isEmpty else { continue }
            desktops[number] = spaces
            apps[pid, default: []].formUnion(spaces)
        }
        return (desktops, apps)
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// Закрытая функция Accessibility: номер окна WindowServer по элементу окна.
    private static let getWindow: GetWindow? = {
        guard let lib = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(lib, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    static func windowNumber(_ element: AXUIElement) -> CGWindowID? {
        var number: CGWindowID = 0
        guard let getWindow, getWindow(element, &number) == .success, number != 0 else { return nil }
        return number
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

    /// Нажимает в меню программы «Новое окно» (или пункт с ⌘N), не выводя её вперёд: окно
    /// откроется на текущем столе. false — такого пункта нет или программа не ответила.
    static func openNewWindow(of app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let bar: AXUIElement = value(appElement, kAXMenuBarAttribute) else { return false }
        var byTitle: AXUIElement?
        var byShortcut: AXUIElement?
        for barItem in children(bar) {
            for menu in children(barItem) {
                for item in children(menu) where value(item, kAXEnabledAttribute) ?? false {
                    let title = (value(item, kAXTitleAttribute) as String?) ?? ""
                    if byTitle == nil, isNewWindow(title) { byTitle = item }
                    let key: String? = value(item, kAXMenuItemCmdCharAttribute)
                    let modifiers: Int? = value(item, kAXMenuItemCmdModifiersAttribute)
                    if byShortcut == nil, key == "N", modifiers == 0 { byShortcut = item }
                }
            }
            if byTitle != nil { break }
        }
        guard let item = byTitle ?? byShortcut else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// «New Window», «New Finder Window», «Новое окно» — но не приватное и не инкогнито.
    private static func isNewWindow(_ title: String) -> Bool {
        let lower = title.lowercased()
        let new = (lower.contains("new") && lower.contains("window")) || (lower.contains("нов") && lower.contains("окно"))
        let privateWindow = ["private", "incognito", "приват", "инкогнито"].contains { lower.contains($0) }
        return new && !privateWindow
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) ?? []
    }

    static func minimize(_ window: Window) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func close(_ window: Window) {
        guard let button: AXUIElement = value(window.element, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Обычное окно документа. Бывает, AppKit отдаёт окно программы, которая не впереди, подролью «диалог»
    /// (так у WExplorer: свернул окно — программа ушла назад — кнопка окна пропадала с панели).
    /// Настоящий диалог не сворачивается, поэтому «диалог» с кнопкой «Свернуть» — тоже окно.
    static func isStandard(_ window: AXUIElement) -> Bool {
        let subrole: String? = value(window, kAXSubroleAttribute)
        if subrole == kAXStandardWindowSubrole as String { return true }
        guard subrole == kAXDialogSubrole as String else { return false }
        let minimize: AXUIElement? = value(window, kAXMinimizeButtonAttribute)
        return minimize != nil
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
