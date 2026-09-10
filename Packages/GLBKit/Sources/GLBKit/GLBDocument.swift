import Foundation
import simd

/// The parsed domain model of a GLB file: the node hierarchy, the triangle
/// geometry hanging off it, and the base-color materials the Viewer paints
/// it with.
///
/// glTF's own coordinate conventions are kept verbatim — right-handed,
/// Y-up, meters — because they are already RealityKit's, so nothing here
/// needs a units or axis conversion (unlike 3MF, which is Z-up in model
/// units).
public struct GLBDocument: Equatable, Sendable {
    /// Every node in the file, in glTF order. Children are referenced by
    /// index into this array; the hierarchy is walked from ``rootNodeIndices``.
    public var nodes: [GLBNode]
    /// The nodes the default scene places, in file order.
    public var rootNodeIndices: [Int]
    /// Every mesh in the file, in glTF order; nodes reference them by index.
    public var meshes: [GLBMesh]
    /// Every material a primitive references, in glTF order.
    public var materials: [GLBMaterial]
    /// Base-color texture images, deduplicated — only the ones a material
    /// actually paints with are carried, so a file's normal, roughness, and
    /// occlusion maps never cost memory in the preview.
    public var images: [GLBImage]
    /// The `asset.generator` string the exporter wrote ("Blender glTF 2.0"),
    /// when it wrote one.
    public var generator: String?

    public init(
        nodes: [GLBNode] = [],
        rootNodeIndices: [Int] = [],
        meshes: [GLBMesh] = [],
        materials: [GLBMaterial] = [],
        images: [GLBImage] = [],
        generator: String? = nil
    ) {
        self.nodes = nodes
        self.rootNodeIndices = rootNodeIndices
        self.meshes = meshes
        self.materials = materials
        self.images = images
        self.generator = generator
    }

    public func node(at index: Int) -> GLBNode? {
        nodes.indices.contains(index) ? nodes[index] : nil
    }

    public func mesh(at index: Int) -> GLBMesh? {
        meshes.indices.contains(index) ? meshes[index] : nil
    }

    public func material(at index: Int) -> GLBMaterial? {
        materials.indices.contains(index) ? materials[index] : nil
    }
}

/// One glTF node: a local transform, optionally a mesh, and children.
public struct GLBNode: Equatable, Sendable {
    public var name: String?
    /// The node's local transform, from its `matrix` or its
    /// translation/rotation/scale triple.
    public var transform: simd_float4x4
    /// Index into ``GLBDocument/meshes``; nil for a pure grouping node.
    public var meshIndex: Int?
    /// Indices into ``GLBDocument/nodes``, validated to be in range.
    public var childIndices: [Int]

    public init(
        name: String? = nil,
        transform: simd_float4x4 = matrix_identity_float4x4,
        meshIndex: Int? = nil,
        childIndices: [Int] = []
    ) {
        self.name = name
        self.transform = transform
        self.meshIndex = meshIndex
        self.childIndices = childIndices
    }
}

/// A glTF mesh: one or more primitives, each with its own material.
public struct GLBMesh: Equatable, Sendable {
    public var name: String?
    public var primitives: [GLBPrimitive]

    public init(name: String? = nil, primitives: [GLBPrimitive] = []) {
        self.name = name
        self.primitives = primitives
    }

    public var triangleCount: Int {
        primitives.reduce(0) { $0 + $1.triangleCount }
    }
}

/// One drawable chunk of a mesh, with its accessors already resolved into
/// vertex arrays. Only triangle primitives survive the parse — points and
/// lines have nothing to render in a preview.
public struct GLBPrimitive: Equatable, Sendable {
    public var positions: [SIMD3<Float>]
    /// Vertex normals as the file supplies them; nil when it doesn't, in
    /// which case the scene builder computes flat-shaded ones (the spec's
    /// rule for a primitive without NORMAL).
    public var normals: [SIMD3<Float>]?
    /// TEXCOORD_0 in glTF's own convention (origin at the image's top-left
    /// corner); nil when the primitive carries none. Renderers whose
    /// convention differs flip it — the parser stays faithful to the file.
    public var textureCoordinates: [SIMD2<Float>]?
    /// Flat triangle indices, three per triangle. A non-indexed primitive
    /// gets the implied 0, 1, 2… sequence so consumers have one shape to
    /// handle.
    public var indices: [UInt32]
    /// Index into ``GLBDocument/materials``; nil means the glTF default
    /// material (opaque white).
    public var materialIndex: Int?

    public var triangleCount: Int { indices.count / 3 }

    public init(
        positions: [SIMD3<Float>] = [],
        normals: [SIMD3<Float>]? = nil,
        textureCoordinates: [SIMD2<Float>]? = nil,
        indices: [UInt32] = [],
        materialIndex: Int? = nil
    ) {
        self.positions = positions
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.indices = indices
        self.materialIndex = materialIndex
    }
}

/// The slice of a glTF material a preview can honor: its base color, as a
/// factor and optionally a texture. Normal, occlusion, and emissive maps are
/// deliberately dropped — they cost megabytes of decode for detail nobody
/// reads at thumbnail size.
public struct GLBMaterial: Equatable, Sendable {
    public var name: String?
    /// `pbrMetallicRoughness.baseColorFactor`, in linear space, defaulting
    /// to the spec's opaque white.
    public var baseColor: GLBColor
    /// Index into ``GLBDocument/images`` for the base-color map; nil when
    /// the material has none, or its image could not be carried (an
    /// unsupported codec, or past the texture budget).
    public var baseColorImageIndex: Int?
    public var metallic: Float
    public var roughness: Float

    public init(
        name: String? = nil,
        baseColor: GLBColor = .white,
        baseColorImageIndex: Int? = nil,
        metallic: Float = 1,
        roughness: Float = 1
    ) {
        self.name = name
        self.baseColor = baseColor
        self.baseColorImageIndex = baseColorImageIndex
        self.metallic = metallic
        self.roughness = roughness
    }

    /// The glTF default material, for primitives that reference none.
    public static let `default` = GLBMaterial()
}

/// Encoded image bytes for a base-color texture, exactly as the file stores
/// them (PNG or JPEG). Decoding — with its bomb guard — belongs to the
/// renderer, not the parser.
public struct GLBImage: Equatable, Sendable {
    public var data: Data
    /// The declared `mimeType`, when the file declares one.
    public var mimeType: String?

    public init(data: Data, mimeType: String? = nil) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// A linear-space RGBA color, glTF's `baseColorFactor` as written.
public struct GLBColor: Hashable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = GLBColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// The same color in sRGB, for handing to AppKit and RealityKit, which
    /// take gamma-encoded components.
    public var sRGBComponents: (red: Float, green: Float, blue: Float, alpha: Float) {
        (Self.encodeSRGB(red), Self.encodeSRGB(green), Self.encodeSRGB(blue), alpha.clamped01)
    }

    /// The sRGB electro-optical transfer function, inverted (linear →
    /// encoded), per IEC 61966-2-1.
    private static func encodeSRGB(_ linear: Float) -> Float {
        let value = linear.clamped01
        return value <= 0.0031308
            ? value * 12.92
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

extension Float {
    fileprivate var clamped01: Float {
        // NaN compares false against both bounds, so it lands on 0 rather
        // than propagating into a color a renderer can't handle.
        self > 0 ? (self < 1 ? self : 1) : 0
    }
}
