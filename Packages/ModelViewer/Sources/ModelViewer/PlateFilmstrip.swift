import AppKit
import SwiftUI
import ThreeMFKit

/// The Plate Filmstrip (CONTEXT.md): a horizontal strip of Plate Thumbnails
/// along the bottom of the Viewer, in a vibrancy material, with a selection
/// ring on the active Plate. Clicking a Plate swaps the scene.
///
/// On-screen clicks only, by design: the Quick Look panel owns arrow keys
/// (file navigation) and Space (close), so the Filmstrip never handles keys
/// (PRD constraint).
struct PlateFilmstrip: View {
    /// One Filmstrip entry: a Plate with its decoded Plate Thumbnail, nil
    /// when the plate has none (the numbered placeholder shows instead).
    /// Built once by the Viewer — the filmstrip re-renders on every camera
    /// tick and must not re-decode PNGs.
    struct Cell {
        let plate: Plate
        let thumbnail: NSImage?
    }

    let cells: [Cell]
    let selectedIndex: Int?
    let select: (Int) -> Void

    /// The Plates the Filmstrip offers for a document: all of them for a
    /// multi-plate Slicer Project, none otherwise — a file with one Plate or
    /// none hides the Filmstrip entirely, and Vanilla files have no Plates.
    static func plates(of document: ThreeMFDocument) -> [Plate] {
        let plates = document.slicerProject?.plates ?? []
        return plates.count > 1 ? plates : []
    }

    var body: some View {
        // Hug the content when it fits; wider strips scroll horizontally.
        ViewThatFits(in: .horizontal) {
            strip
            ScrollView(.horizontal) { strip }
                .scrollIndicators(.never)
        }
        // Outer padding is the Viewer's: it stacks the Filmstrip with the
        // Info Line inside one padded bottom overlay.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var strip: some View {
        HStack(spacing: 6) {
            // Selection is by position, not plate id (see
            // SlicerProjectInfo.defaultPlateIndex for why ids can't be keys).
            ForEach(cells.indices, id: \.self) { index in
                PlateCellView(
                    cell: cells[index],
                    isSelected: index == selectedIndex,
                    select: { select(index) })
            }
        }
        .padding(6)
    }
}

extension PlateFilmstrip.Cell {
    /// The cell for one Plate, its Plate Thumbnail decoded here and never
    /// again — shared by the Viewer and the sliced-file preview so the
    /// decode-once rule lives in one place. In an extension so the
    /// memberwise initializer survives, and on `Cell` rather than the View:
    /// View members are `@MainActor` (the swift-testing trap) and cell
    /// building is pure model work.
    init(plate: Plate) {
        self.init(
            plate: plate,
            thumbnail: plate.thumbnailData.flatMap(PackageImageDecoder.nsImage(from:)))
    }
}

/// One clickable Plate Thumbnail; a Plate without a saved thumbnail shows its
/// number on a quiet placeholder instead.
private struct PlateCellView: View {
    let cell: PlateFilmstrip.Cell
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            content
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        if let thumbnail = cell.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Text("\(cell.plate.id)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var name: String { cell.plate.name ?? "Plate \(cell.plate.id)" }
}
