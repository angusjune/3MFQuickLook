import Foundation
import Testing
@testable import GLBKit

/// The container seam: what the parser accepts as a GLB at all. Everything
/// here arrives as an untrusted download, so each case is a header that lies
/// in a different way.
@Suite struct GLBContainerTests {
    @Test func nonGLBBytesAreRejected() {
        #expect(throws: GLBParseError.notBinaryGLTF) {
            try GLBParser().parse(data: Data("not a glb at all".utf8))
        }
    }

    /// A text `.gltf` file is JSON, not this container — it must fail as
    /// "not a GLB", not as malformed JSON.
    @Test func textGLTFIsRejectedAsNonGLB() {
        #expect(throws: GLBParseError.notBinaryGLTF) {
            try GLBParser().parse(data: Data(#"{"asset":{"version":"2.0"}}"#.utf8))
        }
    }

    @Test func emptyDataIsRejected() {
        #expect(throws: GLBParseError.truncatedContainer) {
            try GLBParser().parse(data: Data())
        }
    }

    @Test func glTF1IsRejectedByVersion() {
        let data = GLBBuilder.triangle()
        var version1 = data
        version1.replaceSubrange(4..<8, with: [1, 0, 0, 0])
        #expect(throws: GLBParseError.unsupportedVersion(1)) {
            try GLBParser().parse(data: version1)
        }
    }

    /// A chunk header claiming more bytes than the file holds must not read
    /// past the end.
    @Test func truncatedChunkIsRejected() {
        let data = GLBBuilder.triangle()
        let truncated = data.prefix(data.count / 2)
        #expect(throws: GLBParseError.truncatedContainer) {
            try GLBParser().parse(data: Data(truncated))
        }
    }

    @Test func headerWithoutChunksIsRejected() {
        var header = Data()
        header.append(contentsOf: [0x67, 0x6C, 0x54, 0x46])  // "glTF"
        header.append(contentsOf: [2, 0, 0, 0])
        header.append(contentsOf: [12, 0, 0, 0])
        #expect(throws: GLBParseError.missingJSONChunk) {
            try GLBParser().parse(data: header)
        }
    }

    /// The JSON cap is a bomb guard: a small file must never be able to
    /// declare a gigabyte of scene description.
    @Test func oversizedJSONChunkIsRejected() {
        let limits = GLBParseLimits(maxJSONBytes: 16)
        #expect(throws: GLBParseError.jsonChunkTooLarge(limit: 16)) {
            try GLBParser(limits: limits).parse(data: GLBBuilder.triangle())
        }
    }

    @Test func malformedJSONReportsTheOffendingKey() {
        let data = GLBBuilder.glb(json: ["accessors": [["componentType": "float"]]])
        #expect(throws: (any Error).self) {
            try GLBParser().parse(data: data)
        }
        do {
            _ = try GLBParser().parse(data: data)
        } catch GLBParseError.malformedJSON(let message) {
            #expect(message.contains("componentType"))
        } catch {
            Issue.record("expected malformedJSON, got \(error)")
        }
    }

    /// Unknown chunk types are reserved for future use; the spec says skip
    /// them, and a file that carries one still previews.
    @Test func unknownChunksAreSkipped() throws {
        var data = GLBBuilder.triangle()
        var extra = Data()
        extra.append(contentsOf: [4, 0, 0, 0])
        extra.append(contentsOf: [0x58, 0x58, 0x58, 0x58])  // "XXXX"
        extra.append(contentsOf: [0, 0, 0, 0])
        let total = UInt32(data.count + extra.count)
        data.append(extra)
        data.replaceSubrange(8..<12, with: withUnsafeBytes(of: total.littleEndian) { Data($0) })

        let document = try GLBParser().parse(data: data)
        #expect(document.meshes.count == 1)
    }
}
