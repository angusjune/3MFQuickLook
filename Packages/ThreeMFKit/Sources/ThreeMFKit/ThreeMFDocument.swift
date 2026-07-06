import simd

/// The parsed domain model of a 3MF package: the geometry, colors, and build
/// layout the Viewer and Thumbnail Extension need. Slicer metadata (plates,
/// filaments) is out of scope here (issue #4).
public struct ThreeMFDocument: Equatable, Sendable {
    public var unit: LengthUnit
    /// All object resources, across every model part, in document order.
    public var objects: [ObjectResource]
    /// The build items of the root model part, in document order.
    public var buildItems: [BuildItem]

    public init(unit: LengthUnit = .millimeter, objects: [ObjectResource] = [], buildItems: [BuildItem] = []) {
        self.unit = unit
        self.objects = objects
        self.buildItems = buildItems
    }

    public func object(_ ref: ResourceRef) -> ObjectResource? {
        objects.first { $0.ref == ref }
    }
}

/// The core-spec model units. Raw values match the `unit` attribute.
public enum LengthUnit: String, Equatable, Sendable {
    case micron, millimeter, centimeter, inch, foot, meter

    public var metersPerUnit: Float {
        switch self {
        case .micron: 1e-6
        case .millimeter: 1e-3
        case .centimeter: 1e-2
        case .inch: 0.0254
        case .foot: 0.3048
        case .meter: 1
        }
    }
}

/// Identifies an object resource within the package: the model part that
/// defines it plus its `id` in that part. Production-extension packages
/// define objects across several parts, so the id alone is not unique.
public struct ResourceRef: Hashable, Sendable {
    /// Zip-absolute part path, e.g. "/3D/3dmodel.model".
    public var partPath: String
    public var id: UInt32

    public init(partPath: String, id: UInt32) {
        self.partPath = partPath
        self.id = id
    }
}

public struct ObjectResource: Equatable, Sendable {
    public var ref: ResourceRef
    public var name: String?
    /// The object-level color resolved from its `pid`/`pindex` property
    /// reference (base material or color group), when present.
    public var defaultColor: ColorRGBA?
    public var content: Content

    public enum Content: Equatable, Sendable {
        case mesh(Mesh)
        case components([Component])
    }

    public init(ref: ResourceRef, name: String? = nil, defaultColor: ColorRGBA? = nil, content: Content) {
        self.ref = ref
        self.name = name
        self.defaultColor = defaultColor
        self.content = content
    }
}

/// Triangle geometry. Indices are flat, three per triangle.
public struct Mesh: Equatable, Sendable {
    public var positions: [SIMD3<Float>]
    public var triangleIndices: [UInt32]
    /// Per-triangle colors resolved from triangle-level property references
    /// (`pid`/`p1`), when any triangle carries one; nil otherwise. Count
    /// matches `triangleCount` when present.
    public var triangleColors: [ColorRGBA]?

    public var triangleCount: Int { triangleIndices.count / 3 }

    public init(positions: [SIMD3<Float>] = [], triangleIndices: [UInt32] = [], triangleColors: [ColorRGBA]? = nil) {
        self.positions = positions
        self.triangleIndices = triangleIndices
        self.triangleColors = triangleColors
    }
}

public struct Component: Equatable, Sendable {
    public var objectRef: ResourceRef
    public var transform: simd_float4x4

    public init(objectRef: ResourceRef, transform: simd_float4x4 = matrix_identity_float4x4) {
        self.objectRef = objectRef
        self.transform = transform
    }
}

public struct BuildItem: Equatable, Sendable {
    public var objectRef: ResourceRef
    public var transform: simd_float4x4

    public init(objectRef: ResourceRef, transform: simd_float4x4 = matrix_identity_float4x4) {
        self.objectRef = objectRef
        self.transform = transform
    }
}

/// An sRGB color from a 3MF `#RRGGBB` or `#RRGGBBAA` value.
public struct ColorRGBA: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(hex: some StringProtocol) {
        guard hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8,
              let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(
                red: UInt8((value >> 16) & 0xFF),
                green: UInt8((value >> 8) & 0xFF),
                blue: UInt8(value & 0xFF))
        } else {
            self.init(
                red: UInt8((value >> 24) & 0xFF),
                green: UInt8((value >> 16) & 0xFF),
                blue: UInt8((value >> 8) & 0xFF),
                alpha: UInt8(value & 0xFF))
        }
    }
}
