import Foundation
import simd
import Testing
import ThreeMFKit
@testable import ModelViewer

/// Locks the Info Line's formatting and its omission policy (issue #7):
/// absent metadata drops its segment — no placeholders, no dashes — and a
/// file with no metadata at all still gets dimensions from geometry.
@Suite struct InfoLineTests {

    // MARK: Formatting

    @Test func dimensionsReadWidthDepthHeightInMillimeters() {
        #expect(InfoLineContent.dimensionsText(SIMD3(220, 150, 42)) == "220 × 150 × 42 mm")
    }

    @Test func dimensionsKeepTenthsOnlyWhenTheyMatter() {
        #expect(InfoLineContent.dimensionsText(SIMD3(25.4, 8.05, 42.999)) == "25.4 × 8.1 × 43 mm")
    }

    @Test func printTimeReadsHoursAndMinutes() {
        #expect(InfoLineContent.printTimeText(5460) == "1h 31m")
    }

    @Test func printTimeUnderAnHourReadsMinutesOnly() {
        #expect(InfoLineContent.printTimeText(45 * 60) == "45m")
    }

    @Test func printTimeOnExactHoursDropsTheMinutes() {
        #expect(InfoLineContent.printTimeText(2 * 3600) == "2h")
    }

    @Test func printTimeUnderAMinuteRoundsUpToOne() {
        #expect(InfoLineContent.printTimeText(20) == "1m")
    }

    @Test func printTimeBeyondADayStaysInHours() {
        // Slicers report long prints in hours, so the Info Line does too.
        #expect(InfoLineContent.printTimeText(26 * 3600 + 5 * 60) == "26h 5m")
    }

    @Test func objectCountPluralizes() {
        #expect(InfoLineContent.objectCountText(1) == "1 object")
        #expect(InfoLineContent.objectCountText(3) == "3 objects")
        #expect(InfoLineContent.objectCountText(0) == "0 objects")
    }

    // MARK: Content building

    private static let rootPart = "/3D/3dmodel.model"

    private static func ref(_ id: UInt32) -> ResourceRef {
        ResourceRef(partPath: rootPart, id: id)
    }

    /// A 10 mm cube document; slicer details are grafted on per test.
    private static func cubeDocument(slicerProject: SlicerProjectInfo? = nil) -> ThreeMFDocument {
        var positions: [SIMD3<Float>] = []
        for z: Float in [0, 10] {
            for y: Float in [0, 10] {
                for x: Float in [0, 10] {
                    positions.append(SIMD3(x, y, z))
                }
            }
        }
        let triangles: [UInt32] = [
            0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6,
            0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7,
            0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5,
        ]
        let mesh = Mesh(positions: positions, triangleIndices: triangles)
        return ThreeMFDocument(
            objects: [ObjectResource(ref: ref(1), content: .mesh(mesh))],
            buildItems: [BuildItem(objectRef: ref(1))],
            slicerProject: slicerProject)
    }

    @Test func vanillaFileShowsOnlyGeometryFacts() {
        let content = InfoLineContent(for: Self.cubeDocument(), plate: nil)
        #expect(content.dimensions == "10 × 10 × 10 mm")
        #expect(content.objectCount == "1 object")
        #expect(content.printTime == nil)
        #expect(content.filamentColors.isEmpty)
    }

    @Test func slicedPlateShowsAllFourSegments() {
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let plate = Plate(
            id: 1, objectRefs: [Self.ref(1)],
            estimatedPrintTime: 5460, usedFilamentIndices: [0])
        let doc = Self.cubeDocument(slicerProject: SlicerProjectInfo(
            filaments: [Filament(color: red, type: "PLA")],
            plates: [plate]))
        let content = InfoLineContent(for: doc, plate: plate)
        #expect(content.dimensions == "10 × 10 × 10 mm")
        #expect(content.objectCount == "1 object")
        #expect(content.printTime == "1h 31m")
        #expect(content.filamentColors == [red])
    }

