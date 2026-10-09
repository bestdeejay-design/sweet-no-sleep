import Foundation

/// Resolves user-facing copy from the English-source string catalog.
///
/// `NSLocalizedString` through `Bundle.module` silently falls back to English
/// when CFBundle's strings loader rejects the compiled table representation
/// (observed with the OpenStep/UTF-16 tables `compile-localizations.py`
/// ships) or when the per-app language list does not reach CFBundle's
/// preference domain. The direct-table path below reads the same
/// `Localizable.strings` with `NSDictionary`, which is proven to parse them,
/// and is tried first; the standard lookup stays as the fallback.
enum L10n {
    private static let cacheLock = NSLock()
    private static var cache: [String: [String: String]] = [:]

    static func text(_ key: String) -> String {
        if let table = currentTable(), let value = table[key], !value.isEmpty {
            return value
        }
        return NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    /// The first localization whose table exists and parses, in the order the
    /// user (then the bundle) prefers. Results are cached per language code.
    private static func currentTable() -> [String: String]? {
        var candidates = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
        candidates.append(contentsOf: Bundle.module.preferredLocalizations)
        candidates.append("en")

        for language in candidates {
            guard !language.isEmpty else { continue }
            cacheLock.lock()
            if let cached = cache[language] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
            guard
                let path = Bundle.module.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                ),
                let table = NSDictionary(contentsOfFile: path) as? [String: String],
                !table.isEmpty
            else { continue }

            cacheLock.lock()
            cache[language] = table
            cacheLock.unlock()
            return table
        }
        return nil
    }
}
