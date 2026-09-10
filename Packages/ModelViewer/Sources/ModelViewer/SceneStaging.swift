import AppKit
import RealityKit
import simd

/// The parts of a scene that belong to the presentation rather than to the
/// file: the studio lighting, the backdrop that catches its shadow, and the
/// vertex math every format's geometry needs on the way in.
///
/// Shared by both scene builders on purpose — a GLB and a 3MF package should
/// be lit and staged identically, so switching between two files in Finder
/// doesn't switch the look of the preview with them.
enum SceneStaging {
    /// Neutral gray for geometry the file doesn't color.
    static let neutralColor = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 1)

    /// The bounds cameras should frame: the document's geometry (the "Model"
    /// subtree), not staging like the backdrop, which is deliberately much
    /// wider than the model. A scene with no geometry at all (an empty Plate)
    /// frames its staging instead, so the camera shows the empty bed.
    @MainActor
    static func modelBounds(of scene: Entity) -> BoundingBox {
        let model = (scene.findEntity(named: "Model") ?? scene).visualBounds(relativeTo: nil)
        return model.extents.max() > 0 ? model : scene.visualBounds(relativeTo: nil)
    }

    /// Soft studio setup: shadow-casting key light plus fill and rim.
    @MainActor
    static func makeLighting() -> Entity {
        let lighting = Entity()
        lighting.name = "Lighting"

        let key = Entity()
        key.components.set(DirectionalLightComponent(color: .white, intensity: 4000))
        key.components.set(DirectionalLightComponent.Shadow())
        key.look(at: .zero, from: [1.0, 1.6, 1.2], relativeTo: nil)
        lighting.addChild(key)

        let fill = Entity()
        fill.components.set(DirectionalLightComponent(color: .white, intensity: 1500))
        fill.look(at: .zero, from: [-1.4, 0.8, 1.0], relativeTo: nil)
        lighting.addChild(fill)

        let rim = Entity()
        rim.components.set(DirectionalLightComponent(color: .white, intensity: 1000))
        rim.look(at: .zero, from: [0.3, 1.0, -1.5], relativeTo: nil)
        lighting.addChild(rim)

        return lighting
    }

    /// A rounded neutral platform just beneath the model, catching the key
    /// light's contact shadow.
    @MainActor
    static func makeBackdrop(beneath model: Entity) -> Entity? {
        let bounds = model.visualBounds(relativeTo: nil)
        guard bounds.extents.max() > 0 else { return nil }

        let span = max(bounds.extents.x, bounds.extents.z)
        let width = max(span * 4, 0.2)
        let plane = ModelEntity(
            mesh: .generatePlane(width: width, depth: width, cornerRadius: width * 0.5),
            materials: [SimpleMaterial(
                color: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1),
                roughness: 1, isMetallic: false)])
        plane.name = "Backdrop"
        // Nudged down to keep flat-bottomed models from z-fighting the plane.
        plane.position = SIMD3(bounds.center.x, bounds.min.y - 0.001, bounds.center.z)
        return plane
    }

    /// Area-weighted vertex normals: face normals (cross products, whose
    /// length is proportional to face area) accumulated per vertex, then
    /// normalized. Used for 3MF, which never stores normals, and for glTF
    /// primitives that omit them.
    static func computedNormals(
        positions: [SIMD3<Float>], indices: [UInt32]
    ) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for triangle in stride(from: 0, to: indices.count - 2, by: 3) {
            let ia = Int(indices[triangle]), ib = Int(indices[triangle + 1]), ic = Int(indices[triangle + 2])
            let a = positions[ia]
            let faceNormal = simd_cross(positions[ib] - a, positions[ic] - a)
            normals[ia] += faceNormal
            normals[ib] += faceNormal
            normals[ic] += faceNormal
        }
        for i in normals.indices {
            let length = simd_length(normals[i])
            normals[i] = length > .ulpOfOne ? normals[i] / length : SIMD3(0, 0, 1)
        }
        return normals
    }

    /// The matte material the 3MF path paints every surface with: printed
    /// parts have no metal and little gloss.
    static func matteMaterial(for color: NSColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.55, isMetallic: false)
    }
}
