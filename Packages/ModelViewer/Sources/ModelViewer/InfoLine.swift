import GLBKit
import SwiftUI
import ThreeMFKit

/// The formatted segments of the Info Line for one staged scene, built once
/// per Plate switch — the line re-renders on every camera tick and must not
/// re-measure geometry. Deliberately not part of the ``InfoLine`` view:
/// `View` is `@MainActor`, and this is pure model logic (formatting is
/// unit-tested off the main actor).
struct InfoLineContent: Equatable {
    /// "Bambu Lab P1S" — Sliced Files only, where the printer stands in for
    /// the geometry facts a stripped package can't provide; nil in the Viewer.
    var printerModel: String?
    /// "220 × 150 × 42 mm"; nil when the scene has no geometry.
    var dimensions: String?
    /// "3 objects" for a 3MF build, "5 meshes" for a GLB scene — straight
    /// from what the Viewer staged; nil for Sliced Files, which stage
    /// nothing.
    var objectCount: String?
    /// "10,185 triangles" — GLB only. It is the first thing anyone asks of a
    /// mesh they were handed, and the one fact a 3MF preview deliberately
    /// doesn't lead with (a print is described by its size, not its
    /// tessellation).
    var triangleCount: String?
    /// "1h 31m"; nil for Vanilla files and unsliced Plates.
    var printTime: String?
    /// One dot per filament the scene uses, in extruder order; empty when
    /// the file defines no colored filaments.
    var filamentColors: [ColorRGBA]

    /// The segments for a document and Plate (nil: the default scene), from
    /// the parse seam's ``ThreeMFDocument/sceneMetrics(for:)`` and
    /// ``ThreeMFDocument/usedFilamentIndices(for:)``.
    /// The segments for whichever format the Viewer is showing.
    init(for document: ModelDocument, plate: Plate?) {
        switch document {
        case .threeMF(let document): self.init(for: document, plate: plate)
        case .glb(let document): self.init(for: document)
        }
    }

    init(for document: ThreeMFDocument, plate: Plate?) {
        let metrics = document.sceneMetrics(for: plate)
        printerModel = nil
        dimensions = metrics.sizeMillimeters.map { Self.dimensionsText($0) }
        objectCount = Self.objectCountText(metrics.objectCount)
        triangleCount = nil
        printTime = (document.stagedPlate(for: plate)?.estimatedPrintTime)
            .map(Self.printTimeText)
        filamentColors = Self.filamentDots(for: plate, in: document)
    }

    /// The segments for a Sliced File's plate (issue #8): printer model,
    /// estimated print time, and the filaments its G-code uses. Never
    /// dimensions or object count — the geometry they would describe is
    /// stripped from these packages.
    /// The segments for a GLB scene: how big it is, how many meshes the
    /// scene places, and how heavy they are. No print time, no filaments —
    /// an asset has neither.
    init(for document: GLBDocument) {
        let metrics = document.sceneMetrics()
        printerModel = nil
        dimensions = metrics.sizeMeters.map(Self.dimensionsText(meters:))
        objectCount = Self.meshCountText(metrics.meshCount)
        triangleCount = Self.triangleCountText(metrics.triangleCount)
        printTime = nil
        filamentColors = []
    }

    init(forSlicedPlate plate: Plate?, in document: ThreeMFDocument) {
        printerModel = document.slicerProject?.printerModel
        dimensions = nil
        objectCount = nil
        triangleCount = nil
        printTime = plate?.estimatedPrintTime.map(Self.printTimeText)
        filamentColors = Self.filamentDots(for: plate, in: document)
    }

    /// The dot colors for a Plate's scene, in extruder order.
    /// usedFilamentIndices only returns valid indices into filaments.
    private static func filamentDots(for plate: Plate?, in document: ThreeMFDocument) -> [ColorRGBA] {
        let filaments = document.slicerProject?.filaments ?? []
        return document.usedFilamentIndices(for: plate).compactMap { filaments[$0].color }
    }

    // MARK: Formatting

