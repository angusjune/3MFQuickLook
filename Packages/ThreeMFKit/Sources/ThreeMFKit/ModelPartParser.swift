import Foundation
import libxml2
import simd

/// The raw contents of one `.model` part, before property references are
/// resolved into colors.
struct ModelPart {
    var partPath: String
    var unit: LengthUnit = .millimeter
    /// Property group id → color list (base materials' `displaycolor` and
    /// materials-extension color groups' `color`, unified).
    var propertyColors: [UInt32: [ColorRGBA]] = [:]
    var rawObjects: [RawObject] = []
    var rawItems: [RawItem] = []
    /// Production-extension `p:path` targets referenced by components/items.
    var referencedPartPaths: [String] = []

    /// Sentinel in per-triangle property arrays for "attribute absent".
    static let noProperty = UInt32.max

    func resolvedObjects() -> [ObjectResource] {
        rawObjects.map { raw in
            let defaultColor = raw.pid.flatMap { pid in
                propertyColors[pid].flatMap { colors in
                    colors.indices.contains(Int(raw.pindex ?? 0)) ? colors[Int(raw.pindex ?? 0)] : colors.first
                }
            }
            let content: ObjectResource.Content
            if raw.hasComponents {
                content = .components(raw.components.map {
                    Component(
                        objectRef: ResourceRef(partPath: $0.path ?? partPath, id: $0.objectID),
                        transform: $0.transform)
                })
            } else {
                content = .mesh(Mesh(
                    positions: raw.positions,
                    triangleIndices: raw.indices,
                    triangleColors: resolvedTriangleColors(of: raw, defaultColor: defaultColor)))
            }
            return ObjectResource(
                ref: ResourceRef(partPath: partPath, id: raw.id),
                name: raw.name,
                defaultColor: defaultColor,
                content: content)
        }
    }

    /// Per-triangle colors, materialized when at least one triangle resolves
    /// one. Triangles without a resolvable color get nil (they render in the
    /// object's color), so partially painted meshes keep their paint.
    private func resolvedTriangleColors(of raw: RawObject, defaultColor: ColorRGBA?) -> [ColorRGBA?]? {
        guard raw.hasTriangleProperties else { return nil }
        var colors: [ColorRGBA?] = []
        colors.reserveCapacity(raw.indices.count / 3)
        var anyResolved = false
        for i in 0..<(raw.indices.count / 3) {
            let pid = raw.triPropertyGroups[i] == Self.noProperty ? raw.pid : raw.triPropertyGroups[i]
            let index = raw.triPropertyIndices[i]
            var color: ColorRGBA?
            if index != Self.noProperty, let pid, let group = propertyColors[pid] {
                color = group.indices.contains(Int(index)) ? group[Int(index)] : group.first
            }
            anyResolved = anyResolved || color != nil
            colors.append(color ?? defaultColor)
        }
        return anyResolved ? colors : nil
    }

    func buildItems() -> [BuildItem] {
        rawItems.map {
            BuildItem(
                objectRef: ResourceRef(partPath: $0.path ?? partPath, id: $0.objectID),
                transform: $0.transform)
        }
    }
}

struct RawObject {
    var id: UInt32
    var name: String?
    var pid: UInt32?
    var pindex: UInt32?
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    /// Aligned per triangle once any triangle carries a property reference
    /// (`hasTriangleProperties`); `ModelPart.noProperty` marks triangles
    /// without one.
    var hasTriangleProperties = false
    var triPropertyGroups: [UInt32] = []
    var triPropertyIndices: [UInt32] = []
    var components: [RawComponent] = []
    var hasComponents = false
}

struct RawComponent {
    var objectID: UInt32
    var path: String?
    var transform: simd_float4x4
}

struct RawItem {
    var objectID: UInt32
    var path: String?
    var transform: simd_float4x4
}

/// Streaming SAX parser (libxml2 push mode, per ADR-0002) for one model part.
///
/// Lenient by design: elements outside the core/material/production vocabulary
/// (beam lattice, slices, slicer dialects…) are skipped along with their
/// subtrees, and `requiredextensions` is deliberately ignored, so files using
/// unimplemented extensions still yield their core geometry.
final class ModelPartSAXParser {
    private enum Ctx: UInt8 {
        case model, resources, object, mesh, vertices, triangles, components
        case basematerials, colorgroup, build, skip
    }

