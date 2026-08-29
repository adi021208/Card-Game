import Foundation

extension String {
    /// Looks up a key that is only known at runtime.
    ///
    /// `String(localized:defaultValue:)` wants a `StaticString` for the key,
    /// which a key computed at runtime can never be — and the engine hands
    /// every one of its keys out as a plain `String`, so all of them come
    /// through here. Looking a key up on its own returns the key itself when
    /// the catalogue has no entry, and that is the hook the fallback hangs on.
    static func deck(_ key: String, or fallback: @autoclosure () -> String) -> String {
        let looked = String(localized: String.LocalizationValue(key))
        return looked == key ? fallback() : looked
    }
}
