import Foundation
import Testing
import ThreeMFKit

/// The ParseLimits seam (issue #10): the Geometry Budget and the zip-bomb
/// caps. The Quick Look extensions parse with limits; the Host App parses
/// unlimited — same parser, same files, different policy.
@Suite struct ParseLimitsTests {

    // MARK: Geometry Budget

    @Test func overBudgetMeshFailsAsOverGeometryBudget() throws {
        // 40 vertices + 80 triangles = 120 geometry elements, budget 100.
        let url = try writeTemporaryPackage(named: "over-budget", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(boxModelXML(triangles: 80, vertices: 40).utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let limits = ParseLimits(geometryBudget: 100)
        #expect(throws: ThreeMFParseError.overGeometryBudget(budget: 100)) {
            try ThreeMFParser(limits: limits).parse(fileAt: url)
        }
    }

    @Test func underBudgetMeshParsesCompletely() throws {
        // 40 + 80 = 120 elements, budget 120: exactly at the budget is under.
        let url = try writeTemporaryPackage(named: "under-budget", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(boxModelXML(triangles: 80, vertices: 40).utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser(limits: ParseLimits(geometryBudget: 120)).parse(fileAt: url)
        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 40)
        #expect(mesh.triangleCount == 80)
    }

    @Test func vertexFloodWithoutTrianglesCountsTowardTheBudget() throws {
        // Allocation defense: vertices alone can exhaust memory, so they
        // spend budget even when no triangle references them.
        let url = try writeTemporaryPackage(named: "vertex-flood", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(boxModelXML(triangles: 0, vertices: 200).utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.overGeometryBudget(budget: 100)) {
            try ThreeMFParser(limits: ParseLimits(geometryBudget: 100)).parse(fileAt: url)
        }
    }

    @Test func budgetIsCumulativeAcrossProductionExtensionParts() throws {
        // Two referenced parts of 60 elements each: each part alone is under
        // the budget of 100, together they exceed it — the budget guards the
        // whole package's allocations, not any single part.
        let rootModel = """
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
            <resources>
            <object id="1" type="model"><components>
            <component objectid="1" p:path="/3D/Objects/a.model"/>
            <component objectid="1" p:path="/3D/Objects/b.model"/>
            </components></object>
            </resources>
            <build><item objectid="1"/></build>
            </model>
            """
        let leaf = boxModelXML(triangles: 40, vertices: 20)
        let url = try writeTemporaryPackage(named: "multi-part-budget", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(rootModel.utf8)),
            ("3D/Objects/a.model", Data(leaf.utf8)),
            ("3D/Objects/b.model", Data(leaf.utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeMFParseError.overGeometryBudget(budget: 100)) {
            try ThreeMFParser(limits: ParseLimits(geometryBudget: 100)).parse(fileAt: url)
        }
        // The Host App's policy parses the same file completely.
        let doc = try ThreeMFParser(limits: .unlimited).parse(fileAt: url)
        #expect(doc.objects.count == 3)
    }

    // MARK: Zip-bomb caps

    @Test func modelPartOverTheStreamedByteCapFailsTyped() throws {
        // A model part whose decompressed size exceeds the cap: highly
        // compressible spam that never ends in triangles — the cap, not the
        // budget, must stop it.
        var spam = """
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
            <resources>
            """
        spam += String(repeating: "<metadatagroup>" + String(repeating: " ", count: 4096) + "</metadatagroup>\n", count: 300)
        spam += "</resources><build/></model>"
        let url = try writeTemporaryPackage(named: "stream-bomb", parts: [
            ("_rels/.rels", Data(relsXML.utf8)),
            ("3D/3dmodel.model", Data(spam.utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let limits = ParseLimits(maxStreamedPartBytes: 64 * 1024)
        #expect(throws: ThreeMFParseError.decompressedPartTooLarge(partPath: "/3D/3dmodel.model")) {
            try ThreeMFParser(limits: limits).parse(fileAt: url)
        }
    }

    @Test func oversizedThumbnailPartIsIgnoredNotMaterialized() throws {
        // An OPC thumbnail relationship pointing at a multi-megabyte "PNG":
        // under the materialized-part cap the bytes are never loaded, and the
        // seam degrades to "no embedded thumbnail" instead of failing.
        let rels = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
             <Relationship Target="/Metadata/thumbnail.png" Id="rel-2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>
            </Relationships>
            """
        let url = try writeTemporaryPackage(named: "thumb-bomb", parts: [
            ("_rels/.rels", Data(rels.utf8)),
            ("3D/3dmodel.model", Data(boxModelXML(triangles: 12, vertices: 8).utf8)),
            ("Metadata/thumbnail.png", Data(repeating: 0x20, count: 2 * 1024 * 1024)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let limits = ParseLimits(maxMaterializedPartBytes: 1024 * 1024)
        #expect(try ThreeMFParser(limits: limits).embeddedThumbnail(fileAt: url) == nil)

        // Unlimited, the same part is served.
        let thumbnail = try ThreeMFParser().embeddedThumbnail(fileAt: url)
        #expect(thumbnail?.data.count == 2 * 1024 * 1024)
    }

    @Test func extensionPresetPassesTheRealCorpusFlagship() throws {
        // The extension preset must keep every legitimate corpus file
        // previewable in 3D — the budget exists for pathological files, not
        // the biggest real one we ship.
        let candidates = [
            "slicer-projects/Civilization-Atlas-Diorama-FanArt-3Dprint.3mf",
            "vanilla/cube_gears.3mf",
        ]
        for relative in candidates where Corpus.has(relative) {
            let doc = try ThreeMFParser(limits: .quickLookExtension)
                .parse(fileAt: Corpus.url(relative))
            #expect(!doc.objects.isEmpty, "\(relative) must parse under the extension preset")
        }
    }
}
