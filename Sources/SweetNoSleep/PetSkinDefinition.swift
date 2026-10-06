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

struct PetSkinDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let colors: PetSkinColors
    let animation: PetAnimationProfile

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
        name: "Киви",
        subtitle: "Тёплый мех и листья",
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
                let manifest = folder.appendingPathComponent("skin.json")
                guard let data = try? Data(contentsOf: manifest),
                      let definition = try? JSONDecoder().decode(PetSkinDefinition.self, from: data),
                      definition.isValid
                else { continue }
                // Later roots override earlier ones, so a user pack can safely
                // replace a built-in ID without changing app source.
                definitions[definition.id] = definition
            }
        }
        return definitions.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func skinDirectories() -> [URL] {
        var roots: [URL] = []
        if let bundleResources = Bundle.main.resourceURL {
            roots.append(bundleResources.appendingPathComponent("PetSkins", isDirectory: true))
        }

        let developmentResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/PetSkins", isDirectory: true)
        roots.append(developmentResources)

        if let userDirectory { roots.append(userDirectory) }
        return roots
    }

    private static func skinFolders(in root: URL) -> [URL] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
