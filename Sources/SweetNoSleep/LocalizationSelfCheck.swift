import Foundation

/// Runtime localization report used by `Scripts/verify-localizations.py`.
///
/// A table that is present and readable is not proof that it loads: the CFBundle
/// strings loader rejects formats it cannot parse, and `NSLocalizedString` then
/// returns the English key without reporting anything. So the check resolves
/// real strings through the real call - `NSLocalizedString(key, tableName: nil,
/// bundle:, value:, comment:)` - and the script compares them with the catalog.
///
/// Two bundles are reported on:
///
/// * `Bundle.module`, the accessor the app itself uses. The report says whether
///   every locale is discovered there and whether its table resolves and parses.
/// * an optional `--bundle <path>`: a scratch bundle the script builds per
///   locale, carrying only that locale and declaring it as its development
///   region. CFBundle has no choice there, so the lookup is deterministic and
///   does not depend on the machine's language list - which is what makes it
///   usable as a CI gate. The file it reads is a byte copy of the shipped one.
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

        // Best effort: publish the language list for this process. CFBundle does
        // not always pick this up (it can read a different preferences domain
        // than NSUserDefaults), which is why the value comparison runs against
        // the scratch bundle instead of depending on it.
        if let locale = value(of: "--locale", in: arguments) {
            UserDefaults.standard.setVolatileDomain(
                ["AppleLanguages": [locale]],
                forName: UserDefaults.argumentDomain
            )
        }

        let bundle: Bundle
        if let path = value(of: "--bundle", in: arguments) {
            guard let scratch = Bundle(path: path) else {
                fail("could not open the scratch bundle at \(path)")
                return 1
            }
            bundle = scratch
        } else {
            bundle = .module
        }
        let locale = value(of: "--locale", in: arguments)

        // Keys always come from the catalog SwiftPM copied into the app's own
        // resource bundle, so the scratch bundle only has to carry the table.
        guard let keys = Bundle.module.catalogKeys(), !keys.isEmpty else {
            fail("no keys found in the bundled Localizable.xcstrings")
            return 1
        }

        var values: [String: String] = [:]
        for key in keys {
            // The exact call `L10n.text` makes, with the bundle under test.
            values[key] = NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
        }

        var fields: [(String, String)] = [
            ("bundle", bundle.bundlePath),
            ("locale", locale ?? ""),
            ("preferred", bundle.preferredLocalizations.joined(separator: ",")),
            ("available", bundle.localizations.joined(separator: ",")),
            ("development", bundle.developmentLocalization ?? ""),
            ("keys", String(keys.count)),
        ]
        if let locale {
            fields.append((
                "table",
                bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale) ?? ""
            ))
            // `NSDictionary` uses the property-list parser, not the CFBundle
            // strings loader, so a non-zero count next to English values in the
            // report means the file is readable and the loader rejected it.
            fields.append(("dictionary", String(bundle.tableEntryCount(forLocalization: locale))))
        }
        if bundle !== Bundle.module {
            let module = Bundle.module
            fields.append(("modulePath", module.bundlePath))
            fields.append(("moduleAvailable", module.localizations.joined(separator: ",")))
            fields.append(("moduleDevelopment", module.developmentLocalization ?? ""))
            if let locale {
                fields.append((
                    "moduleTable",
                    module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale) ?? ""
                ))
                fields.append(("moduleDictionary", String(module.tableEntryCount(forLocalization: locale))))
            }
        }

        var output = "{" + fields.map { #""\#(escaped($0.0))":"\#(escaped($0.1))""# }.joined(separator: ",")
        output += #","values":{"#
        output += keys.map { #""\#(escaped($0))":"\#(escaped(values[$0] ?? ""))""# }.joined(separator: ",")
        output += "}}\n"
        FileHandle.standardOutput.write(Data(output.utf8))
        return 0
    }

    private static func value(of option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

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

extension Bundle {
    /// Every key of a `Localizable.xcstrings` catalog copied into the bundle,
    /// sorted so reports are stable between runs.
    func catalogKeys() -> [String]? {
        guard let url = url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let catalog = object as? [String: Any],
              let strings = catalog["strings"] as? [String: Any]
        else { return nil }
        return strings.keys.sorted()
    }

    /// How many entries the property-list parser finds in a compiled table.
    func tableEntryCount(forLocalization locale: String) -> Int {
        guard let url = url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: locale),
              let table = NSDictionary(contentsOf: url)
        else { return 0 }
        return table.count
    }
}
