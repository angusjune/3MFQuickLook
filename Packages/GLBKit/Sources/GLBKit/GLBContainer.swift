import Foundation

/// The binary glTF wrapper: a 12-byte header followed by length-prefixed
/// chunks. Everything here is bounds-checked against the actual byte count
/// rather than trusting the header — these files arrive as untrusted
/// downloads and are parsed automatically by the Quick Look extensions.
///
/// Layout (glTF 2.0 §4.4, all little-endian):
///
///     u32 magic ("glTF") | u32 version | u32 length
///     [ u32 chunkLength | u32 chunkType | u8[chunkLength] chunkData ]…
struct GLBContainer {
    /// The first chunk: the glTF scene description.
    let json: Data
    /// The BIN chunk holding geometry and embedded images; nil when the file
    /// has none (legal — such a file's buffers must all be data: URIs).
    let binary: Data?

    private static let magic: UInt32 = 0x46546C67  // "glTF"
    private static let jsonChunkType: UInt32 = 0x4E4F534A  // "JSON"
    private static let binaryChunkType: UInt32 = 0x004E4942  // "BIN\0"
    private static let headerSize = 12
    private static let chunkHeaderSize = 8

    init(data: Data, limits: GLBParseLimits = .unlimited) throws {
        guard data.count >= Self.headerSize else { throw GLBParseError.truncatedContainer }
        guard data.readUInt32(at: 0) == Self.magic else { throw GLBParseError.notBinaryGLTF }

        let version = data.readUInt32(at: 4)
        guard version == 2 else { throw GLBParseError.unsupportedVersion(version) }

        // The header's own length field is advisory: honor it when it is
        // sane, but never read past what we actually hold.
        let declared = Int(data.readUInt32(at: 8))
        let end = declared > Self.headerSize ? min(declared, data.count) : data.count

        var json: Data?
        var binary: Data?
        var offset = Self.headerSize
        while offset + Self.chunkHeaderSize <= end {
            let length = Int(data.readUInt32(at: offset))
            let type = data.readUInt32(at: offset + 4)
            let start = offset + Self.chunkHeaderSize
            guard start + length <= end else { throw GLBParseError.truncatedContainer }

            switch type {
            case Self.jsonChunkType where json == nil:
                if let maxJSONBytes = limits.maxJSONBytes, length > maxJSONBytes {
                    throw GLBParseError.jsonChunkTooLarge(limit: maxJSONBytes)
                }
                json = data.slice(from: start, count: length)
            case Self.binaryChunkType where binary == nil:
                binary = data.slice(from: start, count: length)
            default:
                break  // Unknown chunk types are reserved; the spec says skip.
            }
            // Chunk lengths are already 4-byte aligned per spec; a file that
            // lies advances by its own claim and hits the bounds check above.
            offset = start + length
        }

        guard let json else { throw GLBParseError.missingJSONChunk }
        self.json = json
        self.binary = binary
    }
}

extension Data {
    /// Little-endian u32 at a byte offset relative to this value's start.
    /// The caller has already bounds-checked `offset + 4`.
    fileprivate func readUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    /// `count` bytes from `offset`, as a slice — deliberately not a copy, so
    /// a memory-mapped file stays mapped and a 500 MB BIN chunk never lands
    /// in the extension's address space twice. A `Data` slice keeps its
    /// parent's indices, so every read of it goes through `withUnsafeBytes`,
    /// which always yields the slice's own bytes from zero.
    fileprivate func slice(from offset: Int, count: Int) -> Data {
        self[index(startIndex, offsetBy: offset)..<index(startIndex, offsetBy: offset + count)]
    }
}
