// PROTOTYPE — throwaway Quick Look preview extension. See ../NOTES.md
import Cocoa
import Quartz
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let host = NSHostingView(rootView: ProtoPreviewView(fileName: url.lastPathComponent))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        handler(nil)
    }
}
