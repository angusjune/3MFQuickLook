import Foundation
import Testing
import ThreeMFKit

/// Robustness seam (issue #10): whatever the bytes, the parse seam returns a
/// typed ``ThreeMFParseError`` — never a crash, never a hang. Covers the
/// malformed-input layer here; the Geometry Budget and zip-bomb caps join in
/// the ParseLimits tests below.
@Suite struct RobustnessSeamTests {

    /// Writes raw bytes to a throwaway `.3mf` path — the not-actually-a-zip
    /// corpus shapes (garbage, text stubs, truncations) that
    /// `writeTemporaryPackage` can't produce because it always writes a real
    /// archive.
    private func writeRawFile(named name: String, bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        try bytes.write(to: url)
        return url
    }

    // MARK: Malformed input → typed failures

    @Test func garbageBytesFailAsUnreadableArchive() throws {
        let url = try writeRawFile(
            named: "garbage", bytes: Data((0..<4096).map { _ in UInt8.random(in: 0...255) }))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.self) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func fifteenByteTextStubFailsAsUnreadableArchive() throws {
        let url = try writeRawFile(named: "stub", bytes: Data("not a 3mf file\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try ThreeMFParser().parse(fileAt: url)
            Issue.record("text stub parsed as a package")
        } catch let error as ThreeMFParseError {
            guard case .unreadableArchive = error else {
                Issue.record("expected unreadableArchive, got \(error)")
                return
            }
        }
    }

    @Test func emptyFileFailsAsUnreadableArchive() throws {
        let url = try writeRawFile(named: "empty", bytes: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try ThreeMFParser().parse(fileAt: url)
            Issue.record("empty file parsed as a package")
        } catch let error as ThreeMFParseError {
            guard case .unreadableArchive = error else {
                Issue.record("expected unreadableArchive, got \(error)")
                return
            }
        }
    }

    @Test func truncatedArchiveFailsTyped() throws {
        // A real package cut mid-stream: the central directory is gone, so the
        // bytes stop being a zip at all.
        let intact = try writeTemporaryPackage(named: "to-truncate", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(boxModelXML(triangles: 12, vertices: 8).utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: intact) }
        let full = try Data(contentsOf: intact)
        let url = try writeRawFile(named: "truncated", bytes: full.prefix(full.count / 2))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.self) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func archiveWithoutRelationshipsFailsAsMissingRootModel() throws {
        let url = try writeTemporaryPackage(named: "no-rels", parts: [
            ("3D/3dmodel.model", Data(boxModelXML(triangles: 12, vertices: 8).utf8))
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.missingRootModel) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func relationshipsWithoutModelEntryFailAsMissingRootModel() throws {
        let rels = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/Metadata/thumbnail.png" Id="rel-1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>
            </Relationships>
            """
        let url = try writeTemporaryPackage(named: "rels-no-model", parts: [
            ("_rels/.rels", Data(rels.utf8))
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.missingRootModel) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func relationshipToAbsentPartFailsAsMissingModelPart() throws {
        let url = try writeTemporaryPackage(named: "missing-part", parts: [
            ("_rels/.rels", Data(relsXML.utf8))
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.missingModelPart("/3D/3dmodel.model")) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func malformedModelXMLFailsTyped() throws {
        let url = try writeTemporaryPackage(named: "bad-xml", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data("<model><resources><object".utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.malformedModelXML(partPath: "/3D/3dmodel.model")) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func kilometerDeepNestingFailsAsMalformedForEveryPolicy() throws {
        // Depth is a structural allocation cap, enforced even unlimited —
        // each nesting level allocates in libxml2's name stack and ours,
        // and no real model part nests past a handful of levels.
        let deep = "<?xml version=\"1.0\"?>\n"
            + "<model xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\">"
            + String(repeating: "<a>", count: 2000)
            + String(repeating: "</a>", count: 2000)
            + "</model>"
        let url = try writeTemporaryPackage(named: "deep", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(deep.utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.malformedModelXML(partPath: "/3D/3dmodel.model")) {
            try ThreeMFParser().parse(fileAt: url)
        }
    }

    @Test func embeddedThumbnailOfGarbageFailsTypedNotCrashing() throws {
        let url = try writeRawFile(
            named: "garbage-thumb", bytes: Data(repeating: 0x50, count: 1024))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.self) {
            try ThreeMFParser().embeddedThumbnail(fileAt: url)
        }
    }
}

// MARK: - Shared fixture XML

let relsXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
     <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
    </Relationships>
    """

/// A well-formed one-object model part with exactly `vertices` vertices and
/// `triangles` triangles (indices cycle through the vertices; geometric
/// nonsense is fine — the seam under test counts, it doesn't render).
func boxModelXML(triangles: Int, vertices: Int) -> String {
    var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
        <resources><object id="1" type="model"><mesh><vertices>
        """
    for i in 0..<vertices {
        xml += "<vertex x=\"\(i)\" y=\"\(i % 7)\" z=\"\(i % 13)\"/>\n"
    }
    xml += "</vertices><triangles>\n"
    for i in 0..<triangles {
        let v1 = i % vertices
        let v2 = (i + 1) % vertices
        let v3 = (i + 2) % vertices
        xml += "<triangle v1=\"\(v1)\" v2=\"\(v2)\" v3=\"\(v3)\"/>\n"
    }
    xml += """
        </triangles></mesh></object></resources>
        <build><item objectid="1"/></build>
        </model>
        """
    return xml
}
