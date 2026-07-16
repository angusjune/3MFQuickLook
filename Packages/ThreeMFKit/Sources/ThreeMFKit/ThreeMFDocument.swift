import Foundation
import simd

/// The parsed domain model of a 3MF package: the geometry, colors, and build
/// layout the Viewer and Thumbnail Extension need.
public struct ThreeMFDocument: Equatable, Sendable {
    public var unit: LengthUnit
    /// All object resources, across every model part, in document order.
    public var objects: [ObjectResource]
    /// The build items of the root model part, in document order.
    public var buildItems: [BuildItem]
    /// Slicer Project metadata (Bambu Studio / OrcaSlicer dialect); nil for
    /// Vanilla files — including PrusaSlicer projects, which are Vanilla-plus
    /// (CONTEXT.md).
    public var slicerProject: SlicerProjectInfo?

    public init(
        unit: LengthUnit = .millimeter,
        objects: [ObjectResource] = [],
        buildItems: [BuildItem] = [],
        slicerProject: SlicerProjectInfo? = nil
    ) {
        self.unit = unit
        self.objects = objects
        self.buildItems = buildItems
        self.slicerProject = slicerProject
    }

    public func object(_ ref: ResourceRef) -> ObjectResource? {
        objects.first { $0.ref == ref }
    }
}

/// An Embedded Thumbnail (CONTEXT.md): the pre-rendered image a package
/// carries — a Slicer Project's Plate Thumbnail or a Vanilla file's OPC
/// Package Thumbnail. Extracted cheaply, without parsing geometry, so the
/// preview and Finder icon can paint instantly.
public struct EmbeddedThumbnail: Equatable, Sendable {
    /// Zip-absolute path of the image part, e.g. "/Metadata/plate_1.png".
    public var partPath: String
    /// The raw image bytes (PNG or JPEG, as the slicer wrote them).
    public var data: Data

    public init(partPath: String, data: Data) {
        self.partPath = partPath
        self.data = data
    }
}

/// What makes a package a Slicer Project (CONTEXT.md): its Plates, filament
/// definitions, and object→filament assignments, from the Bambu/Orca
/// `Metadata/*.config` parts.
public struct SlicerProjectInfo: Equatable, Sendable {
    /// Filaments in extruder order (extruder N ↔ index N−1).
    public var filaments: [Filament]
    /// All Build Plates, in file order.
    public var plates: [Plate]
    /// 0-based index into `filaments` per object, from the object-level
    /// `extruder` assignment. Objects without an entry use filament 0.
    public var filamentIndexByObject: [ResourceRef: Int]
    /// The printable bed rectangle (model units), from `printable_area`;
    /// nil when the project doesn't record one.
    public var plateRect: PlateRect?

    public init(
        filaments: [Filament] = [],
        plates: [Plate] = [],
        filamentIndexByObject: [ResourceRef: Int] = [:],
        plateRect: PlateRect? = nil
    ) {
        self.filaments = filaments
        self.plates = plates
        self.filamentIndexByObject = filamentIndexByObject
        self.plateRect = plateRect
    }

    /// The Plate the preview shows by default: the first one that has
    /// objects, nil when none does.
    public var defaultPlate: Plate? {
        defaultPlateIndex.map { plates[$0] }
    }

    /// Index of ``defaultPlate`` within ``plates``; nil when no Plate has
    /// objects. The Plate Filmstrip selects by position, not `id` — slicer
    /// `plater_id` values are not guaranteed unique in malformed files.
    public var defaultPlateIndex: Int? {
        plates.firstIndex { !$0.objectRefs.isEmpty }
    }

    /// The filament color the project explicitly assigns to the object (or
    /// part), through its `extruder` entry. Out-of-range indices fall back to
    /// filament 0, matching the slicer; nil when the object has no explicit
    /// assignment.
    public func filamentColor(of ref: ResourceRef) -> ColorRGBA? {
        guard let index = filamentIndexByObject[ref], !filaments.isEmpty else { return nil }
        return (filaments.indices.contains(index) ? filaments[index] : filaments[0]).color
    }
}

/// One filament definition from `project_settings.config`.
public struct Filament: Equatable, Sendable {
    public var color: ColorRGBA?
    /// Material name as the slicer records it, e.g. "PLA".
    public var type: String?

    public init(color: ColorRGBA? = nil, type: String? = nil) {
        self.color = color
        self.type = type
    }
}

/// One Build Plate (CONTEXT.md: Plate): an arrangement of objects printed
/// together, from a `<plate>` block of `model_settings.config`.
public struct Plate: Equatable, Sendable {
    /// The slicer's 1-based `plater_id`.
    public var id: Int
    /// The user-visible plate name; nil when the slicer recorded none.
    public var name: String?
    /// The root-part objects placed on this plate, in file order.
    public var objectRefs: [ResourceRef]
    /// Zip-absolute path of the Plate Thumbnail PNG, when present.
    public var thumbnailPartPath: String?
    /// The Plate Thumbnail image bytes, extracted during the full parse so
    /// the Plate Filmstrip renders without re-opening the package; nil when
    /// the plate declares no thumbnail or the part is missing.
    public var thumbnailData: Data?

    public init(
        id: Int,
        name: String? = nil,
        objectRefs: [ResourceRef] = [],
        thumbnailPartPath: String? = nil,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.objectRefs = objectRefs
        self.thumbnailPartPath = thumbnailPartPath
        self.thumbnailData = thumbnailData
    }
}

/// The printable bed rectangle in model units: the bounding box of the
/// slicer's `printable_area` corners. The origin is usually zero, but Orca
/// printer profiles can offset the bed.
public struct PlateRect: Equatable, Sendable {
    public var origin: SIMD2<Float>
    public var width: Float
    public var depth: Float

    public init(origin: SIMD2<Float> = .zero, width: Float, depth: Float) {
        self.origin = origin
        self.width = width
        self.depth = depth
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
    /// (`pid`/`p1`). Present when at least one triangle resolves a color;
    /// entries are nil for triangles without one (partially painted meshes),
    /// which render in the object's color. Count matches `triangleCount`.
    public var triangleColors: [ColorRGBA?]?

    public var triangleCount: Int { triangleIndices.count / 3 }

    public init(positions: [SIMD3<Float>] = [], triangleIndices: [UInt32] = [], triangleColors: [ColorRGBA?]? = nil) {
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
