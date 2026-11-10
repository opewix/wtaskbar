import Carbon
import Foundation

/// Раскладка клавиатуры для индикатора «РУС / ENG» в области уведомлений.
enum InputSource {
    static let changed = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    struct Source {
        let ref: TISInputSource
        let id: String
        let name: String
        /// Три буквы, как в Windows 10: «РУС», «ENG».
        let label: String
        /// Две латинские буквы, как в XP и Vista: «RU», «EN».
        let code: String
    }

    static var current: Source? {
        guard let ref = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return source(ref)
    }

    /// Раскладки, между которыми переключается пользователь.
    static var enabled: [Source] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.map(source)
    }

    static func select(_ source: Source) {
        TISSelectInputSource(source.ref)
    }

    private static func source(_ ref: TISInputSource) -> Source {
        let id: String = property(ref, kTISPropertyInputSourceID) ?? ""
        let name: String = property(ref, kTISPropertyLocalizedName) ?? id
        let languages: [String] = property(ref, kTISPropertyInputSourceLanguages) ?? []
        let language = languages.first ?? "en"
        let code = Locale(identifier: language).language.languageCode?.identifier ?? language
        return Source(ref: ref, id: id, name: name, label: label(for: language), code: String(code.prefix(2)).uppercased())
    }

    /// Три буквы названия языка на нём самом: «русский» → «РУС», «English» → «ENG».
    private static func label(for language: String) -> String {
        let code = Locale(identifier: language).language.languageCode?.identifier ?? language
        let own = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return String(own.prefix(3)).uppercased()
    }

    private static func property<T>(_ ref: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }
}
