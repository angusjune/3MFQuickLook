import AppKit
import RealityKit
import simd
import ThreeMFKit

/// Builds the RealityKit entity tree the Viewer and the Thumbnail Extension
/// render for a document: real mesh geometry with computed normals and
/// file colors, under an Apple-minimal backdrop with soft studio lighting
/// and a shadow-casting key light (``SceneStaging``).
///
/// The 3MF path lives here; the GLB path lives in ``GLBSceneBuilder``, and
/// ``makeScene(for:plate:)`` over a ``ModelDocument`` is the seam every
/// surface actually calls.
public enum SceneBuilder {
    /// The scene for any model file. The Plate argument only means something
    /// for a Slicer Project; GLB has no plates to switch between.
    @MainActor
    public static func makeScene(for document: ModelDocument, plate: Plate? = nil) -> Entity {
        switch document {
        case .threeMF(let document): makeScene(for: document, plate: plate)
        case .glb(let document): GLBSceneBuilder.makeScene(for: document)
        }
    }

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
        root.addChild(SceneStaging.makeLighting())
        // Slicer Projects sit on a plate hint at the true plate size; Vanilla
        // files (and projects whose metadata lacks a plate size) keep the
        // Apple-minimal backdrop.
        if let hint = makePlateHint(for: document, beneath: model) {
            root.addChild(hint)
        } else if let backdrop = SceneStaging.makeBackdrop(beneath: model) {
            root.addChild(backdrop)
        }
        return root
    }

    /// The bounds cameras should frame — see ``SceneStaging/modelBounds(of:)``.
    @MainActor
    public static func modelBounds(of scene: Entity) -> BoundingBox {
        SceneStaging.modelBounds(of: scene)
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

        // Staging — which items, with which lenient fallbacks — is the
        // document's call (ThreeMFDocument.stagedBuildItems), shared with the
        // Info Line's metrics so the two can never disagree.
        for item in document.stagedBuildItems(for: plate) {
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
            return makeMeshEntity(
                mesh,
                name: object.name,
                color: filamentColor ?? object.defaultColor,
                filaments: slicerProject?.filaments ?? [])
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
    private static func makeMeshEntity(
        _ mesh: Mesh,
        name: String?,
        color: ColorRGBA?,
        filaments: [Filament]
    ) -> Entity {
        let indices = validTriangleIndices(of: mesh)
        guard !mesh.positions.isEmpty, !indices.isEmpty else { return Entity() }

        var descriptor = MeshDescriptor(name: name ?? "mesh")
        descriptor.positions = MeshBuffer(mesh.positions)
        descriptor.normals = MeshBuffer(
            SceneStaging.computedNormals(positions: mesh.positions, indices: indices))
        descriptor.primitives = .triangles(indices)

        // Triangles without a per-triangle color (nil) render in the object's
        // color, so partially painted meshes keep both their paint and base.
        let objectNSColor = color.map(nsColor) ?? SceneStaging.neutralColor
        let materials: [any RealityKit.Material]
        if let triangleColors = perTriangleColors(of: mesh, filaments: filaments),
           triangleColors.count * 3 == indices.count {
            var order: [ColorRGBA?] = []
            var indexOfColor: [ColorRGBA?: UInt32] = [:]
            var faceMaterials: [UInt32] = []
            faceMaterials.reserveCapacity(triangleColors.count)
            for triangleColor in triangleColors {
                // Dedup on the resolved color, so a triangle painted in the
                // object's own color shares its material.
                let resolved = triangleColor ?? color
                if let existing = indexOfColor[resolved] {
                    faceMaterials.append(existing)
                } else {
                    let new = UInt32(order.count)
                    order.append(resolved)
                    indexOfColor[resolved] = new
                    faceMaterials.append(new)
                }
            }
            descriptor.materials = .perFace(faceMaterials)
            materials = order.map {
                SceneStaging.matteMaterial(for: $0.map(nsColor) ?? objectNSColor)
            }
        } else {
            descriptor.materials = .allFaces(0)
            materials = [SceneStaging.matteMaterial(for: objectNSColor)]
        }

        guard let resource = try? MeshResource.generate(from: [descriptor]) else {
            return Entity()
        }
        let entity = ModelEntity(mesh: resource, materials: materials)
        entity.name = name ?? ""
        return entity
    }

    /// The mesh's per-triangle color overrides: paint strokes mapped through
    /// the project's filaments (issue #9) laid over spec property colors —
    /// the stroke is what the slicer shows, so it wins where both exist.
    /// Out-of-range strokes fall back to filament 0, like the object-level
    /// mapping; without filament definitions paint has no meaning and the
    /// property colors (or the plain object color) stand alone.
    private static func perTriangleColors(
        of mesh: Mesh, filaments: [Filament]
    ) -> [ColorRGBA?]? {
        guard let paints = mesh.trianglePaintFilamentIndices, !filaments.isEmpty else {
            return mesh.triangleColors
        }
        var colors = mesh.triangleColors ?? Array(repeating: nil, count: paints.count)
        guard colors.count == paints.count else { return mesh.triangleColors }
        for (triangle, paint) in paints.enumerated() {
            guard let paint else { continue }
            let filament = filaments.indices.contains(paint) ? filaments[paint] : filaments[0]
            if let color = filament.color { colors[triangle] = color }
        }
        return colors
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

    private static func nsColor(_ color: ColorRGBA) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255)
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
}
