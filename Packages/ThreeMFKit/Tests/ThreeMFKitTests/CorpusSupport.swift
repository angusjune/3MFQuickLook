import Foundation
import Testing
import ThreeMFKit
import ZIPFoundation

/// Locates the repo's `Corpus/` directory relative to this source file.
/// Corpus binaries are gitignored, so tests that need one skip (via
/// `.enabled(if:)`) when the file is absent instead of failing.
enum Corpus {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // strip CorpusSupport.swift
        .deletingLastPathComponent()  // strip ThreeMFKitTests
        .deletingLastPathComponent()  // strip Tests
        .deletingLastPathComponent()  // strip ThreeMFKit
        .deletingLastPathComponent()  // strip Packages
        .appendingPathComponent("Corpus")

    static func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    static func has(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relativePath).path)
    }
}

/// Writes a throwaway 3MF package from raw (path, bytes) parts, for tests
/// that need a package no real tool would write. Callers remove the file.
func writeTemporaryPackage(named name: String, parts: [(String, Data)]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("3mf")
    let archive = try Archive(url: url, accessMode: .create)
    for (path, data) in parts {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count),
            provider: { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            })
    }
    return url
}

extension Mesh {
    /// The triangle at `index` as position triplets, for spot-checking corpus
    /// geometry against ground truth.
    func triangle(_ index: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (
            positions[Int(triangleIndices[index * 3])],
            positions[Int(triangleIndices[index * 3 + 1])],
            positions[Int(triangleIndices[index * 3 + 2])]
        )
    }
}

extension ObjectResource {
    var mesh: Mesh? {
        if case .mesh(let mesh) = content { return mesh }
        return nil
    }

    var components: [Component]? {
        if case .components(let components) = content { return components }
        return nil
    }
}
