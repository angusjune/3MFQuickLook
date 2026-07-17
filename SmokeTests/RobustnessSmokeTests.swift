import AppKit
import CoreGraphics
import Foundation
import QuickLookThumbnailing
import Testing

/// End-to-end robustness (issue #10): the pathological corpus through
/// `QLThumbnailGenerator` — the API Finder uses — against the sandboxed
/// Thumbnail Extension. Every file must resolve (a real thumbnail or a
/// graceful refusal) without hanging the pipeline, and the extension's peak
/// memory must stay under its RunningBoard ceiling
/// (docs/geometry-budget.md: 1324 MB soft limit measured on this class of
/// machine).
@Suite struct RobustnessSmokeTests {

    /// The generated pathological fixtures, with whether a real thumbnail
    /// image is required (true) or a graceful refusal is acceptable (false).
    private static let pathologicalCases: [(file: String, expectsImage: Bool)] = [
        ("garbage_bytes.3mf", false),
        ("text_stub.3mf", false),
        ("empty.3mf", false),
        ("truncated_box.3mf", false),
        ("no_rels.3mf", false),
        ("rels_no_model.3mf", false),
        ("missing_model_part.3mf", false),
        ("malformed_model_xml.3mf", false),
        ("zipbomb_model.3mf", false),
        // Valid model behind a bombed thumbnail part: the mesh render must
        // still produce a real image.
        ("zipbomb_thumbnail.3mf", true),
        // Valid model behind a lying PNG header: ditto.
        ("imagebomb_thumbnail.3mf", true),
        ("billion_laughs.3mf", false),
        ("deep_xml.3mf", false),
        // Over the Geometry Budget without an Embedded Thumbnail: the
        // honest generic icon (graceful refusal), never a jetsam kill.
        ("overbudget_grid.3mf", false),
        // Over budget WITH an Embedded Thumbnail: the image must be served
        // through the cheap path — no geometry parse at all.
        ("overbudget_with_thumb.3mf", true),
    ]

