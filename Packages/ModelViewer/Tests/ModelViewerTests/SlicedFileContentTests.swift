import Foundation
import Testing
import ThreeMFKit
@testable import ModelViewer

/// Locks the sliced-file preview's model policy (issue #8): every Plate gets
/// a cell with its image decoded exactly once, the initial selection prefers
/// the default Plate, and the Filmstrip appears only for multi-plate files —
/// the same visibility rule as the Viewer's.
@Suite struct SlicedFileContentTests {

    /// A 1×1 PNG (valid, decodable) standing in for a plate image.
    private static let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private static func document(plates: [Plate]) -> ThreeMFDocument {
        ThreeMFDocument(
            slicerProject: SlicerProjectInfo(plates: plates), isSlicedFile: true)
    }

    @Test func everyPlateGetsACellWithItsDecodedImage() {
        let content = SlicedFileContent(document: Self.document(plates: [
            Plate(id: 1, thumbnailData: Self.tinyPNG),
            Plate(id: 2),
        ]))
        #expect(content.cells.count == 2)
        #expect(content.cells[0].thumbnail != nil)
        #expect(content.cells[1].thumbnail == nil)
    }

    @Test func initialSelectionIsTheDefaultPlate() {
        // Plate 1 is empty; plate 2 has the objects, so it opens selected.
        let ref = ResourceRef(partPath: "/3D/3dmodel.model", id: 2)
        let content = SlicedFileContent(document: Self.document(plates: [
            Plate(id: 1),
            Plate(id: 2, objectRefs: [ref]),
        ]))
        #expect(content.initialSelectedIndex == 1)
    }

    @Test func selectionFallsBackToTheFirstPlateThatSavedAThumbnail() {
        // No plate records objects (a config without model_instance entries):
        // the first plate that saved a Plate Thumbnail wins over a bare one —
        // the same rule the Finder icon follows, so the two never disagree.
        let content = SlicedFileContent(document: Self.document(plates: [
            Plate(id: 1),
            Plate(id: 2, thumbnailPartPath: "/Metadata/plate_2.png", thumbnailData: Self.tinyPNG),
        ]))
        #expect(content.initialSelectedIndex == 1)
    }

    @Test func selectionMatchesTheFinderIconWhenTheDefaultPlateSavedNoThumbnail() {
        // The default Plate (has objects) saved no thumbnail while another
        // plate did: the icon shows that other plate, so the preview must
        // open on it too.
        let ref = ResourceRef(partPath: "/3D/3dmodel.model", id: 2)
        let content = SlicedFileContent(document: Self.document(plates: [
            Plate(id: 1, objectRefs: [ref]),
            Plate(id: 2, thumbnailPartPath: "/Metadata/plate_2.png", thumbnailData: Self.tinyPNG),
        ]))
        #expect(content.initialSelectedIndex == 1)
    }

    @Test func selectionFallsBackToTheFirstPlateWhenNoneHasAnImage() {
        let content = SlicedFileContent(document: Self.document(plates: [
            Plate(id: 1), Plate(id: 2),
        ]))
        #expect(content.initialSelectedIndex == 0)
    }

    @Test func noPlatesMeansNoSelection() {
        let content = SlicedFileContent(document: Self.document(plates: []))
        #expect(content.cells.isEmpty)
        #expect(content.initialSelectedIndex == nil)
    }

    @Test func filmstripAppearsOnlyForMultiPlateFiles() {
        #expect(!SlicedFileContent(document: Self.document(plates: [Plate(id: 1)]))
            .showsFilmstrip)
        #expect(SlicedFileContent(document: Self.document(plates: [
            Plate(id: 1), Plate(id: 2),
        ])).showsFilmstrip)
    }

    @Test func infoContentDescribesTheSelectedPlate() {
        let doc = ThreeMFDocument(
            slicerProject: SlicerProjectInfo(
                plates: [
                    Plate(id: 1, estimatedPrintTime: 3600),
                    Plate(id: 2, estimatedPrintTime: 7245),
                ],
                printerModel: "Bambu Lab X1 Carbon"),
            isSlicedFile: true)
        let content = SlicedFileContent(document: doc)
        #expect(content.infoContent(at: 1).printTime == "2h 1m")
        #expect(content.infoContent(at: 1).printerModel == "Bambu Lab X1 Carbon")
        // Out-of-range or absent selection still yields the file-level line.
        #expect(content.infoContent(at: nil).printerModel == "Bambu Lab X1 Carbon")
        #expect(content.infoContent(at: nil).printTime == nil)
    }
}
