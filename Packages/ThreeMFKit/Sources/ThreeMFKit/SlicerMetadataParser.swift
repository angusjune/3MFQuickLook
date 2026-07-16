import Foundation
import libxml2

/// Reads the Bambu Studio / OrcaSlicer slicer-dialect config parts into
/// ``SlicerProjectInfo``: Plates and object assignments from
/// `Metadata/model_settings.config` (XML), filament colors and the printable
/// area from `Metadata/project_settings.config` (JSON), per-plate print
/// predictions and used filaments from `Metadata/slice_info.config` (XML,
/// written only after slicing). The dialect is undocumented; the corpus
/// files are the spec.
///
/// Lenient by design: a package without the dialect — including PrusaSlicer
/// projects — or with malformed configs yields nil and previews as Vanilla.
enum SlicerMetadataParser {
    static let modelSettingsPath = "/Metadata/model_settings.config"
    static let projectSettingsPath = "/Metadata/project_settings.config"
    static let sliceInfoPath = "/Metadata/slice_info.config"

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
        if let sliceInfo = package.partDataIfPresent(at: sliceInfoPath) {
            applySliceInfo(sliceInfo, to: &info)
        }
        // Pull the Plate Thumbnail bytes now, while the package is open:
        // consumers switch Plates on the already-parsed document and must
        // never re-open the file (issue #6).
        for index in info.plates.indices {
            info.plates[index].thumbnailData = info.plates[index].thumbnailPartPath
                .flatMap { package.partDataIfPresent(at: $0) }
        }
        return info
    }

    /// The Plate Thumbnail path the Finder icon uses. Reads only
    /// `model_settings.config`; never touches geometry. Regular projects
    /// keep the strict rule — the default Plate's thumbnail or nothing, so
    /// the OPC Package Thumbnail (or a mesh render) can stand in. Sliced
    /// Files follow ``SlicerProjectInfo/thumbnailPlateIndex`` — the same
    /// rule as the sliced preview's opening Plate, so icon and panel agree
    /// even when the config records no objects (issue #8). Returns nil when
    /// the package isn't a Slicer Project or the chosen Plate has no
    /// thumbnail.
    static func defaultPlateThumbnailPath(package: OPCPackage, rootPartPath: String) -> String? {
        guard let settings = package.partDataIfPresent(at: modelSettingsPath),
              let info = parseModelSettings(settings, rootPartPath: rootPartPath, objects: [])
        else { return nil }
        if package.containsGCodePart() {
            return info.thumbnailPlateIndex.flatMap { info.plates[$0].thumbnailPartPath }
        }
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

    // MARK: slice_info.config (per-plate print prediction, used filaments)

    /// Applies each sliced plate's `<plate>` block: `index` names the plate
    /// (matching its `plater_id`), `prediction` is the estimated print time
    /// in seconds, and one `<filament id="…">` per filament the sliced
    /// G-code uses (1-based extruder ids). Unsliced projects carry only a
    /// `<header>` — every plate keeps nil and the Info Line derives instead.
    private static func applySliceInfo(_ data: Data, to info: inout SlicerProjectInfo) {
        let plates = info.plates
        LibXML.withDocument(data) { doc -> Void in
            guard let config = xmlDocGetRootElement(doc),
                  xmlStrEqual(config.pointee.name, "config") != 0
            else { return }
            for plateNode in LibXML.children(of: config, named: "plate") {
                guard let id = metadataValue(of: plateNode, key: "index").flatMap(Int.init),
                      let index = plates.firstIndex(where: { $0.id == id })
                else { continue }
                if let prediction = metadataValue(of: plateNode, key: "prediction")
                    .flatMap(Double.init), prediction > 0 {
                    info.plates[index].estimatedPrintTime = prediction
                }
                let filamentIndices = LibXML.children(of: plateNode, named: "filament").compactMap {
                    LibXML.attribute(of: $0, named: "id").flatMap(Int.init).map { $0 - 1 }
                }
                if !filamentIndices.isEmpty {
                    info.plates[index].usedFilamentIndices = filamentIndices
                }
            }
        }
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

        if let model = settings["printer_model"] as? String, !model.isEmpty {
            info.printerModel = model
        }
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
