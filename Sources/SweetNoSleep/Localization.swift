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
        for table in candidateTables() {
            if let value = table[key], !value.isEmpty {
                return value
            }
        }
        return NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    /// Candidate tables in resolution order: the in-app override
    /// (`app.language`), the app-domain `AppleLanguages`, the canonical system
    /// list (`Locale.preferredLanguages`, resolves ru-RU → ru), the bundle's
    /// own preferred localizations, then English. Each candidate is tried with
    /// its full code (ru-RU) and its bare language code (ru), because the
    /// shipped lproj directories are bare-code.
    private static func candidateTables() -> [[String: String]] {
        var candidates: [String] = []
        if let override = UserDefaults.standard.string(forKey: "app.language"), !override.isEmpty {
            candidates.append(override)
        }
        candidates += UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
        candidates += Locale.preferredLanguages
        candidates += Bundle.module.preferredLocalizations
        candidates.append("en")

        var tables: [[String: String]] = []
        var seen = Set<String>()
        for candidate in candidates {
            for code in expansion(candidate) where !seen.contains(code) {
                seen.insert(code)
                if let table = tableForLocalization(code) {
                    tables.append(table)
                }
            }
        }
        return tables
    }

    /// "ru-RU" → ["ru-RU", "ru"]: the full code first, then the bare code.
    private static func expansion(_ code: String) -> [String] {
        let parts = code.split(separator: "-").map(String.init)
        return parts.isEmpty ? [code] : [code, parts[0]]
    }

    private static func tableForLocalization(_ language: String) -> [String: String]? {
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
        else { return nil }

        cacheLock.lock()
        cache[language] = table
        cacheLock.unlock()
        return table
    }
}
