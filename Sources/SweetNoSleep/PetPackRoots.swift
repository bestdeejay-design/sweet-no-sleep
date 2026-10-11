import Foundation

/// Where a pack root comes from. The cases are listed in precedence order: when
/// two roots ship a pack with the same ID, the later kind wins.
enum PetPackRootKind: String, Equatable {
    /// `PetSkins` inside the running app's own bundle. The base layer.
    case bundle
    /// `Resources/PetSkins` of a source checkout. Consulted only by unbundled runs
    /// (`swift run`, a debug binary outside an `.app`), and only the nearest one.
    case repository
    /// A PetSkins folder named explicitly by `SWEET_NO_SLEEP_PACK_ROOT`.
    case override
    /// `~/Library/Application Support/SweetNoSleep/PetSkins`. Overrides everything,
    /// by design: this is how a user installs or replaces a pack.
    case user
}

struct PetPackRoot: Equatable {
    let kind: PetPackRootKind
    let url: URL
}

/// Decides which pack folders the app reads, and in what order.
///
/// The rule (issue #33):
///
/// * A launch from an `.app` bundle reads the bundle's own packs and the user
///   folder, and nothing else. Repository roots are found by walking up from the
///   build path, so they can belong to a different, stale checkout than the one
///   the bundle was built from. They must never override a shipped app.
/// * An unbundled run (`swift run`) reads the nearest `Resources/PetSkins` above
///   the source file, the executable, or the working directory, in that order.
///   Only that one root is used; ancestors are never merged.
/// * `SWEET_NO_SLEEP_PACK_ROOT=<PetSkins folder>` is the only explicit opt-in that
///   puts a repository's packs in front of a bundle. It replaces the repository
///   search entirely.
/// * The user folder always comes last and overrides everything.
enum PetPackRoots {
    static let overrideVariable = "SWEET_NO_SLEEP_PACK_ROOT"
    static let packsFolderName = "PetSkins"
    private static let maxAncestorDepth = 8

    /// Resolves the roots for one process. Pure apart from reading the file system,
    /// so the precedence can be tested without a window or a real bundle.
    static func resolve(
        bundleURL: URL,
        bundleResources: URL?,
        sourceFile: URL,
        executable: URL?,
        workingDirectory: URL,
        userDirectory: URL?,
        environment: [String: String]
    ) -> [PetPackRoot] {
        var roots: [PetPackRoot] = []

        if let bundleResources {
            roots.append(PetPackRoot(
                kind: .bundle,
                url: bundleResources.appendingPathComponent(packsFolderName, isDirectory: true)
            ))
        }

        let override = (environment[overrideVariable] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            roots.append(PetPackRoot(
                kind: .override,
                url: URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            ))
        } else if !isAppBundle(bundleURL) {
            var starts = [sourceFile.deletingLastPathComponent()]
            if let executable {
                starts.append(executable.deletingLastPathComponent())
            }
            starts.append(workingDirectory)
            if let repository = nearestRepositoryPacks(startingAt: starts) {
                roots.append(PetPackRoot(kind: .repository, url: repository))
            }
        }

        if let userDirectory {
            roots.append(PetPackRoot(kind: .user, url: userDirectory))
        }

        // Drop a root that repeats an earlier path, keeping the earlier position.
        var seen = Set<String>()
        return roots.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    /// True when the process runs from an application bundle (`Foo.app`).
    static func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    /// The nearest existing `Resources/PetSkins` above any of `starts`. The starts
    /// are tried in order, so the compiled source file wins over the executable and
    /// the working directory.
    static func nearestRepositoryPacks(startingAt starts: [URL]) -> URL? {
        for start in starts {
            var directory = start.standardizedFileURL
            for _ in 0..<maxAncestorDepth {
                let candidate = directory
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(packsFolderName, isDirectory: true)
                if isDirectory(candidate) {
                    return candidate
                }
                let parent = directory.deletingLastPathComponent()
                guard parent.path != directory.path else { break }
                directory = parent
            }
        }
        return nil
    }

    /// The folder that supplies pack `name` (for example `kot-arbuz`): the one in
    /// the last root, in precedence order, that holds a `skin.json` for it.
    static func winningFolder(named name: String, in roots: [PetPackRoot]) -> URL? {
        for root in roots.reversed() {
            let folder = root.url.appendingPathComponent(name, isDirectory: true)
            let manifest = folder.appendingPathComponent("skin.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return folder
            }
        }
        return nil
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
