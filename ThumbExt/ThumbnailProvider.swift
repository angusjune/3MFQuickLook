import AppKit
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
                let document = try ThreeMFParser().parse(fileAt: fileURL)
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
}
