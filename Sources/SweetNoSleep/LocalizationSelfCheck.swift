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

        // One process per locale. The volatile argument domain is how a process
        // overrides `AppleLanguages` for itself: it is what CFBundle reads when
        // it picks a bundle's preferred localization, and it writes nothing to
        // the user's defaults.
        let locale = value(of: "--locale", in: arguments)
        if let locale {
            UserDefaults.standard.setVolatileDomain(
                ["AppleLanguages": [locale]],
                forName: UserDefaults.argumentDomain
            )
        }

        guard let keys = catalogKeys(), !keys.isEmpty else {
            fail("no keys found in the bundled Localizable.xcstrings")
            return 1
        }

        var values: [String: String] = [:]
        for key in keys {
            values[key] = L10n.text(key)
        }

        let bundle = Bundle.module
        var fields: [(String, String)] = [
            ("bundle", bundle.bundlePath),
            ("locale", locale ?? ""),
            ("preferred", bundle.preferredLocalizations.joined(separator: ",")),
            ("available", bundle.localizations.joined(separator: ",")),
            ("development", bundle.developmentLocalization ?? ""),
            ("keys", String(keys.count)),
            // Where `Bundle.module` could have pointed instead: the generated
            // accessor takes the first candidate that exists, so a stale copy
            // in the build directory can win over the app's.
            ("mainBundle", Bundle.main.bundlePath),
            ("mainResources", Bundle.main.resourceURL?.path ?? ""),
            ("moduleResources", Bundle(for: SelfCheckToken.self).resourceURL?.path ?? ""),
        ]
        if let locale {
            fields.append((
                "table",
                bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale) ?? ""
            ))
            // `NSDictionary` uses the property-list parser, not the CFBundle
            // strings loader, so a non-zero count here with English values in
            // the report means the file is fine and the loader rejected it.
            if let table = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: locale),
               let parsed = NSDictionary(contentsOf: table)
            {
                fields.append(("dictionary", String(parsed.count)))
            } else {
                fields.append(("dictionary", "0"))
            }
        }

        var output = "{" + fields.map { #""\#(escaped($0.0))":"\#(escaped($0.1))""# }.joined(separator: ",")
        output += #","values":{"#
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

    private static func value(of option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Anchor class for `Bundle(for:)`, the same trick SwiftPM uses to find
    /// the resource bundle from inside the module.
    private final class SelfCheckToken {}

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("localization report: \(message)\n".utf8))
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
