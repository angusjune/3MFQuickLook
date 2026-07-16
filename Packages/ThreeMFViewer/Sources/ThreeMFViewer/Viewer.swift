import AppKit
import OSLog
import RealityKit
import SwiftUI
import ThreeMFKit

let viewerLogger = Logger(subsystem: "com.angusjune.ThreeMFViewer", category: "viewer")

/// The shared interactive 3D view used by the Host App and the Preview
/// Extension: the document's scene under the custom camera rig
/// (drag = orbit, scroll/pinch = zoom, secondary drag = pan — ADR-0001
/// amendment). Multi-plate Slicer Projects get the Plate Filmstrip along the
/// bottom (issue #6); clicking a Plate swaps the scene to that Plate's
/// objects from the already-parsed document — the file is never re-read.
/// Beneath it sits the Info Line (issue #7), describing whichever scene is
/// staged.
public struct Viewer: View {
    private let document: ThreeMFDocument
    private let filmstripCells: [PlateFilmstrip.Cell]

    @State private var scene: Entity
    @State private var rig: CameraRig
    @State private var selectedPlateIndex: Int?
    @State private var infoContent: InfoLineContent

    @MainActor
    public init(document: ThreeMFDocument) {
        self.document = document
        self.filmstripCells = PlateFilmstrip.plates(of: document).map {
            PlateFilmstrip.Cell(plate: $0)
        }
        let scene = SceneBuilder.makeScene(for: document)
        _scene = State(initialValue: scene)
        var rig = CameraRig()
        rig.frame(SceneBuilder.modelBounds(of: scene))
        _rig = State(initialValue: rig)
        _selectedPlateIndex = State(initialValue: document.slicerProject?.defaultPlateIndex)
        // Nil plate = the default scene, the same one makeScene just staged.
        _infoContent = State(initialValue: InfoLineContent(for: document, plate: nil))
    }

    public var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(scene)
            let camera = rig.makeCamera()
            camera.name = "RigCamera"
            content.add(camera)
            viewerLogger.info("viewer scene: bounds \(String(describing: SceneBuilder.modelBounds(of: scene)), privacy: .public), camera at \(String(describing: rig.transform.translation), privacy: .public)")
        } update: { content in
            // A Plate switch rebuilt the scene entity; swap it in place.
            if let stale = content.entities.first(where: { $0.name == "Scene" && $0 !== scene }) {
                content.remove(stale)
                content.add(scene)
            }
            if let camera = content.entities.first(where: { $0.name == "RigCamera" }) {
                camera.transform = rig.transform
            }
        }
        .overlay(CameraGestureSurface(rig: $rig))
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if !filmstripCells.isEmpty {
                    PlateFilmstrip(
                        cells: filmstripCells,
                        selectedIndex: selectedPlateIndex,
                        select: switchToPlate)
                }
                InfoLine(content: infoContent)
            }
            .padding(12)
        }
    }

    /// Swaps the 3D scene to the clicked Plate's objects and re-aims the
    /// camera at the new content. Only the rig's target and distance change,
    /// so the user's orbit orientation survives the switch. The Info Line
    /// follows: it always describes the staged Plate.
    private func switchToPlate(at index: Int) {
        guard index != selectedPlateIndex, filmstripCells.indices.contains(index) else { return }
        selectedPlateIndex = index
        let plate = filmstripCells[index].plate
        scene = SceneBuilder.makeScene(for: document, plate: plate)
        rig.frame(SceneBuilder.modelBounds(of: scene))
        infoContent = InfoLineContent(for: document, plate: plate)
        viewerLogger.info("switched to plate \(index + 1, privacy: .public) of \(filmstripCells.count, privacy: .public)")
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
        // Sized so a full-height trackpad swipe zooms ~6×, a wheel notch ~1.2×.
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / 300
            : event.scrollingDeltaY / 10
        onZoom?(exp2(delta))
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification)
    }
}
