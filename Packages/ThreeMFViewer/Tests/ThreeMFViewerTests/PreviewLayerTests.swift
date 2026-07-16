import Testing
import ThreeMFKit
@testable import ThreeMFViewer

/// Locks the static-then-3D handoff contract (issue #5): the preview shows
/// exactly one layer per phase. In particular, once the document is loaded the
/// viewer must be the ONLY layer — the RealityView background is transparent,
/// so a static thumbnail left beneath it composites into the 3D scene
/// (regression: overlapped thumbnail and geometry on slicer projects with
/// transparent plate thumbnails).
@Suite struct PreviewLayerTests {
    private static let document = ThreeMFDocument()

    @Test func loadedShowsOnlyTheViewerEvenWithAStaticImage() {
        #expect(
            PreviewView.layer(for: .loaded(Self.document), hasStaticImage: true)
                == .viewer(Self.document))
    }

    @Test func loadedShowsTheViewerWithoutAStaticImage() {
        #expect(
            PreviewView.layer(for: .loaded(Self.document), hasStaticImage: false)
                == .viewer(Self.document))
    }

    @Test func loadingShowsTheStaticImageWithASceneLoadingIndicator() {
        #expect(
            PreviewView.layer(for: .loading, hasStaticImage: true)
                == .staticImage(sceneIsLoading: true))
    }

    @Test func loadingShowsTheNeutralStateWithoutAStaticImage() {
        #expect(PreviewView.layer(for: .loading, hasStaticImage: false) == .loading)
    }

    @Test func failureKeepsTheStaticImageWithoutALoadingIndicator() {
        #expect(
            PreviewView.layer(for: .failed, hasStaticImage: true)
                == .staticImage(sceneIsLoading: false))
    }

    @Test func failureShowsTheFailureStateWithoutAStaticImage() {
        #expect(PreviewView.layer(for: .failed, hasStaticImage: false) == .failure)
    }

    // Sliced Files (issue #8) route to their own layer — never the 3D
    // viewer, whatever the static image situation.

    @Test func loadedSlicedFileShowsTheSlicedLayerWithAStaticImage() {
        let document = ThreeMFDocument(isSlicedFile: true)
        #expect(
            PreviewView.layer(for: .loaded(document), hasStaticImage: true)
                == .slicedFile(document))
    }

    @Test func loadedSlicedFileShowsTheSlicedLayerWithoutAStaticImage() {
        let document = ThreeMFDocument(isSlicedFile: true)
        #expect(
            PreviewView.layer(for: .loaded(document), hasStaticImage: false)
                == .slicedFile(document))
    }
}
