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

    /// Every pathological corpus file resolves — image or graceful refusal
    /// — and the Thumbnail Extension's lifetime peak footprint stays under
    /// the extension ceiling. The suite-level acceptance criteria of
    /// issue #10 in one pass.
    @Test(
        .timeLimit(.minutes(5)),
        .enabled(if: Smoke.hasCorpusFile("pathological/overbudget_grid.3mf")))
    func pathologicalCorpusResolvesGracefullyWithinTheMemoryCeiling() async throws {
        try await Smoke.registerHostApp()
        // Start from a fresh extension process so the measured lifetime peak
        // belongs to this batch.
        _ = try? await run("/usr/bin/pkill", ["-f", "ThumbExt"])
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

        let peaks = Smoke.thumbExtPids().compactMap(Smoke.peakFootprintMB(of:))
        let peak = peaks.max() ?? 0
        #expect(!peaks.isEmpty, "no live ThumbExt process to instrument")
        #expect(
            peak < 1324,
            "ThumbExt peak \(peak) MB is over the measured extension ceiling")
        print("ThumbExt peak footprint over the pathological corpus: \(Int(peak)) MB")
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
        let hostile = [
            "pathological/garbage_bytes.3mf", "pathological/text_stub.3mf",
            "pathological/empty.3mf", "pathological/truncated_box.3mf",
            "pathological/no_rels.3mf", "pathological/rels_no_model.3mf",
            "pathological/missing_model_part.3mf", "pathological/malformed_model_xml.3mf",
            "pathological/zipbomb_model.3mf", "pathological/zipbomb_thumbnail.3mf",
            "pathological/imagebomb_thumbnail.3mf", "pathological/billion_laughs.3mf",
            "pathological/deep_xml.3mf", "pathological/overbudget_with_thumb.3mf",
        ].filter(Smoke.hasCorpusFile)
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

    private func run(_ executable: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }
}
