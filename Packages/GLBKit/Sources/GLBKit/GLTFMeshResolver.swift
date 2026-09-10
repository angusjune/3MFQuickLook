import Foundation
import simd

/// Turns glTF mesh primitives into ``GLBPrimitive`` vertex arrays, charging
/// the Geometry Budget as it goes.
///
/// Skipping is deliberate and narrow: a primitive is dropped when it is
/// well-formed but undrawable (a point or line topology, no POSITION, an
/// attribute stored in a way the reader doesn't support). Corrupt data still
/// throws — a file that lies about where its vertices live is not a file
/// with fewer parts to draw.
struct GLTFMeshResolver {
    let json: GLTFJSON
    let reader: GLTFAccessorReader
    let limits: GLBParseLimits

    /// Geometry elements — vertices plus triangles — materialized so far.
    /// A class box so the budget is one pool across every mesh, mirroring
    /// the 3MF parser's whole-package pool.
    final class Budget {
        private(set) var consumed = 0

        func charge(_ elements: Int, limit: Int?) throws {
            consumed += max(elements, 0)
            if let limit, consumed > limit {
                throw GLBParseError.overGeometryBudget(budget: limit)
            }
        }
    }

    func resolveMeshes(budget: Budget) throws -> [GLBMesh] {
        try (json.meshes ?? []).map { mesh in
            GLBMesh(
                name: mesh.name,
                primitives: try (mesh.primitives ?? []).compactMap {
                    try resolve(primitive: $0, budget: budget)
                })
        }
    }

    private func resolve(
        primitive: GLTFJSON.Primitive, budget: Budget
    ) throws -> GLBPrimitive? {
        // Topology first: points and lines have nothing to contribute to a
        // preview, and skipping them before any budget is charged keeps a
        // point cloud from crowding out the geometry beside it.
        guard let topology = GLTFJSON.TriangleTopology(rawValue: primitive.mode ?? 4),
              let positionAccessor = primitive.attributes?["POSITION"]
        else { return nil }

        // Charged from the accessor's declared count, before the array is
        // materialized: a file claiming 200 million vertices must be turned
        // away, not allocated for and then rejected.
        let vertexCount = reader.elementCount(accessor: positionAccessor) ?? 0
        try budget.charge(vertexCount, limit: limits.geometryBudget)
        guard let positions = try reader.vectors3(accessor: positionAccessor),
              !positions.isEmpty
        else { return nil }

        let indices = try resolveIndices(
            of: primitive, topology: topology, vertexCount: positions.count, budget: budget)
        guard !indices.isEmpty else { return nil }

        return GLBPrimitive(
            positions: positions,
            normals: try attribute(primitive, "NORMAL", matching: positions.count),
            textureCoordinates: try textureCoordinates(primitive, matching: positions.count),
            indices: indices,
            materialIndex: validatedMaterialIndex(primitive.material))
    }

    /// The primitive's triangle indices, with every topology reduced to
    /// plain triangles and every triangle checked against the vertex count.
    private func resolveIndices(
        of primitive: GLTFJSON.Primitive,
        topology: GLTFJSON.TriangleTopology,
        vertexCount: Int,
        budget: Budget
    ) throws -> [UInt32] {
        let sequence: [UInt32]
        if let accessor = primitive.indices {
            let declared = reader.elementCount(accessor: accessor) ?? 0
            try budget.charge(declared / 3, limit: limits.geometryBudget)
            guard let read = try reader.indices(accessor: accessor) else { return [] }
            sequence = read
        } else {
            // Non-indexed: the spec's implied 0, 1, 2… over the attributes.
            try budget.charge(vertexCount / 3, limit: limits.geometryBudget)
            sequence = (0..<UInt32(vertexCount)).map { $0 }
        }
        return Self.triangles(from: sequence, topology: topology, vertexCount: vertexCount)
    }

    /// Reduces a topology to triangle triples, dropping any triangle that
    /// references a vertex the primitive doesn't have — corrupt extras are
    /// dropped rather than crashing the preview, exactly as the 3MF path
    /// treats out-of-range triangle indices.
    static func triangles(
        from sequence: [UInt32], topology: GLTFJSON.TriangleTopology, vertexCount: Int
    ) -> [UInt32] {
        let limit = UInt32(clamping: vertexCount)
        var triangles: [UInt32] = []

        func append(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            guard a < limit, b < limit, c < limit else { return }
            triangles.append(contentsOf: [a, b, c])
        }

        switch topology {
        case .triangles:
            triangles.reserveCapacity(sequence.count)
            for start in stride(from: 0, to: sequence.count - 2, by: 3) {
                append(sequence[start], sequence[start + 1], sequence[start + 2])
            }
        case .triangleStrip:
            // Winding alternates so every triangle faces the same way.
            for start in 0..<max(sequence.count - 2, 0) {
                let (a, b, c) = (sequence[start], sequence[start + 1], sequence[start + 2])
                start.isMultiple(of: 2) ? append(a, b, c) : append(b, a, c)
            }
        case .triangleFan:
            for start in 1..<max(sequence.count - 1, 1) {
                append(sequence[0], sequence[start], sequence[start + 1])
            }
        }
        return triangles
    }

    /// A VEC3 vertex attribute, accepted only when it supplies exactly one
    /// value per position — a mismatched count is a file describing
    /// something other than this primitive's vertices.
    private func attribute(
        _ primitive: GLTFJSON.Primitive, _ name: String, matching vertexCount: Int
    ) throws -> [SIMD3<Float>]? {
        guard let accessor = primitive.attributes?[name],
              let values = try reader.vectors3(accessor: accessor),
              values.count == vertexCount
        else { return nil }
        return values
    }

    private func textureCoordinates(
        _ primitive: GLTFJSON.Primitive, matching vertexCount: Int
    ) throws -> [SIMD2<Float>]? {
        guard let accessor = primitive.attributes?["TEXCOORD_0"],
              let values = try reader.vectors2(accessor: accessor),
              values.count == vertexCount
        else { return nil }
        return values
    }

    /// Out-of-range material references fall back to the glTF default
    /// material, the same leniency the spec gives a primitive with no
    /// material at all.
    private func validatedMaterialIndex(_ index: Int?) -> Int? {
        guard let index, (json.materials ?? []).indices.contains(index) else { return nil }
        return index
    }
}
