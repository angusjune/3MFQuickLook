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
        triangleColors: [ColorRGBA?]? = nil
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
        return Mesh(positions: positions, triangleIndices: triangles, triangleColors: triangleColors)
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

    // MARK: Corpus-driven (file → document → entity tree)

    nonisolated private static let corpusRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // strip SceneSeamTests.swift
        .deletingLastPathComponent()  // strip ThreeMFViewerTests
        .deletingLastPathComponent()  // strip Tests
        .deletingLastPathComponent()  // strip ThreeMFViewer
        .deletingLastPathComponent()  // strip Packages
        .appendingPathComponent("Corpus")

    @Test(.enabled(if: FileManager.default.fileExists(
        atPath: corpusRoot.appendingPathComponent("vanilla/synthetic_basematerials.3mf").path)))
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
