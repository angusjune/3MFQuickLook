import AppKit
import SwiftUI
import ThreeMFKit

/// The model behind the sliced-file preview: one Filmstrip cell per Plate
/// with its plate image decoded exactly once (shared by the full-size view
/// and the Filmstrip), the initial selection, and the per-plate metadata
/// line. Deliberately not part of ``SlicedFileView``: `View` statics are
/// `@MainActor` and trap under swift-testing; this is pure model logic.
struct SlicedFileContent {
    let document: ThreeMFDocument
    let cells: [PlateFilmstrip.Cell]

    init(document: ThreeMFDocument) {
        self.document = document
        cells = (document.slicerProject?.plates ?? []).map {
            PlateFilmstrip.Cell(plate: $0, thumbnail: $0.thumbnailData.flatMap(NSImage.init(data:)))
        }
    }

    /// The Plate shown when the preview opens: the default Plate (first with
    /// objects, matching the Finder icon), else — configs whose plates carry
    /// no `model_instance` entries record no objects anywhere — the first
    /// plate with an image, else the first plate. Nil only without plates.
    var initialSelectedIndex: Int? {
        document.slicerProject?.defaultPlateIndex
            ?? cells.firstIndex { $0.thumbnail != nil }
            ?? (cells.isEmpty ? nil : 0)
    }

    /// Multi-plate Sliced Files browse their plate images with the
    /// Filmstrip; one plate or none hides it — the Viewer's visibility rule.
    var showsFilmstrip: Bool { cells.count > 1 }

    /// The metadata line for the selected plate (out-of-range or nil: the
    /// file-level segments only).
    func infoContent(at index: Int?) -> InfoLineContent {
        let plate = index.flatMap { cells.indices.contains($0) ? cells[$0].plate : nil }
        return InfoLineContent(forSlicedPlate: plate, in: document)
    }
}

/// The honest preview of a Sliced File (issue #8): the selected Plate's
/// image at full size with the print-metadata line — printer model,
/// estimated print time, filament dots — and, for multi-plate files, the
/// same Plate Filmstrip the Viewer uses, swapping the image instead of the
/// scene. Never a 3D view: these packages carry G-code, not geometry
/// (CONTEXT.md: Sliced File).
struct SlicedFileView: View {
    private let content: SlicedFileContent

    @State private var selectedIndex: Int?

    init(document: ThreeMFDocument) {
        let content = SlicedFileContent(document: document)
        self.content = content
        _selectedIndex = State(initialValue: content.initialSelectedIndex)
    }

    var body: some View {
        plateImage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if content.showsFilmstrip {
                        PlateFilmstrip(
                            cells: content.cells,
                            selectedIndex: selectedIndex,
                            select: { selectedIndex = $0 })
                    }
                    InfoLine(content: content.infoContent(at: selectedIndex))
                }
                .padding(12)
            }
    }

    @ViewBuilder
    private var plateImage: some View {
        if let selectedIndex, let image = content.cells[selectedIndex].thumbnail {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A plate that saved no image (or a file with no plates at all)
            // stays quiet — same posture as the Filmstrip's placeholder.
            Image(systemName: "printer")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
        }
    }
}
