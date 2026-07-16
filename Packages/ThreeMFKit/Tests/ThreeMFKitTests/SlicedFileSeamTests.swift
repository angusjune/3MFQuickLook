import Foundation
import Testing
import ThreeMFKit

/// Parse-seam tests for Sliced Files (issue #8): a `.gcode.3mf` package —
/// sliced G-code plus Plate Thumbnails, mesh geometry stripped — is detected
/// by CONTENT (the G-code parts), never by filename, and exposes its Plate
/// Thumbnails and print metadata instead of a 3D scene. Ground truth for the
/// synthetic fixtures is by construction (Corpus/tools/make_slicer_fixtures.py
/// writes these exact values).
@Suite struct SlicedFileSeamTests {

    private static let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test(.enabled(if: Corpus.has("sliced/synthetic_single.gcode.3mf")))
    func slicedFileExposesPlateThumbnailAndPrintMetadataWithoutGeometry() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("sliced/synthetic_single.gcode.3mf"))

        #expect(doc.isSlicedFile)
        // Geometry is stripped by definition — nothing to stage, ever.
        #expect(doc.objects.isEmpty)
        #expect(doc.buildItems.isEmpty)

        let slicer = try #require(doc.slicerProject)
        #expect(slicer.printerModel == "Bambu Lab P1S")
        #expect(slicer.filaments.map(\.color) == [ColorRGBA(red: 0, green: 0xAE, blue: 0x42)])
        #expect(slicer.filaments.map(\.type) == ["PLA"])

        #expect(slicer.plates.count == 1)
        let plate = try #require(slicer.plates.first)
        #expect(plate.estimatedPrintTime == 3720)
        #expect(plate.usedFilamentIndices == [0])
        #expect(plate.thumbnailPartPath == "/Metadata/plate_1.png")
        #expect(plate.thumbnailData?.prefix(8) == Self.pngMagic)
    }

    @Test(.enabled(if: Corpus.has("sliced/synthetic_multiplate.gcode.3mf")))
    func multiPlateSlicedFileExposesEveryPlateThumbnailAndPrediction() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("sliced/synthetic_multiplate.gcode.3mf"))

        #expect(doc.isSlicedFile)
        let slicer = try #require(doc.slicerProject)
        #expect(slicer.printerModel == "Bambu Lab X1 Carbon")
        #expect(slicer.filaments.map(\.color) == [
            ColorRGBA(red: 255, green: 0, blue: 0),
            ColorRGBA(red: 0, green: 0, blue: 255),
        ])

        #expect(slicer.plates.map(\.id) == [1, 2])
        #expect(slicer.plates.map(\.estimatedPrintTime) == [3600, 7245])
        #expect(slicer.plates.map(\.usedFilamentIndices) == [[0], [1]])
        // Both Plate Thumbnails come out with the parse, so the Filmstrip and
        // the full-size view never re-open the package.
        #expect(slicer.plates[0].thumbnailData?.prefix(8) == Self.pngMagic)
        #expect(slicer.plates[1].thumbnailData?.prefix(8) == Self.pngMagic)
        #expect(slicer.plates[0].thumbnailData != slicer.plates[1].thumbnailData)
    }

    /// The load-bearing acceptance criterion: detection is content-based.
    /// The same sliced package under an extension that hides its nature is
    /// still detected — macOS type-matching cannot tell `.gcode.3mf` from
    /// `.3mf`, so the parser must not rely on the name either.
    @Test(.enabled(if: Corpus.has("sliced/synthetic_single.gcode.3mf")))
    func detectionSurvivesRenamingToAPlainThreeMFExtension() throws {
        let disguised = FileManager.default.temporaryDirectory
            .appendingPathComponent("innocent-project-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        try FileManager.default.copyItem(
            at: Corpus.url("sliced/synthetic_single.gcode.3mf"), to: disguised)
        defer { try? FileManager.default.removeItem(at: disguised) }

        let doc = try ThreeMFParser().parse(fileAt: disguised)
        #expect(doc.isSlicedFile)
    }

    /// The other half of content-based detection: packages without G-code
    /// parts — vanilla, Slicer Projects, PrusaSlicer projects — are never
    /// mistaken for Sliced Files.
    @Test(arguments: [
        "vanilla/box.3mf",
        "vanilla/cube_gears.3mf",
        "slicer-projects/FlightScnr.3mf",
        "slicer-projects/synthetic_multiplate.3mf",
        "slicer-projects/synthetic_prusa.3mf",
    ].filter(Corpus.has))
    func nonSlicedCorpusFilesAreNotDetected(path: String) throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url(path))
        #expect(!doc.isSlicedFile)
    }

    /// The Finder-icon criterion: a Sliced File's Embedded Thumbnail is its
    /// Plate Thumbnail, through the same cheap extraction seam as every
    /// other flavor.
    @Test(.enabled(if: Corpus.has("sliced/synthetic_single.gcode.3mf")))
    func slicedFileYieldsItsPlateThumbnailAsEmbeddedThumbnail() throws {
        let thumbnail = try #require(try ThreeMFParser()
            .embeddedThumbnail(fileAt: Corpus.url("sliced/synthetic_single.gcode.3mf")))
        #expect(thumbnail.partPath == "/Metadata/plate_1.png")
        #expect(thumbnail.data.prefix(8) == Self.pngMagic)
    }

    /// Sliced parsing never touches the model parts: a package whose model
    /// part is garbage still parses as a Sliced File — its configs are the
    /// content, and a stripped or mangled model must not surface an error.
    @Test func slicedParseNeverTouchesTheModelPart() throws {
        let url = try writeTemporaryPackage(named: "sliced-garbage-model", parts: [
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
            Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
            </Relationships>
            """.utf8)),
            ("3D/3dmodel.model", Data("<<< not model XML >>>".utf8)),
            ("Metadata/plate_1.gcode", Data("; gcode\nG28\n".utf8)),
            ("Metadata/model_settings.config", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <config>
              <plate>
                <metadata key="plater_id" value="1"/>
                <metadata key="gcode_file" value="Metadata/plate_1.gcode"/>
                <metadata key="thumbnail_file" value="Metadata/plate_1.png"/>
              </plate>
            </config>
            """.utf8)),
            ("Metadata/plate_1.png", Self.pngMagic + Data("fake-plate-image".utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)
        #expect(doc.isSlicedFile)
        #expect(doc.objects.isEmpty)
        #expect(doc.slicerProject?.plates.first?.thumbnailData
            == Self.pngMagic + Data("fake-plate-image".utf8))
    }

    /// Only slicer-written `Metadata/` G-code marks a Sliced File: a real
    /// project that merely carries a stray G-code attachment elsewhere in
    /// the package keeps its geometry — and its 3D preview.
    @Test func strayGCodeOutsideMetadataDoesNotMarkASlicedFile() throws {
        let url = try writeTemporaryPackage(named: "stray-gcode-project", parts: [
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
            Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
            </Relationships>
            """.utf8)),
            ("3D/3dmodel.model", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
             <resources>
              <object id="1" type="model">
               <mesh>
                <vertices>
                 <vertex x="0" y="0" z="0"/>
                 <vertex x="10" y="0" z="0"/>
                 <vertex x="0" y="10" z="0"/>
                </vertices>
                <triangles>
                 <triangle v1="0" v2="1" v3="2"/>
                </triangles>
               </mesh>
              </object>
             </resources>
             <build>
              <item objectid="1"/>
             </build>
            </model>
            """.utf8)),
            ("Auxiliaries/notes.gcode", Data("; someone's attached G-code\nG28\n".utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)
        #expect(!doc.isSlicedFile)
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.mesh?.triangleCount == 1)
    }

    /// A sliced config whose plates carry no `model_instance` entries has no
    /// "plate with objects" for the default-plate rule to pick — the Finder
    /// icon must still come from the first plate that saved a thumbnail.
    @Test func embeddedThumbnailFallsBackToTheFirstPlateWithAThumbnail() throws {
        let url = try writeTemporaryPackage(named: "sliced-no-instances", parts: [
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
            Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
            </Relationships>
            """.utf8)),
            ("3D/3dmodel.model", Data("<model/>".utf8)),
            ("Metadata/plate_1.gcode", Data("; gcode\nG28\n".utf8)),
            ("Metadata/model_settings.config", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <config>
              <plate>
                <metadata key="plater_id" value="1"/>
                <metadata key="gcode_file" value="Metadata/plate_1.gcode"/>
                <metadata key="thumbnail_file" value="Metadata/plate_1.png"/>
              </plate>
            </config>
            """.utf8)),
            ("Metadata/plate_1.png", Self.pngMagic + Data("fake-plate-image".utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try #require(try ThreeMFParser().embeddedThumbnail(fileAt: url))
        #expect(thumbnail.partPath == "/Metadata/plate_1.png")
    }
}
