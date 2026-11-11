import AppKit

/// Держит окна панели неподвижными при переключении рабочих столов.
///
/// Окно с `canJoinAllSpaces` видно на всех столах, но при переключении macOS уводит его
/// вместе со старым столом и привозит с новым. Окно, которое живёт только в собственном
/// «пространстве» и ни в одном рабочем столе, не двигается и видно всегда. Это закрытый API
/// SkyLight: если функций нет, панель ведёт себя как обычное окно на всех столах.
///
/// Проверено на macOS 26: `SLSMoveWindowsToManagedSpace` такое окно не переносит, поэтому
/// окно добавляется в своё пространство и убирается из всех рабочих столов.
enum SpacePin {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias ChangeSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private struct API {
        let connection: Int32
        let create: SpaceCreate
        let setLevel: SpaceSetAbsoluteLevel
        let show: ShowSpaces
        let add: ChangeSpaces
        let remove: ChangeSpaces
        let copySpaces: CopySpaces
        let copyDisplaySpaces: CopyDisplaySpaces
    }

    private static let api: API? = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, _: T.Type) -> T? {
            dlsym(lib, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let main = load("SLSMainConnectionID", MainConnection.self),
              let create = load("SLSSpaceCreate", SpaceCreate.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
              let show = load("SLSShowSpaces", ShowSpaces.self),
              let add = load("SLSAddWindowsToSpaces", ChangeSpaces.self),
              let remove = load("SLSRemoveWindowsFromSpaces", ChangeSpaces.self),
              let copySpaces = load("SLSCopySpacesForWindows", CopySpaces.self),
              let copyDisplaySpaces = load("SLSCopyManagedDisplaySpaces", CopyDisplaySpaces.self) else { return nil }
        return API(connection: main(), create: create, setLevel: setLevel, show: show,
                   add: add, remove: remove, copySpaces: copySpaces, copyDisplaySpaces: copyDisplaySpaces)
    }()

    private static var space: UInt64 = 0

    static var isAvailable: Bool { api != nil }

    /// Открыт ли на дисплее полноэкранный стол (видео, программа во весь экран).
    /// Закреплённая панель видна и поверх него, поэтому прячется сама — как в Windows.
    static func isFullScreen(_ screen: NSScreen) -> Bool {
        guard let api, let displays = api.copyDisplaySpaces(api.connection)?.takeRetainedValue() as? [[String: Any]],
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let id = CFUUIDCreateString(nil, uuid) as String? else { return false }
        // «Main» — когда у дисплеев общие рабочие столы («Мониторы с отдельными пространствами» выключено).
        let display = displays.first { ($0["Display Identifier"] as? String) == id }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
        let current = display?["Current Space"] as? [String: Any]
        // Тип 4 — полноэкранный стол, 0 — обычный.
        return (current?["type"] as? Int) == 4
    }

    /// Переносит окно в общее для панелей пространство. Вызывать, когда окно уже на экране.
    static func pin(_ window: NSWindow) {
        guard Settings.pinToAllSpaces, let api, window.windowNumber > 0 else { return }
        let cid = api.connection
        if space == 0 {
            space = api.create(cid, 1, nil)
            guard space != 0 else { return }
            _ = api.setLevel(cid, space, 0)
            _ = api.show(cid, [NSNumber(value: space)] as CFArray)
        }
        // Иначе система снова добавит окно на каждый новый рабочий стол.
        window.collectionBehavior.remove(.canJoinAllSpaces)
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        _ = api.add(cid, windows, [NSNumber(value: space)] as CFArray)
        // 7 — все пространства окна: текущее, остальные и пользовательские.
        let desktops = (api.copySpaces(cid, 7, windows)?.takeRetainedValue() as? [NSNumber] ?? [])
            .filter { $0.uint64Value != space }
        if !desktops.isEmpty { _ = api.remove(cid, windows, desktops as CFArray) }
    }
}
