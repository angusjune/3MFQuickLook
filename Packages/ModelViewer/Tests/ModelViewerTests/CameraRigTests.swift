import RealityKit
import simd
import Testing
import ModelViewer

/// The custom camera rig of ADR-0001's amendment: drag = orbit,
/// scroll/pinch = zoom, secondary drag = pan. Pure math, no view.
@Suite struct CameraRigTests {

    private let bounds = BoundingBox(min: SIMD3(-1, 0, -1), max: SIMD3(1, 2, 1))

    private func framedRig() -> CameraRig {
        var rig = CameraRig()
        rig.frame(bounds)
        return rig
    }

    @Test func framingCentersTheTargetAndCoversTheBounds() {
        let rig = framedRig()

        #expect(simd_distance(rig.target, SIMD3(0, 1, 0)) < 1e-5)

        let radius = simd_length(bounds.extents) / 2
        let minimumCoveringDistance = radius / tan(rig.fieldOfViewRadians / 2)
        #expect(rig.distance >= minimumCoveringDistance)

        // The camera looks at the target: its -Z axis points from the
        // position toward the target.
        let transform = rig.transform
        let forward = transform.rotation.act(SIMD3<Float>(0, 0, -1))
        let toTarget = simd_normalize(rig.target - transform.translation)
        #expect(simd_distance(forward, toTarget) < 1e-4)
        #expect(abs(simd_distance(transform.translation, rig.target) - rig.distance) < 1e-4)
    }

    @Test func orbitChangesAzimuthAndClampsElevation() {
        var rig = framedRig()
        let startAzimuth = rig.azimuth

        rig.orbit(byAzimuth: 0.5, elevation: 0)
        #expect(abs(rig.azimuth - (startAzimuth + 0.5)) < 1e-6)

        rig.orbit(byAzimuth: 0, elevation: 10)  // way past vertical
        #expect(rig.elevation < .pi / 2)

        rig.orbit(byAzimuth: 0, elevation: -20)
        #expect(rig.elevation > -.pi / 2)

        // Orbiting never moves the target or the distance.
        let reference = framedRig()
        #expect(rig.target == reference.target)
        #expect(rig.distance == reference.distance)
    }

    @Test func zoomScalesDistanceAndClamps() {
        var rig = framedRig()
        let start = rig.distance

        rig.zoom(byFactor: 2)
        #expect(abs(rig.distance - start / 2) < 1e-5)

        rig.zoom(byFactor: 1e9)  // clamped: can't zoom through the model
        #expect(rig.distance > 0)

        rig.zoom(byFactor: 1e-9)  // clamped: can't zoom out to infinity
        #expect(rig.distance < start * 1000)
    }

    @Test func panMovesTheTargetInTheCameraPlane() {
        var rig = framedRig()
        let before = rig.target
        let transform = rig.transform
        let forward = transform.rotation.act(SIMD3<Float>(0, 0, -1))

        rig.pan(byViewDelta: SIMD2(40, 25), viewportHeight: 600)

        let motion = rig.target - before
        #expect(simd_length(motion) > 0)
        // Pan slides the view parallel to the image plane.
        #expect(abs(simd_dot(simd_normalize(motion), forward)) < 1e-4)
        // Distance and orientation stay fixed.
        #expect(rig.distance == framedRig().distance)
        #expect(rig.azimuth == framedRig().azimuth)
    }

    @Test func panScalesWithDistance() {
        var near = framedRig()
        var far = framedRig()
        far.zoom(byFactor: 0.5)  // twice as far

        near.pan(byViewDelta: SIMD2(10, 0), viewportHeight: 600)
        far.pan(byViewDelta: SIMD2(10, 0), viewportHeight: 600)

        let nearMotion = simd_length(near.target - framedRig().target)
        let farMotion = simd_length(far.target - framedRig().target)
        #expect(abs(farMotion / nearMotion - 2) < 0.01)
    }

    @Test func framingAnEmptyBoundingBoxStaysUsable() {
        var rig = CameraRig()
        rig.frame(BoundingBox(min: .zero, max: .zero))
        #expect(rig.distance > 0)
        #expect(rig.transform.translation.x.isFinite)
    }
}