    /// Requests one thumbnail through the Finder pipeline against a
    /// fresh-named copy (defeats the Quick Look cache). Returns the image,
    /// or nil for a graceful refusal (error or empty reply). A hang is
    /// caught by the calling test's time limit; a crash of the extension
    /// surfaces as a refusal for a file that requires an image.
    private func thumbnail(for relativePath: String) async throws -> CGImage? {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("robust-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        try FileManager.default.copyItem(at: Smoke.corpusFile(relativePath), to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let request = QLThumbnailGenerator.Request(
            fileAt: fixture,
            size: CGSize(width: 128, height: 128),
            scale: 1,
            representationTypes: .thumbnail)
        request.iconMode = false
        do {
            return try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request).cgImage
        } catch {
            return nil
        }
    }

    /// The regression bound on extension peak memory: the profiled design
    /// point (496 MB at exactly the Geometry Budget) plus margin, far below
    /// the 1324 MB RunningBoard soft limit — a leak fails here long before
    /// jetsam territory (docs/geometry-budget.md).
    private static let peakFootprintBoundMB = 700.0

    /// Every pathological corpus file resolves — image or graceful refusal
    /// — and the extensions' lifetime peak footprints stay within the
    /// regression bound. The suite-level acceptance criteria of issue #10
    /// in one pass.
    @Test(
        .timeLimit(.minutes(5)),
        .enabled(if: Smoke.hasCorpusFile("pathological/overbudget_grid.3mf")))
    func pathologicalCorpusResolvesGracefullyWithinTheMemoryCeiling() async throws {
        try await Smoke.registerHostApp()
        // Start from a fresh extension process so the measured lifetime peak
        // belongs to this batch.
        Smoke.killThumbExt()
        try await Task.sleep(for: .seconds(1))

        for (file, expectsImage) in Self.pathologicalCases {
            let relative = "pathological/\(file)"
            guard Smoke.hasCorpusFile(relative) else {
                Issue.record("missing fixture \(relative) — run make_pathological_fixtures.py")
                continue
            }
            let start = ContinuousClock.now
            let image = try await thumbnail(for: relative)
            let elapsed = ContinuousClock.now - start
            if expectsImage {
                #expect(image != nil, "\(file) must produce a real thumbnail")
            }
            // A refusal must be prompt, not a stall. The over-budget grid
            // legitimately parses ~4M elements (debug build) before
            // aborting; everything else refuses in moments.
            #expect(elapsed < .seconds(60), "\(file) stalled: \(elapsed)")
        }

        let thumbPeaks = Smoke.extensionPids("ThumbExt").compactMap(Smoke.peakFootprintMB(of:))
        let peak = thumbPeaks.max() ?? 0
        #expect(!thumbPeaks.isEmpty, "no live ThumbExt process to instrument")
        #expect(
            peak < Self.peakFootprintBoundMB,
            "ThumbExt peak \(peak) MB is over the regression bound")
        print("ThumbExt peak footprint over the pathological corpus: \(Int(peak)) MB")

        // The panel has no headless driver, so PreviewExt is instrumented
        // opportunistically: whenever a Finder session left one alive, it is
        // held to the same bound.
        for previewPeak in Smoke.extensionPids("PreviewExt").compactMap(Smoke.peakFootprintMB(of:)) {
            #expect(
                previewPeak < Self.peakFootprintBoundMB,
                "PreviewExt peak \(previewPeak) MB is over the regression bound")
        }
    }

    /// A folder of 50 corpus files — valid, hostile, and broken, all
    /// requested concurrently the way Finder floods a folder view — gets an
    /// answer for every file with no stall, and every valid file gets real
    /// pixels.
    @Test(
        .timeLimit(.minutes(5)),
        .enabled(if: Smoke.hasCorpusFile("vanilla/box.3mf")))
    func folderOfFiftyCorpusFilesResolvesCompletely() async throws {
        try await Smoke.registerHostApp()

        // Cycle the small corpus (valid files first — those must render).
        let valid = [
            "vanilla/box.3mf", "vanilla/torus.3mf", "vanilla/cube_gears.3mf",
            "vanilla/pyramid_vertexcolor.3mf", "vanilla/rhombicuboctahedron_color.3mf",
            "vanilla/dodeca_chain_loop_color.3mf", "vanilla/synthetic_basematerials.3mf",
            "slicer-projects/synthetic_multiplate.3mf", "slicer-projects/synthetic_painted.3mf",
            "slicer-projects/synthetic_prusa.3mf", "slicer-projects/FlightScnr.3mf",
            "sliced/synthetic_single.gcode.3mf", "sliced/synthetic_multiplate.gcode.3mf",
        ].filter(Smoke.hasCorpusFile)
        // One list of pathological fixtures — the batch test's — so a new
        // fixture joins the folder flood automatically. overbudget_grid is
        // deliberately in: the slowest refusal is exactly the stall
        // candidate this test exists to catch.
        let hostile = Self.pathologicalCases
            .map { "pathological/\($0.file)" }
            .filter(Smoke.hasCorpusFile)
        try #require(!valid.isEmpty, "no valid corpus files present")

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("robust-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var entries: [(url: URL, mustRender: Bool)] = []
        let sources = valid.map { ($0, true) } + hostile.map { ($0, false) }
        for index in 0..<50 {
            let (relative, mustRender) = sources[index % sources.count]
            let name = String(format: "%02d-", index)
                + (relative as NSString).lastPathComponent
            let target = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: Smoke.corpusFile(relative), to: target)
            entries.append((target, mustRender))
        }

        // All 50 at once — the folder-view flood.
        let failures = await withTaskGroup(
            of: (String, Bool, Bool).self, returning: [String].self
        ) { group in
            for (url, mustRender) in entries {
                group.addTask {
                    let request = QLThumbnailGenerator.Request(
                        fileAt: url, size: CGSize(width: 128, height: 128),
                        scale: 1, representationTypes: .thumbnail)
                    request.iconMode = false
                    let image = try? await QLThumbnailGenerator.shared
                        .generateBestRepresentation(for: request).cgImage
                    return (url.lastPathComponent, mustRender, image != nil)
                }
            }
            var failures: [String] = []
            for await (name, mustRender, rendered) in group
            where mustRender && !rendered {
                failures.append(name)
            }
            return failures
        }
        #expect(failures.isEmpty, "valid files without thumbnails: \(failures)")
    }
}
