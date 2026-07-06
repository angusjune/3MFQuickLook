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
}
