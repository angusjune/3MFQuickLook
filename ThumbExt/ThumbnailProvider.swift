import AppKit
import ImageIO
import OSLog
import QuickLookThumbnailing
import ModelViewer

private let logger = Logger(
    subsystem: "com.angusjune.ThreeMFQuickLook.ThumbExt", category: "thumbnail")

final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let fileURL = request.fileURL
        let size = request.maximumSize
        let scale = request.scale
        // The framework accepts the reply handler from any thread; it is called
        // exactly once below.
        nonisolated(unsafe) let handler = handler
        Task { @MainActor in
            do {
                // Embedded-first (issue #5): the file's own Embedded Thumbnail
                // wins when present — no geometry parse, no offscreen render.
                // Everything here runs under the Geometry Budget and the bomb
                // caps (issue #10): this extension parses untrusted downloads
                // automatically inside a hard memory ceiling. GLB files never
                // carry one, so they always take the render path below.
                if let thumbnail = ModelLoader.embeddedThumbnailData(
                       fileAt: fileURL, policy: .quickLookExtension),
                   let reply = Self.embeddedReply(from: thumbnail, maximumSize: size) {
                    logger.info("embedded thumbnail for \(fileURL.lastPathComponent, privacy: .public)")
                    handler(reply, nil)
                    return
                }

                // No embedded image: render the mesh offscreen. A Sliced
                // File that reaches this point has no Plate Thumbnail to
                // show and no geometry to render (stripped by definition) —
                // the generic icon is the honest fallback, never an empty
                // scene.
                let document = try ModelLoader.load(
                    fileAt: fileURL, policy: .quickLookExtension)
                guard !document.isSlicedFile else {
                    logger.info("sliced file without plate image: \(fileURL.lastPathComponent, privacy: .public)")
                    handler(nil, nil)
                    return
                }
                let scene = SceneBuilder.makeScene(for: document)
                let image = try await OffscreenSceneRenderer.render(scene, size: size, scale: scale)
                logger.info("rendered thumbnail for \(fileURL.lastPathComponent, privacy: .public)")
                // @Sendable: QuickLook invokes the drawing block on its own
                // thread; without it the closure inherits this Task's MainActor
                // isolation and the runtime kills the appex at draw time.
                handler(QLThumbnailReply(contextSize: size) { @Sendable context in
                    // Fill the context's own clip box, not a `size`-sized rect:
                    // the reply context's user space carries the request's
                    // scale, so a rect measured in points covered only the
                    // lower-left 1/scale of a Retina context (CG's origin is
                    // bottom-left) and Finder showed a small, corner-pinned
                    // render. The clip box is in user space either way.
                    context.draw(image, in: context.boundingBoxOfClipPath)
                    return true
                }, nil)
            } catch where ModelLoader.isOverGeometryBudget(error) {
                // Over the Geometry Budget with no Embedded Thumbnail to
                // show: the generic icon is the honest, jetsam-safe answer —
                // same posture as a Sliced File without a Plate image.
                logger.info(
                    "over geometry budget for \(fileURL.lastPathComponent, privacy: .public)")
                handler(nil, nil)
            } catch {
                logger.error("thumbnail failed for \(fileURL.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                handler(nil, error)
            }
        }
    }

    /// A thumbnail reply that draws the Embedded Thumbnail image, aspect-fit
    /// within `maximumSize` so Finder shows it at its true proportions. Returns
    /// nil when the bytes don't decode as an image — or declare bomb-sized
    /// dimensions (issue #10) — so the caller falls back to mesh rendering.
    private static func embeddedReply(from data: Data, maximumSize: CGSize) -> QLThumbnailReply? {
        guard let image = PackageImageDecoder.cgImage(from: data) else { return nil }

        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let fit = min(maximumSize.width / imageSize.width, maximumSize.height / imageSize.height)
        let contextSize = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)

        // CGImage is immutable and thread-safe to read from the drawing block
        // QuickLook invokes on its own thread.
        return QLThumbnailReply(contextSize: contextSize) { @Sendable context in
            // Same scale trap as the mesh-render reply above: fill the clip
            // box. `contextSize` already carries the aspect fit, so filling
            // it keeps the image's true proportions.
            context.draw(image, in: context.boundingBoxOfClipPath)
            return true
        }
    }
}
