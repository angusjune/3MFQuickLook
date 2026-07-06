import AppKit
import RealityKit
import SwiftUI
import ThreeMFKit

/// The shared interactive 3D view used by the Host App and the Preview
/// Extension: the document's scene under the custom camera rig
/// (drag = orbit, scroll/pinch = zoom, secondary drag = pan — ADR-0001
/// amendment).
public struct Viewer: View {
    private let scene: Entity
    @State private var rig: CameraRig

    @MainActor
    public init(document: ThreeMFDocument) {
        let scene = SceneBuilder.makeScene(for: document)
        self.scene = scene
        var rig = CameraRig()
        rig.frame(scene.visualBounds(relativeTo: nil))
        _rig = State(initialValue: rig)
    }

    public var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(scene)
            let camera = PerspectiveCamera()
            camera.name = "RigCamera"
            camera.camera.fieldOfViewInDegrees = rig.fieldOfViewRadians * 180 / .pi
            camera.transform = rig.transform
            content.add(camera)
        } update: { content in
            if let camera = content.entities.first(where: { $0.name == "RigCamera" }) {
                camera.transform = rig.transform
            }
        }
        .overlay(CameraGestureSurface(rig: $rig))
    }
}

/// Transparent AppKit surface that feeds mouse, scroll-wheel, and trackpad
/// events to the camera rig. SwiftUI gestures can't observe scroll wheels or
/// secondary-button drags; the prototype confirmed these NSEvents all reach
/// the sandboxed Preview Extension.
private struct CameraGestureSurface: NSViewRepresentable {
    @Binding var rig: CameraRig

    func makeNSView(context: Context) -> EventCaptureView {
        let view = EventCaptureView()
        connect(view)
        return view
    }

    func updateNSView(_ view: EventCaptureView, context: Context) {
        connect(view)
    }

    private func connect(_ view: EventCaptureView) {
        view.onOrbit = { deltaX, deltaY in
            // Points → radians: a full-height drag sweeps about half a turn.
            rig.orbit(byAzimuth: Float(-deltaX) * 0.008, elevation: Float(deltaY) * 0.008)
        }
        view.onPan = { deltaX, deltaY, viewportHeight in
            rig.pan(byViewDelta: SIMD2(Float(deltaX), Float(deltaY)), viewportHeight: Float(viewportHeight))
        }
        view.onZoom = { factor in
            rig.zoom(byFactor: Float(factor))
        }
    }
}

final class EventCaptureView: NSView {
    var onOrbit: ((CGFloat, CGFloat) -> Void)?
    var onPan: ((CGFloat, CGFloat, CGFloat) -> Void)?
    var onZoom: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        onOrbit?(event.deltaX, event.deltaY)
    }

    override func rightMouseDragged(with event: NSEvent) {
        onPan?(event.deltaX, event.deltaY, bounds.height)
    }

    override func otherMouseDragged(with event: NSEvent) {
        onPan?(event.deltaX, event.deltaY, bounds.height)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / 120
            : event.scrollingDeltaY / 12
        onZoom?(exp2(delta))
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification)
    }
}
