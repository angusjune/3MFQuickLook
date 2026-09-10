import AppKit
import SwiftUI
import ModelViewer

/// A document window: the shared static-then-3D ``PreviewView`` over the file.
/// The Host App has no Geometry Budget (CONTEXT.md) — every file, however
/// large, parses and renders completely; it gets the same instant-first-paint
/// Embedded Thumbnail handoff as the preview, for the formats that carry one.
struct DocumentView: View {
    private let data: Data
    private let staticImage: NSImage?

    init(data: Data) {
        self.data = data
        // Cheap, geometry-free: paint the Embedded Thumbnail first if the file
        // carries one. Geometry is unlimited here, but the image decode keeps
        // the bomb guard — a lying PNG header is never legitimate content.
        self.staticImage = ModelLoader.embeddedImage(data: data, policy: .unlimited)
    }

    var body: some View {
        PreviewView(staticImage: staticImage) {
            try ModelLoader.load(data: data, policy: .unlimited)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
