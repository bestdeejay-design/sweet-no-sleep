import Foundation

/// Headless report of the pack roots this process resolves, read by
/// `Scripts/verify-pack-roots.py`. Like the localization report it runs before any
/// window exists, and it exits without starting the app:
///
///     SweetNoSleep --pack-roots
///
/// Output is tab-separated, one record per line:
///
///     root<TAB><kind><TAB><path><TAB><present|absent>
///     pack<TAB><id><TAB><folder that renders it>
enum PackRootSelfCheck {
    static let flag = "--pack-roots"

    /// Prints the report when `flag` is present on the command line.
    ///
    /// - Returns: The process exit status, or `nil` when the app should launch normally.
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains(flag) else { return nil }

        let roots = PetSkinLibrary.packRoots()
        for root in roots {
            let state = PetPackRoots.isDirectory(root.url) ? "present" : "absent"
            print(["root", root.kind.rawValue, root.url.path, state].joined(separator: "\t"))
        }
        for definition in PetSkinLibrary.load(roots: roots) {
            let folder = definition.packURL?.path ?? "-"
            print(["pack", definition.id, folder].joined(separator: "\t"))
        }
        return 0
    }
}
