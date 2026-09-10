import Foundation
import GLBKit
import simd
import Testing
@testable import ModelViewer

/// The Info Line for a GLB: the facts that describe an asset, in the unit
/// the format is actually written in.
@Suite struct GLBInfoLineTests {
    @Test func metreScaleModelsReadInMetres() {
        #expect(InfoLineContent.dimensionsText(meters: SIMD3(1.02, 1.89, 0.87))
            == "1.02 × 1.89 × 0.87 m")
    }

    /// Below a meter the same extents read in millimeters: "0.04 m" is a
    /// worse way to say "40 mm", and a great many assets are palm-sized.
    @Test func subMetreModelsReadInMillimetres() {
        #expect(InfoLineContent.dimensionsText(meters: SIMD3(0.04, 0.09, 0.025))
            == "40 × 90 × 25 mm")
    }

    @Test func triangleCountsAreGroupedAndExact() {
        #expect(InfoLineContent.triangleCountText(10185) == "10,185 triangles")
        #expect(InfoLineContent.triangleCountText(1) == "1 triangle")
        #expect(InfoLineContent.triangleCountText(0) == "0 triangles")
    }

    @Test func meshCountsAreSingularAtOne() {
        #expect(InfoLineContent.meshCountText(1) == "1 mesh")
        #expect(InfoLineContent.meshCountText(5) == "5 meshes")
    }

    /// The whole line for a real-shaped document: size, meshes, triangles —
    /// and none of the print segments, which an asset has no answer for.
    @Test func describesTheStagedScene() {
        let mesh = GLBMesh(primitives: [GLBPrimitive(
            positions: [SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(0, 3, 0)],
            indices: [0, 1, 2])])
        let document = GLBDocument(
            nodes: [GLBNode(meshIndex: 0)], rootNodeIndices: [0], meshes: [mesh])

        let content = InfoLineContent(for: .glb(document), plate: nil)
        #expect(content.dimensions == "2.00 × 3.00 × 0.00 m")
        #expect(content.objectCount == "1 mesh")
        #expect(content.triangleCount == "1 triangle")
        #expect(content.printTime == nil)
        #expect(content.printerModel == nil)
        #expect(content.filamentColors.isEmpty)
    }

    /// An empty scene drops its dimensions segment rather than printing
    /// zeros — the same omission policy the 3MF line follows.
    @Test func emptySceneDropsItsDimensions() {
        let content = InfoLineContent(for: .glb(GLBDocument()), plate: nil)
        #expect(content.dimensions == nil)
        #expect(content.objectCount == "0 meshes")
    }
}
