import AppKit
import Quartz
import SwiftUI
import ThreeMFKit
import ThreeMFViewer

final class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let document = try ThreeMFParser().parse(fileAt: url)
        let hostingView = NSHostingView(rootView: Viewer(document: document))
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.width, .height]
        view.addSubview(hostingView)
    }
}
