import Foundation

/// Headless test of the pack-root precedence (issue #33).
///
/// It builds the layout that broke the maintainer's Mac: an app bundle written to
/// `dist/` inside a checkout whose `Resources/PetSkins` still holds the v1 art, with
/// the build path and the working directory both inside that checkout. Then it
/// checks which pack folder each launch shape renders. The "baked" bytes are the
/// ones inside the bundle; a shipped launch must render exactly those.
@main
struct PackRootsTest {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("ok   \(label)")
        } else {
            print("FAIL \(label)")
            failures += 1
        }
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A pack folder whose `head.png` carries `head` as its bytes.
    static func makePack(in packs: URL, named name: String, head: String) throws {
        let folder = packs.appendingPathComponent(name, isDirectory: true)
        try write("{}", to: folder.appendingPathComponent("skin.json"))
        try write(head, to: folder.appendingPathComponent("head.png"))
    }

    static func head(of folder: URL?) -> String? {
        guard let folder else { return nil }
        return try? String(contentsOf: folder.appendingPathComponent("head.png"), encoding: .utf8)
    }

    static func main() {
        do {
            try run()
        } catch {
            print("FAIL setup: \(error)")
            exit(1)
        }
        if failures == 0 {
            print("Pack root tests passed.")
            exit(0)
        }
        print("Pack root tests failed: \(failures)")
        exit(1)
    }

    static func run() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-roots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let checkout = base.appendingPathComponent("sweet-no-sleep", isDirectory: true)
        let app = checkout.appendingPathComponent("dist/Sweet No Sleep - Kiwi Cat.app", isDirectory: true)
        let bundleResources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundlePacks = bundleResources.appendingPathComponent("PetSkins", isDirectory: true)
        let executable = app.appendingPathComponent("Contents/MacOS/SweetNoSleep")
        let stalePacks = checkout.appendingPathComponent("Resources/PetSkins", isDirectory: true)
        // The compiled source file, as #filePath records it on the build machine.
        let sourceFile = checkout.appendingPathComponent("Sources/SweetNoSleep/PetSkinDefinition.swift")
        let userPacks = base.appendingPathComponent("home/Library/Application Support/SweetNoSleep/PetSkins", isDirectory: true)

        let shippedPacks = ["kot-arbuz", "kot-arbuz-moonlight"]
        for name in shippedPacks {
            try makePack(in: bundlePacks, named: name, head: "v2 \(name)")
            try makePack(in: stalePacks, named: name, head: "v1 \(name)")
        }

        // 1. A shipped launch from a bundle that sits inside a stale checkout.
        let shipped = PetPackRoots.resolve(
            bundleURL: app,
            bundleResources: bundleResources,
            sourceFile: sourceFile,
            executable: executable,
            workingDirectory: checkout,
            userDirectory: userPacks,
            environment: [:]
        )
        expect(shipped.map(\.kind) == [.bundle, .user], "shipped launch consults bundle then user, no repository root")
        expect(shipped.first?.url.standardizedFileURL.path == bundlePacks.standardizedFileURL.path,
               "bundle root is the app's own PetSkins")
        for name in shippedPacks {
            let winner = PetPackRoots.winningFolder(named: name, in: shipped)
            expect(head(of: winner) == "v2 \(name)", "shipped launch renders the baked-in v2 \(name)")
            expect(winner?.standardizedFileURL.path == bundlePacks.appendingPathComponent(name).standardizedFileURL.path,
                   "\(name) is read from inside the bundle")
        }

        // 2. An empty or blank override variable is ignored.
        let blank = PetPackRoots.resolve(
            bundleURL: app,
            bundleResources: bundleResources,
            sourceFile: sourceFile,
            executable: executable,
            workingDirectory: checkout,
            userDirectory: userPacks,
            environment: [PetPackRoots.overrideVariable: "   "]
        )
        expect(blank.map(\.kind) == [.bundle, .user], "blank override variable is ignored")

        // 3. The explicit opt-in is honored, and only it brings the checkout in.
        let optedIn = PetPackRoots.resolve(
            bundleURL: app,
            bundleResources: bundleResources,
            sourceFile: sourceFile,
            executable: executable,
            workingDirectory: checkout,
            userDirectory: userPacks,
            environment: [PetPackRoots.overrideVariable: stalePacks.path]
        )
        expect(optedIn.map(\.kind) == [.bundle, .override, .user], "explicit override sits between bundle and user")
        expect(head(of: PetPackRoots.winningFolder(named: "kot-arbuz", in: optedIn)) == "v1 kot-arbuz",
               "explicit override is the only way the checkout's pack wins")

        // 4. A user pack overrides the bundled ID, by design.
        try makePack(in: userPacks, named: "kot-arbuz", head: "user kot-arbuz")
        expect(head(of: PetPackRoots.winningFolder(named: "kot-arbuz", in: shipped)) == "user kot-arbuz",
               "user pack overrides the bundled kot-arbuz")
        expect(head(of: PetPackRoots.winningFolder(named: "kot-arbuz-moonlight", in: shipped)) == "v2 kot-arbuz-moonlight",
               "user pack leaves the other bundled packs alone")

        // 5. An unbundled run (swift run) uses the nearest checkout, and only that one.
        let debugDirectory = checkout.appendingPathComponent(".build/debug", isDirectory: true)
        let unbundled = PetPackRoots.resolve(
            bundleURL: debugDirectory,
            bundleResources: nil,
            sourceFile: sourceFile,
            executable: debugDirectory.appendingPathComponent("SweetNoSleep"),
            workingDirectory: checkout,
            userDirectory: nil,
            environment: [:]
        )
        expect(unbundled.map(\.kind) == [.repository], "unbundled run consults the nearest repository root")
        expect(unbundled.first?.url.standardizedFileURL.path == stalePacks.standardizedFileURL.path,
               "unbundled run reads the checkout it was built from")

        // 6. An app outside any checkout has no repository to find, so only its bundle counts.
        let lone = base.appendingPathComponent("Applications/Sweet No Sleep - Kiwi Cat.app", isDirectory: true)
        let loneResources = lone.appendingPathComponent("Contents/Resources", isDirectory: true)
        let loneRoots = PetPackRoots.resolve(
            bundleURL: lone,
            bundleResources: loneResources,
            sourceFile: base.appendingPathComponent("elsewhere/Sources/SweetNoSleep/PetSkinDefinition.swift"),
            executable: lone.appendingPathComponent("Contents/MacOS/SweetNoSleep"),
            workingDirectory: base,
            userDirectory: nil,
            environment: [:]
        )
        expect(loneRoots.map(\.kind) == [.bundle], "app outside a checkout resolves only its bundle")
    }
}
