import AppKit
import Foundation

/// Reads the art catalog in `Resources/Media`.
///
/// The catalog is produced by `Scripts/render-media.sh` from the SVG sources in
/// `Resources/Art` and copied into the app bundle by `Scripts/build-app.sh`. When
/// the app runs from a source checkout (`swift run`) the same files are loaded
/// from the repository, mirroring how `PetSkinLibrary` finds bundled skins.
enum MediaLibrary {
    /// Menu bar icons are drawn on a 22 pt grid; the retina files are 2x pixels.
    static let menuBarIconPointSize = NSSize(width: 22, height: 22)
    /// Skin previews match the Settings card slot.
    static let skinPreviewPointSize = NSSize(width: 104, height: 52)

    /// Loads a rendered PNG and pins its logical size to `pointSize`, so the 2x
    /// file stays crisp on retina displays instead of being treated as 44 pt art.
    static func image(named name: String, pointSize: NSSize, template: Bool = false) -> NSImage? {
        for directory in mediaDirectories() {
            let candidate = directory.appendingPathComponent(name, isDirectory: false)
            guard let image = NSImage(contentsOf: candidate) else { continue }
            image.size = pointSize
            image.isTemplate = template
            return image
        }
        return nil
    }

    /// Template image for the menu bar: `menubar-awake` while a session keeps the
    /// Mac awake, `menubar-asleep` otherwise. Returns nil when the media pack was
    /// not rendered, so callers can fall back to an SF Symbol.
    static func menuBarIcon(isAwake: Bool) -> NSImage? {
        let stem = isAwake ? "menubar-awake" : "menubar-asleep"
        let retina = "\(stem)@2x.png"
        let standard = "\(stem).png"
        if let image = image(named: retina, pointSize: menuBarIconPointSize, template: true) {
            return image
        }
        return image(named: standard, pointSize: menuBarIconPointSize, template: true)
    }

    /// Preview art for a skin card. Bundled skins use `preview-<id>@2x.png` from
    /// the catalog; an author of a custom pack can drop `preview.png` (or
    /// `preview@2x.png`) next to its `skin.json`.
    static func skinPreviewImage(for skin: PetSkinDefinition) -> NSImage? {
        let catalogNames = ["preview-\(skin.id)@2x.png", "preview-\(skin.id).png"]
        for name in catalogNames {
            if let image = image(named: name, pointSize: skinPreviewPointSize) { return image }
        }

        for root in PetSkinLibrary.skinDirectories() {
            let folder = root.appendingPathComponent(skin.id, isDirectory: true)
            for name in ["preview@2x.png", "preview.png"] {
                let candidate = folder.appendingPathComponent(name, isDirectory: false)
                if let image = NSImage(contentsOf: candidate) {
                    image.size = skinPreviewPointSize
                    return image
                }
            }
        }
        return nil
    }

    /// Bundle resources first, then the repository checkout used by `swift run`.
    private static func mediaDirectories() -> [URL] {
        var roots: [URL] = []
        if let bundleResources = Bundle.main.resourceURL {
            roots.append(bundleResources.appendingPathComponent("Media", isDirectory: true))
        }

        // #filePath is absolute in Xcode and relative under SwiftPM; searching
        // upward from both the source file and the executable covers `swift run`
        // started from any directory.
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sourceFile = URL(fileURLWithPath: String(#filePath), relativeTo: workingDirectory)
            .absoluteURL
            .standardizedFileURL
        appendRepositoryRoots(startingAt: sourceFile.deletingLastPathComponent(), to: &roots)
        if let executable = Bundle.main.executableURL {
            appendRepositoryRoots(startingAt: executable.deletingLastPathComponent(), to: &roots)
        }
        appendRepositoryRoots(startingAt: workingDirectory, to: &roots)

        var seenPaths = Set<String>()
        return roots.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    private static func appendRepositoryRoots(startingAt start: URL, to roots: inout [URL]) {
        var directory = start.standardizedFileURL
        for _ in 0..<8 {
            roots.append(directory.appendingPathComponent("Resources/Media", isDirectory: true))
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
    }
}
