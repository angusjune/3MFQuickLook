import RealityKit
import SwiftUI
import ThreeMFKit

/// The shared interactive 3D view used by the Host App and the Preview
/// Extension.
///
/// Walking-skeleton placeholder: shows the placeholder scene with RealityKit's
/// built-in orbit control. Issue #3 adds the custom camera rig
/// (drag = orbit, scroll/pinch = zoom, secondary drag = pan) — the built-in
/// `CameraControls` modes each map only a single drag gesture.
public struct Viewer: View {
    private let document: ThreeMFDocument

    public init(document: ThreeMFDocument) {
        self.document = document
    }

    public var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(SceneBuilder.makeScene(for: document))
        }
        .realityViewCameraControls(.orbit)
    }
}
