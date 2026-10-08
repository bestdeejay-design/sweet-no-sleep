import Foundation

/// Celebration effects available to data-only skin packs.
enum PetCelebrationEffect: String, Codable, CaseIterable, Hashable {
    case leaves
    case moonDust
    case berryHearts
    case starburst
}

struct PetSkinColors: Codable, Hashable {
    let fur: String
    let furLight: String
    let outline: String
    let innerEar: String
    let iris: String
    let accent: String
    let cheek: String
}

/// Motion values are authored per skin, so a new look can feel different without
/// editing the pet renderer or the power/session code.
struct PetAnimationProfile: Codable, Hashable {
    let breathingFrequency: Double
    let breathingAmplitude: Double
    let tailFrequency: Double
    let tailAmplitude: Double
    let celebrationEffect: PetCelebrationEffect
}

/// How a character pack is drawn. Built-in packs are procedural Canvas cats;
/// a pack that ships `pet.json` is a sprite character built from layer images.
enum PetCharacterKind: String, Codable, Hashable {
    case procedural
    case sprite
}

/// The layered rig of a `pet.json` format 2 character pack.
///
/// All coordinates are normalized to the shared square layer canvas. The head
/// rotates and bobs around `headPivot`, each leg layer swings around its own
/// hip pivot, and the eye sockets anchor the vector eyes the renderer draws on
/// top of the head layer (the painted eyes are inpainted out of the artwork).
struct PetCharacterRig: Codable, Hashable {
    let headPivotX: Double
    let headPivotY: Double
    let legPivotAX: Double
    let legPivotAY: Double
    let legPivotBX: Double
    let legPivotBY: Double
    let legPivotCX: Double
    let legPivotCY: Double
    let eyeLeftX: Double
    let eyeLeftY: Double
    let eyeRightX: Double
    let eyeRightY: Double
    let eyeRadiusX: Double
    let eyeRadiusY: Double

    var isValid: Bool {
        let points = [
            headPivotX, headPivotY, legPivotAX, legPivotAY,
            legPivotBX, legPivotBY, legPivotCX, legPivotCY,
            eyeLeftX, eyeLeftY, eyeRightX, eyeRightY
        ]
        return points.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && eyeRadiusX.isFinite && (0.004...0.2).contains(eyeRadiusX)
            && eyeRadiusY.isFinite && (0.004...0.2).contains(eyeRadiusY)
    }
}

/// Character anchors and motion values from `pet.json`.
///
/// The sprite layers share one square canvas. `heightRatio` is how much of that
/// canvas the character's height occupies, `tailPivot*` are normalized canvas
/// coordinates of the tail rotation point, and `tailSwingDegrees` is the calm
/// idle amplitude of the tail wag. Format 2 packs additionally carry `rig`:
/// head/leg pivots and eye sockets for the layered animation.
struct PetCharacterArt: Codable, Hashable {
    let kind: PetCharacterKind
    let canvas: Int
    let heightRatio: Double
    let tailPivotX: Double
    let tailPivotY: Double
    let tailSwingDegrees: Double
    let rig: PetCharacterRig?

    static let procedural = PetCharacterArt(
        kind: .procedural,
        canvas: 0,
        heightRatio: 0,
        tailPivotX: 0,
        tailPivotY: 0,
        tailSwingDegrees: 0,
        rig: nil
    )

    var isSprite: Bool { kind == .sprite }

    /// True when the pack ships the head/leg/eye layers of format 2.
    var isRigged: Bool { rig != nil }

    var isValid: Bool {
        guard kind == .sprite else { return true }
        return (64...4096).contains(canvas)
            && heightRatio.isFinite
            && (0.2...1.0).contains(heightRatio)
            && tailPivotX.isFinite
            && (0...1).contains(tailPivotX)
            && tailPivotY.isFinite
            && (0...1).contains(tailPivotY)
            && tailSwingDegrees.isFinite
            && (0...30).contains(tailSwingDegrees)
            && (rig?.isValid ?? true)
    }
}

/// `pet.json` switches a pack from the procedural cat to a sprite character.
///
/// Format 1 ships the body and tail layers; format 2 adds the layered rig
/// (head, one layer per leg, eye sockets). Older format 1 packs keep loading:
/// the renderer falls back to the body/tail-only pose for them.
struct PetCharacterManifest: Decodable {
    static let supportedFormats: Set<Int> = [1, 2]
    let art: PetCharacterArt
    let bodyLayerName: String
    let tailLayerName: String
    let headLayerName: String
    let legsALayerName: String
    let legsBLayerName: String
    let legsCLayerName: String
    /// True when the manifest promises the format 2 rig layers.
    let isRigged: Bool

