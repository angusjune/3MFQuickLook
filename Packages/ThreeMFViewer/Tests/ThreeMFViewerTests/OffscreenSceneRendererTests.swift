import CoreGraphics
import RealityKit
import Testing
import ThreeMFKit
import ThreeMFViewer

@MainActor
@Suite struct OffscreenSceneRendererTests {
    @Test(.timeLimit(.minutes(1)))
    func renderingTheSceneCompletesAtTheRequestedSize() async throws {
        let scene = SceneBuilder.makeScene(for: ThreeMFDocument())
        let image = try await OffscreenSceneRenderer.render(
            scene, size: CGSize(width: 128, height: 128), scale: 1)
        #expect(image.width == 128)
        #expect(image.height == 128)
    }
}
