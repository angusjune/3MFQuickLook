import Foundation

/// Parse-time resource policy for GLB files: the Geometry Budget plus the
/// caps on the parts of a file that are read whole into memory.
///
/// The twin of `ThreeMFKit.ParseLimits`, deliberately kept as a separate
/// type rather than shared: the two formats have different things to bound
/// (a GLB has no zip stream to guard, a 3MF has no texture payload), and the
/// packages stay independent. The numbers that must agree — the Geometry
/// Budget — are documented together in docs/geometry-budget.md.
public struct GLBParseLimits: Equatable, Sendable {
    /// The Geometry Budget (CONTEXT.md): the maximum geometry elements —
    /// vertices plus triangles, summed across every primitive — the parse
    /// will materialize. Crossing it aborts with
    /// ``GLBParseError/overGeometryBudget(budget:)`` so the preview can point
    /// at the Host App instead of attempting 3D. Nil: unlimited.
    public var geometryBudget: Int?

    /// The maximum size of the JSON chunk. A glTF scene description is
    /// kilobytes to low megabytes even for huge files; a header claiming
    /// gigabytes of JSON is not legitimate content.
    /// Nil: unlimited.
    public var maxJSONBytes: Int?

    /// The maximum total encoded bytes of base-color texture images carried
    /// into the document. Textures are garnish: past this the material keeps
    /// its base color factor and loses its map, never a parse failure.
    /// Nil: unlimited.
    public var maxTextureBytes: Int?

    public init(
        geometryBudget: Int? = nil,
        maxJSONBytes: Int? = nil,
        maxTextureBytes: Int? = nil
    ) {
        self.geometryBudget = geometryBudget
        self.maxJSONBytes = maxJSONBytes
        self.maxTextureBytes = maxTextureBytes
    }

    /// No limits: the Host App's policy, and the default.
    public static let unlimited = GLBParseLimits()

    /// The Preview and Thumbnail Extensions' policy. The Geometry Budget
    /// matches the 3MF one element for element — it bounds the same
    /// RealityKit allocations under the same extension memory ceiling
    /// (docs/geometry-budget.md).
    public static let quickLookExtension = GLBParseLimits(
        geometryBudget: 4_000_000,
        maxJSONBytes: 64 * 1024 * 1024,
        maxTextureBytes: 64 * 1024 * 1024)
}
