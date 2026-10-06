import Foundation

/// Resolves user-facing copy from the English-source string catalog.
enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