    @Test func unslicedPlateOmitsPrintTimeButKeepsDerivedDots() {
        let green = ColorRGBA(red: 0, green: 255, blue: 0)
        let plate = Plate(id: 1, objectRefs: [Self.ref(1)])
        let doc = Self.cubeDocument(slicerProject: SlicerProjectInfo(
            filaments: [Filament(color: green, type: "PETG")],
            plates: [plate]))
        let content = InfoLineContent(for: doc, plate: plate)
        #expect(content.printTime == nil)
        #expect(content.filamentColors == [green])
    }

    @Test func filamentsWithoutColorsDropTheirDots() {
        let plate = Plate(id: 1, objectRefs: [Self.ref(1)], usedFilamentIndices: [0, 1])
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let doc = Self.cubeDocument(slicerProject: SlicerProjectInfo(
            filaments: [Filament(color: nil, type: "PLA"), Filament(color: red, type: "PETG")],
            plates: [plate]))
        #expect(InfoLineContent(for: doc, plate: plate).filamentColors == [red])
    }

    @Test func emptyPlateStillReportsItsCount() {
        let plate = Plate(id: 2)
        let doc = Self.cubeDocument(slicerProject: SlicerProjectInfo(
            plates: [Plate(id: 1, objectRefs: [Self.ref(1)]), plate]))
        let content = InfoLineContent(for: doc, plate: plate)
        #expect(content.dimensions == nil)
        #expect(content.objectCount == "0 objects")
    }

    @Test func nilPlateDescribesTheDefaultScene() {
        let sliced = Plate(id: 1, objectRefs: [Self.ref(1)], estimatedPrintTime: 3600)
        let doc = Self.cubeDocument(slicerProject: SlicerProjectInfo(plates: [sliced]))
        #expect(InfoLineContent(for: doc, plate: nil) == InfoLineContent(for: doc, plate: sliced))
    }

    // MARK: Sliced Files (issue #8)

    /// A Sliced File document: no geometry, configs only.
    private static func slicedDocument(
        plates: [Plate], filaments: [Filament] = [], printerModel: String? = nil
    ) -> ThreeMFDocument {
        ThreeMFDocument(
            slicerProject: SlicerProjectInfo(
                filaments: filaments, plates: plates, printerModel: printerModel),
            isSlicedFile: true)
    }

    @Test func slicedPlateLineShowsPrinterTimeAndDotsButNeverGeometryFacts() {
        let green = ColorRGBA(red: 0, green: 0xAE, blue: 0x42)
        let plate = Plate(id: 1, estimatedPrintTime: 3720, usedFilamentIndices: [0])
        let doc = Self.slicedDocument(
            plates: [plate],
            filaments: [Filament(color: green, type: "PLA")],
            printerModel: "Bambu Lab P1S")

        let content = InfoLineContent(forSlicedPlate: plate, in: doc)
        #expect(content.printerModel == "Bambu Lab P1S")
        #expect(content.dimensions == nil)
        #expect(content.objectCount == nil)
        #expect(content.printTime == "1h 2m")
        #expect(content.filamentColors == [green])
    }

    @Test func slicedLineDropsAbsentSegments() {
        let content = InfoLineContent(
            forSlicedPlate: Plate(id: 1), in: Self.slicedDocument(plates: [Plate(id: 1)]))
        #expect(content.printerModel == nil)
        #expect(content.printTime == nil)
        #expect(content.filamentColors.isEmpty)
    }

    @Test func geometryLineNeverShowsThePrinterModel() {
        // The printer model is Sliced-File chrome only; the Viewer's Info
        // Line keeps its issue-7 segments even when the project records one.
        let doc = Self.cubeDocument(slicerProject: SlicerProjectInfo(
            plates: [Plate(id: 1, objectRefs: [Self.ref(1)])],
            printerModel: "Bambu Lab X1 Carbon"))
        #expect(InfoLineContent(for: doc, plate: nil).printerModel == nil)
    }
}
