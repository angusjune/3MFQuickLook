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
    let plates: [Plate]
    /// One decoded Plate Thumbnail per plate (same order); nil entries show
    /// the numbered placeholder. Decoded once by the Viewer, not per render.
    let thumbnails: [NSImage?]
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
            cells
            ScrollView(.horizontal) { cells }
                .scrollIndicators(.never)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(12)
    }

    private var cells: some View {
        HStack(spacing: 6) {
            // Selection is by position: slicer plater_ids are not guaranteed
            // unique in malformed files.
            ForEach(plates.indices, id: \.self) { index in
                PlateCell(
                    plate: plates[index],
                    thumbnail: thumbnails.indices.contains(index) ? thumbnails[index] : nil,
                    isSelected: index == selectedIndex,
                    select: { select(index) })
            }
        }
        .padding(6)
    }
}

/// One clickable Plate Thumbnail; a Plate without a saved thumbnail shows its
/// number on a quiet placeholder instead.
private struct PlateCell: View {
    let plate: Plate
    let thumbnail: NSImage?
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
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Text("\(plate.id)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var name: String { plate.name ?? "Plate \(plate.id)" }
}
