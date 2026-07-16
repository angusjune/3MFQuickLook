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
    private static let extensionIDs = [
        "com.angusjune.ThreeMFQuickLook.PreviewExt",
        "com.angusjune.ThreeMFQuickLook.ThumbExt",
    ]

    /// A real vanilla corpus file: with the real parser, a garbage payload
    /// would (correctly) fail, so the smoke fixture must be a valid package.
    private static let corpusFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // strip ThumbnailSmokeTests.swift
        .deletingLastPathComponent()  // strip SmokeTests
        .appendingPathComponent("Corpus/vanilla/box.3mf")

    @Test(
        .timeLimit(.minutes(2)),
        .enabled(if: FileManager.default.fileExists(atPath: corpusFile.path)))
    func thumbnailForA3MFFileHasVisibleContent() async throws {
        try await registerHostApp()

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

    @Test(.timeLimit(.minutes(2)))
    func quickLookContentTypesResolveAfterHostAppRegistration() async throws {
        try await registerHostApp()

        let appURL = try #require(Self.hostAppURL)
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

    /// Launches the built Host App (a sibling of this test bundle in the build
    /// products directory) so macOS registers its Quick Look extensions, and
    /// waits until pluginkit reports both extensions.
    private func registerHostApp() async throws {
        let appURL = try #require(Self.hostAppURL)
        try #require(
            FileManager.default.fileExists(atPath: appURL.path),
            "Host App not found at \(appURL.path) — build the ThreeMFQuickLook scheme first")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        let deadline = Date().addingTimeInterval(30)
        var registered = false
        while !registered, Date() < deadline {
            registered = Self.extensionIDs.allSatisfy(pluginkitKnows)
            if !registered { try await Task.sleep(for: .milliseconds(500)) }
        }
        try #require(registered, "extensions never appeared in pluginkit -m: \(Self.extensionIDs)")
    }

    private static var hostAppURL: URL? {
        let productsDirectory = Bundle(for: BundleLocator.self).bundleURL
            .deletingLastPathComponent()
        return productsDirectory.appendingPathComponent("3MF QuickLook.app")
    }

    private func pluginkitKnows(_ identifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", identifier]
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains(identifier)
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
        guard drewImage else { return 0 }
        return Set(pixels).count
    }
}

private final class BundleLocator {}
