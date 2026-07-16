import Foundation

/// Decodes Bambu Studio / OrcaSlicer triangle paint strokes: the
/// `paint_color` attribute, which both slicers write with PrusaSlicer's
/// TriangleSelector bitstream.
///
/// The bitstream describes one triangle's recursive sub-triangle
/// segmentation, packed into hex nibbles written in REVERSE order (the
/// stream starts at the string's last character). Each node is one nibble:
/// the low 2 bits are the number of split sides — 0 makes the node a leaf —
/// and the high 2 bits are the leaf's paint state, where `0b11` marks an
/// extended state carried as the next nibble plus 3. Split nodes use the
/// high bits for the split's "special side" (irrelevant here) and are
/// followed by their `splitSides + 1` children, depth-first. State 0 is
/// unpainted; state N paints filament N (1-based).
enum PaintColor {
    /// The dominant paint state of one encoded triangle: the state covering
    /// the largest share of its area, approximating each split's children as
    /// equal shares (per the PRD, sub-triangle fidelity is out of scope).
    /// Ties prefer paint over bare so faint strokes stay visible. Returns 0
    /// (unpainted) for empty or garbage values; a truncated stream counts
    /// whatever decoded before the cut.
    static func dominantState(of value: UnsafeBufferPointer<UInt8>) -> UInt32 {
        var cursor = value.count
        func nextNibble() -> UInt32? {
            cursor -= 1
            guard cursor >= 0, let digit = hexDigit(value[cursor]) else { return nil }
            return digit
        }

        var areaByState: [UInt32: Double] = [:]
        // Sibling order doesn't matter for area tallies, so a plain stack of
        // pending subtree shares stands in for the recursion.
        var pendingShares: [Double] = [1]
        while let share = pendingShares.popLast() {
            guard let code = nextNibble() else { break }
            let splitSides = code & 0b11
            if splitSides == 0 {
                var state = code >> 2
                if state == 0b11 {
                    guard let extended = nextNibble() else { break }
                    state = extended + 3
                }
                areaByState[state, default: 0] += share
            } else {
                let children = Double(splitSides) + 1
                pendingShares.append(
                    contentsOf: repeatElement(share / children, count: Int(splitSides) + 1))
            }
        }

        var dominant: (state: UInt32, area: Double) = (0, areaByState[0] ?? 0)
        for (state, area) in areaByState where state != 0 {
            // Painted beats bare on a tie; the lower state breaks painted
            // ties, keeping the pick independent of dictionary order.
            if area > dominant.area
                || (area == dominant.area && (dominant.state == 0 || state < dominant.state)) {
                dominant = (state, area)
            }
        }
        return dominant.state
    }

    private static func hexDigit(_ char: UInt8) -> UInt32? {
        switch char {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(char - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(char - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(char - UInt8(ascii: "A")) + 10
        default: nil
        }
    }
}
