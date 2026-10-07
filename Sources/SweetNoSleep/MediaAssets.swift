import AppKit
import Foundation

/// Loads the rendered, hand-authored media from an app bundle or source checkout.
enum MediaAssets {
    static func menuBarIcon(isAwake: Bool) -> NSImage? {
        let state = isAwake ? "awake" : "asleep"
        return image(named: "menubar-\(state)", logicalSize: NSSize(width: 22, height: 22), isTemplate: true)
    }

    static func skinPreview(for skinID: String) -> NSImage? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !skinID.isEmpty, skinID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return image(named: "preview-\(skinID)", logicalSize: NSSize(width: 240, height: 160), isTemplate: false)
    }

    private static func image(named name: String, logicalSize: NSSize, isTemplate: Bool) -> NSImage? {
        for directory in renderedDirectories() {
            // Prefer the Retina image. Its NSImage point size is normalized below.
            for suffix in ["@2x.png", ".png"] {
                let url = directory.appendingPathComponent(name + suffix)
                guard let image = NSImage(contentsOf: url) else { continue }
                image.size = logicalSize
                image.isTemplate = isTemplate
                return image
            }
        }
        return nil
    }

    private static func renderedDirectories() -> [URL] {
        var directories: [URL] = []
        for resourceRoot in [Bundle.main.resourceURL, Bundle.module.resourceURL].compactMap({ $0 }) {
            directories.append(resourceRoot.appendingPathComponent("Media", isDirectory: true))
            directories.append(resourceRoot.appendingPathComponent("Art/Rendered", isDirectory: true))
        }

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sourceFile = URL(fileURLWithPath: String(#filePath), relativeTo: workingDirectory)
            .absoluteURL
            .standardizedFileURL
        let startingPoints = [workingDirectory, sourceFile.deletingLastPathComponent()]
        for start in startingPoints {
            var directory = start.standardizedFileURL
            for _ in 0..<8 {
                directories.append(directory.appendingPathComponent("Resources/Art/Rendered", isDirectory: true))
                let parent = directory.deletingLastPathComponent()
                guard parent.path != directory.path else { break }
                directory = parent
            }
        }

        var seen = Set<String>()
        return directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
