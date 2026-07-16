import AppKit
import RealityKit
import simd
import Testing
import ThreeMFKit
import ThreeMFViewer

/// Scene-seam tests: given a document, the entity tree has these entities,
/// transforms, and materials. Headless — no pixel assertions.
@MainActor
@Suite struct SceneSeamTests {

    // MARK: Fixtures

    private static let rootPart = "/3D/3dmodel.model"

    /// A unit cube mesh: 8 vertices, 12 triangles.
    private static func cubeMesh(
        size: Float = 10,
        triangleColors: [ColorRGBA?]? = nil,
        paintIndices: [Int?]? = nil
    ) -> Mesh {
        var positions: [SIMD3<Float>] = []
        for z: Float in [0, 1] {
            for y: Float in [0, 1] {
                for x: Float in [0, 1] {
                    positions.append(SIMD3(x, y, z) * size)
                }
            }
        }
        let triangles: [UInt32] = [
            0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6,
            0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7,
            0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5,
        ]
        return Mesh(
            positions: positions,
            triangleIndices: triangles,
            triangleColors: triangleColors,
            trianglePaintFilamentIndices: paintIndices)
    }

    private static func document(
        objects: [ObjectResource],
        buildItems: [BuildItem]
    ) -> ThreeMFDocument {
        ThreeMFDocument(unit: .millimeter, objects: objects, buildItems: buildItems)
    }

    private static func cubeDocument(
        defaultColor: ColorRGBA? = nil,
        triangleColors: [ColorRGBA?]? = nil,
        itemTransform: simd_float4x4 = matrix_identity_float4x4
    ) -> ThreeMFDocument {
        let ref = ResourceRef(partPath: rootPart, id: 1)
        return document(
            objects: [ObjectResource(
                ref: ref,
                defaultColor: defaultColor,
                content: .mesh(cubeMesh(triangleColors: triangleColors)))],
            buildItems: [BuildItem(objectRef: ref, transform: itemTransform)])
    }

    // MARK: Helpers

    private func modelEntities(in entity: Entity) -> [ModelEntity] {
        var result: [ModelEntity] = []
        if let model = entity as? ModelEntity { result.append(model) }
        for child in entity.children {
            result.append(contentsOf: modelEntities(in: child))
        }
        return result
    }

    private func modelSubtree(of scene: Entity) throws -> Entity {
        try #require(scene.findEntity(named: "Model"))
    }

    private func lights(in entity: Entity) -> [DirectionalLightComponent] {
        var result: [DirectionalLightComponent] = []
        if let light = entity.components[DirectionalLightComponent.self] { result.append(light) }
        for child in entity.children {
            result.append(contentsOf: lights(in: child))
        }
        return result
    }

    private func tint(of material: any Material) throws -> SIMD3<Float> {
        let simple = try #require(material as? SimpleMaterial)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        simple.color.tint.usingColorSpace(.deviceRGB)?
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD3(Float(red), Float(green), Float(blue))
    }

    // MARK: Geometry

    @Test func meshObjectBecomesOneModelEntityWithComputedNormals() throws {
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument())

        let models = modelEntities(in: try modelSubtree(of: scene))
        #expect(models.count == 1)

