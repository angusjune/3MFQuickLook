import AppKit
import SwiftUI
import ThreeMFKit
import ThreeMFViewer

/// A document window: the shared static-then-3D ``PreviewView`` over the file.
/// The Host App has no Geometry Budget (CONTEXT.md) — every file, however
/// large, parses and renders completely; it gets the same instant-first-paint
/// Embedded Thumbnail handoff as the preview.
struct DocumentView: View {
    private let data: Data
    private let staticImage: NSImage?

    init(data: Data) {
        self.data = data
        // Cheap, geometry-free: paint the Embedded Thumbnail first if the file
        // carries one.
        self.staticImage = (try? ThreeMFParser().embeddedThumbnail(data: data))
            .flatMap { NSImage(data: $0.data) }
    }

    var body: some View {
        PreviewView(staticImage: staticImage) {
            try ThreeMFParser().parse(data: data)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
