import AppKit
import CoreGraphics
import Foundation
import QuickLookThumbnailing
import Testing
import UniformTypeIdentifiers

/// End-to-end smoke: requests a `.3mf` thumbnail through `QLThumbnailGenerator`
/// — the API Finder uses — and asserts real pixels came back from the sandboxed
/// Thumbnail Extension.
///
/// Never probe via `qlmanage -t`: it hangs against extension-based providers
/// (prototype finding).
@Suite struct ThumbnailSmokeTests {
    /// A real vanilla corpus file: with the real parser, a garbage payload
    /// would (correctly) fail, so the smoke fixture must be a valid package.
    private static let corpusFile = Smoke.corpusFile("vanilla/box.3mf")

    /// The painted fixture (issue #9) carries no embedded Plate Thumbnail,
    /// so its thumbnail must come from the mesh-render fallback — the
    /// surface the paint-color acceptance criterion names.
    private static let paintedCorpusFile = Smoke.corpusFile("slicer-projects/synthetic_painted.3mf")

    @Test(
        .timeLimit(.minutes(2)),
        .enabled(if: FileManager.default.fileExists(atPath: corpusFile.path)))
    func thumbnailForA3MFFileHasVisibleContent() async throws {
        try await Smoke.registerHostApp()

        // Copied to a fresh name so Quick Look can't serve a stale cache.
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoke-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        try FileManager.default.copyItem(at: Self.corpusFile, to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let request = QLThumbnailGenerator.Request(
            fileAt: fixture,
            size: CGSize(width: 256, height: 256),
            scale: 2,
            representationTypes: .thumbnail)
        request.iconMode = false

        let representation = try await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)

        let image = representation.cgImage
        #expect(image.width > 0)
        #expect(
            distinctPixelValueCount(in: image) > 1,
            "thumbnail should not be a uniform blank")
    }

    /// Issue #9: paint colors reach the mesh-render fallback thumbnail. The
    /// fixture's cube (base filament yellow, faces painted red and green
    /// among others) must produce clearly red, green, and yellow pixels —
    /// hue presence, not pixel comparison.
    @Test(
        .timeLimit(.minutes(2)),
        .enabled(if: FileManager.default.fileExists(atPath: paintedCorpusFile.path)))
    func paintedModelThumbnailShowsItsPaintColors() async throws {
        try await Smoke.registerHostApp()

        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoke-painted-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        try FileManager.default.copyItem(at: Self.paintedCorpusFile, to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let request = QLThumbnailGenerator.Request(
            fileAt: fixture,
            size: CGSize(width: 256, height: 256),
            scale: 2,
            representationTypes: .thumbnail)
        request.iconMode = false

        let representation = try await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)

        let pixels = rgbaPixels(of: representation.cgImage)
        func hueCount(_ isHue: (UInt32, UInt32, UInt32) -> Bool) -> Int {
            pixels.count { pixel in
                isHue(pixel & 0xFF, (pixel >> 8) & 0xFF, (pixel >> 16) & 0xFF)
            }
        }
        let red = hueCount { r, g, b in r > 120 && r > 2 * g && r > 2 * b }
        let green = hueCount { r, g, b in g > 120 && g > 2 * r && g > 2 * b }
        let yellow = hueCount { r, g, b in r > 120 && g > 120 && 2 * b < r && 2 * b < g }
        #expect(red > 100, "painted red face missing from the thumbnail")
        #expect(green > 100, "painted green face missing from the thumbnail")
        #expect(yellow > 100, "base-filament yellow faces missing from the thumbnail")
    }

    /// Regression: the reply's drawing block filled a rect measured in points
    /// while the reply context's user space carries the request's scale, so a
    /// scale-2 request drew the render into the lower-left quarter of the
    /// frame (Core Graphics' origin is bottom-left) and Finder showed a small,
    /// corner-pinned thumbnail. Asserted per quadrant rather than as a
    /// bounding box because the bitmap's row order is not part of the
    /// contract: under the bug three of the four quadrants were empty
    /// whichever way up the buffer is read.
    @Test(
        .timeLimit(.minutes(2)),
        .enabled(if: FileManager.default.fileExists(atPath: corpusFile.path)))
    func thumbnailFillsTheWholeFrameAtRetinaScale() async throws {
        try await Smoke.registerHostApp()

        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoke-fill-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        try FileManager.default.copyItem(at: Self.corpusFile, to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        // scale 2 is what triggered the bug: at scale 1 the points-sized rect
        // happened to cover the whole context, so the fault stayed invisible.
        let request = QLThumbnailGenerator.Request(
            fileAt: fixture,
            size: CGSize(width: 256, height: 256),
            scale: 2,
            representationTypes: .thumbnail)
        request.iconMode = false

        let representation = try await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        let image = representation.cgImage
        let pixels = rgbaPixels(of: image)
        try #require(!pixels.isEmpty)

        let width = image.width
        let height = image.height
        func drawnFraction(xRange: Range<Int>, yRange: Range<Int>) -> Double {
            var drawn = 0
            for y in yRange {
                for x in xRange where (pixels[y * width + x] >> 24) & 0xFF > 8 {
                    drawn += 1
                }
            }
            return Double(drawn) / Double(xRange.count * yRange.count)
        }

        let left = 0..<(width / 2), right = (width / 2)..<width
        let top = 0..<(height / 2), bottom = (height / 2)..<height
        for (name, xs, ys) in [
            ("left/top", left, top), ("right/top", right, top),
            ("left/bottom", left, bottom), ("right/bottom", right, bottom),
        ] {
            #expect(
                drawnFraction(xRange: xs, yRange: ys) > 0.1,
                "\(name) quadrant is blank — the render is not filling the thumbnail frame")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func quickLookContentTypesResolveAfterHostAppRegistration() async throws {
        try await Smoke.registerHostApp()

        let appURL = try #require(Smoke.hostAppURL)
        let metadataContentType = spotlightContentType(of: Self.corpusFile)
        for extensionName in ["PreviewExt", "ThumbExt"] {
            let infoURL = appURL
                .appendingPathComponent("Contents/PlugIns")
                .appendingPathComponent("\(extensionName).appex")
                .appendingPathComponent("Contents/Info.plist")
            let data = try Data(contentsOf: infoURL)
            let plist = try #require(
                PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    as? [String: Any])
            let extensionInfo = try #require(plist["NSExtension"] as? [String: Any])
            let attributes = try #require(
                extensionInfo["NSExtensionAttributes"] as? [String: Any])
            let identifiers = try #require(attributes["QLSupportedContentTypes"] as? [String])

            for identifier in identifiers {
                #expect(
                    UTType(identifier) != nil,
                    "\(extensionName) declares an invalid Quick Look content type: \(identifier)")
            }

            if let metadataContentType {
                #expect(
                    identifiers.contains(metadataContentType),
                    "\(extensionName) must support Finder's metadata content type: \(metadataContentType)")
            }

            if extensionName == "PreviewExt" {
                #expect(
                    attributes["QLIsDataBasedPreview"] as? Bool == false,
                    "PreviewExt must be declared as a view-based Quick Look preview")
            }
        }
    }

    private func spotlightContentType(of url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-raw", "-name", "kMDItemContentType", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty, output != "(null)" else { return nil }
        return output
    }

    private func distinctPixelValueCount(in image: CGImage) -> Int {
        Set(rgbaPixels(of: image)).count
    }

    /// The image as RGBA8 pixel values, red in the low byte; empty when the
    /// image can't be drawn.
    private func rgbaPixels(of image: CGImage) -> [UInt32] {
        let width = image.width
        let height = image.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drewImage ? pixels : []
    }
}
