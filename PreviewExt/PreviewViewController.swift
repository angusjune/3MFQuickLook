import AppKit
import OSLog
import Quartz
import SwiftUI
import ThreeMFKit
import ThreeMFViewer

private let logger = Logger(
    subsystem: "com.angusjune.ThreeMFQuickLook.PreviewExt", category: "preview")

final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let document = try ThreeMFParser().parse(fileAt: url)
            let hostingView = NSHostingView(rootView: Viewer(document: document))
            hostingView.frame = view.bounds
            hostingView.autoresizingMask = [.width, .height]
            view.addSubview(hostingView)
            logger.info("previewing \(url.lastPathComponent, privacy: .public)")
            handler(nil)
        } catch {
            logger.error("preview failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            handler(error)
        }
    }
}