    private var part: ModelPart
    private var stack: [Ctx] = []
    private var currentObject: RawObject?
    private var currentGroupID: UInt32?
    private var currentGroupColors: [ColorRGBA] = []
    private var context: xmlParserCtxtPtr?

    init(partPath: String) {
        part = ModelPart(partPath: partPath)
        stack.reserveCapacity(16)
    }

    deinit {
        if let context { xmlFreeParserCtxt(context) }
    }

    func feed(_ data: Data) throws {
        if context == nil {
            try start(firstChunk: data)
            return
        }
        let rc = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            xmlParseChunk(
                context, buffer.bindMemory(to: CChar.self).baseAddress,
                Int32(buffer.count), 0)
        }
        guard rc == 0 else { throw ThreeMFParseError.malformedModelXML(partPath: part.partPath) }
    }

    func finish() throws -> ModelPart {
        if context == nil { try start(firstChunk: Data()) }
        let rc = xmlParseChunk(context, nil, 0, 1)
        guard rc == 0, context!.pointee.wellFormed != 0 else {
            throw ThreeMFParseError.malformedModelXML(partPath: part.partPath)
        }
        return part
    }

    private func start(firstChunk: Data) throws {
        var handler = xmlSAXHandler()
        handler.initialized = XML_SAX2_MAGIC
        handler.startElementNs = { userData, localname, _, uri, _, _, attributeCount, _, attributes in
            guard let userData, let localname else { return }
            let parser = Unmanaged<ModelPartSAXParser>.fromOpaque(userData).takeUnretainedValue()
            parser.startElement(localname, uri: uri, attributes: attributes, count: Int(attributeCount))
        }
        handler.endElementNs = { userData, _, _, _ in
            guard let userData else { return }
            let parser = Unmanaged<ModelPartSAXParser>.fromOpaque(userData).takeUnretainedValue()
            parser.endElement()
        }
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        context = xmlCreatePushParserCtxt(&handler, selfPointer, nil, 0, nil)
        guard let context else { throw ThreeMFParseError.malformedModelXML(partPath: part.partPath) }
        xmlCtxtUseOptions(context, Int32(XML_PARSE_NONET.rawValue | XML_PARSE_NOENT.rawValue))
        if !firstChunk.isEmpty {
            let rc = firstChunk.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                xmlParseChunk(
                    self.context, buffer.bindMemory(to: CChar.self).baseAddress,
                    Int32(buffer.count), 0)
            }
            guard rc == 0 else { throw ThreeMFParseError.malformedModelXML(partPath: part.partPath) }
        }
    }

    // MARK: Element dispatch

    private static let coreNS: StaticString = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    private static let materialNS: StaticString = "http://schemas.microsoft.com/3dmanufacturing/material/2015/02"

    private func startElement(
        _ name: UnsafePointer<xmlChar>,
        uri: UnsafePointer<xmlChar>?,
        attributes: UnsafeMutablePointer<UnsafePointer<xmlChar>?>?,
        count: Int
    ) {
        let attrs = SAXAttributes(base: attributes, count: count)
        switch stack.last {
        case nil:
            if matches(name, "model"), inNS(uri, Self.coreNS) {
                if let unit = attrs.string("unit").flatMap(LengthUnit.init(rawValue:)) {
                    part.unit = unit
                }
                stack.append(.model)
            } else {
                stack.append(.skip)
            }
        case .model:
            if matches(name, "resources"), inNS(uri, Self.coreNS) {
                stack.append(.resources)
            } else if matches(name, "build"), inNS(uri, Self.coreNS) {
                stack.append(.build)
            } else {
                stack.append(.skip)
            }
        case .resources:
            if matches(name, "object"), inNS(uri, Self.coreNS) {
                currentObject = RawObject(
                    id: attrs.uint("id") ?? 0,
                    name: attrs.string("name"),
                    pid: attrs.uint("pid"),
                    pindex: attrs.uint("pindex"))
                stack.append(.object)
            } else if matches(name, "basematerials"), inNS(uri, Self.coreNS) {
                currentGroupID = attrs.uint("id")
                currentGroupColors = []
                stack.append(.basematerials)
            } else if matches(name, "colorgroup"), inNS(uri, Self.materialNS) {
                currentGroupID = attrs.uint("id")
                currentGroupColors = []
                stack.append(.colorgroup)
            } else {
                stack.append(.skip)
            }
        case .object:
            if matches(name, "mesh"), inNS(uri, Self.coreNS) {
                stack.append(.mesh)
            } else if matches(name, "components"), inNS(uri, Self.coreNS) {
                currentObject?.hasComponents = true
                stack.append(.components)
            } else {
                stack.append(.skip)
            }
        case .mesh:
            if matches(name, "vertices"), inNS(uri, Self.coreNS) {
                stack.append(.vertices)
            } else if matches(name, "triangles"), inNS(uri, Self.coreNS) {
                stack.append(.triangles)
            } else {
                stack.append(.skip)
            }
        case .vertices:
            if matches(name, "vertex") {
                let x = attrs.float("x") ?? 0
                let y = attrs.float("y") ?? 0
                let z = attrs.float("z") ?? 0
                currentObject?.positions.append(SIMD3(x, y, z))
            }
            stack.append(.skip)
        case .triangles:
            if matches(name, "triangle") {
                appendTriangle(attrs)
            }
            stack.append(.skip)
        case .components:
            if matches(name, "component"), inNS(uri, Self.coreNS), let objectID = attrs.uint("objectid") {
                let path = attrs.string("path").map(zipAbsolutePartPath)
                if let path { part.referencedPartPaths.append(path) }
                currentObject?.components.append(RawComponent(
                    objectID: objectID,
                    path: path,
                    transform: attrs.transform("transform") ?? matrix_identity_float4x4))
            }
            stack.append(.skip)
        case .basematerials:
            if matches(name, "base"), let color = attrs.color("displaycolor") {
                currentGroupColors.append(color)
            }
            stack.append(.skip)
        case .colorgroup:
            if matches(name, "color"), inNS(uri, Self.materialNS), let color = attrs.color("color") {
                currentGroupColors.append(color)
            }
            stack.append(.skip)
        case .build:
            if matches(name, "item"), inNS(uri, Self.coreNS), let objectID = attrs.uint("objectid") {
                let path = attrs.string("path").map(zipAbsolutePartPath)
                if let path { part.referencedPartPaths.append(path) }
                part.rawItems.append(RawItem(
                    objectID: objectID,
                    path: path,
                    transform: attrs.transform("transform") ?? matrix_identity_float4x4))
            }
            stack.append(.skip)
        case .skip:
            stack.append(.skip)
        }
    }

    private func endElement() {
        guard let popped = stack.popLast() else { return }
        switch popped {
        case .object:
            if let object = currentObject {
                part.rawObjects.append(object)
                currentObject = nil
            }
        case .basematerials, .colorgroup:
            if let id = currentGroupID {
                part.propertyColors[id] = currentGroupColors
            }
            currentGroupID = nil
            currentGroupColors = []
        default:
            break
        }
    }

    private func appendTriangle(_ attrs: SAXAttributes) {
        guard var object = currentObject else { return }
        currentObject = nil  // avoid CoW copies of the big arrays while mutating
        defer { currentObject = object }

        guard let v1 = attrs.uint("v1"), let v2 = attrs.uint("v2"), let v3 = attrs.uint("v3") else {
            return
        }
        object.indices.append(v1)
        object.indices.append(v2)
        object.indices.append(v3)

        let pid = attrs.uint("pid")
        let p1 = attrs.uint("p1")
        let triangleCount = object.indices.count / 3
        if (pid != nil || p1 != nil) && !object.hasTriangleProperties {
            object.hasTriangleProperties = true
            object.triPropertyGroups = Array(repeating: ModelPart.noProperty, count: triangleCount - 1)
            object.triPropertyIndices = Array(repeating: ModelPart.noProperty, count: triangleCount - 1)
        }
        if object.hasTriangleProperties {
            object.triPropertyGroups.append(pid ?? ModelPart.noProperty)
            object.triPropertyIndices.append(p1 ?? ModelPart.noProperty)
        }
    }

    // MARK: Name/namespace matching (no per-call allocation)

    private func matches(_ name: UnsafePointer<xmlChar>, _ literal: StaticString) -> Bool {
        xmlStringEquals(name, literal)
    }

    private func inNS(_ uri: UnsafePointer<xmlChar>?, _ literal: StaticString) -> Bool {
        guard let uri else { return false }
        return xmlStringEquals(uri, literal)
    }
}

