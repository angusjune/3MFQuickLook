// PROTOTYPE — throwaway thumbnail extension probing RealityRenderer offscreen. See ../NOTES.md
import QuickLookThumbnailing
import RealityKit
import Metal
import AppKit

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let size = request.maximumSize
        let scale = request.scale
        Task { @MainActor in
            var rendered: CGImage?
            do {
                rendered = try await Self.renderOffscreen(size: size, scale: scale)
                NSLog("ProtoQL ThumbExt: RealityRenderer succeeded")
            } catch {
                NSLog("ProtoQL ThumbExt: RealityRenderer FAILED: \(error)")
            }
            let reply = QLThumbnailReply(contextSize: size) { (ctx: CGContext) -> Bool in
                let rect = CGRect(origin: .zero, size: size)
                if let rendered {
                    ctx.draw(rendered, in: rect)
                } else {
                    // Red X = RealityRenderer failed in this sandbox.
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(NSColor.systemRed.cgColor)
                    ctx.setLineWidth(max(4, size.width / 16))
                    ctx.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 8))
                    ctx.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 8))
                    ctx.move(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8))
                    ctx.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 8))
                    ctx.strokePath()
                }
                return true
            }
            handler(reply, nil)
        }
    }

    @MainActor
    static func renderOffscreen(size: CGSize, scale: CGFloat) async throws -> CGImage {
        enum ProbeError: Error { case noMetal, noTexture, noImage }
        guard let device = MTLCreateSystemDefaultDevice() else { throw ProbeError.noMetal }

        let width = max(Int(size.width * scale), 64)
        let height = max(Int(size.height * scale), 64)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { throw ProbeError.noTexture }

        let renderer = try RealityRenderer()

        // Unlit so the result is visible regardless of IBL availability.
        let root = Entity()
        let colors: [NSColor] = [.systemOrange, .systemBlue, .systemGreen]
        for (i, color) in colors.enumerated() {
            let box = ModelEntity(
                mesh: .generateBox(size: 0.4, cornerRadius: 0.04),
                materials: [UnlitMaterial(color: color)]
            )
            box.position = [Float(i - 1) * 0.55, 0, 0]
            root.addChild(box)
        }
        renderer.entities.append(root)

        let camera = PerspectiveCamera()
        camera.look(at: .zero, from: [1.1, 0.9, 1.6], relativeTo: nil)
        renderer.entities.append(camera)
        renderer.activeCamera = camera

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try renderer.updateAndRender(deltaTime: 0.1, cameraOutput: output, onComplete: { _ in
                    if let image = Self.image(from: texture, width: width, height: height) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: ProbeError.noImage)
                    }
                })
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func image(from texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &bytes, bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let ctx = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}
