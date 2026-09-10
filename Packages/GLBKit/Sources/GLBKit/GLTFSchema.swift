import Foundation

/// The slice of the glTF 2.0 JSON schema this parser reads. Every member is
/// optional exactly where the spec allows it to be absent, so a file that
/// omits an optional array decodes rather than failing.
///
/// Unknown keys (`extras`, unsupported `extensions`, animation and camera
/// arrays) are simply not modelled: `Decodable` ignores them.
struct GLTFJSON: Decodable {
    var asset: Asset?
    var scene: Int?
    var scenes: [Scene]?
    var nodes: [Node]?
    var meshes: [Mesh]?
    var accessors: [Accessor]?
    var bufferViews: [BufferView]?
    var buffers: [Buffer]?
    var materials: [Material]?
    var textures: [Texture]?
    var images: [Image]?
    var extensionsRequired: [String]?

    struct Asset: Decodable {
        var version: String?
        var generator: String?
    }

    struct Scene: Decodable {
        var name: String?
        var nodes: [Int]?
    }

    struct Node: Decodable {
        var name: String?
        var mesh: Int?
        var children: [Int]?
        /// Column-major 4×4, when the node uses a matrix.
        var matrix: [Float]?
        var translation: [Float]?
        /// Quaternion as (x, y, z, w) — note glTF's w-last order.
        var rotation: [Float]?
        var scale: [Float]?
    }

    struct Mesh: Decodable {
        var name: String?
        var primitives: [Primitive]?
    }

    struct Primitive: Decodable {
        /// Attribute name ("POSITION", "NORMAL", "TEXCOORD_0"…) → accessor
        /// index.
        var attributes: [String: Int]?
        var indices: Int?
        var material: Int?
        /// Primitive topology; 4 (TRIANGLES) when absent.
        var mode: Int?
        /// Present when the primitive's geometry is compressed — Draco keeps
        /// its accessors here instead of the plain `attributes` above.
        var `extensions`: [String: AnyIgnored]?
    }

    struct Accessor: Decodable {
        var bufferView: Int?
        var byteOffset: Int?
        var componentType: Int
        var count: Int
        /// "SCALAR", "VEC2", "VEC3", "VEC4", "MAT4"…
        var type: String
        var normalized: Bool?
        /// Sparse accessors substitute individual elements; unsupported, and
        /// modelled only so its presence can be detected.
        var sparse: AnyIgnored?
    }

    struct BufferView: Decodable {
        var buffer: Int
        var byteOffset: Int?
        var byteLength: Int
        /// Interleaved vertex data spaces elements this many bytes apart;
        /// absent means tightly packed.
        var byteStride: Int?
    }

    struct Buffer: Decodable {
        var byteLength: Int?
        /// Absent for the GLB BIN chunk (buffer 0). A `data:` URI is read;
        /// any other URI points outside the file and is never followed.
        var uri: String?
    }

    struct Material: Decodable {
        var name: String?
        var pbrMetallicRoughness: PBRMetallicRoughness?
        var doubleSided: Bool?
    }

    struct PBRMetallicRoughness: Decodable {
        /// Linear RGBA; the spec's default is opaque white.
        var baseColorFactor: [Float]?
        var baseColorTexture: TextureReference?
        var metallicFactor: Float?
        var roughnessFactor: Float?
    }

    struct TextureReference: Decodable {
        var index: Int
        /// Which TEXCOORD_n set the texture samples; only set 0 is honored.
        var texCoord: Int?
    }

    struct Texture: Decodable {
        /// Index into `images`; absent when the image only exists through an
        /// extension this parser doesn't read (KHR_texture_basisu).
        var source: Int?
    }

    struct Image: Decodable {
        var name: String?
        var mimeType: String?
        var bufferView: Int?
        /// A `data:` URI is decoded; any other URI points outside the file
        /// and is never followed.
        var uri: String?
    }

    /// A JSON value whose contents are irrelevant — only its presence
    /// matters. Decodes anything without materializing it.
    struct AnyIgnored: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

extension GLTFJSON {
    /// glTF primitive topologies this parser can turn into triangles.
    enum TriangleTopology: Int {
        case triangles = 4
        case triangleStrip = 5
        case triangleFan = 6
    }

    /// Component types, as the spec's GL enum values.
    enum ComponentType: Int {
        case byte = 5120
        case unsignedByte = 5121
        case short = 5122
        case unsignedShort = 5123
        case unsignedInt = 5125
        case float = 5126

        var byteCount: Int {
            switch self {
            case .byte, .unsignedByte: 1
            case .short, .unsignedShort: 2
            case .unsignedInt, .float: 4
            }
        }
    }

    /// Number of components per element for an accessor `type` string; nil
    /// for a type this parser doesn't read.
    static func componentCount(ofType type: String) -> Int? {
        switch type {
        case "SCALAR": 1
        case "VEC2": 2
        case "VEC3": 3
        case "VEC4": 4
        case "MAT2": 4
        case "MAT3": 9
        case "MAT4": 16
        default: nil
        }
    }
}
