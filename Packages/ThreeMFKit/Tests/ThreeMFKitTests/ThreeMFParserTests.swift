import Foundation
import Testing
import ThreeMFKit

@Suite struct ThreeMFParserTests {
    @Test func parsingAMissingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).3mf")
        #expect(throws: (any Error).self) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func parsingANonZipFileThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("3mf")
        try Data("not a zip archive".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: (any Error).self) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func parsingNonZipDataThrows() {
        #expect(throws: (any Error).self) {
            try ThreeMFParser().parse(data: Data("not a zip archive".utf8))
        }
    }

    /// The Host App reads documents through `FileDocument` (bytes, not a URL);
    /// the in-memory path must yield the same document as the file path.
    @Test(.enabled(if: Corpus.has("vanilla/box.3mf")))
    func parsingDataMatchesParsingFile() throws {
        let url = Corpus.url("vanilla/box.3mf")
        let fromFile = try ThreeMFParser().parse(fileAt: url)
        let fromData = try ThreeMFParser().parse(data: Data(contentsOf: url))
        #expect(fromData == fromFile)
    }
}
