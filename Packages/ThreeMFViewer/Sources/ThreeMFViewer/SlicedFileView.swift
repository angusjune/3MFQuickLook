import AppKit
import SwiftUI
import ThreeMFKit

/// The model behind the sliced-file preview: one Filmstrip cell per Plate
/// with its Plate Thumbnail decoded exactly once (shared by the full-size
/// view and the Filmstrip), the initial selection, and the per-plate
/// metadata line. Deliberately not part of ``SlicedFileView``: `View`
/// statics are `@MainActor` and trap under swift-testing; this is pure
/// model logic.
struct SlicedFileContent {
    let document: ThreeMFDocument
    let cells: [PlateFilmstrip.Cell]

    init(document: ThreeMFDocument) {
        self.document = document
        cells = (document.slicerProject?.plates ?? []).map { PlateFilmstrip.Cell(plate: $0) }
    }

    /// The Plate shown when the preview opens:
    /// ``SlicerProjectInfo/thumbnailPlateIndex`` — the same rule the Finder
    /// icon follows, so panel and icon never disagree — else the default
    /// Plate, else the first. Nil only without plates.
    var initialSelectedIndex: Int? {
        document.slicerProject?.thumbnailPlateIndex
            ?? document.slicerProject?.defaultPlateIndex
            ?? (cells.isEmpty ? nil : 0)
    }

    /// Multi-plate Sliced Files browse their Plate Thumbnails with the
    /// Filmstrip; one plate or none hides it — the Viewer's visibility rule.
    var showsFilmstrip: Bool { cells.count > 1 }

    /// The full-size Plate Thumbnail for a selection; nil for a plate that
    /// saved none (or an out-of-range index — a stale selection must
    /// degrade to the placeholder, never trap).
    func image(at index: Int?) -> NSImage? {
        cell(at: index)?.thumbnail
    }

    /// The metadata line for the selected plate (out-of-range or nil: the
    /// file-level segments only).
    func infoContent(at index: Int?) -> InfoLineContent {
        InfoLineContent(forSlicedPlate: cell(at: index)?.plate, in: document)
    }

    private func cell(at index: Int?) -> PlateFilmstrip.Cell? {
        index.flatMap { cells.indices.contains($0) ? cells[$0] : nil }
    }
}

/// The honest preview of a Sliced File (issue #8): the selected Plate's
/// Thumbnail at full size with the print-metadata line — printer model,
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
        if let image = content.image(at: selectedIndex) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A Plate that saved no Thumbnail (or a file with no Plates at
            // all) stays quiet — same posture as the Filmstrip placeholder.
            Image(systemName: "printer")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
        }
    }
}
