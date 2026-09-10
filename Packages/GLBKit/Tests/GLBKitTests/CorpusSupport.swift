import Foundation

/// Locates the repo's `Corpus/` directory relative to this source file.
/// Corpus binaries are gitignored, so tests that need one skip (via
/// `.enabled(if:)`) when the file is absent instead of failing — the same
/// arrangement the 3MF suite uses.
enum Corpus {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // strip CorpusSupport.swift
        .deletingLastPathComponent()  // strip GLBKitTests
        .deletingLastPathComponent()  // strip Tests
        .deletingLastPathComponent()  // strip GLBKit
        .deletingLastPathComponent()  // strip Packages
        .appendingPathComponent("Corpus")

    static func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    static func has(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relativePath).path)
    }
}
