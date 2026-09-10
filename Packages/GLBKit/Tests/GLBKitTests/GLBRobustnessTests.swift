import Foundation
import simd
import Testing
@testable import GLBKit

/// Hostile and merely broken files. The dividing line under test: input that
/// *lies about its own layout* is an error, while input that is honest but
/// undrawable is skipped so the rest of the file still previews.
@Suite struct GLBRobustnessTests {
    @Test func accessorReachingPastItsBufferViewIsRejected() {
        // The buffer view holds 3 vertices; the accessor claims 300.
        let data = GLBBuilder.triangle(extraJSON: [
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 300, "type": "VEC3"],
                ["bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ]
        ])
        #expect(throws: GLBParseError.malformedAccessor(index: 0)) {
            try GLBParser().parse(data: data)
        }
    }

    @Test func bufferViewReachingPastItsBufferIsRejected() {
        let data = GLBBuilder.triangle(extraJSON: [
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": 1 << 30],
                ["buffer": 0, "byteOffset": 36, "byteLength": 6],
            ]
        ])
        #expect(throws: GLBParseError.malformedAccessor(index: 0)) {
            try GLBParser().parse(data: data)
        }
    }

    /// A count near `Int.max` must be turned away by arithmetic that can't
    /// itself overflow.
    @Test func astronomicalAccessorCountIsRejected() {
        let data = GLBBuilder.triangle(extraJSON: [
            "accessors": [
                [
                    "bufferView": 0, "componentType": 5126,
                    "count": Int.max / 2, "type": "VEC3",
                ],
                ["bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ]
        ])
        #expect(throws: (any Error).self) { try GLBParser().parse(data: data) }
    }

    @Test func accessorPointingAtAMissingBufferViewIsRejected() {
        let data = GLBBuilder.triangle(extraJSON: [
            "accessors": [
                ["bufferView": 9, "componentType": 5126, "count": 3, "type": "VEC3"],
                ["bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ]
        ])
        #expect(throws: GLBParseError.malformedAccessor(index: 0)) {
            try GLBParser().parse(data: data)
        }
    }

    /// A buffer that names a file next to this one is never followed: the
    /// extensions are sandboxed, and a preview must read only what it was
    /// handed.
    @Test func externalBufferIsNotFollowed() {
        let data = GLBBuilder.triangle(extraJSON: [
            "buffers": [["byteLength": 48, "uri": "geometry.bin"]]
        ])
        #expect(throws: GLBParseError.unresolvableBuffer(index: 0)) {
            try GLBParser().parse(data: data)
        }
    }

    /// Indices past the end of the vertex array are dropped triangle by
    /// triangle, the way the 3MF path drops corrupt extras.
    @Test func outOfRangeTriangleIndicesAreDropped() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            indices: [0, 1, 2, 0, 1, 99]))
        #expect(document.meshes[0].primitives[0].indices == [0, 1, 2])
    }

    /// A primitive whose indices are *all* unusable leaves nothing to draw;
    /// when that is the whole file, it fails rather than previewing empty.
    @Test func fileWithNoDrawableGeometryIsRejected() {
        let data = GLBBuilder.triangle(indices: [98, 99, 100])
        #expect(throws: GLBParseError.noRenderableGeometry) {
            try GLBParser().parse(data: data)
        }
    }

    @Test func pointAndLinePrimitivesAreSkipped() {
        // mode 0 is POINTS: valid glTF, nothing to render in a preview.
        #expect(throws: GLBParseError.noRenderableGeometry) {
            try GLBParser().parse(data: GLBBuilder.triangle(primitive: ["mode": 0]))
        }
    }

    /// Sparse accessors are unsupported, not corrupt: the primitive is
    /// skipped rather than the file rejected as malformed.
    @Test func sparseAccessorIsSkipped() {
        let data = GLBBuilder.triangle(extraJSON: [
            "accessors": [
                [
                    "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                    "sparse": ["count": 1],
                ],
                ["bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ]
        ])
        #expect(throws: GLBParseError.noRenderableGeometry) {
            try GLBParser().parse(data: data)
        }
    }

    /// An attribute whose count disagrees with POSITION describes some other
    /// primitive's vertices; the geometry still draws, without it.
    @Test func mismatchedAttributeCountIsIgnored() throws {
        let data = GLBBuilder.triangle(
            primitive: ["attributes": ["POSITION": 0, "NORMAL": 1], "indices": 1])
        let document = try GLBParser().parse(data: data)
        #expect(document.meshes[0].primitives[0].normals == nil)
        #expect(document.meshes[0].primitives[0].triangleCount == 1)
    }

    // MARK: Topology

    @Test func triangleStripIsExpandedWithAlternatingWinding() {
        let triangles = GLTFMeshResolver.triangles(
            from: [0, 1, 2, 3, 4], topology: .triangleStrip, vertexCount: 5)
        #expect(triangles == [0, 1, 2, 2, 1, 3, 2, 3, 4])
    }

    @Test func triangleFanIsExpandedAroundTheFirstVertex() {
        let triangles = GLTFMeshResolver.triangles(
            from: [0, 1, 2, 3], topology: .triangleFan, vertexCount: 4)
        #expect(triangles == [0, 1, 2, 0, 2, 3])
    }

    @Test func trailingPartialTriangleIsDropped() {
        let triangles = GLTFMeshResolver.triangles(
            from: [0, 1, 2, 0, 1], topology: .triangles, vertexCount: 3)
        #expect(triangles == [0, 1, 2])
    }

    // MARK: Geometry Budget

    @Test func geometryPastTheBudgetIsRejected() {
        let limits = GLBParseLimits(geometryBudget: 2)
        #expect(throws: GLBParseError.overGeometryBudget(budget: 2)) {
            try GLBParser(limits: limits).parse(data: GLBBuilder.triangle())
        }
    }

    /// The budget is charged from the accessor's declared count, before the
    /// vertex array is built: a file claiming hundreds of millions of
    /// vertices must be turned away, not allocated for.
    @Test func budgetIsChargedBeforeMaterializing() {
        let data = GLBBuilder.triangle(extraJSON: [
            "accessors": [
                [
                    "bufferView": 0, "componentType": 5126,
                    "count": 500_000_000, "type": "VEC3",
                ],
                ["bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ]
        ])
        #expect(throws: GLBParseError.overGeometryBudget(budget: 4_000_000)) {
            try GLBParser(limits: .quickLookExtension).parse(data: data)
        }
    }

    /// The budget is one pool for the whole file, so geometry can't dodge it
    /// by spreading across meshes — the same rule the 3MF parser applies
    /// across model parts.
    @Test func budgetIsPooledAcrossMeshes() {
        let data = GLBBuilder.triangle(extraJSON: [
            "meshes": [
                ["primitives": [["attributes": ["POSITION": 0], "indices": 1]]],
                ["primitives": [["attributes": ["POSITION": 0], "indices": 1]]],
            ],
            "nodes": [["mesh": 0], ["mesh": 1]],
            "scenes": [["nodes": [0, 1]]],
        ])
        // One triangle mesh is 3 vertices + 1 triangle = 4 elements; two fit
        // in 8 but not in 7.
        #expect(throws: Never.self) {
            try GLBParser(limits: GLBParseLimits(geometryBudget: 8)).parse(data: data)
        }
        #expect(throws: GLBParseError.overGeometryBudget(budget: 7)) {
            try GLBParser(limits: GLBParseLimits(geometryBudget: 7)).parse(data: data)
        }
    }
}
