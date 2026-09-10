import Foundation
import simd

/// Reads glTF accessors out of the file's buffers into plain Swift arrays.
///
/// Two failure modes, kept strictly apart (see ``GLBParseError``):
/// *corrupt* — an index or a declared layout that doesn't fit its buffer —
/// throws, while *valid but unsupported* — a sparse accessor, an attribute
/// stored as a type this parser doesn't read — returns nil so the caller can
/// skip that primitive and render the rest of the file.
struct GLTFAccessorReader {
    let json: GLTFJSON
    /// Resolved buffer bytes, index-aligned with `json.buffers`; nil where a
    /// buffer points outside the file.
    let buffers: [Data?]

    /// A VEC3 float attribute — POSITION or NORMAL.
    func vectors3(accessor index: Int) throws -> [SIMD3<Float>]? {
        guard let layout = try layout(accessor: index), layout.componentCount == 3 else {
            return nil
        }
        return layout.buffer.withUnsafeBytes { raw in
            (0..<layout.count).map { element in
                let base = layout.start + element * layout.stride
                return SIMD3(
                    layout.component(raw, base, 0),
                    layout.component(raw, base, 1),
                    layout.component(raw, base, 2))
            }
        }
    }

    /// A VEC2 float attribute — TEXCOORD_0. Texture coordinates are the one
    /// place normalized integer storage is common, and ``Layout/component``
    /// handles it.
    func vectors2(accessor index: Int) throws -> [SIMD2<Float>]? {
        guard let layout = try layout(accessor: index), layout.componentCount == 2 else {
            return nil
        }
        return layout.buffer.withUnsafeBytes { raw in
            (0..<layout.count).map { element in
                let base = layout.start + element * layout.stride
                return SIMD2(layout.component(raw, base, 0), layout.component(raw, base, 1))
            }
        }
    }

    /// A SCALAR unsigned-integer index accessor.
    func indices(accessor index: Int) throws -> [UInt32]? {
        guard let layout = try layout(accessor: index), layout.componentCount == 1 else {
            return nil
        }
        let componentType = layout.componentType
        guard componentType == .unsignedByte
            || componentType == .unsignedShort
            || componentType == .unsignedInt
        else { return nil }

        return layout.buffer.withUnsafeBytes { raw in
            (0..<layout.count).map { element in
                let offset = layout.start + element * layout.stride
                return switch componentType {
                case .unsignedByte: UInt32(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                case .unsignedShort:
                    UInt32(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                default:
                    UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                }
            }
        }
    }

    /// The number of elements an accessor declares, without reading it —
    /// used to charge the Geometry Budget before materializing anything.
    /// Nil when the accessor doesn't exist.
    func elementCount(accessor index: Int) -> Int? {
        guard let accessor = json.accessors?[safe: index] else { return nil }
        return max(accessor.count, 0)
    }

    // MARK: Layout

    /// Where an accessor's elements actually live, once every index in the
    /// chain has been checked against the bytes the file really holds.
    private struct Layout {
        let buffer: Data
        /// Byte offset of element 0, relative to `buffer`'s own start.
        let start: Int
        let stride: Int
        let count: Int
        let componentType: GLTFJSON.ComponentType
        let componentCount: Int
        let normalized: Bool

        /// One component of one element, as a float — decoding glTF's
        /// normalized integer storage on the way (spec §3.6.2.2).
        @inline(__always)
        func component(_ raw: UnsafeRawBufferPointer, _ elementOffset: Int, _ index: Int) -> Float {
            let offset = elementOffset + index * componentType.byteCount
            switch componentType {
            case .float:
                return Float(bitPattern: UInt32(
                    littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
            case .byte:
                let value = Float(raw.loadUnaligned(fromByteOffset: offset, as: Int8.self))
                return normalized ? max(value / 127, -1) : value
            case .unsignedByte:
                let value = Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                return normalized ? value / 255 : value
            case .short:
                let value = Float(Int16(
                    littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
                return normalized ? max(value / 32767, -1) : value
            case .unsignedShort:
                let value = Float(UInt16(
                    littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                return normalized ? value / 65535 : value
            case .unsignedInt:
                return Float(UInt32(
                    littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
            }
        }
    }

    /// Resolves and validates an accessor's storage. Throws on anything
    /// corrupt; returns nil for a well-formed accessor this parser can't
    /// read (sparse, an unmodelled component type, or one with no buffer
    /// view — the spec's implicit all-zeros data, which has nothing to draw).
    private func layout(accessor index: Int) throws -> Layout? {
        guard let accessor = json.accessors?[safe: index] else {
            throw GLBParseError.malformedAccessor(index: index)
        }
        guard accessor.sparse == nil,
              let componentType = GLTFJSON.ComponentType(rawValue: accessor.componentType),
              let componentCount = GLTFJSON.componentCount(ofType: accessor.type),
              let viewIndex = accessor.bufferView
        else { return nil }

        guard accessor.count >= 0 else { throw GLBParseError.malformedAccessor(index: index) }
        guard let view = json.bufferViews?[safe: viewIndex] else {
            throw GLBParseError.malformedAccessor(index: index)
        }
        guard let buffer = buffers[safe: view.buffer] else {
            throw GLBParseError.malformedAccessor(index: index)
        }
        guard let buffer else { throw GLBParseError.unresolvableBuffer(index: view.buffer) }

        let viewStart = view.byteOffset ?? 0
        let viewLength = view.byteLength
        guard viewStart >= 0, viewLength >= 0, viewStart + viewLength <= buffer.count else {
            throw GLBParseError.malformedAccessor(index: index)
        }

        let elementSize = componentCount * componentType.byteCount
        let stride = view.byteStride ?? elementSize
        let accessorOffset = accessor.byteOffset ?? 0
        guard stride >= elementSize, accessorOffset >= 0 else {
            throw GLBParseError.malformedAccessor(index: index)
        }
        // Overflow-checked: a hostile file can declare a count of 2^62.
        let (span, spanOverflowed) = max(accessor.count - 1, 0).multipliedReportingOverflow(by: stride)
        let (needed, neededOverflowed) = span.addingReportingOverflow(
            accessor.count == 0 ? 0 : elementSize)
        guard !spanOverflowed, !neededOverflowed,
              accessorOffset + needed <= viewLength
        else { throw GLBParseError.malformedAccessor(index: index) }

        return Layout(
            buffer: buffer,
            start: viewStart + accessorOffset,
            stride: stride,
            count: accessor.count,
            componentType: componentType,
            componentCount: componentCount,
            normalized: accessor.normalized ?? false)
    }
}

extension Array {
    /// Bounds-checked subscript: glTF is a graph of integer indices, all of
    /// them untrusted.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
