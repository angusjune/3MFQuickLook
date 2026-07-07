import AppKit
import SwiftUI
import ThreeMFKit

/// The "instant first paint" preview (issue #5): paints the Embedded Thumbnail
/// immediately, parses geometry off the main thread, then crossfades to the
/// interactive ``Viewer`` when the scene is ready. Files with no embedded
/// image show a neutral loading state instead, then crossfade the same way.
/// There is no blank panel at any point.
///
/// Shared by the Preview Extension and the Host App: both hand it a
/// pre-extracted static image and a parse closure.
public struct PreviewView: View {
    private let staticImage: NSImage?
    private let parse: @Sendable () throws -> ThreeMFDocument

    private enum Phase: Equatable {
        case loading
        case loaded(ThreeMFDocument)
        case failed
    }

    @State private var phase: Phase = .loading

    /// - Parameters:
    ///   - staticImage: the decoded Embedded Thumbnail to paint first, or nil
    ///     to show a neutral loading state until the scene is ready.
    ///   - parse: builds the document; run off the main thread by this view.
    public init(
        staticImage: NSImage?,
        parse: @escaping @Sendable () throws -> ThreeMFDocument
    ) {
        self.staticImage = staticImage
        self.parse = parse
    }

    public var body: some View {
        ZStack {
            base

            // The 3D scene crossfades in over the base layer once parsing
            // completes; the opaque RealityView then covers it entirely. The
            // opacity transition on insertion is what makes it fade rather than
            // pop, so the state change in `run()` is wrapped in `withAnimation`.
            if case .loaded(let document) = phase {
                Viewer(document: document)
                    .transition(.opacity)
            }
        }
        .task { await run() }
    }

    /// The layer beneath the 3D scene: the embedded image when present,
    /// otherwise a neutral loading or failure state. When parsing fails but an
    /// embedded image is present, the image simply stays — it is the graceful
    /// static fallback (the open-in-app hint for over-budget files is #10).
    @ViewBuilder
    private var base: some View {
        if let staticImage {
            Image(nsImage: staticImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        } else if phase == .failed {
            failureState
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }

    private var failureState: some View {
        ContentUnavailableView {
            Label("Can’t Read This File", systemImage: "cube.transparent")
        } description: {
            Text("This 3MF file couldn’t be opened.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func run() async {
        let parse = self.parse
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try parse()
            }.value
            withAnimation(.easeInOut(duration: 0.35)) { phase = .loaded(document) }
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) { phase = .failed }
        }
    }
}
