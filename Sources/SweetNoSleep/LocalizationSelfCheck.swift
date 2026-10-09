import Foundation

/// Runtime localization report used by `Scripts/verify-localizations.py`.
///
/// A table that is present and readable is not proof that it loads: the CFBundle
/// strings loader rejects formats it cannot parse and `NSLocalizedString` then
/// returns the English key without any error. So the check has to resolve real
/// strings through the real call site - `L10n.text`, i.e.
/// `NSLocalizedString(key, tableName: nil, bundle: .module, value: key)` - and
/// compare the results against the source catalog.
///
/// The report is a JSON object on stdout:
///
/// ```json
/// {"bundle": "...", "preferred": ["ru"], "keys": 240, "values": {"Settings": "<translated>"}}
/// ```
///
/// It is driven from `main.swift`, before AppKit or SwiftUI start, so it runs on
/// a headless CI runner and never touches the menu bar. The locale comes from
/// the caller as a launch argument (`-AppleLanguages "(ru)"`), which is how
/// macOS selects a language at launch; one process per locale keeps Foundation's
/// bundle cache from reusing the first locale.
///
/// Kept free of non-ASCII text on purpose: `Scripts/validate-media.py` rejects
/// Cyrillic under `Sources/` so a stray translation can never creep into code
/// (the catalog is the only place translated copy belongs).
enum LocalizationSelfCheck {
    static let flag = "--localization-report"

    /// Runs the report when `flag` is present on the command line.
    ///
    /// - Returns: The process exit status, or `nil` when the app should launch
    ///   normally.
    static func runIfRequested() -> Int32? {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return nil }
        guard let keys = catalogKeys(), !keys.isEmpty else {
            FileHandle.standardError.write(
                Data("localization report: no keys found in the bundled Localizable.xcstrings\n".utf8)
            )
            return 1
        }

        var values: [String: String] = [:]
        for key in keys {
            values[key] = L10n.text(key)
        }

        let bundlePath = Bundle.module.bundlePath
        let preferred = Bundle.module.preferredLocalizations
        var output = #"{"bundle":"\#(escaped(bundlePath))","preferred":["#
        output += preferred.map { #""\#(escaped($0))""# }.joined(separator: ",")
        output += #"],"keys":\#(keys.count),"values":{"#
        output += keys.map { #""\#(escaped($0))":"\#(escaped(values[$0] ?? ""))""# }.joined(separator: ",")
        output += "}}\n"
        FileHandle.standardOutput.write(Data(output.utf8))
        return 0
    }

    /// Every key of the catalog SwiftPM copied into the resource bundle, sorted
    /// so the report is stable between runs.
    private static func catalogKeys() -> [String]? {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let catalog = object as? [String: Any],
              let strings = catalog["strings"] as? [String: Any]
        else { return nil }
        return strings.keys.sorted()
    }

    private static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