/// NUL-terminated xmlChar string == StaticString, without allocating.
private func xmlStringEquals(_ string: UnsafePointer<xmlChar>, _ literal: StaticString) -> Bool {
    literal.withUTF8Buffer { buffer in
        memcmp(string, buffer.baseAddress!, buffer.count) == 0 && string[buffer.count] == 0
    }
}

/// The SAX2 attribute array: 5 pointers per attribute
/// (localname, prefix, URI, value start, value end). Values are ranges into
/// the parser buffer, not NUL-terminated. Attributes are matched by localname
/// only — the 3MF vocabularies don't overlap attribute names.
private struct SAXAttributes {
    let base: UnsafeMutablePointer<UnsafePointer<xmlChar>?>?
    let count: Int

    private func value(_ name: StaticString) -> (start: UnsafePointer<xmlChar>, count: Int)? {
        guard let base else { return nil }
        for i in 0..<count {
            guard let localname = base[i * 5] else { continue }
            if xmlStringEquals(localname, name), let start = base[i * 5 + 3], let end = base[i * 5 + 4] {
                return (start, end - start)
            }
        }
        return nil
    }

    func string(_ name: StaticString) -> String? {
        value(name).map { String(decoding: UnsafeBufferPointer(start: $0.start, count: $0.count), as: UTF8.self) }
    }