        let mesh = try #require(models.first?.model?.mesh)
        let part = try #require(mesh.contents.models.first?.parts.first)
        #expect(part.triangleIndices?.count == 36)
        let normals = try #require(part.normals)
        let positions = part.positions
        #expect(normals.count == positions.count)
        // Computed vertex normals of a closed cube all point outward from its
        // center (correct winding handling).
        let center = positions.elements.reduce(SIMD3<Float>.zero, +) / Float(positions.count)
        for (normal, position) in zip(normals.elements, positions.elements) {
            #expect(simd_dot(normal, position - center) > 0)
        }
    }

    @Test func modelRootAppliesUnitScaleAndZUpToYUpConversion() throws {
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument())

        let model = try modelSubtree(of: scene)
        #expect(model.transform.scale.max() - 0.001 < 1e-6)
        // -90° about X carries the 3MF +Z (up) axis onto RealityKit's +Y.
        let mappedUp = model.transform.rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(simd_distance(mappedUp, SIMD3(0, 1, 0)) < 1e-5)
    }

    @Test func buildItemTransformPlacesTheObject() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(30, 5, -2, 1)
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument(itemTransform: transform))

        let models = modelEntities(in: try modelSubtree(of: scene))
        let placed = try #require(models.first)
        #expect(placed.position(relativeTo: try modelSubtree(of: scene)) == SIMD3(30, 5, -2))
    }

    @Test func componentTransformsCompose() throws {
        let meshRef = ResourceRef(partPath: "/3D/Objects/part.model", id: 1)
        let assemblyRef = ResourceRef(partPath: Self.rootPart, id: 2)
        var componentTransform = matrix_identity_float4x4
        componentTransform.columns.3 = SIMD4(0, 0, 7, 1)
        var itemTransform = matrix_identity_float4x4
        itemTransform.columns.3 = SIMD4(100, 0, 0, 1)

        let doc = Self.document(
            objects: [
                ObjectResource(ref: meshRef, content: .mesh(Self.cubeMesh())),
                ObjectResource(ref: assemblyRef, content: .components([
                    Component(objectRef: meshRef, transform: componentTransform)
                ])),
            ],
            buildItems: [BuildItem(objectRef: assemblyRef, transform: itemTransform)])

        let scene = SceneBuilder.makeScene(for: doc)
        let models = modelEntities(in: try modelSubtree(of: scene))
        #expect(models.count == 1)
        let world = try #require(models.first).position(relativeTo: try modelSubtree(of: scene))
        #expect(simd_distance(world, SIMD3(100, 0, 7)) < 1e-5)
    }

    // MARK: Colors

    @Test func objectDefaultColorTintsTheMaterial() throws {
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument(defaultColor: red))

        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 1)
        let tint = try tint(of: materials[0])
        #expect(simd_distance(tint, SIMD3(1, 0, 0)) < 0.02)
    }

    @Test func perTriangleColorsSplitTheMeshByColor() throws {
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let blue = ColorRGBA(red: 0, green: 0, blue: 255)
        let colors = Array(repeating: red, count: 6) + Array(repeating: blue, count: 6)
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument(triangleColors: colors))

        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 2)
        let tints = try materials.map { try tint(of: $0) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 0, 1)) < 0.02 })

        let mesh = try #require(model.model?.mesh)
        let triangleTotal = mesh.contents.models.reduce(0) { sum, m in
            sum + m.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }
        }
        #expect(triangleTotal == 12)
    }

    @Test func partiallyPaintedTrianglesFallBackToTheObjectColor() throws {
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let blue = ColorRGBA(red: 0, green: 0, blue: 255)
        let colors: [ColorRGBA?] = Array(repeating: red, count: 6) + Array(repeating: nil, count: 6)
        let scene = SceneBuilder.makeScene(
            for: Self.cubeDocument(defaultColor: blue, triangleColors: colors))

        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 2)
        let tints = try materials.map { try tint(of: $0) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 0, 1)) < 0.02 })
    }

    // MARK: Paint (issue #9)

    /// One painted mesh object wrapped in a Slicer Project whose filaments
    /// carry the given colors; the object itself prints on `baseFilament`.
    private static func paintedDocument(
        mesh: Mesh,
        filaments: [ColorRGBA?],
        baseFilament: Int? = nil
    ) -> ThreeMFDocument {
        let ref = ResourceRef(partPath: rootPart, id: 1)
        var doc = document(
            objects: [ObjectResource(ref: ref, content: .mesh(mesh))],
            buildItems: [BuildItem(objectRef: ref)])
        doc.slicerProject = SlicerProjectInfo(
            filaments: filaments.map { Filament(color: $0, type: "PLA") },
            plates: [Plate(id: 1, objectRefs: [ref])],
            filamentIndexByObject: baseFilament.map { [ref: $0] } ?? [:],
            plateRect: PlateRect(width: 180, depth: 180))
        return doc
    }

    @Test func paintedTrianglesGetFilamentColorsAndUnpaintedKeepTheObjectFilament() throws {
        // Six faces painted filament 0 (red), three filament 1 (green); the
        // remaining three stay on the object's own filament 2 (blue).
        let paint: [Int?] = Array(repeating: 0, count: 6)
            + Array(repeating: 1, count: 3)
            + Array(repeating: nil, count: 3)
        let doc = Self.paintedDocument(
            mesh: Self.cubeMesh(paintIndices: paint),
            filaments: [
                ColorRGBA(red: 255, green: 0, blue: 0),
                ColorRGBA(red: 0, green: 255, blue: 0),
                ColorRGBA(red: 0, green: 0, blue: 255),
            ],
            baseFilament: 2)

        let scene = SceneBuilder.makeScene(for: doc)
        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 3)
        let tints = try materials.map { try tint(of: $0) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 1, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 0, 1)) < 0.02 })

        // Every face survives the per-color split.
        let mesh = try #require(model.model?.mesh)
        let triangleTotal = mesh.contents.models.reduce(0) { sum, m in
            sum + m.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }
        }
        #expect(triangleTotal == 12)
    }

    @Test func paintWinsOverPropertyColorsOnTheSameTriangle() throws {
        // The slicer's own view shows the stroke, not the CAD color beneath.
        let yellow = ColorRGBA(red: 255, green: 255, blue: 0)
        let paint: [Int?] = Array(repeating: 0, count: 6) + Array(repeating: nil, count: 6)
        let doc = Self.paintedDocument(
            mesh: Self.cubeMesh(
                triangleColors: Array(repeating: yellow, count: 12),
                paintIndices: paint),
            filaments: [ColorRGBA(red: 255, green: 0, blue: 0)])

        let scene = SceneBuilder.makeScene(for: doc)
        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 2)
        let tints = try materials.map { try tint(of: $0) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(1, 1, 0)) < 0.02 })
    }

    @Test func outOfRangePaintFallsBackToFilamentZero() throws {
        // Lenient like the object-level mapping: a stroke referencing a
        // filament the project never defined prints on filament 0.
        let paint: [Int?] = Array(repeating: 7, count: 6) + Array(repeating: nil, count: 6)
        let doc = Self.paintedDocument(
            mesh: Self.cubeMesh(paintIndices: paint),
            filaments: [
                ColorRGBA(red: 255, green: 0, blue: 0),
                ColorRGBA(red: 0, green: 255, blue: 0),
            ],
            baseFilament: 1)

        let scene = SceneBuilder.makeScene(for: doc)
        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 2)
        let tints = try materials.map { try tint(of: $0) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 1, 0)) < 0.02 })
    }

    @Test func paintWithoutFilamentDefinitionsFallsBackToTheObjectColor() throws {
        // A painted mesh stripped of its Slicer Project (or one whose config
        // lost its filaments) has nothing to map through — the object color
        // wins over a crash or a phantom palette.
        let blue = ColorRGBA(red: 0, green: 0, blue: 255)
        let paint: [Int?] = Array(repeating: 0, count: 12)
        let doc = Self.cubeDocument(defaultColor: blue)
        var painted = doc
        painted.objects[0].content = .mesh(Self.cubeMesh(paintIndices: paint))

        let scene = SceneBuilder.makeScene(for: painted)
        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let materials = try #require(model.model?.materials)
        #expect(materials.count == 1)
        #expect(simd_distance(try tint(of: materials[0]), SIMD3(0, 0, 1)) < 0.02)
    }

    // MARK: Slicer Projects

    /// Two mesh objects (ids 1, 2) with build items, wrapped in slicer info:
    /// filaments red + green, object 1 → extruder 1, object 2 → extruder 2.
    private static func slicerDocument(
        plates: [Plate]? = nil,
        plateRect: PlateRect? = PlateRect(width: 180, depth: 180)
    ) -> ThreeMFDocument {
        let refs = [ResourceRef(partPath: rootPart, id: 1), ResourceRef(partPath: rootPart, id: 2)]
        var itemTransform = matrix_identity_float4x4
        itemTransform.columns.3 = SIMD4(100, 100, 0, 1)
        var doc = document(
            objects: refs.map { ObjectResource(ref: $0, content: .mesh(cubeMesh())) },
            buildItems: [
                BuildItem(objectRef: refs[0]),
                BuildItem(objectRef: refs[1], transform: itemTransform),
            ])
        doc.slicerProject = SlicerProjectInfo(
            filaments: [
                Filament(color: ColorRGBA(red: 255, green: 0, blue: 0), type: "PLA"),
                Filament(color: ColorRGBA(red: 0, green: 255, blue: 0), type: "PETG"),
            ],
            plates: plates ?? [Plate(id: 1, objectRefs: refs)],
            filamentIndexByObject: [refs[0]: 0, refs[1]: 1],
            plateRect: plateRect)
        return doc
    }

    @Test func slicerProjectMapsFilamentColorsToPartMaterials() throws {
        let scene = SceneBuilder.makeScene(for: Self.slicerDocument())

        let models = modelEntities(in: try modelSubtree(of: scene))
        #expect(models.count == 2)
        let tints = try models.map { try tint(of: try #require($0.model?.materials.first)) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 1, 0)) < 0.02 })
    }

    @Test func filamentColorFlowsThroughComponentsToUncoloredMeshes() throws {
        // Bambu packages wrap every mesh in a root component object; the root
        // object's filament assignment must color the referenced mesh.
        let meshRef = ResourceRef(partPath: "/3D/Objects/object_1.model", id: 1)
        let wrapperRef = ResourceRef(partPath: Self.rootPart, id: 2)
        var doc = Self.document(
            objects: [
                ObjectResource(ref: meshRef, content: .mesh(Self.cubeMesh())),
                ObjectResource(ref: wrapperRef, content: .components([
                    Component(objectRef: meshRef)
                ])),
            ],
            buildItems: [BuildItem(objectRef: wrapperRef)])
        doc.slicerProject = SlicerProjectInfo(
            filaments: [Filament(color: ColorRGBA(red: 0, green: 0, blue: 255), type: "PLA")],
            plates: [Plate(id: 1, objectRefs: [wrapperRef])],
            filamentIndexByObject: [wrapperRef: 0],
            plateRect: PlateRect(width: 256, depth: 256))

        let scene = SceneBuilder.makeScene(for: doc)
        let model = try #require(modelEntities(in: try modelSubtree(of: scene)).first)
        let tint = try tint(of: try #require(model.model?.materials.first))
        #expect(simd_distance(tint, SIMD3(0, 0, 1)) < 0.02)
    }

    @Test func slicerProjectShowsPlateHintAtTruePlateSizeInsteadOfBackdrop() throws {
        let scene = SceneBuilder.makeScene(for: Self.slicerDocument())

        let hint = try #require(scene.findEntity(named: "PlateHint"))
        // 180×180 mm at millimeter scale → 0.18×0.18 m in world space, flat.
        let extents = hint.visualBounds(relativeTo: nil).extents
        #expect(abs(extents.x - 0.18) < 1e-4)
        #expect(abs(extents.z - 0.18) < 1e-4)
        #expect(extents.y < 0.005)
        // The hint tops out at the bed plane (world y = 0), beneath the model.
        #expect(hint.visualBounds(relativeTo: nil).max.y <= 1e-4)

        #expect(scene.findEntity(named: "Backdrop") == nil)
    }

    @Test func partLevelExtruderOverridesTheObjectFilamentColor() throws {
        // A two-part object: the wrapper prints on filament 0 (red); one part
        // carries its own assignment to filament 1 (green).
        let pyramidRef = ResourceRef(partPath: "/3D/Objects/object_2.model", id: 1)
        let topperRef = ResourceRef(partPath: "/3D/Objects/object_2.model", id: 2)
        let wrapperRef = ResourceRef(partPath: Self.rootPart, id: 4)
        var doc = Self.document(
            objects: [
                ObjectResource(ref: pyramidRef, content: .mesh(Self.cubeMesh())),
                ObjectResource(ref: topperRef, content: .mesh(Self.cubeMesh())),
                ObjectResource(ref: wrapperRef, content: .components([
                    Component(objectRef: pyramidRef),
                    Component(objectRef: topperRef),
                ])),
            ],
            buildItems: [BuildItem(objectRef: wrapperRef)])
        doc.slicerProject = SlicerProjectInfo(
            filaments: [
                Filament(color: ColorRGBA(red: 255, green: 0, blue: 0), type: "PLA"),
                Filament(color: ColorRGBA(red: 0, green: 255, blue: 0), type: "PETG"),
            ],
            plates: [Plate(id: 1, objectRefs: [wrapperRef])],
            filamentIndexByObject: [wrapperRef: 0, topperRef: 1],
            plateRect: PlateRect(width: 180, depth: 180))

        let scene = SceneBuilder.makeScene(for: doc)
        let models = modelEntities(in: try modelSubtree(of: scene))
        #expect(models.count == 2)
        let tints = try models.map { try tint(of: try #require($0.model?.materials.first)) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 1, 0)) < 0.02 })
    }

    @Test func plateHintHonorsAnOffsetBedOrigin() throws {
        // An Orca-style offset bed: printable_area from (-20, -30). The build
        // (cubes spanning 0…110) fits inside it, so the hint must sit at the
        // metadata origin, not at zero.
        let scene = SceneBuilder.makeScene(for: Self.slicerDocument(
            plateRect: PlateRect(origin: SIMD2(-20, -30), width: 180, depth: 180)))

        let hint = try #require(scene.findEntity(named: "PlateHint"))
        let bounds = hint.visualBounds(relativeTo: nil)
        // Model space (mm, Z-up) → world (m, Y-up): x → x/1000, y → -z/1000.
        #expect(abs(bounds.min.x - -0.02) < 1e-4)
        #expect(abs(bounds.max.x - 0.16) < 1e-4)
        #expect(abs(bounds.max.z - 0.03) < 1e-4)
        #expect(abs(bounds.min.z - -0.15) < 1e-4)
    }

    @Test func sceneDefaultsToTheFirstPlateThatHasObjects() throws {
        // Plate 1 is empty; plate 2 holds only object 1 (red). Object 2's
        // build item must not be staged.
        let refs = [ResourceRef(partPath: Self.rootPart, id: 1), ResourceRef(partPath: Self.rootPart, id: 2)]
        let doc = Self.slicerDocument(plates: [
            Plate(id: 1),
            Plate(id: 2, objectRefs: [refs[0]]),
            Plate(id: 3, objectRefs: [refs[1]]),
        ])

        let scene = SceneBuilder.makeScene(for: doc)
        let models = modelEntities(in: try modelSubtree(of: scene))
        #expect(models.count == 1)
        let tint = try tint(of: try #require(models.first?.model?.materials.first))
        #expect(simd_distance(tint, SIMD3(1, 0, 0)) < 0.02)
    }

    @Test func explicitPlateStagesOnlyThatPlatesObjects() throws {
        // Plate switching (issue #6): asking for plate 3 stages object 2
        // (green) alone, regardless of the default plate.
        let refs = [ResourceRef(partPath: Self.rootPart, id: 1), ResourceRef(partPath: Self.rootPart, id: 2)]
        let doc = Self.slicerDocument(plates: [
            Plate(id: 1),
            Plate(id: 2, objectRefs: [refs[0]]),
            Plate(id: 3, objectRefs: [refs[1]]),
        ])

        let plates = try #require(doc.slicerProject?.plates)
        let scene = SceneBuilder.makeScene(for: doc, plate: plates[2])
        let models = modelEntities(in: try modelSubtree(of: scene))
        #expect(models.count == 1)
        let tint = try tint(of: try #require(models.first?.model?.materials.first))
        #expect(simd_distance(tint, SIMD3(0, 1, 0)) < 0.02)
    }

    @Test func explicitlyEmptyPlateStagesNothing() throws {
        // Clicking a Plate with no assignments must show the empty bed, not
        // fall back to the whole build.
        let doc = Self.slicerDocument(plates: [
            Plate(id: 1),
            Plate(id: 2, objectRefs: [ResourceRef(partPath: Self.rootPart, id: 1)]),
        ])

        let plates = try #require(doc.slicerProject?.plates)
        let scene = SceneBuilder.makeScene(for: doc, plate: plates[0])
        #expect(modelEntities(in: try modelSubtree(of: scene)).isEmpty)
        // The camera still has something to frame: the plate hint's bed.
        let bounds = SceneBuilder.modelBounds(of: scene)
        #expect(abs(bounds.extents.x - 0.18) < 1e-3)
        #expect(abs(bounds.extents.z - 0.18) < 1e-3)
    }

    @Test func explicitPlateWithUnmatchedAssignmentsFallsBackToTheWholeBuild() throws {
        // The lenient whole-build fallback holds for explicitly selected
        // plates too: a broken config must not empty the preview.
        let doc = Self.slicerDocument(plates: [
            Plate(id: 1, objectRefs: [ResourceRef(partPath: Self.rootPart, id: 99)]),
        ])

        let plates = try #require(doc.slicerProject?.plates)
        let scene = SceneBuilder.makeScene(for: doc, plate: plates[0])
        #expect(modelEntities(in: try modelSubtree(of: scene)).count == 2)
    }

    @Test func plateAssignmentsThatMatchNoBuildItemFallBackToTheWholeBuild() throws {
        // Defensive: a config referencing unknown objects must not empty the
        // preview.
        let doc = Self.slicerDocument(plates: [
            Plate(id: 1, objectRefs: [ResourceRef(partPath: Self.rootPart, id: 99)]),
        ])

        let scene = SceneBuilder.makeScene(for: doc)
        #expect(modelEntities(in: try modelSubtree(of: scene)).count == 2)
    }

    @Test func vanillaSceneHasNoPlateHint() throws {
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument())
        #expect(scene.findEntity(named: "PlateHint") == nil)
        #expect(scene.findEntity(named: "Backdrop") != nil)
    }

    @Test func slicerProjectWithoutPlateSizeKeepsTheBackdrop() throws {
        let scene = SceneBuilder.makeScene(for: Self.slicerDocument(plateRect: nil))
        #expect(scene.findEntity(named: "PlateHint") == nil)
        #expect(scene.findEntity(named: "Backdrop") != nil)
    }

    // MARK: Corpus-driven (file → document → entity tree)

    nonisolated private static let corpusRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // strip SceneSeamTests.swift
        .deletingLastPathComponent()  // strip ThreeMFViewerTests
        .deletingLastPathComponent()  // strip Tests
        .deletingLastPathComponent()  // strip ThreeMFViewer
        .deletingLastPathComponent()  // strip Packages
        .appendingPathComponent("Corpus")

    /// Corpus binaries are gitignored; tests that need one skip when absent.
    nonisolated private static func corpusHas(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: corpusRoot.appendingPathComponent(relativePath).path)
    }

    @Test(.enabled(if: corpusHas("vanilla/synthetic_basematerials.3mf")))
    func corpusBaseMaterialsFileBuildsColoredPlacedEntities() throws {
        let url = Self.corpusRoot.appendingPathComponent("vanilla/synthetic_basematerials.3mf")
        let scene = SceneBuilder.makeScene(for: try ThreeMFParser().parse(fileAt: url))

        let model = try modelSubtree(of: scene)
        let entities = modelEntities(in: model)
        #expect(entities.count == 2)

        let tints = try entities.map { try tint(of: try #require($0.model?.materials.first)) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0x46 / 255.0, 0x82 / 255.0, 0xB4 / 255.0)) < 0.02 })

        // The tetra's build item carries the 30 mm X translation.
        let translations = entities.map { $0.position(relativeTo: model) }
        #expect(translations.contains { simd_distance($0, SIMD3(30, 0, 0)) < 1e-4 })
    }

    @Test(.enabled(if: corpusHas("slicer-projects/FlightScnr.3mf")))
    func corpusBambuProjectBuildsFilamentColoredPartsOnPlateHint() throws {
        let url = Self.corpusRoot.appendingPathComponent("slicer-projects/FlightScnr.3mf")
        let scene = SceneBuilder.makeScene(for: try ThreeMFParser().parse(fileAt: url))

        // Three parts, all on extruder 1 → filament #000000 (ground truth:
        // unzip dumps of the config parts).
        let entities = modelEntities(in: try modelSubtree(of: scene))
        #expect(entities.count == 3)
        for entity in entities {
            let tint = try tint(of: try #require(entity.model?.materials.first))
            #expect(simd_distance(tint, SIMD3(0, 0, 0)) < 0.02)
        }

        // printable_area 256×256 mm → 0.256 m plate hint; no round backdrop.
        let hint = try #require(scene.findEntity(named: "PlateHint"))
        let extents = hint.visualBounds(relativeTo: nil).extents
        #expect(abs(extents.x - 0.256) < 1e-4)
        #expect(abs(extents.z - 0.256) < 1e-4)
        #expect(scene.findEntity(named: "Backdrop") == nil)
    }

    @Test(.enabled(if: corpusHas("slicer-projects/synthetic_painted.3mf")))
    func corpusPaintedProjectRendersItsPaintColors() throws {
        // Ground truth by construction (make_slicer_fixtures.py): a cube on
        // extruder 4 (yellow) painted red / green / blue / yellow, with one
        // out-of-range stroke that must fall back to filament 0 (red).
        let url = Self.corpusRoot.appendingPathComponent("slicer-projects/synthetic_painted.3mf")
        let scene = SceneBuilder.makeScene(for: try ThreeMFParser().parse(fileAt: url))

        let parts = modelEntities(in: try modelSubtree(of: scene)).filter { $0.model != nil }
        #expect(parts.count == 1)
        let materials = try #require(parts.first?.model?.materials)
        #expect(materials.count == 4)
        let tints = try materials.map { try tint(of: $0) }
        #expect(tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 1, 0)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(0, 0, 1)) < 0.02 })
        #expect(tints.contains { simd_distance($0, SIMD3(1, 1, 0)) < 0.02 })
    }

    @Test(.enabled(if: corpusHas("slicer-projects/synthetic_multiplate.3mf")))
    func corpusMultiPlateProjectShowsOnlyTheDefaultPlate() throws {
        let url = Self.corpusRoot.appendingPathComponent("slicer-projects/synthetic_multiplate.3mf")
        let scene = SceneBuilder.makeScene(for: try ThreeMFParser().parse(fileAt: url))

        // Plate 1 is empty → plate 2 (the cube on extruder 1, #FF0000) is the
        // default; the pyramid on plate 3 must not be staged.
        let entities = modelEntities(in: try modelSubtree(of: scene))
        let parts = entities.filter { $0.model != nil }
        #expect(parts.count == 1)
        let tint = try tint(of: try #require(parts.first?.model?.materials.first))
        #expect(simd_distance(tint, SIMD3(1, 0, 0)) < 0.02)
    }

    @Test(.enabled(if: corpusHas("slicer-projects/synthetic_multiplate.3mf")))
    func corpusMultiPlateProjectBuildsEachPlatesOwnScene() throws {
        let url = Self.corpusRoot.appendingPathComponent("slicer-projects/synthetic_multiplate.3mf")
        let document = try ThreeMFParser().parse(fileAt: url)
        let plates = try #require(document.slicerProject?.plates)
        #expect(plates.count == 3)

        // Plate 2: exactly the cube, on extruder 1 → #FF0000.
        let plate2 = SceneBuilder.makeScene(for: document, plate: plates[1])
        let plate2Parts = modelEntities(in: try modelSubtree(of: plate2)).filter { $0.model != nil }
        #expect(plate2Parts.count == 1)
        let plate2Tint = try tint(of: try #require(plate2Parts.first?.model?.materials.first))
        #expect(simd_distance(plate2Tint, SIMD3(1, 0, 0)) < 0.02)

        // Plate 3: the pyramid (object extruder 2 → #00FF00) plus the topper
        // (part-level extruder 1 override → #FF0000).
        let plate3 = SceneBuilder.makeScene(for: document, plate: plates[2])
        let plate3Parts = modelEntities(in: try modelSubtree(of: plate3)).filter { $0.model != nil }
        #expect(plate3Parts.count == 2)
        let plate3Tints = try plate3Parts.map { try tint(of: try #require($0.model?.materials.first)) }
        #expect(plate3Tints.contains { simd_distance($0, SIMD3(0, 1, 0)) < 0.02 })
        #expect(plate3Tints.contains { simd_distance($0, SIMD3(1, 0, 0)) < 0.02 })

        // Plate 1 is genuinely empty: nothing staged.
        let plate1 = SceneBuilder.makeScene(for: document, plate: plates[0])
        #expect(modelEntities(in: try modelSubtree(of: plate1)).filter { $0.model != nil }.isEmpty)
    }

    @Test(.enabled(if: corpusHas("slicer-projects/synthetic_multiplate.3mf")))
    func plateSwitchingNeedsNoFileAccessAfterTheParse() throws {
        // The issue #6 guarantee, made physical: parse a copy of the fixture,
        // DELETE it, then build every per-plate scene and read every Plate
        // Thumbnail. Switching Plates on a loaded document never re-reads
        // the file.
        let source = Self.corpusRoot.appendingPathComponent("slicer-projects/synthetic_multiplate.3mf")
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-reparse-\(UUID().uuidString).3mf")
        try FileManager.default.copyItem(at: source, to: copy)
        let document = try ThreeMFParser().parse(fileAt: copy)
        try FileManager.default.removeItem(at: copy)

        let plates = try #require(document.slicerProject?.plates)
        for plate in plates {
            let scene = SceneBuilder.makeScene(for: document, plate: plate)
            #expect(scene.findEntity(named: "Model") != nil)
        }
        #expect(plates.contains { $0.thumbnailData != nil })
    }

    // MARK: Staging

    @Test func sceneHasStudioLightingWithAShadowCastingKeyLight() throws {
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument())

        let lighting = lights(in: scene)
        #expect(lighting.count >= 2)

        var hasShadow = false
        func visit(_ entity: Entity) {
            if entity.components.has(DirectionalLightComponent.Shadow.self) { hasShadow = true }
            entity.children.forEach(visit)
        }
        visit(scene)
        #expect(hasShadow)
    }

    @Test func sceneHasABackdropBeneathTheModel() throws {
        let scene = SceneBuilder.makeScene(for: Self.cubeDocument())

        let backdrop = try #require(scene.findEntity(named: "Backdrop"))
        let backdropTop = backdrop.visualBounds(relativeTo: scene).max.y
        let modelBottom = try modelSubtree(of: scene).visualBounds(relativeTo: scene).min.y
        #expect(backdropTop <= modelBottom + 1e-4)
    }

    // MARK: Leniency

    @Test func documentWithoutBuildItemsShowsAllMeshObjects() throws {
        let doc = Self.document(
            objects: [ObjectResource(
                ref: ResourceRef(partPath: Self.rootPart, id: 1),
                content: .mesh(Self.cubeMesh()))],
            buildItems: [])

        let scene = SceneBuilder.makeScene(for: doc)
        #expect(modelEntities(in: try modelSubtree(of: scene)).count == 1)
    }

    @Test func buildItemReferencingAMissingObjectIsSkipped() throws {
        let ref = ResourceRef(partPath: Self.rootPart, id: 1)
        let doc = Self.document(
            objects: [ObjectResource(ref: ref, content: .mesh(Self.cubeMesh()))],
            buildItems: [
                BuildItem(objectRef: ref),
                BuildItem(objectRef: ResourceRef(partPath: Self.rootPart, id: 99)),
            ])

        let scene = SceneBuilder.makeScene(for: doc)
        #expect(modelEntities(in: try modelSubtree(of: scene)).count == 1)
    }

    @Test func emptyDocumentStillBuildsAScene() throws {
        let scene = SceneBuilder.makeScene(for: ThreeMFDocument())
        #expect(!lights(in: scene).isEmpty)
    }
}
