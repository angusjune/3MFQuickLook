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

/// OPC part references come in both "/3D/x.model" and "3D/x.model" forms;
/// the domain stores them zip-absolute (leading slash).
func zipAbsolutePartPath(_ path: String) -> String {
    path.hasPrefix("/") ? path : "/" + path
}

/// Read access to the OPC (zip) container of a 3MF package.
final class OPCPackage {
    private static let modelRelationshipType =
        "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    /// The core OPC (Open Packaging Conventions) thumbnail relationship type —
    /// the whole-package cover image some CAD exporters write.
    private static let thumbnailRelationshipType =
        "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"

    private let archive: Archive

    init(url: URL) throws {
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ThreeMFParseError.unreadableArchive(String(describing: error))
        }
    }

    init(data: Data) throws {
        do {
            archive = try Archive(data: data, accessMode: .read)
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

    /// The raw bytes of a part, or nil when the package has no such part
    /// (or it cannot be read).
    func partDataIfPresent(at partPath: String) -> Data? {
        guard archive[String(partPath.drop(while: { $0 == "/" }))] != nil else { return nil }
        return try? partData(at: partPath)
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
        return zipAbsolutePartPath(target)
    }

    /// The OPC Package Thumbnail's zip-absolute part path, from the package
    /// `_rels/.rels` relationship of type
    /// `…/2006/relationships/metadata/thumbnail`; nil when absent. Reads only
    /// the tiny relationships part — never any geometry.
    func packageThumbnailPartPath() -> String? {
        guard let rels = try? partData(at: "/_rels/.rels"),
              let target = Self.firstRelationshipTarget(in: rels, ofType: Self.thumbnailRelationshipType)
        else { return nil }
        return zipAbsolutePartPath(target)
    }

    private static func firstModelRelationshipTarget(in data: Data) -> String? {
        firstRelationshipTarget(in: data, ofType: modelRelationshipType)
    }

    private static func firstRelationshipTarget(in data: Data, ofType type: String) -> String? {
        LibXML.withDocument(data) { doc in
            guard let root = xmlDocGetRootElement(doc) else { return nil }
            for relationship in LibXML.children(of: root, named: "Relationship")
            where LibXML.attribute(of: relationship, named: "Type") == type {
                return LibXML.attribute(of: relationship, named: "Target")
            }
            return nil
        }
    }
}
