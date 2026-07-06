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

    @Test(.enabled(if: Corpus.has("vanilla/box.3mf")))
    func vanillaFileHasNoSlicerProjectInfo() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/box.3mf"))
        #expect(doc.slicer == nil)
    }
}
