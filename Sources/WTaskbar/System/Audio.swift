import AudioToolbox
import CoreAudio
import Foundation

/// Громкость устройства вывода по умолчанию — через CoreAudio, как регулятор в строке меню macOS.
/// Любое изменение — с панели, с клавиатуры, из другой программы — рассылает `Audio.changed`.
enum Audio {
    static let changed = Notification.Name("WTaskbarAudioChanged")

    struct Device: Equatable {
        let id: AudioObjectID
        let name: String
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let queue = DispatchQueue.main
    /// Устройство, на изменения которого подписаны: при смене устройства подписку переносим.
    private static var watched: AudioObjectID?

    // MARK: Устройство

    static var defaultDevice: AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static var current: Device? {
        defaultDevice.map { Device(id: $0, name: name(of: $0)) }
    }

    /// Устройства, у которых есть выход: колонки, наушники, AirPlay, HDMI.
    static var outputDevices: [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutput).map { Device(id: $0, name: name(of: $0)) }
    }

    static func select(_ device: Device) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = device.id
        AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "" }
        return name.takeRetainedValue() as String
    }

    // MARK: Громкость

    /// Общая громкость — та же, что у регулятора macOS: свойство «виртуальной главной громкости».
    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Можно ли менять громкость: у HDMI и части USB-устройств её нет.
    static var hasVolume: Bool {
        guard let id = defaultDevice else { return false }
        var address = volumeAddress()
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(id, &address)
            && AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    /// Громкость 0…1.
    static var volume: Float {
        get {
            guard let id = defaultDevice else { return 0 }
            var address = volumeAddress()
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
            return value
        }
        set {
            guard let id = defaultDevice else { return }
            var address = volumeAddress()
            var value = Float32(min(max(newValue, 0), 1))
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            // Как в Windows: тронул регулятор — звук включается.
            if isMuted && value > 0 { isMuted = false }
        }
    }

    static var isMuted: Bool {
        get {
            guard let id = defaultDevice else { return false }
            var address = muteAddress()
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
            return value != 0
        }
        set {
            guard let id = defaultDevice else { return }
            var address = muteAddress()
            var value = UInt32(newValue ? 1 : 0)
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }

    /// Громкость в процентах, как подпись регулятора Windows.
    static var percent: Int { Int((volume * 100).rounded()) }

    // MARK: Слежение

    /// Подписка на смену устройства, громкости и «без звука». Вызывается один раз при запуске.
    static func startWatching() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(system, &address, queue) { _, _ in
            watchDevice()
            post()
        }
        var devices = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(system, &devices, queue) { _, _ in post() }
        watchDevice()
    }

    private static let deviceListener: AudioObjectPropertyListenerBlock = { _, _ in post() }

    private static func watchDevice() {
        if let old = watched {
            var volume = volumeAddress(), mute = muteAddress()
            AudioObjectRemovePropertyListenerBlock(old, &volume, queue, deviceListener)
            AudioObjectRemovePropertyListenerBlock(old, &mute, queue, deviceListener)
        }
        watched = defaultDevice
        guard let id = watched else { return }
        var volume = volumeAddress(), mute = muteAddress()
        AudioObjectAddPropertyListenerBlock(id, &volume, queue, deviceListener)
        AudioObjectAddPropertyListenerBlock(id, &mute, queue, deviceListener)
    }

    private static func post() {
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