    /// Width × depth × height along the model-space axes (3MF is Z-up).
    static func dimensionsText(_ sizeMillimeters: SIMD3<Float>) -> String {
        let dims = [sizeMillimeters.x, sizeMillimeters.y, sizeMillimeters.z]
        return dims.map(millimeters).joined(separator: " × ") + " mm"
    }

    /// One decimal only when it carries information: "25.4", but "43", not
    /// "43.0". Formatted via %f, never Int() — a hostile file's 1e30
    /// coordinate must not trap the conversion.
    private static func millimeters(_ value: Float) -> String {
        let tenths = (value * 10).rounded() / 10
        return String(format: tenths == tenths.rounded() ? "%.0f" : "%.1f", tenths)
    }

    /// Slicer-style hours and minutes: "1h 31m", "45m", "2h". Never zero —
    /// a just-started estimate reads "1m" — and long prints stay in hours,
    /// as slicers report them.
    static func printTimeText(_ seconds: TimeInterval) -> String {
        // Clamped so a hostile file's huge prediction can't trap Int().
        let totalMinutes = Int(min(max((seconds / 60).rounded(), 1), 60_000_000))
        let (hours, minutes) = totalMinutes.quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func objectCountText(_ count: Int) -> String {
        count == 1 ? "1 object" : "\(count) objects"
    }

    static func meshCountText(_ count: Int) -> String {
        count == 1 ? "1 mesh" : "\(count) meshes"
    }

    /// Grouped, and exact: "10,185 triangles". Rounding it to "10K" would
    /// hide the difference between a game-ready asset and a raw scan, which
    /// is most of why the number is there.
    static func triangleCountText(_ count: Int) -> String {
        let grouped = count.formatted(.number.grouping(.automatic))
        return count == 1 ? "1 triangle" : "\(grouped) triangles"
    }

    /// A GLB's extents in the format's own unit, meters — but stated in
    /// millimeters below a meter, because "0.04 m" is a worse way to say
    /// "40 mm" and a great many assets are palm-sized.
    static func dimensionsText(meters size: SIMD3<Float>) -> String {
        let dims = [size.x, size.y, size.z]
        guard dims.max() ?? 0 >= 1 else {
            return dimensionsText(size * 1000)
        }
        return dims.map { String(format: "%.2f", $0) }.joined(separator: " × ") + " m"
    }
}

/// The Info Line (CONTEXT.md): the single unobtrusive line of metadata in the
/// Viewer — bounding dimensions and object count for every file, plus
/// estimated print time and filament color dots for Slicer Projects. Sliced
/// Files swap the geometry facts for the printer model (issue #8). The only
/// text chrome in the preview, in the same vibrancy material as the
/// Filmstrip. Absent metadata drops its segment — no placeholders, no dashes.
struct InfoLine: View {
    let content: InfoLineContent

    var body: some View {
        HStack(spacing: 6) {
            Text(textSegments.joined(separator: " · "))
            if !content.filamentColors.isEmpty {
                Text("·")
                HStack(spacing: 4) {
                    ForEach(content.filamentColors.indices, id: \.self) { index in
                        FilamentDot(color: content.filamentColors[index])
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var textSegments: [String] {
        [
            content.printerModel, content.dimensions, content.objectCount,
            content.triangleCount, content.printTime,
        ].compactMap { $0 }
    }

    private var accessibilitySummary: String {
        var parts = textSegments
        if !content.filamentColors.isEmpty {
            let count = content.filamentColors.count
            parts.append(count == 1 ? "1 filament" : "\(count) filaments")
        }
        return parts.joined(separator: ", ")
    }
}

/// One filament color dot; the hairline border keeps light filaments visible
/// on the vibrancy material.
private struct FilamentDot: View {
    let color: ColorRGBA

    var body: some View {
        Circle()
            .fill(Color(
                red: Double(color.red) / 255,
                green: Double(color.green) / 255,
                blue: Double(color.blue) / 255))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
            .frame(width: 9, height: 9)
    }
}
