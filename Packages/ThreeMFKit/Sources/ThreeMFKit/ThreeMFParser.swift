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
        try parse(package: OPCPackage(url: url))
    }

    /// Parses a 3MF package held in memory — the Host App's document windows
    /// read files through `FileDocument`, which supplies bytes, not a URL.
    public func parse(data: Data) throws -> ThreeMFDocument {
        try parse(package: OPCPackage(data: data))
    }

    /// The package's Embedded Thumbnail, extracted cheaply without parsing
    /// geometry — the "instant first paint" seam (issue #5). For a Slicer
    /// Project it's the default Plate's Thumbnail (first plate with objects);
    /// otherwise the OPC Package Thumbnail. Returns nil when the package
    /// carries neither.
    public func embeddedThumbnail(fileAt url: URL) throws -> EmbeddedThumbnail? {
        try embeddedThumbnail(package: OPCPackage(url: url))
    }

    /// The Embedded Thumbnail of a package held in memory.
    public func embeddedThumbnail(data: Data) throws -> EmbeddedThumbnail? {
        try embeddedThumbnail(package: OPCPackage(data: data))
    }

    private func embeddedThumbnail(package: OPCPackage) throws -> EmbeddedThumbnail? {
        // Slicer Project: the default plate's own thumbnail wins, even when
        // the package also declares an OPC Package Thumbnail (Bambu writes
        // both). Reads only the relationships and config parts.
        if let rootPath = try? package.rootModelPartPath(),
           let platePath = SlicerMetadataParser.defaultPlateThumbnailPath(
               package: package, rootPartPath: rootPath),
           let data = package.partDataIfPresent(at: platePath) {
            return EmbeddedThumbnail(partPath: platePath, data: data)
        }
        // Vanilla file: the whole-package OPC thumbnail, when a CAD exporter
        // wrote one.
        if let opcPath = package.packageThumbnailPartPath(),
           let data = package.partDataIfPresent(at: opcPath) {
            return EmbeddedThumbnail(partPath: opcPath, data: data)
        }
        return nil
    }

    private func parse(package: OPCPackage) throws -> ThreeMFDocument {
        // Sliced File (CONTEXT.md): sliced G-code plus plate thumbnails, mesh
        // geometry stripped. Its configs are the whole content — the model
        // parts are empty by construction and are never parsed, so a mangled
        // one can't surface an error where an honest preview is possible.
        if package.containsGCodePart() {
            let rootPath = (try? package.rootModelPartPath()) ?? "/3D/3dmodel.model"
            return ThreeMFDocument(
                slicerProject: SlicerMetadataParser.parse(
                    package: package, rootPartPath: rootPath, objects: []),
                isSlicedFile: true)
        }

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
        let objects = partOrder.flatMap { parts[$0]!.resolvedObjects() }
        return ThreeMFDocument(
            unit: root.unit,
            objects: objects,
            buildItems: root.buildItems(),
            slicerProject: SlicerMetadataParser.parse(
                package: package, rootPartPath: rootPath, objects: objects))
    }
}
