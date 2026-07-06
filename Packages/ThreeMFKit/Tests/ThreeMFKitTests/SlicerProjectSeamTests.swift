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
        let slicer = try #require(doc.slicer)

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
        #expect(slicer.defaultPlate == plate)

        // Every object carries <metadata key="extruder" value="1"/> → index 0.
        for id in [UInt32(2), 4, 6] {
            #expect(slicer.filamentIndexByObject[ResourceRef(partPath: Self.rootPart, id: id)] == 0)
        }

        // printable_area ['0x0', '256x0', '256x256', '0x256'].
        #expect(slicer.plateSize == PlateSize(width: 256, depth: 256))
    }

    // Ground truth for the synthetic fixtures is by construction:
    // Corpus/tools/make_slicer_fixtures.py writes these exact values.

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_multiplate.3mf")))
    func multiPlateProjectExposesAllPlatesAndBothFilaments() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_multiplate.3mf"))
        let slicer = try #require(doc.slicer)

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

        // Cube → extruder 1 → filament 0, pyramid → extruder 2 → filament 1.
        #expect(slicer.filamentIndexByObject[ResourceRef(partPath: Self.rootPart, id: 2)] == 0)
        #expect(slicer.filamentIndexByObject[ResourceRef(partPath: Self.rootPart, id: 4)] == 1)

        #expect(slicer.plateSize == PlateSize(width: 180, depth: 180))

        // Production-extension geometry split across parts loads completely.
        #expect(doc.objects.count == 4)
        let cube = try #require(doc.object(ResourceRef(partPath: "/3D/Objects/object_1.model", id: 1))?.mesh)
        #expect(cube.positions.count == 8)
        #expect(cube.triangleCount == 12)
        let pyramid = try #require(doc.object(ResourceRef(partPath: "/3D/Objects/object_2.model", id: 1))?.mesh)
        #expect(pyramid.positions.count == 5)
        #expect(pyramid.triangleCount == 6)
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_prusa.3mf")))
    func prusaProjectStaysVanillaPlusButParsesGeometry() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_prusa.3mf"))

        // PrusaSlicer projects are Vanilla-plus (CONTEXT.md), never Slicer
        // Projects: no Bambu configs → no slicer info.
        #expect(doc.slicer == nil)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 8)
        #expect(mesh.triangleCount == 12)
        let translation = try #require(doc.buildItems.first).transform.columns.3
        #expect(translation == SIMD4(115, 95, 0, 1))
    }

    @Test(.enabled(if: Corpus.has("vanilla/box.3mf")))
    func vanillaFileHasNoSlicerProjectInfo() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/box.3mf"))
        #expect(doc.slicer == nil)
    }
}
