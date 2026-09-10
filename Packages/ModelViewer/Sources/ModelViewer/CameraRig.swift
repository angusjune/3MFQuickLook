import RealityKit
import simd

/// The Viewer's camera model (ADR-0001 amendment: custom rig, not
/// `CameraControls`): an orbit camera around a target point.
/// Drag = orbit, scroll/pinch = zoom, secondary drag = pan. Pure math so the
/// gesture-to-camera behavior is testable without a view.
public struct CameraRig: Equatable, Sendable {
    public var target: SIMD3<Float> = .zero
    /// Radians around +Y; 0 puts the camera on the +Z side of the target.
    public var azimuth: Float = -0.6
    /// Radians above the horizon, clamped short of the poles.
    public var elevation: Float = 0.35
    public var distance: Float = 1

    public var fieldOfViewRadians: Float = 60 * .pi / 180

    private var minimumDistance: Float = 0.001
    private var maximumDistance: Float = 100

    private static let elevationLimit: Float = .pi / 2 * 0.98

    public init() {}

    /// Re-aims the rig at `bounds`: target on the center, distance far enough
    /// that the bounding sphere fits the vertical field of view with margin.
    public mutating func frame(_ bounds: BoundingBox) {
        target = bounds.center
        let radius = max(simd_length(bounds.extents) / 2, 0.005)
        distance = radius / tan(fieldOfViewRadians / 2) * 1.3
        minimumDistance = radius * 0.05
        maximumDistance = radius * 40
    }

    public mutating func orbit(byAzimuth deltaAzimuth: Float, elevation deltaElevation: Float) {
        azimuth += deltaAzimuth
        elevation = min(max(elevation + deltaElevation, -Self.elevationLimit), Self.elevationLimit)
    }

    /// Factors > 1 zoom in; the distance is clamped so the model can be
    /// neither entered nor lost.
    public mutating func zoom(byFactor factor: Float) {
        guard factor > 0, factor.isFinite else { return }
        distance = min(max(distance / factor, minimumDistance), maximumDistance)
    }

    /// Slides the target parallel to the image plane. `delta` is in view
    /// points (+x right, +y down, AppKit drag convention); the world offset is
    /// sized so the content follows the cursor at the target's depth.
    public mutating func pan(byViewDelta delta: SIMD2<Float>, viewportHeight: Float) {
        guard viewportHeight > 0 else { return }
        let worldPerPoint = 2 * distance * tan(fieldOfViewRadians / 2) / viewportHeight
        let axes = cameraAxes()
        target += (-delta.x * axes.right + delta.y * axes.up) * worldPerPoint
    }

    /// The camera's pose: at the spherical offset from the target, looking at
    /// the target with +Y up.
    public var transform: Transform {
        let axes = cameraAxes()
        let rotation = simd_quatf(simd_float3x3(columns: (axes.right, axes.up, axes.back)))
        return Transform(
            scale: .one,
            rotation: rotation,
            translation: target + axes.back * distance)
    }

    private func cameraAxes() -> (right: SIMD3<Float>, up: SIMD3<Float>, back: SIMD3<Float>) {
        let back = SIMD3(
            sin(azimuth) * cos(elevation),
            sin(elevation),
            cos(azimuth) * cos(elevation))
        let right = simd_normalize(simd_cross(SIMD3(0, 1, 0), back))
        let up = simd_cross(back, right)
        return (right, up, back)
    }
}

public extension CameraRig {
    /// A `PerspectiveCamera` configured for this rig: its field of view, clip
    /// planes suited to metric model scenes, and the rig's current pose.
    /// Millimeter models frame at centimeter camera distances — the default
    /// near plane (1 m) would clip such scenes away entirely.
    @MainActor
    func makeCamera() -> PerspectiveCamera {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = fieldOfViewRadians * 180 / .pi
        camera.camera.near = 0.001
        camera.camera.far = 1000
        camera.transform = transform
        return camera
    }
}
