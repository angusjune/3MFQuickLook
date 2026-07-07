import Foundation
import libxml2

/// Reads the Bambu Studio / OrcaSlicer slicer-dialect config parts into
/// ``SlicerProjectInfo``: Plates and object assignments from
/// `Metadata/model_settings.config` (XML), filament colors and the printable
/// area from `Metadata/project_settings.config` (JSON). The dialect is
/// undocumented; the corpus files are the spec.
///
/// Lenient by design: a package without the dialect — including PrusaSlicer
/// projects — or with malformed configs yields nil and previews as Vanilla.
enum SlicerMetadataParser {
    static let modelSettingsPath = "/Metadata/model_settings.config"
    static let projectSettingsPath = "/Metadata/project_settings.config"

    static func parse(
        package: OPCPackage, rootPartPath: String, objects: [ObjectResource]
    ) -> SlicerProjectInfo? {
        guard let settings = package.partDataIfPresent(at: modelSettingsPath),
              var info = parseModelSettings(settings, rootPartPath: rootPartPath, objects: objects),
              !info.plates.isEmpty
        else { return nil }

        if let project = package.partDataIfPresent(at: projectSettingsPath) {
            applyProjectSettings(project, to: &info)
        }
        return info
    }

    /// The Plate Thumbnail path of the plate the preview shows by default —
    /// the first Plate that has objects (CONTEXT.md thumbnail policy). Reads
    /// only `model_settings.config`; never touches geometry. Returns nil when
    /// the package isn't a Slicer Project or the default plate has no
    /// thumbnail.
    static func defaultPlateThumbnailPath(package: OPCPackage, rootPartPath: String) -> String? {
        guard let settings = package.partDataIfPresent(at: modelSettingsPath),
              let info = parseModelSettings(settings, rootPartPath: rootPartPath, objects: [])
        else { return nil }
        return info.defaultPlate?.thumbnailPartPath
    }

    // MARK: model_settings.config (plates, assignments)

    private static func parseModelSettings(
        _ data: Data, rootPartPath: String, objects: [ObjectResource]
    ) -> SlicerProjectInfo? {
        LibXML.withDocument(data) { doc in
            guard let config = xmlDocGetRootElement(doc),
                  xmlStrEqual(config.pointee.name, "config") != 0
            else { return nil }

            var info = SlicerProjectInfo()
            for object in LibXML.children(of: config, named: "object") {
                guard let id = LibXML.attribute(of: object, named: "id").flatMap({ UInt32($0) })
                else { continue }
                let ref = ResourceRef(partPath: rootPartPath, id: id)
                if let extruder = metadataValue(of: object, key: "extruder").flatMap({ Int($0) }) {
                    info.filamentIndexByObject[ref] = max(0, extruder - 1)
                }
                applyPartExtruders(of: object, rootObjectRef: ref, objects: objects, to: &info)
            }
            for (index, plate) in LibXML.children(of: config, named: "plate").enumerated() {
                let name = metadataValue(of: plate, key: "plater_name")
                let objectRefs = LibXML.children(of: plate, named: "model_instance").compactMap {
                    metadataValue(of: $0, key: "object_id").flatMap(UInt32.init).map {
                        ResourceRef(partPath: rootPartPath, id: $0)
                    }
                }
                info.plates.append(Plate(
                    id: metadataValue(of: plate, key: "plater_id").flatMap(Int.init) ?? index + 1,
                    name: name?.isEmpty == false ? name : nil,
                    objectRefs: objectRefs,
                    thumbnailPartPath: metadataValue(of: plate, key: "thumbnail_file")
                        .map(zipAbsolutePartPath)))
            }
            return info
        }
    }

    /// Records part-level `extruder` assignments. A `<part id="P">` of
    /// `<object id="O">` names the component of root object O whose target
    /// object id is P (the Bambu convention, confirmed against the corpus:
    /// part ids equal the referenced sub-part object ids).
    private static func applyPartExtruders(
        of objectNode: xmlNodePtr,
        rootObjectRef: ResourceRef,
        objects: [ObjectResource],
        to info: inout SlicerProjectInfo
    ) {
        var partIndices: [UInt32: Int] = [:]
        for part in LibXML.children(of: objectNode, named: "part") {
            guard let id = LibXML.attribute(of: part, named: "id").flatMap({ UInt32($0) }),
                  let extruder = metadataValue(of: part, key: "extruder").flatMap({ Int($0) })
            else { continue }
            partIndices[id] = max(0, extruder - 1)
        }
        guard !partIndices.isEmpty,
              let rootObject = objects.first(where: { $0.ref == rootObjectRef }),
              case .components(let components) = rootObject.content
        else { return }
        for component in components {
            if let index = partIndices[component.objectRef.id] {
                info.filamentIndexByObject[component.objectRef] = index
            }
        }
    }

    /// The `value` of a `<metadata key="…" value="…"/>` child.
    private static func metadataValue(of node: xmlNodePtr, key: String) -> String? {
        for metadata in LibXML.children(of: node, named: "metadata")
        where LibXML.attribute(of: metadata, named: "key") == key {
            return LibXML.attribute(of: metadata, named: "value")
        }
        return nil
    }

    // MARK: project_settings.config (filaments, printable area)

    private static func applyProjectSettings(_ data: Data, to info: inout SlicerProjectInfo) {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let settings = json as? [String: Any]
        else { return }

        let colors = (settings["filament_colour"] as? [String] ?? []).map(ColorRGBA.init(hex:))
        let types = settings["filament_type"] as? [String] ?? []
        info.filaments = (0..<max(colors.count, types.count)).map { index in
            Filament(
                color: colors.indices.contains(index) ? colors[index] : nil,
                type: types.indices.contains(index) ? types[index] : nil)
        }

        info.plateRect = plateRect(fromPrintableArea: settings["printable_area"] as? [String])
    }

    /// The bounding rectangle of the `printable_area` corner list
    /// (`["0x0", "256x0", …]`, millimeters).
    private static func plateRect(fromPrintableArea corners: [String]?) -> PlateRect? {
        guard let corners, corners.count >= 3 else { return nil }
        var minX = Float.infinity, maxX = -Float.infinity
        var minY = Float.infinity, maxY = -Float.infinity
        for corner in corners {
            let parts = corner.split(separator: "x")
            guard parts.count == 2, let x = Float(parts[0]), let y = Float(parts[1]) else {
                return nil
            }
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        guard maxX > minX, maxY > minY else { return nil }
        return PlateRect(origin: SIMD2(minX, minY), width: maxX - minX, depth: maxY - minY)
    }
}
