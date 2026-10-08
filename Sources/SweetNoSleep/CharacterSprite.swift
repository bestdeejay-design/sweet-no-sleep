import AppKit
import CoreGraphics
import Foundation

/// A loaded sprite character: the layers of a `pet.json` pack.
///
/// All layers are square and share one canvas, so drawing them into the same
/// rect (legs, tail, body, head) restores the master artwork; each layer then
/// rotates around the pivot the manifest declares. Format 1 packs ship body and
/// tail only, and the head/leg layers stay nil.
struct CharacterSprite {
    let body: CGImage
    let tail: CGImage
    let head: CGImage?
    let legsA: CGImage?
    let legsB: CGImage?
    let legsC: CGImage?
    let art: PetCharacterArt

    var canvasSide: CGFloat { CGFloat(art.canvas) }

    /// Height of the character inside the square canvas (0...1).
    var heightRatio: CGFloat { CGFloat(art.heightRatio) }

    var tailPivot: CGPoint {
        CGPoint(x: CGFloat(art.tailPivotX), y: CGFloat(art.tailPivotY))
    }

    /// The layered rig, when every rig layer loaded successfully.
    var rig: PetCharacterRig? {
        guard let rig = art.rig, head != nil, legsA != nil, legsB != nil, legsC != nil else { return nil }
        return rig
    }
}

/// Loads and caches sprite layers per pack folder.
///
/// The Canvas renderer is not actor-isolated, so the cache is guarded by a lock
/// and only immutable `CGImage` values are handed out.
final class CharacterSpriteStore {
    static let shared = CharacterSpriteStore()

    private let lock = NSLock()
    private var cache: [String: CharacterSprite] = [:]

    func sprite(for definition: PetSkinDefinition) -> CharacterSprite? {
        guard let folder = definition.packURL else { return nil }
        return sprite(for: definition, in: folder)
    }

    func sprite(for definition: PetSkinDefinition, in folder: URL) -> CharacterSprite? {
        guard definition.isSpriteCharacter else { return nil }
        let key = folder.standardizedFileURL.path

        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached { return cached }

        let manifestURL = folder.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetCharacterManifest.self, from: data),
              manifest.art.isValid,
              let body = Self.cgImage(at: folder.appendingPathComponent(manifest.bodyLayerName)),
              let tail = Self.cgImage(at: folder.appendingPathComponent(manifest.tailLayerName))
        else { return nil }

        // A format 2 pack that lost one rig layer is refused wholesale, exactly
        // as Scripts/validate-skins.py does, instead of drawing a headless cat.
        var head: CGImage?
        var legsA: CGImage?
        var legsB: CGImage?
        var legsC: CGImage?
        if manifest.isRigged {
            guard let loadedHead = Self.cgImage(at: folder.appendingPathComponent(manifest.headLayerName)),
                  let loadedLegsA = Self.cgImage(at: folder.appendingPathComponent(manifest.legsALayerName)),
                  let loadedLegsB = Self.cgImage(at: folder.appendingPathComponent(manifest.legsBLayerName)),
                  let loadedLegsC = Self.cgImage(at: folder.appendingPathComponent(manifest.legsCLayerName))
            else { return nil }
            head = loadedHead
            legsA = loadedLegsA
            legsB = loadedLegsB
            legsC = loadedLegsC
        }

        let sprite = CharacterSprite(body: body, tail: tail, head: head, legsA: legsA, legsB: legsB, legsC: legsC, art: manifest.art)
        lock.lock()
        cache[key] = sprite
        lock.unlock()
        return sprite
    }

    /// Called when the user asks for a refreshed skin list.
    func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func cgImage(at url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
