import Foundation

/// Why a GLB file could not be turned into a ``GLBDocument``.
///
/// The split is deliberate: *corrupt* input (a truncated chunk, an accessor
/// pointing past its buffer) is an error, while input that is valid but
/// carries nothing this preview can draw (a points-only primitive, a
/// texture in a codec ImageIO can't read) is skipped leniently by the
/// parser and never surfaces here.
public enum GLBParseError: Error, Equatable, Sendable {
    /// The file does not start with the `glTF` magic — not a GLB at all.
    /// (Text `.gltf` files land here too: they are JSON, not this container.)
    case notBinaryGLTF
    /// A container version this parser doesn't speak. Only glTF 2 exists in
    /// practice; glTF 1 is a different, incompatible format.
    case unsupportedVersion(UInt32)
    /// The header, a chunk header, or a chunk's payload runs past the end of
    /// the file.
    case truncatedContainer
    /// No JSON chunk, or it isn't the first chunk the spec requires.
    case missingJSONChunk
    /// The JSON chunk is past ``GLBParseLimits/maxJSONBytes``.
    case jsonChunkTooLarge(limit: Int)
    /// The JSON chunk isn't valid glTF JSON. Carries the underlying decoding
    /// message, which names the offending key.
    case malformedJSON(String)
    /// The file declares an extension in `extensionsRequired` that this
    /// parser can't honor — Draco or meshopt compression, most often. The
    /// geometry is genuinely unreadable without it, so this is an error
    /// rather than a silent partial render.
    case unsupportedRequiredExtension(String)
    /// A buffer this file's geometry needs isn't in the container: an
    /// external `uri` (never followed — the extensions are sandboxed and a
    /// preview must not reach outside the file it was handed) or a missing
    /// BIN chunk.
    case unresolvableBuffer(index: Int)
    /// An accessor, buffer view, or index is out of range, or declares a
    /// layout that doesn't fit its buffer view.
    case malformedAccessor(index: Int)
    /// The file parsed, but nothing in it can be drawn: every primitive was
    /// unsupported or empty. Reported rather than returning an empty
    /// document, so the preview says "can't read this" instead of showing an
    /// empty stage.
    case noRenderableGeometry
    /// The file's geometry is past the Geometry Budget (CONTEXT.md). Mirrors
    /// `ThreeMFParseError.overGeometryBudget` so both preview paths report
    /// the same condition.
    case overGeometryBudget(budget: Int)
}

extension GLBParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notBinaryGLTF:
            "Not a binary glTF (.glb) file."
        case .unsupportedVersion(let version):
            "Unsupported glTF container version \(version); only version 2 is supported."
        case .truncatedContainer:
            "The file ends in the middle of a chunk."
        case .missingJSONChunk:
            "The file has no glTF JSON chunk."
        case .jsonChunkTooLarge(let limit):
            "The glTF JSON chunk is larger than \(limit) bytes."
        case .malformedJSON(let message):
            "The glTF JSON could not be read: \(message)"
        case .unsupportedRequiredExtension(let name):
            "The file requires the unsupported glTF extension “\(name)”."
        case .unresolvableBuffer(let index):
            "Buffer \(index) is not contained in the file."
        case .malformedAccessor(let index):
            "Accessor \(index) does not fit the data it points at."
        case .noRenderableGeometry:
            "The file contains no triangle geometry to display."
        case .overGeometryBudget(let budget):
            "The file's geometry exceeds the \(budget)-element preview budget."
        }
    }
}
