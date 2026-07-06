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

    static func parse(package: OPCPackage, rootPartPath: String) -> SlicerProjectInfo? {
        guard let settings = package.partDataIfPresent(at: modelSettingsPath),
              var info = parseModelSettings(settings, rootPartPath: rootPartPath),
              !info.plates.isEmpty
        else { return nil }

        if let project = package.partDataIfPresent(at: projectSettingsPath) {
            applyProjectSettings(project, to: &info)
        }
        return info
    }

    // MARK: model_settings.config (plates, assignments)

    private static func parseModelSettings(
        _ data: Data, rootPartPath: String
    ) -> SlicerProjectInfo? {
        LibXML.withDocument(data) { doc in
            guard let config = xmlDocGetRootElement(doc),
                  xmlStrEqual(config.pointee.name, "config") != 0
            else { return nil }

            var info = SlicerProjectInfo()
            for object in LibXML.children(of: config, named: "object") {
                guard let id = LibXML.attribute(of: object, named: "id").flatMap({ UInt32($0) }),
                      let extruder = metadataValue(of: object, key: "extruder").flatMap({ Int($0) })
                else { continue }
                let ref = ResourceRef(partPath: rootPartPath, id: id)
                info.filamentIndexByObject[ref] = max(0, extruder - 1)
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

        info.plateSize = plateSize(fromPrintableArea: settings["printable_area"] as? [String])
    }

    /// The bounding rectangle of the `printable_area` corner list
    /// (`["0x0", "256x0", …]`, millimeters).
    private static func plateSize(fromPrintableArea corners: [String]?) -> PlateSize? {
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
        return PlateSize(width: maxX - minX, depth: maxY - minY)
    }
}
