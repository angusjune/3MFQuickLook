import Foundation

/// Parses a 3MF package file into a ``ThreeMFDocument``.
///
/// Per ADR-0002: ZIPFoundation reads the OPC container, libxml2 SAX push
/// parsing streams each model part. Handles the core spec plus the materials
/// (color groups) and production (multi-part `p:path` references) extensions;
/// anything else is skipped leniently.
public struct ThreeMFParser: Sendable {
    public init() {}

    public func parse(fileAt url: URL) throws -> ThreeMFDocument {
        let package = try OPCPackage(url: url)
        let rootPath = try package.rootModelPartPath()

        var parts: [String: ModelPart] = [:]
        var partOrder: [String] = []
        var pending = [rootPath]
        while !pending.isEmpty {
            let path = pending.removeFirst()
            guard parts[path] == nil else { continue }
            let parser = ModelPartSAXParser(partPath: path)
            try package.streamPart(at: path) { try parser.feed($0) }
            let part = try parser.finish()
            parts[path] = part
            partOrder.append(path)
            pending.append(contentsOf: part.referencedPartPaths.filter { parts[$0] == nil })
        }

        let root = parts[rootPath]!
        return ThreeMFDocument(
            unit: root.unit,
            objects: partOrder.flatMap { parts[$0]!.resolvedObjects() },
            buildItems: root.buildItems(),
            slicer: SlicerMetadataParser.parse(package: package, rootPartPath: rootPath))
    }
}
