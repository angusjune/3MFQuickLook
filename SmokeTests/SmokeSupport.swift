import AppKit
import Darwin
import Foundation
import Testing

/// Shared plumbing for the end-to-end smoke suites: locating the corpus and
/// the built Host App, registering its Quick Look extensions, and reading
/// extension-process memory peaks.
enum Smoke {
    static let extensionIDs = [
        "com.angusjune.ThreeMFQuickLook.PreviewExt",
        "com.angusjune.ThreeMFQuickLook.ThumbExt",
    ]

    static let corpusRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // strip SmokeSupport.swift
        .deletingLastPathComponent()  // strip SmokeTests
        .appendingPathComponent("Corpus")

    static func corpusFile(_ relativePath: String) -> URL {
        corpusRoot.appendingPathComponent(relativePath)
    }

    static func hasCorpusFile(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: corpusFile(relativePath).path)
    }

    static var hostAppURL: URL? {
        let productsDirectory = Bundle(for: BundleLocator.self).bundleURL
            .deletingLastPathComponent()
        return productsDirectory.appendingPathComponent("3MF QuickLook.app")
    }

    /// Launches the built Host App (a sibling of this test bundle in the build
    /// products directory) so macOS registers its Quick Look extensions, and
    /// waits until pluginkit reports both extensions.
    static func registerHostApp() async throws {
        let appURL = try #require(hostAppURL)
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
            registered = extensionIDs.allSatisfy(pluginkitKnows)
            if !registered { try await Task.sleep(for: .milliseconds(500)) }
        }
        try #require(registered, "extensions never appeared in pluginkit -m: \(extensionIDs)")
    }

    static func pluginkitKnows(_ identifier: String) -> Bool {
        (output(of: "/usr/bin/pluginkit", ["-m", "-i", identifier]) ?? "")
            .contains(identifier)
    }

    /// All live ThumbExt process ids.
    static func thumbExtPids() -> [pid_t] {
        (output(of: "/usr/bin/pgrep", ["ThumbExt"]) ?? "")
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The process's lifetime peak physical footprint in MB — the same
    /// counter `threemf-bench` reports for itself, read cross-process
    /// (issue #10's instrumentation). Nil when the pid is gone or unreadable.
    static func peakFootprintMB(of pid: pid_t) -> Double? {
        var usage = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0 else { return nil }
        return Double(usage.ri_lifetime_max_phys_footprint) / 1_048_576
    }

    private static func output(of executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private final class BundleLocator {}
