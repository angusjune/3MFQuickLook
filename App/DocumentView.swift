import SwiftUI
import ThreeMFKit
import ThreeMFViewer

/// A document window: the shared Viewer over the fully parsed file. The Host
/// App has no Geometry Budget (CONTEXT.md) — every file, however large,
/// parses and renders completely.
struct DocumentView: View {
    let data: Data

    private enum Phase {
        case loading
        case loaded(ThreeMFDocument)
        case failed(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading model…")
            case .loaded(let document):
                Viewer(document: document)
            case .failed(let reason):
                ContentUnavailableView {
                    Label("Can’t Read This File", systemImage: "cube.transparent")
                } description: {
                    Text(reason)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .task(id: data) { await load() }
    }

    private func load() async {
        let data = data
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try ThreeMFParser().parse(data: data)
            }.value
            phase = .loaded(document)
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
