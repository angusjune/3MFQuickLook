import Foundation
import Testing
import ThreeMFKit

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
