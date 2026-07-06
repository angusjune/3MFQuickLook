import AppKit
import RealityKit
import ThreeMFKit

/// Builds the RealityKit entity tree the Viewer and the Thumbnail Extension
/// render for a document.
///
/// Walking-skeleton placeholder: ignores the document and returns three boxes
/// plus a directional light. One box is unlit so the scene stays visible even
/// where image-based lighting is unavailable (offscreen RealityRenderer).
/// Issue #3 replaces this with real mesh geometry, backdrop, and studio
/// lighting.
public enum SceneBuilder {
    @MainActor
    public static func makeScene(for document: ThreeMFDocument) -> Entity {
        let root = Entity()

        let colors: [(NSColor, unlit: Bool)] = [
            (.systemOrange, false),
            (.systemBlue, false),
            (.systemGreen, true),
        ]
        for (index, (color, unlit)) in colors.enumerated() {
            let material: any RealityKit.Material = unlit
                ? UnlitMaterial(color: color)
                : SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)
            let box = ModelEntity(
                mesh: .generateBox(size: 0.4, cornerRadius: 0.04),
                materials: [material]
            )
            box.position = [Float(index - 1) * 0.55, 0, 0]
            root.addChild(box)
        }

        let light = Entity()
        light.components.set(DirectionalLightComponent(color: .white, intensity: 3000))
        light.look(at: .zero, from: [1.0, 1.5, 1.5], relativeTo: nil)
        root.addChild(light)

        return root
    }
}
