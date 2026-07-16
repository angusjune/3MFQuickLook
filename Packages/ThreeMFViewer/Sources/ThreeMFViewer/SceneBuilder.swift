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

    /// - Parameter plate: the Build Plate to stage, or nil for the default —
    ///   a Slicer Project's first Plate with objects, a Vanilla file's whole
    ///   build. Plate switching (issue #6) rebuilds the scene from the same
    ///   parsed document; the file is never re-read.
    @MainActor
    public static func makeScene(for document: ThreeMFDocument, plate: Plate? = nil) -> Entity {
        let root = Entity()
        root.name = "Scene"

        let model = makeModelSubtree(for: document, plate: plate)
        root.addChild(model)
        root.addChild(makeLighting())
        // Slicer Projects sit on a plate hint at the true plate size; Vanilla
        // files (and projects whose metadata lacks a plate size) keep the
        // Apple-minimal backdrop.
        if let hint = makePlateHint(for: document, beneath: model) {
            root.addChild(hint)
        } else if let backdrop = makeBackdrop(beneath: model) {
            root.addChild(backdrop)
        }
        return root
    }

    /// The bounds cameras should frame: the document's geometry (the "Model"
    /// subtree), not staging like the backdrop, which is deliberately much
    /// wider than the model. A scene with no geometry at all (an empty Plate)
    /// frames its staging instead, so the camera shows the empty bed.
    @MainActor
    public static func modelBounds(of scene: Entity) -> BoundingBox {
        let model = (scene.findEntity(named: "Model") ?? scene).visualBounds(relativeTo: nil)
        return model.extents.max() > 0 ? model : scene.visualBounds(relativeTo: nil)
    }

    // MARK: Model subtree

    /// The document's build, in 3MF model space, wrapped in one entity that
    /// converts to RealityKit conventions: model units → meters, Z-up → Y-up.
    @MainActor
    private static func makeModelSubtree(for document: ThreeMFDocument, plate: Plate?) -> Entity {
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
        let allItems = document.buildItems.isEmpty
            ? document.objects.compactMap { object -> BuildItem? in
                guard case .mesh = object.content else { return nil }
                return BuildItem(objectRef: object.ref)
            }
            : document.buildItems
        let items = plateItems(of: allItems, plate: plate ?? document.slicerProject?.defaultPlate)

        for item in items {
            guard let object = objectsByRef[item.objectRef] else { continue }
            // Objects without an explicit assignment print on filament 0.
            let itemColor = document.slicerProject?.filamentColor(of: item.objectRef)
                ?? document.slicerProject?.filaments.first?.color
            let entity = makeEntity(
                for: object,
                objectsByRef: objectsByRef,
                visited: [],
                slicerProject: document.slicerProject,
                filamentColor: itemColor)
            entity.transform = Transform(matrix: item.transform)
            model.addChild(entity)
        }
        return model
    }

    /// The build items staged for a Plate: the plate's assigned items, with
    /// two edges. Assignments that match no build item fall back to the whole
    /// build (lenient: a broken config must not empty the preview); a Plate
    /// with no assignments at all is genuinely empty and stages nothing.
    /// No plate — a Vanilla file — stages everything.
    private static func plateItems(of items: [BuildItem], plate: Plate?) -> [BuildItem] {
        guard let plate else { return items }
        guard !plate.objectRefs.isEmpty else { return [] }
        let assigned = Set(plate.objectRefs)
        let plateItems = items.filter { assigned.contains($0.objectRef) }
        return plateItems.isEmpty ? items : plateItems
    }

    @MainActor
    private static func makeEntity(
        for object: ObjectResource,
        objectsByRef: [ResourceRef: ObjectResource],
        visited: Set<ResourceRef>,
        slicerProject: SlicerProjectInfo? = nil,
        filamentColor: ColorRGBA? = nil
    ) -> Entity {
        guard !visited.contains(object.ref) else { return Entity() }
        switch object.content {
        case .mesh(let mesh):
            // The slicer's plate view shows parts in their filament color, so
            // it wins over any CAD material color the mesh carries.
            return makeMeshEntity(mesh, name: object.name, color: filamentColor ?? object.defaultColor)
        case .components(let components):
            let parent = Entity()
            parent.name = object.name ?? ""
            for component in components {
                guard let target = objectsByRef[component.objectRef] else { continue }
                let child = makeEntity(
                    for: target,
                    objectsByRef: objectsByRef,
                    visited: visited.union([object.ref]),
                    slicerProject: slicerProject,
                    // A part-level extruder assignment overrides the color
                    // inherited from the containing object.
                    filamentColor: slicerProject?.filamentColor(of: target.ref) ?? filamentColor)
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

    /// A flat plate outline at the Slicer Project's true plate size: a thin
    /// bed surface with a border ring inset along its edge, built in model
    /// space (mm, Z-up) under the same units conversion as the Model subtree.
    ///
    /// Placed at the model-space origin, where slicer bed coordinates start —
    /// unless the geometry doesn't fit there (multi-plate global coordinates),
    /// in which case it centers under the geometry instead.
    @MainActor
    private static func makePlateHint(for document: ThreeMFDocument, beneath model: Entity) -> Entity? {
        guard let rect = document.slicerProject?.plateRect else { return nil }

        let hint = Entity()
        hint.name = "PlateHint"
        hint.transform = model.transform

        let surfaceThickness: Float = 0.4
        let line = max(rect.width, rect.depth) * 0.01

        let surface = ModelEntity(
            mesh: .generateBox(size: SIMD3(rect.width, rect.depth, surfaceThickness)),
            materials: [SimpleMaterial(
                color: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1),
                roughness: 1, isMetallic: false)])
        // Top face just below the bed plane so flat-bottomed parts don't
        // z-fight it.
        surface.position = SIMD3(rect.width / 2, rect.depth / 2, -surfaceThickness / 2 - 0.05)
        hint.addChild(surface)

        let borderMaterial = SimpleMaterial(
            color: NSColor(srgbRed: 0.68, green: 0.68, blue: 0.70, alpha: 1),
            roughness: 0.9, isMetallic: false)
        let edges: [(SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(rect.width, line), SIMD2(rect.width / 2, line / 2)),
            (SIMD2(rect.width, line), SIMD2(rect.width / 2, rect.depth - line / 2)),
            (SIMD2(line, rect.depth - 2 * line), SIMD2(line / 2, rect.depth / 2)),
            (SIMD2(line, rect.depth - 2 * line), SIMD2(rect.width - line / 2, rect.depth / 2)),
        ]
        for (extent, center) in edges {
            let edge = ModelEntity(
                mesh: .generateBox(size: SIMD3(extent.x, extent.y, surfaceThickness)),
                materials: [borderMaterial])
            edge.position = SIMD3(center.x, center.y, -surfaceThickness / 2)
            hint.addChild(edge)
        }

        // The hint sits at the metadata's bed origin; fall back to centering
        // when the build sits elsewhere (multi-plate global space).
        var offset = rect.origin
        let bounds = model.visualBounds(relativeTo: nil)
        if bounds.extents.max() > 0 {
            let scale = document.unit.metersPerUnit
            let minX = bounds.min.x / scale, maxX = bounds.max.x / scale
            let minY = -bounds.max.z / scale, maxY = -bounds.min.z / scale
            let tolerance: Float = 1
            let fitsAtOrigin = minX >= rect.origin.x - tolerance
                && maxX <= rect.origin.x + rect.width + tolerance
                && minY >= rect.origin.y - tolerance
                && maxY <= rect.origin.y + rect.depth + tolerance
            if !fitsAtOrigin {
                offset = SIMD2(
                    (minX + maxX - rect.width) / 2,
                    (minY + maxY - rect.depth) / 2)
            }
        }
        for child in hint.children {
            child.position.x += offset.x
            child.position.y += offset.y
        }
        return hint
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
