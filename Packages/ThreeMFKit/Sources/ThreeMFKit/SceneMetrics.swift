import Foundation
import simd

/// The Info Line's geometry-derived facts about one staged scene (issue #7):
/// what the Viewer shows for a document and Plate.
public struct SceneMetrics: Equatable, Sendable {
    /// Bounding size of the staged geometry along the model-space axes —
    /// width × depth × height, 3MF being Z-up — in millimeters; nil when
    /// nothing is staged.
    public var sizeMillimeters: SIMD3<Float>?
    /// Number of placed objects (staged build items).
    public var objectCount: Int

    public init(sizeMillimeters: SIMD3<Float>? = nil, objectCount: Int = 0) {
        self.sizeMillimeters = sizeMillimeters
        self.objectCount = objectCount
    }
}

extension ThreeMFDocument {
    /// The Plate a scene request resolves to: the override itself, or —
    /// given nil — the default Plate. The one resolution rule the scene,
    /// its metrics, the filament dots, and the Info Line's print time all
    /// share. Nil for Vanilla files, which have no Plates.
    public func stagedPlate(for plate: Plate? = nil) -> Plate? {
        plate ?? slicerProject?.defaultPlate
    }

    /// The build items staged for a Plate — the single source of truth the
    /// scene, its metrics, and the filament dots all share, so the Info Line
    /// always describes exactly what the Viewer shows.
    ///
    /// Nil means the default: a Slicer Project's default Plate, a Vanilla
    /// file's whole build. A file without build items stages its mesh objects
    /// (lenient fallback). A Plate's assignments that match no build item
    /// fall back to the whole build (a broken config must not empty the
    /// preview); a Plate with no assignments at all is genuinely empty and
    /// stages nothing.
    public func stagedBuildItems(for plate: Plate? = nil) -> [BuildItem] {
        let allItems = buildItems.isEmpty
            ? objects.compactMap { object -> BuildItem? in
                guard case .mesh = object.content else { return nil }
                return BuildItem(objectRef: object.ref)
            }
            : buildItems
        guard let plate = stagedPlate(for: plate) else { return allItems }
        guard !plate.objectRefs.isEmpty else { return [] }
        let assigned = Set(plate.objectRefs)
        let plateItems = allItems.filter { assigned.contains($0.objectRef) }
        return plateItems.isEmpty ? allItems : plateItems
    }

    /// Bounding dimensions and object count of the scene staged for a Plate
    /// (nil: the default scene). Vertices are measured through their full
    /// transform chain, so rotated arrangements report exact extents.
    public func sceneMetrics(for plate: Plate? = nil) -> SceneMetrics {
        let items = stagedBuildItems(for: plate)
        let objectsByRef = objectsByRef()
        var bounds = Bounds()
        for item in items {
            guard let object = objectsByRef[item.objectRef] else { continue }
            accumulateBounds(
                of: object, transform: item.transform, visited: [],
                objectsByRef: objectsByRef, into: &bounds)
        }
        let millimetersPerUnit = unit.metersPerUnit * 1000
        return SceneMetrics(
            sizeMillimeters: bounds.size.map { $0 * millimetersPerUnit },
            objectCount: items.count)
    }

    /// The filaments the Plate's scene uses (nil: the default scene), as
    /// sorted unique indices into ``SlicerProjectInfo/filaments``. A sliced
    /// plate's recorded list wins — it sees paint colors assignment
    /// derivation can't; otherwise the indices derive from the staged
    /// objects' assignments, defaulting to filament 0 like the slicer.
    /// Out-of-range indices fall back to 0, matching
    /// ``SlicerProjectInfo/filamentColor(of:)``. Empty for Vanilla files.
    public func usedFilamentIndices(for plate: Plate? = nil) -> [Int] {
        guard let slicer = slicerProject, !slicer.filaments.isEmpty else { return [] }
        let clamp = { (index: Int) in slicer.filaments.indices.contains(index) ? index : 0 }
        if let recorded = stagedPlate(for: plate)?.usedFilamentIndices {
            return Set(recorded.map(clamp)).sorted()
        }
        let objectsByRef = objectsByRef()
        var used: Set<Int> = []
        for item in stagedBuildItems(for: plate) {
            guard let object = objectsByRef[item.objectRef] else { continue }
            collectFilamentIndices(
                of: object, inherited: slicer.filamentIndexByObject[object.ref] ?? 0,
                assignments: slicer.filamentIndexByObject, visited: [],
                objectsByRef: objectsByRef, into: &used)
        }
        return Set(used.map(clamp)).sorted()
    }

    private func objectsByRef() -> [ResourceRef: ObjectResource] {
        Dictionary(objects.map { ($0.ref, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private struct Bounds {
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)

        mutating func expand(to point: SIMD3<Float>) {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }

        var size: SIMD3<Float>? {
            minimum.x <= maximum.x ? maximum - minimum : nil
        }
    }

    private func accumulateBounds(
        of object: ObjectResource,
        transform: simd_float4x4,
        visited: Set<ResourceRef>,
        objectsByRef: [ResourceRef: ObjectResource],
        into bounds: inout Bounds
    ) {
        guard !visited.contains(object.ref) else { return }
        switch object.content {
        case .mesh(let mesh):
            for position in mesh.positions {
                let transformed = transform * SIMD4(position, 1)
                bounds.expand(to: SIMD3(transformed.x, transformed.y, transformed.z))
            }
        case .components(let components):
            for component in components {
                guard let target = objectsByRef[component.objectRef] else { continue }
                accumulateBounds(
                    of: target,
                    transform: transform * component.transform,
                    visited: visited.union([object.ref]),
                    objectsByRef: objectsByRef,
                    into: &bounds)
            }
        }
    }

    /// Mirrors the scene's color resolution (SceneBuilder.makeEntity): each
    /// mesh leaf prints on its part-level assignment when it has one, else
    /// the index inherited from its containing object.
    private func collectFilamentIndices(
        of object: ObjectResource,
        inherited: Int,
        assignments: [ResourceRef: Int],
        visited: Set<ResourceRef>,
        objectsByRef: [ResourceRef: ObjectResource],
        into used: inout Set<Int>
    ) {
        guard !visited.contains(object.ref) else { return }
        switch object.content {
        case .mesh:
            used.insert(inherited)
        case .components(let components):
            for component in components {
                guard let target = objectsByRef[component.objectRef] else { continue }
                collectFilamentIndices(
                    of: target,
                    inherited: assignments[target.ref] ?? inherited,
                    assignments: assignments,
                    visited: visited.union([object.ref]),
                    objectsByRef: objectsByRef,
                    into: &used)
            }
        }
    }
}