    private enum CodingKeys: String, CodingKey {
        case format
        case kind
        case canvas
        case heightRatio
        case tailPivotX
        case tailPivotY
        case tailSwingDegrees
        case headPivotX
        case headPivotY
        case legPivotAX
        case legPivotAY
        case legPivotBX
        case legPivotBY
        case legPivotCX
        case legPivotCY
        case eyeLeftX
        case eyeLeftY
        case eyeRightX
        case eyeRightY
        case eyeRadiusX
        case eyeRadiusY
        case bodyLayer
        case tailLayer
        case headLayer
        case legsALayer
        case legsBLayer
        case legsCLayer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Int.self, forKey: .format)
        guard Self.supportedFormats.contains(format) else {
            throw PetCharacterManifestError.unsupportedFormat(format)
        }
        isRigged = format >= 2
        var rig: PetCharacterRig?
        if isRigged {
            rig = PetCharacterRig(
                headPivotX: try container.decode(Double.self, forKey: .headPivotX),
                headPivotY: try container.decode(Double.self, forKey: .headPivotY),
                legPivotAX: try container.decode(Double.self, forKey: .legPivotAX),
                legPivotAY: try container.decode(Double.self, forKey: .legPivotAY),
                legPivotBX: try container.decode(Double.self, forKey: .legPivotBX),
                legPivotBY: try container.decode(Double.self, forKey: .legPivotBY),
                legPivotCX: try container.decode(Double.self, forKey: .legPivotCX),
                legPivotCY: try container.decode(Double.self, forKey: .legPivotCY),
                eyeLeftX: try container.decode(Double.self, forKey: .eyeLeftX),
                eyeLeftY: try container.decode(Double.self, forKey: .eyeLeftY),
                eyeRightX: try container.decode(Double.self, forKey: .eyeRightX),
                eyeRightY: try container.decode(Double.self, forKey: .eyeRightY),
                eyeRadiusX: try container.decode(Double.self, forKey: .eyeRadiusX),
                eyeRadiusY: try container.decode(Double.self, forKey: .eyeRadiusY)
            )
        }
        art = PetCharacterArt(
            kind: try container.decode(PetCharacterKind.self, forKey: .kind),
            canvas: try container.decode(Int.self, forKey: .canvas),
            heightRatio: try container.decode(Double.self, forKey: .heightRatio),
            tailPivotX: try container.decode(Double.self, forKey: .tailPivotX),
            tailPivotY: try container.decode(Double.self, forKey: .tailPivotY),
            tailSwingDegrees: try container.decodeIfPresent(Double.self, forKey: .tailSwingDegrees) ?? 3.5,
            rig: rig
        )
        bodyLayerName = try container.decodeIfPresent(String.self, forKey: .bodyLayer) ?? "body.png"
        tailLayerName = try container.decodeIfPresent(String.self, forKey: .tailLayer) ?? "tail.png"
        headLayerName = try container.decodeIfPresent(String.self, forKey: .headLayer) ?? "head.png"
        legsALayerName = try container.decodeIfPresent(String.self, forKey: .legsALayer) ?? "legs-a.png"
        legsBLayerName = try container.decodeIfPresent(String.self, forKey: .legsBLayer) ?? "legs-b.png"
        legsCLayerName = try container.decodeIfPresent(String.self, forKey: .legsCLayer) ?? "legs-c.png"
        let layerNames = [bodyLayerName, tailLayerName] + (isRigged ? [headLayerName, legsALayerName, legsBLayerName, legsCLayerName] : [])
        guard art.isValid, layerNames.allSatisfy(PetCharacterManifest.isSafeLayerName) else {
            throw PetCharacterManifestError.invalidArt
        }
    }

    static func isSafeLayerName(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        return !name.isEmpty
            && !name.contains("..")
            && name.hasSuffix(".png")
            && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

enum PetCharacterManifestError: Error {
    case unsupportedFormat(Int)
    case invalidArt
}

struct PetSkinDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let colors: PetSkinColors
    let animation: PetAnimationProfile
    /// The persona the pet should be called by in the UI. Skins of the built-in
    /// cat omit it (the app falls back to "Kiwi"); a character pack like
    /// Kot-Arbuz declares its own name so the app never calls it "Kiwi".
    var characterName: String? = nil
    /// Pack format version. 1 (default) is a palette/motion pack; 2 may add a
    /// `pet.json` character manifest and its sprite layers.
    var format: Int? = nil
    /// Present when the pack ships `pet.json`; nil means the built-in cat.
    var art: PetCharacterArt? = nil
    /// Folder the pack was loaded from; needed to resolve the sprite layers.
    var packURL: URL? = nil

    /// Declared pack format, defaulting to the original data-only packs.
    var formatVersion: Int { format ?? 1 }

    /// Name the UI addresses this pet by: the pack's persona, else "Kiwi".
    var personaName: String { characterName ?? "Kiwi" }

    /// The art this pack is drawn with (procedural unless `pet.json` says otherwise).
    var character: PetCharacterArt { art ?? .procedural }

    var isSpriteCharacter: Bool { formatVersion >= 2 && character.isSprite }

    var isValid: Bool {
        let allowedIDCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let safeID = !id.isEmpty && id.count <= 48 && id.unicodeScalars.allSatisfy { allowedIDCharacters.contains($0) }
        let hexColors = [colors.fur, colors.furLight, colors.outline, colors.innerEar, colors.iris, colors.accent, colors.cheek]
        let colorsAreValid = hexColors.allSatisfy { color in
            let value = color.hasPrefix("#") ? String(color.dropFirst()) : color
            return value.count == 6 && UInt32(value, radix: 16) != nil
        }
        return safeID
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && colorsAreValid
            && (1...2).contains(formatVersion)
            && character.isValid
            && animation.breathingFrequency.isFinite
            && (0.2...8).contains(animation.breathingFrequency)
            && animation.breathingAmplitude.isFinite
            && (0...0.08).contains(animation.breathingAmplitude)
            && animation.tailFrequency.isFinite
            && (0.2...10).contains(animation.tailFrequency)
            && animation.tailAmplitude.isFinite
            && (0...0.35).contains(animation.tailAmplitude)
    }

    static let fallback = PetSkinDefinition(
        id: "kiwi",
        name: L10n.text("Kiwi"),
        subtitle: L10n.text("Warm fur and leafy details"),
        colors: PetSkinColors(fur: "#E8C894", furLight: "#FFF0D2", outline: "#5D443B", innerEar: "#E88D85", iris: "#5C9B73", accent: "#75C56A", cheek: "#E99B8E"),
        animation: PetAnimationProfile(breathingFrequency: 2.2, breathingAmplitude: 0.018, tailFrequency: 3.0, tailAmplitude: 0.14, celebrationEffect: .leaves)
    )
}

