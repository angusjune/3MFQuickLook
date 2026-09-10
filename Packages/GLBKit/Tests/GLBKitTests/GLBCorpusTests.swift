import Foundation
import Testing
@testable import GLBKit

/// Real exporter output, which is where the hand-built fixtures stop being
/// convincing: interleaved buffers, embedded PBR texture sets, and — in the
/// skinned case — a mesh whose vertices only make sense in its bind pose.
@Suite struct GLBCorpusTests {
    @Test(.enabled(if: Corpus.has("glb/textured-scene.glb")))
    func parsesATexturedSceneExport() throws {
        let document = try GLBParser().parse(fileAt: Corpus.url("glb/textured-scene.glb"))

        #expect(!document.rootNodeIndices.isEmpty)
        #expect(document.sceneMetrics().triangleCount > 0)
        // Only base-color maps are carried, so the document holds fewer
        // images than the file's full PBR texture set.
        #expect(document.images.count <= document.materials.count)
        #expect(document.materials.contains { $0.baseColorImageIndex != nil })
    }

    /// A skinned, animated character previews in its bind pose: the parse
    /// reads past the skin and the animation channels rather than failing.
    @Test(.enabled(if: Corpus.has("glb/skinned-figure.glb")))
    func parsesASkinnedAnimatedCharacter() throws {
        let document = try GLBParser().parse(fileAt: Corpus.url("glb/skinned-figure.glb"))
        let metrics = document.sceneMetrics()

        #expect(metrics.meshCount >= 1)
        #expect(metrics.triangleCount > 0)
        #expect(metrics.sizeMeters != nil)
    }

    /// The extensions' policy on the same files: either they parse inside
    /// the Geometry Budget, or they report exactly that — never anything
    /// else.
    @Test(.enabled(if: Corpus.has("glb/textured-scene.glb")))
    func corpusFilesParseOrReportTheBudget() throws {
        do {
            _ = try GLBParser(limits: .quickLookExtension)
                .parse(fileAt: Corpus.url("glb/textured-scene.glb"))
        } catch GLBParseError.overGeometryBudget {
            // Acceptable: the preview falls back to the open-in-app hint.
        }
    }
}