    func uint(_ name: StaticString) -> UInt32? {
        guard let (start, count) = value(name), count > 0 else { return nil }
        var result: UInt32 = 0
        for i in 0..<count {
            let digit = start[i]
            guard digit >= UInt8(ascii: "0"), digit <= UInt8(ascii: "9") else { return nil }
            let (multiplied, overflow1) = result.multipliedReportingOverflow(by: 10)
            let (added, overflow2) = multiplied.addingReportingOverflow(UInt32(digit - UInt8(ascii: "0")))
            guard !overflow1, !overflow2 else { return nil }
            result = added
        }
        return result
    }

    func float(_ name: StaticString) -> Float? {
        guard let (start, count) = value(name), count > 0, count < 64 else { return nil }
        return withUnsafeTemporaryAllocation(of: CChar.self, capacity: count + 1) { buffer in
            memcpy(buffer.baseAddress!, start, count)
            buffer[count] = 0
            var end: UnsafeMutablePointer<CChar>?
            let parsed = strtof(buffer.baseAddress, &end)
            return end == buffer.baseAddress! + count ? parsed : nil
        }
    }

    func color(_ name: StaticString) -> ColorRGBA? {
        string(name).flatMap(ColorRGBA.init(hex:))
    }

    /// A 3MF 4x3 row-major matrix ("m00 m01 m02 m10 … m30 m31 m32", applied to
    /// row vectors) as a column-vector `simd_float4x4`.
    func transform(_ name: StaticString) -> simd_float4x4? {
        guard let (start, count) = value(name), count > 0, count < 512 else { return nil }
        var values = [Float](repeating: 0, count: 12)
        let parsedAll = withUnsafeTemporaryAllocation(of: CChar.self, capacity: count + 1) { buffer -> Bool in
            memcpy(buffer.baseAddress!, start, count)
            buffer[count] = 0
            var cursor: UnsafeMutablePointer<CChar>? = buffer.baseAddress
            for i in 0..<12 {
                var end: UnsafeMutablePointer<CChar>?
                let parsed = strtof(cursor, &end)
                guard end != cursor else { return false }
                values[i] = parsed
                cursor = end
            }
            return true
        }
        guard parsedAll else { return nil }
        return simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], 0),
            SIMD4(values[3], values[4], values[5], 0),
            SIMD4(values[6], values[7], values[8], 0),
            SIMD4(values[9], values[10], values[11], 1)
        ))
    }
}