/// Loads built-in packs from the app bundle and user-created packs from
/// Application Support. In a source checkout it also reads the repo Resources.
enum PetSkinLibrary {
    static var userDirectory: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("SweetNoSleep/PetSkins", isDirectory: true)
    }

    static func load() -> [PetSkinDefinition] {
        var definitions: [String: PetSkinDefinition] = [:]
        for root in skinDirectories() {
            for folder in skinFolders(in: root) {
                guard let definition = loadDefinition(from: folder) else { continue }
                // Later roots override earlier ones, so a user pack can safely
                // replace a built-in ID without changing app source.
                definitions[definition.id] = definition
            }
        }
        return definitions.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Reads one pack folder: `skin.json` plus the optional `pet.json` character
    /// manifest. A pack is skipped when its files are unusable, so Settings never
    /// offers a character that cannot be drawn.
    static func loadDefinition(from folder: URL) -> PetSkinDefinition? {
        let manifestURL = folder.appendingPathComponent("skin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var definition = try? JSONDecoder().decode(PetSkinDefinition.self, from: data)
        else { return nil }

        definition.art = characterArt(in: folder)
        definition.packURL = folder
        // Format 2 promises a character: refuse to load half of one, exactly as
        // Scripts/validate-skins.py does, instead of drawing a palette cat.
        if definition.formatVersion >= 2, definition.art == nil { return nil }
        guard definition.isValid else { return nil }
        if definition.isSpriteCharacter,
           CharacterSpriteStore.shared.sprite(for: definition, in: folder) == nil {
            return nil
        }
        return definition
    }

    private static func characterArt(in folder: URL) -> PetCharacterArt? {
        let manifestURL = folder.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetCharacterManifest.self, from: data)
        else { return nil }
        return manifest.art
    }

    private static func skinDirectories() -> [URL] {
        var roots: [URL] = []
        if let bundleResources = Bundle.main.resourceURL {
            roots.append(bundleResources.appendingPathComponent("PetSkins", isDirectory: true))
        }

        // #filePath may be absolute in Xcode or relative under SwiftPM. Also
        // search upward from the running executable so `swift run --package-path`
        // works even when the process was launched from a different directory.
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sourceFile = URL(fileURLWithPath: String(#filePath), relativeTo: workingDirectory)
            .absoluteURL
            .standardizedFileURL
        appendRepositoryRoots(startingAt: sourceFile.deletingLastPathComponent(), to: &roots)

        if let executable = Bundle.main.executableURL {
            appendRepositoryRoots(startingAt: executable.deletingLastPathComponent(), to: &roots)
        }
        appendRepositoryRoots(startingAt: workingDirectory, to: &roots)

        // User packs are last and can intentionally override a bundled ID.
        if let userDirectory { roots.append(userDirectory) }

        var seenPaths = Set<String>()
        return roots.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    private static func appendRepositoryRoots(startingAt start: URL, to roots: inout [URL]) {
        var directory = start.standardizedFileURL
        for _ in 0..<8 {
            roots.append(directory.appendingPathComponent("Resources/PetSkins", isDirectory: true))
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
    }

    private static func skinFolders(in root: URL) -> [URL] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
