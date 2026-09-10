import Testing
import ThreeMFKit
@testable import ModelViewer

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

    // Over-budget files (issue #10) never attempt 3D: the Embedded
    // Thumbnail stays up with the open-in-app hint, or the hint stands
    // alone when the package carries no image.

    @Test func overBudgetKeepsTheStaticImageWithTheOpenInAppHint() {
        #expect(
            PreviewView.layer(for: .overBudget, hasStaticImage: true)
                == .overBudget(staticImage: true))
    }

    @Test func overBudgetShowsTheHintMessageWithoutAStaticImage() {
        #expect(
            PreviewView.layer(for: .overBudget, hasStaticImage: false)
                == .overBudget(staticImage: false))
    }

    // The phase a parse failure lands in: only the Geometry Budget breach
    // routes to the over-budget hint — corrupt files keep the honest
    // failure message.

    @Test func overGeometryBudgetErrorBecomesTheOverBudgetPhase() {
        let error = ThreeMFParseError.overGeometryBudget(budget: 4_000_000)
        #expect(PreviewView.failurePhase(for: error) == .overBudget)
    }

    @Test func otherParseErrorsBecomeTheFailedPhase() {
        let error = ThreeMFParseError.unreadableArchive("not a zip")
        #expect(PreviewView.failurePhase(for: error) == .failed)
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
