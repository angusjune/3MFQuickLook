import AppKit
import OSLog
import Quartz
import SwiftUI
import ModelViewer

private let logger = Logger(
    subsystem: "com.angusjune.ThreeMFQuickLook.PreviewExt", category: "preview")
private let signposter = OSSignposter(logger: logger)

final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // First paint: extract the Embedded Thumbnail cheaply (no geometry) and
        // hand it to PreviewView so the panel shows something within tens of
        // milliseconds while the 3D scene parses in the background.
        let state = signposter.beginInterval("FirstPaint")
        let start = ContinuousClock.now

        // The extension parses untrusted downloads automatically, so both
        // reads run under the Geometry Budget and the bomb caps (issue #10);
        // the image decode is capped the same way. A GLB has no Embedded
        // Thumbnail to find — glTF has no thumbnail convention — so it goes
        // straight to the loading state and then the 3D scene.
        let image = ModelLoader.embeddedImage(fileAt: url, policy: .quickLookExtension)

        let rootView = PreviewView(staticImage: image) {
            try ModelLoader.load(fileAt: url, policy: .quickLookExtension)
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.width, .height]
        view.addSubview(hostingView)

        signposter.endInterval("FirstPaint", state)
        let elapsed = ContinuousClock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        logger.info(
            "first paint for \(url.lastPathComponent, privacy: .public) in \(milliseconds, format: .fixed(precision: 1))ms (embedded thumbnail: \(image != nil, privacy: .public))")
        handler(nil)
    }
}
