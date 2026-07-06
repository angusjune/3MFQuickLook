import AppKit
import RealityKit
import simd
import ThreeMFKit

/// Builds the RealityKit entity tree the Viewer and the Thumbnail Extension
/// render for a document: real mesh geometry with computed normals and
/// file colors, under an Apple-minimal backdrop with soft studio lighting
/// and a shadow-casting key light.
public enum SceneBuilder {
    /// Neutral filament gray for geometry the file doesn't color.
    static let neutralColor = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 1)

    @MainActor
    public static func makeScene(for document: ThreeMFDocument) -> Entity {
        let root = Entity()

        let model = makeModelSubtree(for: document)
        root.addChild(model)
        root.addChild(makeLighting())
        if let backdrop = makeBackdrop(beneath: model) {
            root.addChild(backdrop)
        }
        return root
    }

    /// The bounds cameras should frame: the document's geometry (the "Model"
    /// subtree), not staging like the backdrop, which is deliberately much
    /// wider than the model.
    @MainActor
    public static func modelBounds(of scene: Entity) -> BoundingBox {
        (scene.findEntity(named: "Model") ?? scene).visualBounds(relativeTo: nil)
    }

    // MARK: Model subtree

    /// The document's build, in 3MF model space, wrapped in one entity that
    /// converts to RealityKit conventions: model units → meters, Z-up → Y-up.
    @MainActor
    private static func makeModelSubtree(for document: ThreeMFDocument) -> Entity {
        let model = Entity()
        model.name = "Model"
        model.transform = Transform(
            scale: SIMD3(repeating: document.unit.metersPerUnit),
            rotation: simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0)),
            translation: .zero)

        let objectsByRef = Dictionary(
            document.objects.map { ($0.ref, $0) },
            uniquingKeysWith: { first, _ in first })

        // Lenient fallback: a file without build items still shows its mesh
        // objects.
        let items = document.buildItems.isEmpty
            ? document.objects.compactMap { object -> BuildItem? in
                guard case .mesh = object.content else { return nil }
                return BuildItem(objectRef: object.ref)
            }
            : document.buildItems

        for item in items {
            guard let object = objectsByRef[item.objectRef] else { continue }
            let entity = makeEntity(for: object, objectsByRef: objectsByRef, visited: [])
            entity.transform = Transform(matrix: item.transform)
            model.addChild(entity)
        }
        return model
    }

    @MainActor
    private static func makeEntity(
        for object: ObjectResource,
        objectsByRef: [ResourceRef: ObjectResource],
        visited: Set<ResourceRef>
    ) -> Entity {
        guard !visited.contains(object.ref) else { return Entity() }
        switch object.content {
        case .mesh(let mesh):
            return makeMeshEntity(mesh, name: object.name, color: object.defaultColor)
        case .components(let components):
            let parent = Entity()
            parent.name = object.name ?? ""
            for component in components {
                guard let target = objectsByRef[component.objectRef] else { continue }
                let child = makeEntity(
                    for: target,
                    objectsByRef: objectsByRef,
                    visited: visited.union([object.ref]))
                child.transform = Transform(matrix: component.transform)
                parent.addChild(child)
            }
            return parent
        }
    }

    @MainActor
    private static func makeMeshEntity(_ mesh: Mesh, name: String?, color: ColorRGBA?) -> Entity {
        let indices = validTriangleIndices(of: mesh)
        guard !mesh.positions.isEmpty, !indices.isEmpty else { return Entity() }

        var descriptor = MeshDescriptor(name: name ?? "mesh")
        descriptor.positions = MeshBuffer(mesh.positions)
        descriptor.normals = MeshBuffer(computedNormals(positions: mesh.positions, indices: indices))
        descriptor.primitives = .triangles(indices)

        // Triangles without a per-triangle color (nil) render in the object's
        // color, so partially painted meshes keep both their paint and base.
        let objectNSColor = color.map(nsColor) ?? neutralColor
        let materials: [any RealityKit.Material]
        if let triangleColors = mesh.triangleColors, triangleColors.count * 3 == indices.count {
            var order: [ColorRGBA?] = []
            var indexOfColor: [ColorRGBA?: UInt32] = [:]
            var faceMaterials: [UInt32] = []
            faceMaterials.reserveCapacity(triangleColors.count)
            for color in triangleColors {
                if let existing = indexOfColor[color] {
                    faceMaterials.append(existing)
                } else {
                    let new = UInt32(order.count)
                    order.append(color)
                    indexOfColor[color] = new
                    faceMaterials.append(new)
                }
            }
            descriptor.materials = .perFace(faceMaterials)
            materials = order.map { material(for: $0.map(nsColor) ?? objectNSColor) }
        } else {
            descriptor.materials = .allFaces(0)
            materials = [material(for: objectNSColor)]
        }

        guard let resource = try? MeshResource.generate(from: [descriptor]) else {
            return Entity()
        }
        let entity = ModelEntity(mesh: resource, materials: materials)
        entity.name = name ?? ""
        return entity
    }

    /// Triangles whose indices stay inside the vertex range; corrupt extras
    /// are dropped rather than crashing the preview.
    private static func validTriangleIndices(of mesh: Mesh) -> [UInt32] {
        let vertexCount = UInt32(mesh.positions.count)
        let indices = mesh.triangleIndices
        guard indices.contains(where: { $0 >= vertexCount }) else { return indices }
        var valid: [UInt32] = []
        valid.reserveCapacity(indices.count)
        for triangle in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = indices[triangle], b = indices[triangle + 1], c = indices[triangle + 2]
            if a < vertexCount, b < vertexCount, c < vertexCount {
                valid.append(a)
                valid.append(b)
                valid.append(c)
            }
        }
        return valid
    }

    /// Area-weighted vertex normals: face normals (cross products, whose
    /// length is proportional to face area) accumulated per vertex, then
    /// normalized.
    private static func computedNormals(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
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

    private static func material(for color: NSColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.55, isMetallic: false)
    }

    private static func nsColor(_ color: ColorRGBA) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255)
    }

    // MARK: Staging

    /// Soft studio setup: shadow-casting key light plus fill and rim.
    @MainActor
    private static func makeLighting() -> Entity {
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
    private static func makeBackdrop(beneath model: Entity) -> Entity? {
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
}
