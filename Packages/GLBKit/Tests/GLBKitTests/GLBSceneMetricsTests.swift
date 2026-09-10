import Foundation
import simd
import Testing
@testable import GLBKit

/// The seam the Info Line reads: what the Viewer is actually showing,
/// measured through the same node walk the scene is built from.
@Suite struct GLBSceneMetricsTests {
    @Test func measuresTheDefaultScene() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(positions: [
            SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(0, 3, 0),
        ]))
        let metrics = document.sceneMetrics()

        #expect(metrics.sizeMeters == SIMD3(2, 3, 0))
        #expect(metrics.meshCount == 1)
        #expect(metrics.triangleCount == 1)
    }

    /// A node's scale reaches the measured extents: the Info Line describes
    /// the model as placed, not as authored.
    @Test func measuresThroughNodeTransforms() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            node: ["mesh": 0, "scale": [10, 10, 10]]))
        #expect(document.sceneMetrics().sizeMeters == SIMD3(10, 10, 0))
    }

    /// One mesh placed by two nodes counts twice — that is what the Viewer
    /// draws, and what a "2 meshes" reading should mean.
    @Test func countsEachPlacementOfAnInstancedMesh() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "nodes": [
                ["mesh": 0],
                ["mesh": 0, "translation": [5, 0, 0]],
            ],
            "scenes": [["nodes": [0, 1]]],
        ]))
        let metrics = document.sceneMetrics()

        #expect(metrics.meshCount == 2)
        #expect(metrics.triangleCount == 2)
        #expect(metrics.sizeMeters == SIMD3(6, 1, 0))
    }

    /// Child transforms compose with their parents'.
    @Test func composesNestedNodeTransforms() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "nodes": [
                ["translation": [10, 0, 0], "children": [1]],
                ["mesh": 0, "translation": [0, 10, 0]],
            ],
            "scenes": [["nodes": [0]]],
        ]))
        let placement = try #require(document.placements().first)
        #expect(placement.transform.columns.3 == SIMD4(10, 10, 0, 1))
    }

    /// glTF requires a forest, but a malformed file can close a loop and a
    /// preview must not spin on it.
    @Test func cyclicNodeGraphTerminates() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "nodes": [
                ["mesh": 0, "children": [1]],
                ["mesh": 0, "children": [0]],
            ],
            "scenes": [["nodes": [0]]],
        ]))
        #expect(document.placements().count == 2)
    }

    /// A node the scene doesn't place isn't drawn, so it isn't measured.
    @Test func ignoresNodesOutsideTheScene() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "nodes": [["mesh": 0], ["mesh": 0, "translation": [100, 0, 0]]],
            "scenes": [["nodes": [0]]],
        ]))
        #expect(document.sceneMetrics().meshCount == 1)
    }
}
