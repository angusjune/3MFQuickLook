import Foundation
import Testing
import ThreeMFKit

/// The pathological corpus (issue #10) against the parse seam, under the
/// extensions' own limits: every hostile or broken file must produce a typed
/// failure (or lenient degradation) in bounded time — no crash, no runaway
/// decompression, no unbounded allocation. Fixtures come from
/// `Corpus/tools/make_pathological_fixtures.py`.
@Suite struct PathologicalCorpusTests {

    private static let limits = ParseLimits.quickLookExtension

    private func expectTypedFailure(
        _ relative: String,
        within seconds: Double = 10,
        matching: (ThreeMFParseError) -> Bool = { _ in true }
    ) {
        let start = ContinuousClock.now
        do {
            _ = try ThreeMFParser(limits: Self.limits).parse(fileAt: Corpus.url(relative))
            Issue.record("\(relative) parsed — expected a typed failure")
        } catch let error as ThreeMFParseError {
            #expect(matching(error), "\(relative): unexpected typed error \(error)")
        } catch {
            Issue.record("\(relative) threw an untyped error: \(error)")
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(seconds), "\(relative) took \(elapsed) — not bounded")
    }

    @Test(.enabled(if: Corpus.has("pathological/garbage_bytes.3mf")))
    func garbageBytes() {
        expectTypedFailure("pathological/garbage_bytes.3mf") {
            if case .unreadableArchive = $0 { return true } else { return false }
        }
    }

    @Test(.enabled(if: Corpus.has("pathological/text_stub.3mf")))
    func textStub() {
        expectTypedFailure("pathological/text_stub.3mf") {
            if case .unreadableArchive = $0 { return true } else { return false }
        }
    }

    @Test(.enabled(if: Corpus.has("pathological/empty.3mf")))
    func emptyFile() {
        expectTypedFailure("pathological/empty.3mf") {
            if case .unreadableArchive = $0 { return true } else { return false }
        }
    }

    @Test(.enabled(if: Corpus.has("pathological/truncated_box.3mf")))
    func truncatedArchive() {
        expectTypedFailure("pathological/truncated_box.3mf")
    }

    @Test(.enabled(if: Corpus.has("pathological/no_rels.3mf")))
    func archiveWithoutRels() {
        expectTypedFailure("pathological/no_rels.3mf") { $0 == .missingRootModel }
    }

    @Test(.enabled(if: Corpus.has("pathological/rels_no_model.3mf")))
    func relsWithoutModelEntry() {
        expectTypedFailure("pathological/rels_no_model.3mf") { $0 == .missingRootModel }
    }

    @Test(.enabled(if: Corpus.has("pathological/missing_model_part.3mf")))
    func missingModelPart() {
        expectTypedFailure("pathological/missing_model_part.3mf") {
            $0 == .missingModelPart("/3D/3dmodel.model")
        }
    }

    @Test(.enabled(if: Corpus.has("pathological/malformed_model_xml.3mf")))
    func malformedModelXML() {
        expectTypedFailure("pathological/malformed_model_xml.3mf") {
            $0 == .malformedModelXML(partPath: "/3D/3dmodel.model")
        }
    }

    // MARK: Hostile input

    @Test(.enabled(if: Corpus.has("pathological/zipbomb_model.3mf")))
    func zipBombModelPartHitsTheStreamedCap() {
        // ~600 MB decompressed from a ~750 KB archive: the 512 MB streamed
        // cap must cut it off, in bounded time and memory.
        expectTypedFailure("pathological/zipbomb_model.3mf", within: 30) {
            $0 == .decompressedPartTooLarge(partPath: "/3D/3dmodel.model")
        }
    }

    @Test(.enabled(if: Corpus.has("pathological/zipbomb_thumbnail.3mf")))
    func zipBombThumbnailIsNeverMaterialized() throws {
        // The 128 MB "PNG" dies at the 64 MB materialized cap — no embedded
        // thumbnail — while the honest model part keeps its 3D preview.
        let url = Corpus.url("pathological/zipbomb_thumbnail.3mf")
        #expect(try ThreeMFParser(limits: Self.limits).embeddedThumbnail(fileAt: url) == nil)

        let doc = try ThreeMFParser(limits: Self.limits).parse(fileAt: url)
        #expect(doc.objects.first?.mesh?.triangleCount == 12)
    }

    @Test(.enabled(if: Corpus.has("pathological/imagebomb_thumbnail.3mf")))
    func imageBombPassesTheParseSeamIntact() throws {
        // The gigapixel lie lives in the PNG header, not the zip: the parse
        // seam serves the (tiny) bytes and the decode seam rejects them —
        // PackageImageDecoderTests owns that half of the defense.
        let url = Corpus.url("pathological/imagebomb_thumbnail.3mf")
        let thumbnail = try #require(
            try ThreeMFParser(limits: Self.limits).embeddedThumbnail(fileAt: url))
        #expect(thumbnail.data.count < 1024)
    }

    @Test(.enabled(if: Corpus.has("pathological/billion_laughs.3mf")))
    func billionLaughsFailsFast() {
        expectTypedFailure("pathological/billion_laughs.3mf")
    }

    @Test(.enabled(if: Corpus.has("pathological/deep_xml.3mf")))
    func deeplyNestedXMLFailsFast() {
        expectTypedFailure("pathological/deep_xml.3mf")
    }

    // MARK: Over the Geometry Budget

    @Test(
        .timeLimit(.minutes(2)),
        .enabled(if: Corpus.has("pathological/overbudget_grid.3mf")))
    func overBudgetFileFailsTypedForExtensionsAndParsesForTheHostApp() throws {
        let url = Corpus.url("pathological/overbudget_grid.3mf")

        // The extensions' answer: a typed budget breach, promptly.
        expectTypedFailure("pathological/overbudget_grid.3mf", within: 60) {
            $0 == .overGeometryBudget(budget: 4_000_000)
        }

        // The Host App's answer: the same file, loaded completely.
        let doc = try ThreeMFParser(limits: .unlimited).parse(fileAt: url)
        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.triangleCount + mesh.positions.count > 4_000_000)
    }
}
