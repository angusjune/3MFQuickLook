import RealityKit
import Testing
import ThreeMFKit
import ThreeMFViewer

@MainActor
@Suite struct SceneBuilderTests {
    @Test func sceneForADocumentHasRenderableContent() {
        let scene = SceneBuilder.makeScene(for: ThreeMFDocument())
        #expect(modelEntityCount(in: scene) > 0)
    }

    private func modelEntityCount(in entity: Entity) -> Int {
        let own = entity.components.has(ModelComponent.self) ? 1 : 0
        return entity.children.reduce(own) { $0 + modelEntityCount(in: $1) }
    }
}
