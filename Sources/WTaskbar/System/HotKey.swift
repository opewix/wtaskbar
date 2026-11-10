import Carbon

/// Глобальная горячая клавиша ⌃Esc для «Пуска». Carbon-API не требует разрешений.
enum HotKey {
    private static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?
    private static var installed = false

    static func setEnabled(_ enabled: Bool, _ action: @escaping () -> Void) {
        handler = action
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.handler?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        if enabled, ref == nil {
            let id = EventHotKeyID(signature: OSType(0x5754_4B42), id: 1) // 'WTKB'
            RegisterEventHotKey(UInt32(kVK_Escape), UInt32(controlKey), id, GetApplicationEventTarget(), 0, &ref)
        } else if !enabled, let current = ref {
            UnregisterEventHotKey(current)
            ref = nil
        }
    }
}
