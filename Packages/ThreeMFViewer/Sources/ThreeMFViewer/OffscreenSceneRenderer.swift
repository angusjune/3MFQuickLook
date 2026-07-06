import AppKit
import Metal
import RealityKit

/// Renders an entity tree to a `CGImage` without a window, via
/// `RealityRenderer`. Used by the Thumbnail Extension; prototype-confirmed to
/// work inside the sandboxed thumbnail appex.
@MainActor
public enum OffscreenSceneRenderer {
    public enum RenderError: Error {
        case metalUnavailable
        case textureCreationFailed
        case imageReadbackFailed
    }

    public static func render(_ scene: Entity, size: CGSize, scale: CGFloat) async throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.metalUnavailable
        }

        let width = max(Int(size.width * scale), 64)
        let height = max(Int(size.height * scale), 64)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderError.textureCreationFailed
        }

        let renderer = try RealityRenderer()
        renderer.entities.append(scene)

        // Auto-frame the scene with the same rig math the Viewer uses, so
        // thumbnails match the preview's default view.
        var rig = CameraRig()
        rig.frame(scene.visualBounds(relativeTo: nil))
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = rig.fieldOfViewRadians * 180 / .pi
        camera.transform = rig.transform
        renderer.entities.append(camera)
        renderer.activeCamera = camera

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))

        // Safe to read from the completion handler: it fires only after the GPU
        // has finished writing, and nothing else touches the texture afterwards.
        nonisolated(unsafe) let readbackTexture = texture

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try renderer.updateAndRender(deltaTime: 0.1, cameraOutput: output, onComplete: { _ in
                    if let image = image(from: readbackTexture, width: width, height: height) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: RenderError.imageReadbackFailed)
                    }
                })
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private nonisolated static func image(from texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &bytes, bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        return context.makeImage()
    }
}
