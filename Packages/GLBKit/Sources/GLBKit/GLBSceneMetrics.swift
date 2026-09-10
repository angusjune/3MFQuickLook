import Foundation
import simd

/// The Info Line's geometry-derived facts about a GLB's scene: what the
/// Viewer is showing. The counterpart of `ThreeMFKit.SceneMetrics`, with the
/// facts that mean something for an asset rather than for a print — no plate,
/// no filament, but a triangle count, which is the first thing anyone asks of
/// a mesh they were handed.
public struct GLBSceneMetrics: Equatable, Sendable {
    /// Bounding size of the placed geometry along the scene axes — width ×
    /// height × depth, glTF being Y-up — in meters, the format's own unit;
    /// nil when nothing is placed.
    public var sizeMeters: SIMD3<Float>?
    /// Number of placed meshes: one per node that carries geometry, so an
    /// asset instanced five times counts five times, as the Viewer draws it.
    public var meshCount: Int
    public var triangleCount: Int

    public init(sizeMeters: SIMD3<Float>? = nil, meshCount: Int = 0, triangleCount: Int = 0) {
        self.sizeMeters = sizeMeters
        self.meshCount = meshCount
        self.triangleCount = triangleCount
    }
}

/// One mesh placed in the scene: which mesh, and where it ends up after the
/// whole chain of node transforms above it.
public struct GLBPlacement: Equatable, Sendable {
    public var meshIndex: Int
    public var transform: simd_float4x4
    /// The placing node's name, for the entity the scene builder makes.
    public var name: String?

    public init(meshIndex: Int, transform: simd_float4x4, name: String? = nil) {
        self.meshIndex = meshIndex
        self.transform = transform
        self.name = name
    }
}

extension GLBDocument {
    /// Every mesh the default scene places, flattened into world transforms
    /// — the single source of truth the scene and its metrics share, so the
    /// Info Line always describes exactly what the Viewer draws.
    ///
    /// The walk carries a visited set: glTF requires the node graph to be a
    /// forest, but a malformed file can point a node back at its own
    /// ancestor and a preview must not spin on it.
    public func placements() -> [GLBPlacement] {
        var placements: [GLBPlacement] = []
        for root in rootNodeIndices {
            collectPlacements(
                nodeIndex: root, parentTransform: matrix_identity_float4x4,
                visited: [], into: &placements)
        }
        return placements
    }

    private func collectPlacements(
        nodeIndex: Int,
        parentTransform: simd_float4x4,
        visited: Set<Int>,
        into placements: inout [GLBPlacement]
    ) {
        guard !visited.contains(nodeIndex), let node = node(at: nodeIndex) else { return }
        let transform = parentTransform * node.transform
        if let meshIndex = node.meshIndex {
            placements.append(
                GLBPlacement(meshIndex: meshIndex, transform: transform, name: node.name))
        }
        for child in node.childIndices {
            collectPlacements(
                nodeIndex: child, parentTransform: transform,
                visited: visited.union([nodeIndex]), into: &placements)
        }
    }

    /// Bounding dimensions, placed-mesh count, and triangle count of the
    /// scene. Vertices are measured through their full transform chain, so a
    /// rotated or scaled placement reports its true extents.
    public func sceneMetrics() -> GLBSceneMetrics {
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)
        var triangleCount = 0
        let placements = placements()

        for placement in placements {
            guard let mesh = mesh(at: placement.meshIndex) else { continue }
            triangleCount += mesh.triangleCount
            for primitive in mesh.primitives {
                for position in primitive.positions {
                    let world = placement.transform * SIMD4(position, 1)
                    minimum = simd_min(minimum, SIMD3(world.x, world.y, world.z))
                    maximum = simd_max(maximum, SIMD3(world.x, world.y, world.z))
                }
            }
        }

        return GLBSceneMetrics(
            sizeMeters: minimum.x <= maximum.x ? maximum - minimum : nil,
            meshCount: placements.count,
            triangleCount: triangleCount)
    }
}
