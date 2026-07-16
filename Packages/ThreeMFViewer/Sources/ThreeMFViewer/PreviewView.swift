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

    enum Phase: Equatable {
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
            // Exactly one layer per phase — see `layer(for:hasStaticImage:)`.
            // The RealityView background is transparent, so the static base
            // must leave the hierarchy when the viewer arrives or it would
            // composite into the 3D scene. The paired opacity transitions turn
            // the swap into a crossfade; the state change in `run()` is
            // wrapped in `withAnimation`.
            switch Self.layer(for: phase, hasStaticImage: staticImage != nil) {
            case .staticImage(let sceneIsLoading):
                if let staticImage {
                    Image(nsImage: staticImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            if sceneIsLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .padding(12)
                            }
                        }
                        .transition(.opacity)
                }
            case .loading:
                loadingState.transition(.opacity)
            case .failure:
                failureState.transition(.opacity)
            case .viewer(let document):
                Viewer(document: document)
                    .transition(.opacity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task { await run() }
    }

    /// Which single layer the preview shows for a phase. The viewer REPLACES
    /// the static image rather than covering it. When parsing fails but an
    /// embedded image is present, the image simply stays — it is the graceful
    /// static fallback (the open-in-app hint for over-budget files is #10).
    static func layer(for phase: Phase, hasStaticImage: Bool) -> Layer {
        switch phase {
        case .loaded(let document): .viewer(document)
        case .loading where hasStaticImage: .staticImage(sceneIsLoading: true)
        case .loading: .loading
        case .failed where hasStaticImage: .staticImage(sceneIsLoading: false)
        case .failed: .failure
        }
    }

    enum Layer: Equatable {
        /// The embedded image; `sceneIsLoading` adds the corner spinner that
        /// tells the user the interactive 3D scene is still on its way.
        case staticImage(sceneIsLoading: Bool)
        case loading
        case failure
        case viewer(ThreeMFDocument)
    }

    private var loadingState: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureState: some View {
        ContentUnavailableView {
            Label("Can’t Read This File", systemImage: "cube.transparent")
        } description: {
            Text("This 3MF file couldn’t be opened.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
