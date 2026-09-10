import AppKit
import GLBKit
import SwiftUI
import ThreeMFKit

/// The "instant first paint" preview (issue #5): paints the Embedded Thumbnail
/// immediately, parses geometry off the main thread, then crossfades to the
/// interactive ``Viewer`` when the scene is ready. Files with no embedded
/// image show a neutral loading state instead, then crossfade the same way.
/// There is no blank panel at any point. Sliced Files crossfade to
/// ``SlicedFileView`` instead — Plate Thumbnails and print metadata, never
/// a 3D scene (issue #8).
///
/// Shared by the Preview Extension and the Host App, and by both formats:
/// each surface hands it a pre-extracted static image and a parse closure,
/// and the closure decides which format it is reading. GLB files simply
/// never have a static image — glTF has no thumbnail convention — so they
/// take the neutral loading state on the way to the 3D scene.
public struct PreviewView: View {
    private let staticImage: NSImage?
    private let parse: @Sendable () throws -> ModelDocument

    enum Phase: Equatable {
        case loading
        case loaded(ModelDocument)
        case failed
        /// The package's geometry exceeds the Geometry Budget (issue #10):
        /// the preview never attempts 3D and points at the Host App instead.
        case overBudget
    }

    @State private var phase: Phase = .loading

    /// - Parameters:
    ///   - staticImage: the decoded Embedded Thumbnail to paint first, or nil
    ///     to show a neutral loading state until the scene is ready.
    ///   - parse: builds the document; run off the main thread by this view.
    public init(
        staticImage: NSImage?,
        parse: @escaping @Sendable () throws -> ModelDocument
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
            case .overBudget(staticImage: true):
                if let staticImage {
                    Image(nsImage: staticImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) { openInAppHint }
                        .transition(.opacity)
                }
            case .overBudget(staticImage: false):
                overBudgetState.transition(.opacity)
            case .viewer(let document):
                Viewer(document: document)
                    .transition(.opacity)
            case .slicedFile(let document):
                SlicedFileView(document: document)
                    .transition(.opacity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task { await run() }
    }

    /// Which single layer the preview shows for a phase. The viewer REPLACES
    /// the static image rather than covering it. When parsing fails but an
    /// embedded image is present, the image simply stays — it is the graceful
    /// static fallback.
    static func layer(for phase: Phase, hasStaticImage: Bool) -> Layer {
        switch phase {
        case .loaded(.threeMF(let document)) where document.isSlicedFile:
            .slicedFile(document)
        case .loaded(let document): .viewer(document)
        case .loading where hasStaticImage: .staticImage(sceneIsLoading: true)
        case .loading: .loading
        case .failed where hasStaticImage: .staticImage(sceneIsLoading: false)
        case .failed: .failure
        case .overBudget: .overBudget(staticImage: hasStaticImage)
        }
    }

    /// The phase a parse failure lands in: only the Geometry Budget breach
    /// earns the over-budget hint — the file is fine, it is just too big for
    /// the extension. Everything else is an honest failure. Both parsers
    /// report the budget in their own error type; both mean the same thing
    /// here.
    static func failurePhase(for error: Error) -> Phase {
        ModelLoader.isOverGeometryBudget(error) ? .overBudget : .failed
    }

    enum Layer: Equatable {
        /// The embedded image; `sceneIsLoading` adds the corner spinner that
        /// tells the user the interactive 3D scene is still on its way.
        case staticImage(sceneIsLoading: Bool)
        case loading
        case failure
        case viewer(ModelDocument)
        /// Sliced Files never reach the 3D viewer — their honest preview is
        /// the Plate Thumbnails plus print metadata.
        case slicedFile(ThreeMFDocument)
        /// Over the Geometry Budget (issue #10): the Embedded Thumbnail with
        /// the open-in-app hint, or the hint alone when there is no image.
        case overBudget(staticImage: Bool)
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
            Text("This file couldn’t be opened.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overBudgetState: some View {
        ContentUnavailableView {
            Label("Too Detailed for Quick Look", systemImage: "cube.transparent")
        } description: {
            Text("Open in 3MF QuickLook to view the full model.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The discreet over-budget hint in the image corner — same visual
    /// posture as the loading spinner it replaces.
    private var openInAppHint: some View {
        Text("Open in 3MF QuickLook")
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
    }

    private func run() async {
        let parse = self.parse
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try parse()
            }.value
            withAnimation(.easeInOut(duration: 0.35)) { phase = .loaded(document) }
        } catch {
            let failure = Self.failurePhase(for: error)
            withAnimation(.easeInOut(duration: 0.2)) { phase = failure }
        }
    }
}
