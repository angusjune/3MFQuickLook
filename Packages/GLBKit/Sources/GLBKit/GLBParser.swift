import Foundation
import simd

/// Parses a binary glTF (`.glb`) file into a ``GLBDocument``.
///
/// Native and dependency-free, for the same reasons the 3MF parser is
/// (ADR-0002): the container is a header and three integers, and the
/// alternative is a C++ toolkit inside a sandboxed extension with a hard
/// memory ceiling. The parse is deliberately partial — geometry, node
/// hierarchy, and base color — because that is what a preview draws.
/// Animation, skinning, cameras, and lights are read past: a skinned mesh
/// previews in its bind pose, which is the pose its exporter's own
/// thumbnail shows.
public struct GLBParser: Sendable {
    private let limits: GLBParseLimits

    /// glTF extensions that change where geometry lives, rather than how it
    /// looks. A file *requiring* one of these has no readable vertices at
    /// all, so it fails rather than previewing as an empty stage. Every
    /// other required extension is tolerated: the worst case is a material
    /// that renders a shade off, and refusing the whole file over that would
    /// be the wrong trade for a preview.
    private static let unsupportedRequiredExtensions: Set<String> = [
        "KHR_draco_mesh_compression",
        "EXT_meshopt_compression",
    ]

    /// - Parameter limits: the parse-time resource policy. The Quick Look
    ///   extensions pass ``GLBParseLimits/quickLookExtension``; the Host App
    ///   and tests parse ``GLBParseLimits/unlimited``.
    public init(limits: GLBParseLimits = .unlimited) {
        self.limits = limits
    }

    /// Parses the file at `url`. Mapped rather than read: a half-gigabyte
    /// asset must not land in the extension's address space in full when the
    /// Geometry Budget is about to turn it away anyway.
    public func parse(fileAt url: URL) throws -> GLBDocument {
        try parse(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Parses a GLB held in memory — the Host App's document windows read
    /// files through `FileDocument`, which supplies bytes, not a URL.
    public func parse(data: Data) throws -> GLBDocument {
        let container = try GLBContainer(data: data, limits: limits)
        let json = try Self.decodeJSON(container.json)
        try Self.checkRequiredExtensions(json)

        let buffers = Self.resolveBuffers(json, binaryChunk: container.binary)
        let reader = GLTFAccessorReader(json: json, buffers: buffers)
        let meshes = try GLTFMeshResolver(json: json, reader: reader, limits: limits)
            .resolveMeshes(budget: GLTFMeshResolver.Budget())
        guard meshes.contains(where: { !$0.primitives.isEmpty }) else {
            throw GLBParseError.noRenderableGeometry
        }

        let (materials, images) = GLTFMaterialResolver(
            json: json, buffers: buffers, limits: limits).resolve()
        let nodes = Self.resolveNodes(json, meshCount: meshes.count)

        return GLBDocument(
            nodes: nodes,
            rootNodeIndices: Self.rootNodeIndices(json, nodes: nodes),
            meshes: meshes,
            materials: materials,
            images: images,
            generator: json.asset?.generator)
    }

    // MARK: JSON

    private static func decodeJSON(_ data: Data) throws -> GLTFJSON {
        do {
            return try JSONDecoder().decode(GLTFJSON.self, from: data)
        } catch let error as DecodingError {
            throw GLBParseError.malformedJSON(Self.message(for: error))
        } catch {
            throw GLBParseError.malformedJSON(error.localizedDescription)
        }
    }

    /// A short, specific reason a document failed to decode — the key that
    /// went wrong, not a paragraph of `Codable` internals.
    private static func message(for error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
             .keyNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func checkRequiredExtensions(_ json: GLTFJSON) throws {
        for name in json.extensionsRequired ?? []
        where unsupportedRequiredExtensions.contains(name) {
            throw GLBParseError.unsupportedRequiredExtension(name)
        }
    }

    // MARK: Buffers

    /// The bytes behind each declared buffer, index-aligned with
    /// `json.buffers`. Buffer 0 without a URI is the GLB's own BIN chunk;
    /// `data:` URIs are decoded (they live inside the already-capped JSON
    /// chunk); any other URI names a file beside this one, which a sandboxed
    /// preview never opens — those buffers stay nil and any accessor
    /// reaching for one reports ``GLBParseError/unresolvableBuffer(index:)``.
    private static func resolveBuffers(_ json: GLTFJSON, binaryChunk: Data?) -> [Data?] {
        (json.buffers ?? []).enumerated().map { index, buffer in
            guard let uri = buffer.uri else {
                return index == 0 ? binaryChunk : nil
            }
            return GLTFMaterialResolver.decodeDataURI(uri)
        }
    }

    // MARK: Nodes

    /// Node transforms and child links, with every index checked. Malformed
    /// files can still describe a cycle; consumers walk the hierarchy with a
    /// visited set, exactly as the 3MF path does for component references.
    private static func resolveNodes(_ json: GLTFJSON, meshCount: Int) -> [GLBNode] {
        let jsonNodes = json.nodes ?? []
        return jsonNodes.enumerated().map { index, node in
            GLBNode(
                name: node.name,
                transform: transform(of: node),
                meshIndex: node.mesh.flatMap { (0..<meshCount).contains($0) ? $0 : nil },
                childIndices: (node.children ?? []).filter {
                    jsonNodes.indices.contains($0) && $0 != index
                })
        }
    }

    /// The node's local transform: its `matrix` when it has one, else the
    /// spec's T · R · S composition of its translation, rotation, and scale.
    private static func transform(of node: GLTFJSON.Node) -> simd_float4x4 {
        if let matrix = node.matrix, matrix.count == 16 {
            // glTF stores matrices column-major, which is simd's own order.
            return simd_float4x4(
                SIMD4(matrix[0], matrix[1], matrix[2], matrix[3]),
                SIMD4(matrix[4], matrix[5], matrix[6], matrix[7]),
                SIMD4(matrix[8], matrix[9], matrix[10], matrix[11]),
                SIMD4(matrix[12], matrix[13], matrix[14], matrix[15]))
        }

        var result = matrix_identity_float4x4
        if let rotation = node.rotation, rotation.count == 4 {
            // glTF orders quaternions (x, y, z, w); simd's initializer takes
            // the same order — but its `vector` property is w-last too, so
            // the pairing is easy to get backwards. Spelled out on purpose.
            result = simd_float4x4(simd_quatf(
                ix: rotation[0], iy: rotation[1], iz: rotation[2], r: rotation[3]))
        }
        if let scale = node.scale, scale.count == 3 {
            result.columns.0 *= scale[0]
            result.columns.1 *= scale[1]
            result.columns.2 *= scale[2]
        }
        if let translation = node.translation, translation.count == 3 {
            result.columns.3 = SIMD4(translation[0], translation[1], translation[2], 1)
        }
        return result
    }

    /// The nodes the default scene places. Falls back — for files that
    /// declare no scene, or name one that isn't there — to every node no
    /// other node claims as a child, which is what the hierarchy says even
    /// when the scene list doesn't.
    private static func rootNodeIndices(_ json: GLTFJSON, nodes: [GLBNode]) -> [Int] {
        let scenes = json.scenes ?? []
        let declared = (scenes[safe: json.scene ?? 0] ?? scenes.first)?.nodes
        if let declared {
            let valid = declared.filter { nodes.indices.contains($0) }
            if !valid.isEmpty { return valid }
        }
        let claimed = Set(nodes.flatMap(\.childIndices))
        return nodes.indices.filter { !claimed.contains($0) }
    }
}
