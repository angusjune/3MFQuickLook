import AppKit
import ImageIO
import OSLog
import QuickLookThumbnailing
import ThreeMFKit
import ThreeMFViewer

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
                if let thumbnail = try? ThreeMFParser().embeddedThumbnail(fileAt: fileURL),
                   let reply = Self.embeddedReply(from: thumbnail.data, maximumSize: size) {
                    logger.info("embedded thumbnail for \(fileURL.lastPathComponent, privacy: .public)")
                    handler(reply, nil)
                    return
                }

                // No embedded image: render the mesh offscreen. A Sliced
                // File that reaches this point has no Plate Thumbnail to
                // show and no geometry to render (stripped by definition) —
                // the generic icon is the honest fallback, never an empty
                // scene.
                let document = try ThreeMFParser().parse(fileAt: fileURL)
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
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                    return true
                }, nil)
            } catch {
                logger.error("thumbnail failed for \(fileURL.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                handler(nil, error)
            }
        }
    }

    /// A thumbnail reply that draws the Embedded Thumbnail image, aspect-fit
    /// within `maximumSize` so Finder shows it at its true proportions. Returns
    /// nil when the bytes don't decode as an image, so the caller falls back to
    /// mesh rendering.
    private static func embeddedReply(from data: Data, maximumSize: CGSize) -> QLThumbnailReply? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let fit = min(maximumSize.width / imageSize.width, maximumSize.height / imageSize.height)
        let contextSize = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)

        // CGImage is immutable and thread-safe to read from the drawing block
        // QuickLook invokes on its own thread.
        return QLThumbnailReply(contextSize: contextSize) { @Sendable context in
            context.draw(image, in: CGRect(origin: .zero, size: contextSize))
            return true
        }
    }
}
