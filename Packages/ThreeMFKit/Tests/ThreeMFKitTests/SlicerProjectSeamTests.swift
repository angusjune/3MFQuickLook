import Foundation
import Testing
import ThreeMFKit

/// Parse-seam tests for Slicer Project metadata (issue #4): given a corpus
/// file, the document exposes these Plates, filaments, and assignments.
/// Ground truth comes from independent inspection of the config parts
/// (`unzip -p … Metadata/model_settings.config` / `project_settings.config`),
/// not from this parser.
@Suite struct SlicerProjectSeamTests {

    private static let rootPart = "/3D/3dmodel.model"

    @Test(.enabled(if: Corpus.has("slicer-projects/FlightScnr.3mf")))
    func bambuProjectExposesPlateFilamentsAndAssignments() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("slicer-projects/FlightScnr.3mf"))
        let slicer = try #require(doc.slicerProject)

        // project_settings.config: filament_colour ["#000000"], filament_type ["PLA"].
        #expect(slicer.filaments.count == 1)
        #expect(slicer.filaments.first?.color == ColorRGBA(red: 0, green: 0, blue: 0))
        #expect(slicer.filaments.first?.type == "PLA")

        // model_settings.config: one <plate> (plater_id 1, empty plater_name)
        // holding model_instances for objects 2, 4, 6.
        #expect(slicer.plates.count == 1)
        let plate = try #require(slicer.plates.first)
        #expect(plate.id == 1)
        #expect(plate.name == nil)
        #expect(plate.objectRefs == [2, 4, 6].map {
            ResourceRef(partPath: Self.rootPart, id: $0)
        })
        #expect(plate.thumbnailPartPath == "/Metadata/plate_1.png")
        // The package contains that part (8521 bytes, `unzip -l`); a full
        // parse extracts it so Plate Thumbnails render without re-opening
        // the file.
        #expect(plate.thumbnailData?.count == 8521)
        #expect(slicer.defaultPlate == plate)

        // Every object carries <metadata key="extruder" value="1"/> → index 0.
        for id in [UInt32(2), 4, 6] {
            #expect(slicer.filamentIndexByObject[ResourceRef(partPath: Self.rootPart, id: id)] == 0)
        }

        // printable_area ['0x0', '256x0', '256x256', '0x256'].
        #expect(slicer.plateRect == PlateRect(width: 256, depth: 256))
    }

    // Ground truth for the synthetic fixtures is by construction:
    // Corpus/tools/make_slicer_fixtures.py writes these exact values.

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_multiplate.3mf")))
    func multiPlateProjectExposesAllPlatesAndBothFilaments() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_multiplate.3mf"))
        let slicer = try #require(doc.slicerProject)

        #expect(slicer.filaments.map(\.color) == [
            ColorRGBA(red: 255, green: 0, blue: 0),
            ColorRGBA(red: 0, green: 255, blue: 0),
        ])
        #expect(slicer.filaments.map(\.type) == ["PLA", "PETG"])

        #expect(slicer.plates.count == 3)
        #expect(slicer.plates.map(\.id) == [1, 2, 3])
        #expect(slicer.plates[0].objectRefs.isEmpty)
        #expect(slicer.plates[1].name == "Cube Plate")
        #expect(slicer.plates[1].objectRefs == [ResourceRef(partPath: Self.rootPart, id: 2)])
        #expect(slicer.plates[1].thumbnailPartPath == "/Metadata/plate_2.png")
        #expect(slicer.plates[2].objectRefs == [ResourceRef(partPath: Self.rootPart, id: 4)])

        // Plate 1 is empty, so plate 2 is the default.
        #expect(slicer.defaultPlate?.id == 2)
        #expect(slicer.defaultPlateIndex == 1)

        // Cube → extruder 1 → filament 0, pyramid → extruder 2 → filament 1.
        #expect(slicer.filamentIndexByObject[ResourceRef(partPath: Self.rootPart, id: 2)] == 0)
        #expect(slicer.filamentIndexByObject[ResourceRef(partPath: Self.rootPart, id: 4)] == 1)

        // Part-level assignment: the "Topper" part (id 2 → object_2.model
        // object 2) carries its own extruder 1; the pyramid part inherits the
        // object level and gets no explicit entry.
        let topperRef = ResourceRef(partPath: "/3D/Objects/object_2.model", id: 2)
        #expect(slicer.filamentIndexByObject[topperRef] == 0)
        #expect(slicer.filamentColor(of: topperRef) == ColorRGBA(red: 255, green: 0, blue: 0))
        #expect(slicer.filamentIndexByObject[ResourceRef(partPath: "/3D/Objects/object_2.model", id: 1)] == nil)

        #expect(slicer.plateRect == PlateRect(width: 180, depth: 180))

        // Production-extension geometry split across parts loads completely.
        #expect(doc.objects.count == 5)
        let cube = try #require(doc.object(ResourceRef(partPath: "/3D/Objects/object_1.model", id: 1))?.mesh)
        #expect(cube.positions.count == 8)
        #expect(cube.triangleCount == 12)
        let pyramid = try #require(doc.object(ResourceRef(partPath: "/3D/Objects/object_2.model", id: 1))?.mesh)
        #expect(pyramid.positions.count == 5)
        #expect(pyramid.triangleCount == 6)
        let topper = try #require(doc.object(topperRef)?.mesh)
        #expect(topper.positions.count == 8)
        #expect(topper.triangleCount == 12)
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_multiplate.3mf")))
    func plateThumbnailBytesAreExtractedAtParseTime() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_multiplate.3mf"))
        let slicer = try #require(doc.slicerProject)

        // Plate 2 declares Metadata/plate_2.png and the package contains it
        // (a 4x4 solid-red PNG, by fixture construction).
        let data = try #require(slicer.plates[1].thumbnailData)
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))

        // Plates 1 and 3 record no thumbnail_file → no bytes either.
        #expect(slicer.plates[0].thumbnailData == nil)
        #expect(slicer.plates[2].thumbnailData == nil)
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_multiplate.3mf")))
    func slicedPlateExposesPredictionAndUsedFilaments() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_multiplate.3mf"))
        let slicer = try #require(doc.slicerProject)

        // slice_info.config: only plate 2 was sliced — prediction 5460 s,
        // one <filament id="1"> → filament index 0.
        #expect(slicer.plates[1].estimatedPrintTime == 5460)
        #expect(slicer.plates[1].usedFilamentIndices == [0])
        #expect(doc.usedFilamentIndices(for: slicer.plates[1]) == [0])

        // Plates 1 and 3 were never sliced: no print time, and the used
        // filaments derive from assignments instead — plate 3's pyramid is
        // extruder 2 with its Topper part overridden to extruder 1.
        #expect(slicer.plates[0].estimatedPrintTime == nil)
        #expect(slicer.plates[2].estimatedPrintTime == nil)
        #expect(slicer.plates[2].usedFilamentIndices == nil)
        #expect(doc.usedFilamentIndices(for: slicer.plates[2]) == [0, 1])
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_multiplate.3mf")))
    func plateMetricsMeasureTheStagedGeometry() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_multiplate.3mf"))
        let slicer = try #require(doc.slicerProject)

        // Plate 2: the 20 mm cube, one placed object.
        #expect(doc.sceneMetrics(for: slicer.plates[1])
            == SceneMetrics(sizeMillimeters: SIMD3(20, 20, 20), objectCount: 1))
        // Plate 3: 30 mm pyramid plus the 10 mm topper lifted 15 → z 0…25.
        #expect(doc.sceneMetrics(for: slicer.plates[2])
            == SceneMetrics(sizeMillimeters: SIMD3(30, 30, 25), objectCount: 1))
        // Plate 1 is genuinely empty.
        #expect(doc.sceneMetrics(for: slicer.plates[0]) == SceneMetrics(objectCount: 0))
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/FlightScnr.3mf")))
    func unslicedProjectHasNoPrintTimeButDerivesItsFilament() throws {
        // FlightScnr's slice_info.config is a bare header (saved unsliced):
        // no prediction, no per-plate filament list.
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("slicer-projects/FlightScnr.3mf"))
        let plate = try #require(doc.slicerProject?.plates.first)
        #expect(plate.estimatedPrintTime == nil)
        #expect(plate.usedFilamentIndices == nil)
        // All objects are assigned extruder 1 → the single filament derives.
        #expect(doc.usedFilamentIndices(for: plate) == [0])
    }

    @Test func defaultPlateIsNilWhenNoPlateHasObjects() {
        let info = SlicerProjectInfo(plates: [Plate(id: 1), Plate(id: 2)])
        #expect(info.defaultPlate == nil)
        #expect(info.defaultPlateIndex == nil)
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_prusa.3mf")))
    func prusaProjectStaysVanillaPlusButParsesGeometry() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_prusa.3mf"))

        // PrusaSlicer projects are Vanilla-plus (CONTEXT.md), never Slicer
        // Projects: no Bambu configs → no slicer info.
        #expect(doc.slicerProject == nil)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 8)
        #expect(mesh.triangleCount == 12)
        let translation = try #require(doc.buildItems.first).transform.columns.3
        #expect(translation == SIMD4(115, 95, 0, 1))
    }

    @Test(.enabled(if: Corpus.has("vanilla/box.3mf")))
    func vanillaFileHasNoSlicerProjectInfo() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/box.3mf"))
        #expect(doc.slicerProject == nil)
    }
}
