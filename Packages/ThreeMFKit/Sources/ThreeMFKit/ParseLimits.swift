import Foundation

/// Parse-time resource policy (issue #10): the Geometry Budget plus the
/// zip-bomb caps. The Quick Look extensions parse untrusted downloads
/// automatically inside hard memory limits, so they pass
/// ``quickLookExtension``; the Host App is user-initiated and loads
/// everything, so it parses ``unlimited``.
public struct ParseLimits: Equatable, Sendable {
    /// The Geometry Budget (CONTEXT.md): the maximum geometry elements —
    /// vertices plus triangles, summed across every model part — the parse
    /// will materialize. Crossing it aborts with
    /// ``ThreeMFParseError/overGeometryBudget(budget:)`` so the preview can
    /// stay on the Embedded Thumbnail instead of attempting 3D. Vertices
    /// count because they allocate even when no triangle references them.
    /// Nil: unlimited.
    public var geometryBudget: Int?

    /// Zip-bomb cap: the maximum decompressed bytes streamed out of any
    /// single model part. Geometry is parsed streaming, so this bounds
    /// decompression *work* (a tiny archive expanding to gigabytes of
    /// skipped XML), not memory — the Geometry Budget bounds memory.
    /// Crossing it aborts with
    /// ``ThreeMFParseError/decompressedPartTooLarge(partPath:)``.
    /// Nil: unlimited.
    public var maxStreamedPartBytes: Int?

    /// Zip-bomb cap: the maximum decompressed size of any part read whole
    /// into memory — Embedded Thumbnails and slicer config parts. These
    /// parts are garnish, so an oversized one is treated as absent
    /// (lenient), never materialized, and never a parse failure.
    /// Nil: unlimited.
    public var maxMaterializedPartBytes: Int?

    public init(
        geometryBudget: Int? = nil,
        maxStreamedPartBytes: Int? = nil,
        maxMaterializedPartBytes: Int? = nil
    ) {
        self.geometryBudget = geometryBudget
        self.maxStreamedPartBytes = maxStreamedPartBytes
        self.maxMaterializedPartBytes = maxMaterializedPartBytes
    }

    /// No limits: the Host App's policy, and the default.
    public static let unlimited = ParseLimits()

    /// The Preview and Thumbnail Extensions' policy. Values derived from
    /// profiling against the extension memory ceiling — the measurements and
    /// rationale live in docs/geometry-budget.md.
    public static let quickLookExtension = ParseLimits(
        geometryBudget: 4_000_000,
        maxStreamedPartBytes: 512 * 1024 * 1024,
        maxMaterializedPartBytes: 64 * 1024 * 1024)
}
