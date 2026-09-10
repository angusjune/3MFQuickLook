import AppKit
import GLBKit
import RealityKit
import simd
import Testing
@testable import ModelViewer

/// Scene-seam tests for the GLB path: given a document, the entity tree has
/// these entities, transforms and materials. Headless — no pixel assertions.
@MainActor
@Suite struct GLBSceneSeamTests {

    // MARK: Fixtures

    private static func triangle(
        positions: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
        textureCoordinates: [SIMD2<Float>]? = nil,
        materialIndex: Int? = nil
    ) -> GLBPrimitive {
        GLBPrimitive(
            positions: positions,
            textureCoordinates: textureCoordinates,
            indices: [0, 1, 2],
            materialIndex: materialIndex)
    }

    private static func document(
        nodes: [GLBNode] = [GLBNode(name: "Cube", meshIndex: 0)],
        roots: [Int] = [0],
        meshes: [GLBMesh]? = nil,
        materials: [GLBMaterial] = [],
        images: [GLBImage] = []
    ) -> GLBDocument {
        GLBDocument(
            nodes: nodes,
            rootNodeIndices: roots,
            meshes: meshes ?? [GLBMesh(name: "Mesh", primitives: [triangle()])],
            materials: materials,
            images: images)
    }

    private func modelSubtree(of document: GLBDocument) throws -> Entity {
        let scene = SceneBuilder.makeScene(for: .glb(document))
        return try #require(scene.findEntity(named: "Model"))
    }

    // MARK: Staging

    @Test func stagesTheModelUnderTheSharedLightingAndBackdrop() throws {
        let scene = SceneBuilder.makeScene(for: .glb(Self.document()))

        #expect(scene.name == "Scene")
        #expect(scene.findEntity(named: "Model") != nil)
        #expect(scene.findEntity(named: "Lighting") != nil)
        #expect(scene.findEntity(named: "Backdrop") != nil)
    }

    /// A GLB is an asset, not a print job: no bed to stand it on.
    @Test func hasNoPlateHint() throws {
        let scene = SceneBuilder.makeScene(for: .glb(Self.document()))
        #expect(scene.findEntity(named: "PlateHint") == nil)
    }

    /// The single most load-bearing fact of this path: glTF and RealityKit
    /// share a convention, so a vertex one meter up the glTF Y axis is one
    /// meter up the world Y axis — no unit scale, no axis swap.
    @Test func appliesNoCoordinateConversion() throws {
        let document = Self.document(meshes: [
            GLBMesh(primitives: [Self.triangle(positions: [
                SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
            ])])
        ])
        let model = try modelSubtree(of: document)

        #expect(model.transform.matrix == matrix_identity_float4x4)
        let bounds = model.visualBounds(relativeTo: nil)
        #expect(abs(bounds.max.y - 1) < 1e-4)
        #expect(abs(bounds.max.z) < 1e-4)
    }

    // MARK: Placement

    @Test func placesOneEntityPerNode() throws {
        let document = Self.document(
            nodes: [
                GLBNode(name: "Left", meshIndex: 0),
                GLBNode(
                    name: "Right",
                    transform: simd_float4x4(translation: SIMD3(5, 0, 0)),
                    meshIndex: 0),
            ],
            roots: [0, 1])
        let model = try modelSubtree(of: document)

        #expect(model.children.count == 2)
        #expect(model.children.map(\.name) == ["Left", "Right"])
        #expect(model.children[1].transform.translation == SIMD3(5, 0, 0))
    }

    /// Child nodes arrive with their parents' transforms already composed
    /// in, from the same flattening walk the Info Line measures.
    @Test func composesNestedNodeTransforms() throws {
        let document = Self.document(
            nodes: [
                GLBNode(
                    name: "Group",
                    transform: simd_float4x4(translation: SIMD3(0, 10, 0)),
                    childIndices: [1]),
                GLBNode(
                    name: "Child",
                    transform: simd_float4x4(translation: SIMD3(3, 0, 0)),
                    meshIndex: 0),
            ],
            roots: [0])
        let model = try modelSubtree(of: document)

        #expect(model.children.count == 1)
        #expect(model.children[0].transform.translation == SIMD3(3, 10, 0))
    }

    /// A node with no mesh contributes no entity — grouping nodes are
    /// already baked into the placements' transforms.
    @Test func skipsNodesWithoutGeometry() throws {
        let document = Self.document(
            nodes: [GLBNode(name: "Empty"), GLBNode(name: "Real", meshIndex: 0)],
            roots: [0, 1])
        #expect(try modelSubtree(of: document).children.count == 1)
    }

    @Test func emptyDocumentStagesNothingAndDoesNotCrash() throws {
        let model = try modelSubtree(of: GLBDocument())
        #expect(model.children.isEmpty)
    }

    // MARK: Materials

    @Test func givesEachPrimitiveItsOwnMaterial() throws {
        let document = Self.document(
            meshes: [GLBMesh(primitives: [
                Self.triangle(materialIndex: 0),
                Self.triangle(materialIndex: 1),
            ])],
            materials: [
                GLBMaterial(name: "Red", baseColor: GLBColor(red: 1, green: 0, blue: 0)),
                GLBMaterial(name: "Blue", baseColor: GLBColor(red: 0, green: 0, blue: 1)),
            ])
        let model = try modelSubtree(of: document)
        let entity = try #require(model.children.first as? ModelEntity)

        #expect(entity.model?.materials.count == 2)
        #expect(entity.model?.materials.allSatisfy { $0 is PhysicallyBasedMaterial } == true)
    }

    /// A primitive with no material still renders — the glTF default is an
    /// opaque white PBR material, not an absent one.
    @Test func primitiveWithoutAMaterialGetsTheGLTFDefault() throws {
        let model = try modelSubtree(of: Self.document())
        let entity = try #require(model.children.first as? ModelEntity)
        #expect(entity.model?.materials.count == 1)
    }

    /// An image that doesn't decode costs the material its map, never the
    /// file its preview.
    @Test func undecodableTextureStillRendersTheMaterial() throws {
        let document = Self.document(
            meshes: [GLBMesh(primitives: [
                Self.triangle(
                    textureCoordinates: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
                    materialIndex: 0)
            ])],
            materials: [GLBMaterial(baseColorImageIndex: 0)],
            images: [GLBImage(data: Data("not an image".utf8))])
        let model = try modelSubtree(of: document)

        #expect((model.children.first as? ModelEntity)?.model?.materials.count == 1)
    }

    /// A mesh placed twice builds its buffers once; the two entities share
    /// the resource rather than duplicating megabytes of vertices.
    @Test func sharesMeshResourcesAcrossPlacements() throws {
        let document = Self.document(
            nodes: [GLBNode(meshIndex: 0), GLBNode(meshIndex: 0)],
            roots: [0, 1])
        let model = try modelSubtree(of: document)

        let first = try #require((model.children[0] as? ModelEntity)?.model?.mesh)
        let second = try #require((model.children[1] as? ModelEntity)?.model?.mesh)
        #expect(first === second)
    }
}

extension simd_float4x4 {
    fileprivate init(translation: SIMD3<Float>) {
        self.init(
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0),
            SIMD4(translation.x, translation.y, translation.z, 1))
    }
}
