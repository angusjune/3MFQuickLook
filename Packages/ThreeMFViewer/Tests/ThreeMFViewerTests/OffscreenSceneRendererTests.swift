import CoreGraphics
import Foundation
import RealityKit
import simd
import Testing
import ThreeMFKit
import ThreeMFViewer

@MainActor
@Suite struct OffscreenSceneRendererTests {

    /// A colored cube document, off-origin so auto-framing has to aim.
    private func cubeDocument() -> ThreeMFDocument {
        var positions: [SIMD3<Float>] = []
        for z: Float in [0, 1] {
            for y: Float in [0, 1] {
                for x: Float in [0, 1] {
                    positions.append(SIMD3(x, y, z) * 20 + SIMD3(2000, 2000, 0))
                }
            }
        }
        let mesh = Mesh(
            positions: positions,
            triangleIndices: [
                0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6,
                0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7,
                0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5,
            ])
        let ref = ResourceRef(partPath: "/3D/3dmodel.model", id: 1)
        return ThreeMFDocument(
            unit: .millimeter,
            objects: [ObjectResource(
                ref: ref,
                defaultColor: ColorRGBA(red: 230, green: 60, blue: 40),
                content: .mesh(mesh))],
            buildItems: [BuildItem(objectRef: ref)])
    }

    @Test(.timeLimit(.minutes(1)))
    func renderingADocumentSceneCompletesAtTheRequestedSizeWithVisibleContent() async throws {
        let scene = SceneBuilder.makeScene(for: cubeDocument())
        let image = try await OffscreenSceneRenderer.render(
            scene, size: CGSize(width: 128, height: 128), scale: 2)
        #expect(image.width == 256)
        #expect(image.height == 256)

        // Auto-framing must put the far-off-origin model in view: pixels of
        // the cube's red must appear (BGRA little-endian → A R G B words).
        let data = try #require(image.dataProvider?.data as Data?)
        var redPixels = 0
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for pixel in buffer.bindMemory(to: UInt32.self) {
                let red = (pixel >> 16) & 0xFF, green = (pixel >> 8) & 0xFF, blue = pixel & 0xFF
                if red > 80, red > green * 2, red > blue * 2 { redPixels += 1 }
            }
        }
        #expect(redPixels > 100, "model not visible in auto-framed render")
    }

    @Test(.timeLimit(.minutes(1)))
    func renderingAnEmptyDocumentSceneStillProducesAnImage() async throws {
        let scene = SceneBuilder.makeScene(for: ThreeMFDocument())
        let image = try await OffscreenSceneRenderer.render(
            scene, size: CGSize(width: 128, height: 128), scale: 1)
        #expect(image.width == 128)
        #expect(image.height == 128)
    }
}
