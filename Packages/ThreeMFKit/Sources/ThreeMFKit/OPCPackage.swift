import Foundation
import ZIPFoundation
import libxml2

public enum ThreeMFParseError: Error, Equatable {
    /// The file is not a readable zip archive.
    case unreadableArchive(String)
    /// The package has no `_rels/.rels` relationship to a 3D model part.
    case missingRootModel
    /// A referenced model part is absent from the archive.
    case missingModelPart(String)
    /// A model part is not well-formed XML.
    case malformedModelXML(partPath: String)
}

/// Read access to the OPC (zip) container of a 3MF package.
final class OPCPackage {
    private static let modelRelationshipType =
        "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"

    private let archive: Archive

    init(url: URL) throws {
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ThreeMFParseError.unreadableArchive(String(describing: error))
        }
    }

    /// Streams the raw bytes of a part to `consumer` in chunks.
    /// `partPath` is zip-absolute ("/3D/3dmodel.model").
    func streamPart(at partPath: String, consumer: (Data) throws -> Void) throws {
        guard let entry = archive[String(partPath.drop(while: { $0 == "/" }))] else {
            throw ThreeMFParseError.missingModelPart(partPath)
        }
        _ = try archive.extract(entry, consumer: consumer)
    }

    func partData(at partPath: String) throws -> Data {
        var data = Data()
        try streamPart(at: partPath) { data.append($0) }
        return data
    }

    /// The package's root model part, from the `_rels/.rels` relationship of
    /// type `…/3dmanufacturing/2013/01/3dmodel`.
    func rootModelPartPath() throws -> String {
        guard let rels = try? partData(at: "/_rels/.rels") else {
            throw ThreeMFParseError.missingRootModel
        }
        guard let target = Self.firstModelRelationshipTarget(in: rels) else {
            throw ThreeMFParseError.missingRootModel
        }
        return target.hasPrefix("/") ? target : "/" + target
    }

    private static func firstModelRelationshipTarget(in data: Data) -> String? {
        let doc: xmlDocPtr? = data.withUnsafeBytes { buffer in
            xmlReadMemory(
                buffer.bindMemory(to: CChar.self).baseAddress, Int32(buffer.count),
                nil, nil, Int32(XML_PARSE_NONET.rawValue))
        }
        guard let doc else { return nil }
        defer { xmlFreeDoc(doc) }

        guard let root = xmlDocGetRootElement(doc) else { return nil }
        var node = root.pointee.children
        while let current = node {
            defer { node = current.pointee.next }
            guard current.pointee.type == XML_ELEMENT_NODE,
                  xmlStrEqual(current.pointee.name, "Relationship") != 0,
                  attributeValue(of: current, named: "Type") == modelRelationshipType,
                  let target = attributeValue(of: current, named: "Target")
            else { continue }
            return target
        }
        return nil
    }

    /// Reads an attribute's text without `xmlGetProp` — that would allocate
    /// and require `xmlFree`, a mutable libxml2 global Swift 6 rejects.
    private static func attributeValue(of node: xmlNodePtr, named name: String) -> String? {
        guard let attribute = xmlHasProp(node, name),
              let text = attribute.pointee.children,
              let content = text.pointee.content
        else { return nil }
        return String(cString: content)
    }
}
