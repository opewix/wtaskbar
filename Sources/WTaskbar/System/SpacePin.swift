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
        let current = display(of: screen)?["Current Space"] as? [String: Any]
        // Тип 4 — полноэкранный стол, 0 — обычный.
        return (current?["type"] as? Int) == 4
    }

    /// Запись дисплея в списке столов WindowServer.
    private static func display(of screen: NSScreen) -> [String: Any]? {
        guard let api, let displays = api.copyDisplaySpaces(api.connection)?.takeRetainedValue() as? [[String: Any]],
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let id = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        // «Main» — когда у дисплеев общие рабочие столы («Мониторы с отдельными пространствами» выключено).
        return displays.first { ($0["Display Identifier"] as? String) == id }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
    }

    /// Столы дисплея по порядку, как в Mission Control (вместе с полноэкранными), открытый сейчас
    /// и отдельно обычные рабочие столы — «Рабочий стол 1, 2…».
    static func order(of screen: NSScreen) -> (spaces: [UInt64], current: UInt64, desktops: [UInt64])? {
        guard let display = display(of: screen),
              let current = (display["Current Space"] as? [String: Any]).flatMap(spaceID) else { return nil }
        let list = display["Spaces"] as? [[String: Any]] ?? []
        return (list.compactMap(spaceID), current, list.filter { ($0["type"] as? Int) != 4 }.compactMap(spaceID))
    }

    /// Столы каждого дисплея: открытый сейчас и все его рабочие столы; плюс все полноэкранные.
    /// nil — API нет.
    static func layout() -> (displays: [(current: UInt64?, spaces: Set<UInt64>)], fullScreen: Set<UInt64>)? {
        guard let api, let list = api.copyDisplaySpaces(api.connection)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        var displays: [(current: UInt64?, spaces: Set<UInt64>)] = []
        var fullScreen = Set<UInt64>()
        for display in list {
            var spaces = Set<UInt64>()
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = spaceID(space) else { continue }
                // Тип 4 — полноэкранный стол, 0 — обычный.
                if (space["type"] as? Int) == 4 { fullScreen.insert(id) } else { spaces.insert(id) }
            }
            displays.append(((display["Current Space"] as? [String: Any]).flatMap(spaceID), spaces))
        }
        return (displays, fullScreen)
    }

    /// На каких столах окно (номер окна WindowServer).
    static func desktops(ofWindow number: CGWindowID) -> [UInt64] {
        guard let api else { return [] }
        let windows = [NSNumber(value: number)] as CFArray
        return (api.copySpaces(api.connection, 7, windows)?.takeRetainedValue() as? [NSNumber] ?? []).map(\.uint64Value)
    }

    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        (space["id64"] as? NSNumber)?.uint64Value ?? (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
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

/// Какие столы панель считает текущими. macOS меняет текущий стол только в конце анимации
/// перехода (около секунды), поэтому после свайпа панель сама считает текущим стол назначения
/// (`predict`), пока macOS его не подтвердит.
enum Desktops {
    /// Текущие столы по macOS.
    private(set) static var actual = Set<UInt64>()
    private(set) static var fullScreen = Set<UInt64>()
    /// Упреждение: на дисплее со столами `display` текущим считаем `target`.
    private static var predicted: (display: Set<UInt64>, target: UInt64, at: Date)?

    /// Стол, куда едем, пока macOS не подтвердила переход.
    static var predictedTarget: UInt64? { predicted?.target }

    static var current: Set<UInt64> {
        guard let predicted else { return actual }
        return actual.subtracting(predicted.display).union([predicted.target])
    }

    /// Свайп на дисплее под курсором ушёл к соседнему столу: +1 — следующий, −1 — предыдущий.
    /// false — соседа нет (край) или столы не узнать.
    static func predict(_ direction: Int) -> Bool {
        guard let order = orderUnderCursor() else { return false }
        // Второй свайп до конца первой анимации идёт от стола, куда уже едем.
        var from = order.current
        if let predicted, order.spaces.contains(predicted.target) { from = predicted.target }
        guard let index = order.spaces.firstIndex(of: from), order.spaces.indices.contains(index + direction) else { return false }
        predicted = (Set(order.spaces), order.spaces[index + direction], Date())
        return true
    }

    /// Клавишами выбран рабочий стол по номеру (с нуля) на дисплее под курсором.
    /// false — такого стола нет или он уже открыт.
    static func predict(desktop index: Int) -> Bool {
        guard let order = orderUnderCursor(), order.desktops.indices.contains(index) else { return false }
        let target = order.desktops[index]
        // Уже едем туда или уже там.
        guard target != (predicted?.target ?? order.current) else { return false }
        predicted = (Set(order.spaces), target, Date())
        return true
    }

    private static func orderUnderCursor() -> (spaces: [UInt64], current: UInt64, desktops: [UInt64])? {
        let mouse = NSEvent.mouseLocation
        return (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main).flatMap(SpacePin.order)
    }

    /// Упреждение не подтвердилось за время анимации с запасом — стол остался прежним.
    /// true — упреждение снято.
    static func expirePrediction(after seconds: TimeInterval) -> Bool {
        guard let predicted, Date().timeIntervalSince(predicted.at) >= seconds else { return false }
        self.predicted = nil
        return true
    }

    /// Окно на текущем столе. Стол не узнать или API нет — считаем, что здесь. Полноэкранные окна
    /// живут на своём столе — их, как развёрнутые, показываем везде.
    static func contains(_ spaces: [UInt64]) -> Bool {
        spaces.isEmpty || current.isEmpty || spaces.contains { current.contains($0) || fullScreen.contains($0) }
    }

    /// true — набор текущих столов изменился.
    @discardableResult
    static func update() -> Bool {
        guard let layout = SpacePin.layout() else { return false }
        let fresh = Set(layout.displays.compactMap(\.current))
        // macOS пришла на предсказанный стол — упреждение больше не нужно.
        if let predicted, fresh.contains(predicted.target) { self.predicted = nil }
        guard fresh != actual || layout.fullScreen != fullScreen else { return false }
        actual = fresh
        fullScreen = layout.fullScreen
        return true
    }
}
