import Testing
import ThreeMFKit
@testable import ModelViewer

/// Locks the Filmstrip visibility policy (issue #6): the Filmstrip is shown
/// only for multi-plate Slicer Projects. One Plate, zero Plates, or a Vanilla
/// file hide it entirely.
@Suite struct PlateFilmstripTests {

    private static func slicerDocument(plates: [Plate]) -> ThreeMFDocument {
        ThreeMFDocument(slicerProject: SlicerProjectInfo(plates: plates))
    }

    @Test func multiPlateProjectOffersEveryPlateInFileOrder() {
        let plates = [Plate(id: 1), Plate(id: 2), Plate(id: 3)]
        #expect(PlateFilmstrip.plates(of: Self.slicerDocument(plates: plates)) == plates)
    }

    @Test func singlePlateProjectHidesTheFilmstrip() {
        #expect(PlateFilmstrip.plates(of: Self.slicerDocument(plates: [Plate(id: 1)])).isEmpty)
    }

    @Test func projectWithZeroPlatesHidesTheFilmstrip() {
        #expect(PlateFilmstrip.plates(of: Self.slicerDocument(plates: [])).isEmpty)
    }

    @Test func vanillaFileHidesTheFilmstrip() {
        #expect(PlateFilmstrip.plates(of: ThreeMFDocument()).isEmpty)
    }
}
