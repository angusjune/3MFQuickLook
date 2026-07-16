import Foundation
import Testing
import ThreeMFKit

/// Parse-seam tests for Embedded Thumbnail extraction (issue #5): given this
/// package, the parser yields this embedded image — cheaply, without parsing
/// geometry. Corpus ground truth comes from independent inspection
/// (`unzip -l` / `unzip -p … _rels/.rels`), not from this parser.
@Suite struct EmbeddedThumbnailTests {

    private static let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test(.enabled(if: Corpus.has("slicer-projects/FlightScnr.3mf")))
    func slicerProjectYieldsItsPlateThumbnail() throws {
        let thumbnail = try #require(try ThreeMFParser()
            .embeddedThumbnail(fileAt: Corpus.url("slicer-projects/FlightScnr.3mf")))

        // Ground truth: Metadata/plate_1.png, 8521 bytes, PNG magic. The
        // package also declares an OPC Package Thumbnail
        // (/Auxiliaries/.thumbnails/thumbnail_3mf.png); the Plate Thumbnail
        // must win for Slicer Projects.
        #expect(thumbnail.partPath == "/Metadata/plate_1.png")
        #expect(thumbnail.data.count == 8521)
        #expect(thumbnail.data.prefix(8) == Self.pngMagic)
    }

    @Test(.enabled(if: Corpus.has("vanilla/cube_gears_prod.3mf")))
    func vanillaFileYieldsItsOPCPackageThumbnail() throws {
        let thumbnail = try #require(try ThreeMFParser()
            .embeddedThumbnail(fileAt: Corpus.url("vanilla/cube_gears_prod.3mf")))

        // Ground truth: _rels/.rels declares a metadata/thumbnail relationship
        // to /Metadata/thumbnail.png, 170168 bytes.
        #expect(thumbnail.partPath == "/Metadata/thumbnail.png")
        #expect(thumbnail.data.count == 170_168)
        #expect(thumbnail.data.prefix(8) == Self.pngMagic)
    }

    @Test(.enabled(if: Corpus.has("vanilla/box.3mf")))
    func fileWithoutEmbeddedImageYieldsNil() throws {
        // box.3mf is a bare core-spec package: no plate thumbnail, no OPC
        // thumbnail relationship. Extraction returns nil so the preview shows
        // its neutral loading state instead of a stale image.
        let thumbnail = try ThreeMFParser()
            .embeddedThumbnail(fileAt: Corpus.url("vanilla/box.3mf"))
        #expect(thumbnail == nil)
    }

    /// The load-bearing guarantee: extracting the Embedded Thumbnail never
    /// parses geometry. A package whose model part is unparseable garbage but
    /// which carries a valid OPC thumbnail still yields that thumbnail, even
    /// though a full parse of the same package throws.
    @Test func extractionSkipsGeometryEvenWhenTheModelPartIsUnparseable() throws {
        let png = Self.pngMagic + Data("fake-image-body".utf8)
        let url = try writeTemporaryPackage(named: "embedded-thumbnail", parts: [
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
            Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
             <Relationship Target="/Metadata/thumbnail.png" Id="rel-2" \
            Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>
            </Relationships>
            """.utf8)),
            ("3D/3dmodel.model", Data("<<< this is not well-formed model XML at all >>>".utf8)),
            ("Metadata/thumbnail.png", png),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try #require(try ThreeMFParser().embeddedThumbnail(fileAt: url))
        #expect(thumbnail.partPath == "/Metadata/thumbnail.png")
        #expect(thumbnail.data == png)

        // The same package cannot be fully parsed — proof the model part is
        // never touched during extraction.
        #expect(throws: (any Error).self) {
            _ = try ThreeMFParser().parse(fileAt: url)
        }
    }

    /// The sliced-only scope of the any-plate fallback (issue #8): a REGULAR
    /// project (no G-code) whose default plate saved no thumbnail keeps the
    /// strict rule — another plate's thumbnail never stands in; the OPC
    /// Package Thumbnail does.
    @Test func regularProjectNeverBorrowsAnotherPlatesThumbnail() throws {
        let png = Self.pngMagic + Data("opc-package-thumbnail".utf8)
        let url = try writeTemporaryPackage(named: "strict-default-plate", parts: [
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
            Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
             <Relationship Target="/Metadata/thumbnail.png" Id="rel-2" \
            Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>
            </Relationships>
            """.utf8)),
            ("3D/3dmodel.model", Data("<model/>".utf8)),
            // Plate 1 (the default: it has the objects) saved no thumbnail;
            // plate 2 saved one but has no objects.
            ("Metadata/model_settings.config", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <config>
              <plate>
                <metadata key="plater_id" value="1"/>
                <model_instance>
                  <metadata key="object_id" value="2"/>
                </model_instance>
              </plate>
              <plate>
                <metadata key="plater_id" value="2"/>
                <metadata key="thumbnail_file" value="Metadata/plate_2.png"/>
              </plate>
            </config>
            """.utf8)),
            ("Metadata/plate_2.png", Self.pngMagic + Data("plate-2-thumbnail".utf8)),
            ("Metadata/thumbnail.png", png),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try #require(try ThreeMFParser().embeddedThumbnail(fileAt: url))
        #expect(thumbnail.partPath == "/Metadata/thumbnail.png")
        #expect(thumbnail.data == png)
    }

    /// The "instant first paint" property, empirically: on a large real
    /// Slicer Project, pulling the Embedded Thumbnail costs a small fraction of
    /// a full parse — because it never streams geometry. A full parse of this
    /// ~1.7M-triangle file takes seconds; extraction takes milliseconds.
    @Test(.enabled(if: Corpus.has("slicer-projects/Civilization-Atlas-Diorama-FanArt-3Dprint.3mf")))
    func extractionCostsFarLessThanAFullParse() throws {
        let url = Corpus.url("slicer-projects/Civilization-Atlas-Diorama-FanArt-3Dprint.3mf")
        let clock = ContinuousClock()

        let extractTime = clock.measure {
            _ = try? ThreeMFParser().embeddedThumbnail(fileAt: url)
        }
        let parseTime = clock.measure {
            _ = try? ThreeMFParser().parse(fileAt: url)
        }

        // The instant-first-paint budget: extraction stays well under the
        // PRD's ~100ms first-paint target, and is a small fraction of a full
        // parse of the same file.
        #expect(extractTime < .milliseconds(100))
        #expect(extractTime < parseTime / 10)
    }

}
