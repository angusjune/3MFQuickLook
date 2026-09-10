import Foundation
import simd
import Testing
@testable import GLBKit

/// The parse seam: what a well-formed GLB turns into.
@Suite struct GLBParserTests {
    @Test func parsesASingleTriangle() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle())

        #expect(document.rootNodeIndices == [0])
        #expect(document.nodes.count == 1)
        #expect(document.nodes[0].meshIndex == 0)
        let primitive = try #require(document.meshes.first?.primitives.first)
        #expect(primitive.positions == [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)])
        #expect(primitive.indices == [0, 1, 2])
        #expect(primitive.triangleCount == 1)
        #expect(primitive.normals == nil)
        #expect(primitive.materialIndex == nil)
    }

    /// The Host App reads documents as bytes and the extensions as URLs; the
    /// two paths must agree.
    @Test func parsingDataMatchesParsingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("glb")
        try GLBBuilder.triangle().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try GLBParser().parse(fileAt: url) == GLBParser().parse(data: GLBBuilder.triangle()))
    }

    /// A primitive with no `indices` draws its vertices in order (spec
    /// §3.7.2.1); consumers should never have to handle both shapes.
    @Test func nonIndexedPrimitiveGetsImpliedIndices() throws {
        let data = GLBBuilder.triangle(primitive: ["indices": NSNull()])
        let document = try GLBParser().parse(data: data)
        #expect(document.meshes[0].primitives[0].indices == [0, 1, 2])
    }

    @Test func readsNormalsAndTextureCoordinates() throws {
        // POSITION, NORMAL and TEXCOORD_0 over the same three vertices.
        var binary = Data()
        for value in [Float](repeating: 0, count: 9) { binary.append(float: value) }
        for _ in 0..<3 {
            binary.append(float: 0)
            binary.append(float: 0)
            binary.append(float: 1)
        }
        for _ in 0..<3 {
            binary.append(float: 0.25)
            binary.append(float: 0.75)
        }
        for index in [UInt16(0), 1, 2] { binary.append(uint16: index) }
        while !binary.count.isMultiple(of: 4) { binary.append(0) }

        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2],
                    "indices": 3,
                ]]
            ]],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
                ["bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"],
                ["bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC2"],
                ["bufferView": 3, "componentType": 5123, "count": 3, "type": "SCALAR"],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": 36],
                ["buffer": 0, "byteOffset": 36, "byteLength": 36],
                ["buffer": 0, "byteOffset": 72, "byteLength": 24],
                ["buffer": 0, "byteOffset": 96, "byteLength": 6],
            ],
            "buffers": [["byteLength": binary.count]],
        ]
        let document = try GLBParser().parse(data: GLBBuilder.glb(json: json, binary: binary))

        let primitive = document.meshes[0].primitives[0]
        #expect(primitive.normals == [SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)])
        // Kept in glTF's own convention: the parser does not flip V.
        #expect(primitive.textureCoordinates == [
            SIMD2(0.25, 0.75), SIMD2(0.25, 0.75), SIMD2(0.25, 0.75),
        ])
    }

    /// Interleaved vertex data — one buffer view, `byteStride` between
    /// elements — is what most exporters actually write.
    @Test func readsInterleavedAttributes() throws {
        var binary = Data()
        for vertex in 0..<3 {
            binary.append(float: Float(vertex))  // POSITION
            binary.append(float: 0)
            binary.append(float: 0)
            binary.append(float: 0.5)  // TEXCOORD_0
            binary.append(float: 0.5)
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [[
                "primitives": [["attributes": ["POSITION": 0, "TEXCOORD_0": 1]]]
            ]],
            "accessors": [
                ["bufferView": 0, "byteOffset": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
                ["bufferView": 0, "byteOffset": 12, "componentType": 5126, "count": 3, "type": "VEC2"],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": binary.count, "byteStride": 20]
            ],
            "buffers": [["byteLength": binary.count]],
        ]
        let document = try GLBParser().parse(data: GLBBuilder.glb(json: json, binary: binary))

        let primitive = document.meshes[0].primitives[0]
        #expect(primitive.positions == [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(2, 0, 0)])
        #expect(primitive.textureCoordinates?.count == 3)
    }

    /// KHR_mesh_quantization territory: normalized integer attributes are
    /// scaled back into floats rather than read as raw counts.
    @Test func normalizedIntegerTextureCoordinatesAreScaled() throws {
        var binary = Data()
        for _ in 0..<3 {
            binary.append(float: 0)
            binary.append(float: 0)
            binary.append(float: 0)
        }
        for _ in 0..<3 {
            binary.append(uint16: 65535)
            binary.append(uint16: 0)
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0, "TEXCOORD_0": 1]]]]],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
                [
                    "bufferView": 1, "componentType": 5123, "count": 3,
                    "type": "VEC2", "normalized": true,
                ],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": 36],
                ["buffer": 0, "byteOffset": 36, "byteLength": 12],
            ],
            "buffers": [["byteLength": binary.count]],
        ]
        let document = try GLBParser().parse(data: GLBBuilder.glb(json: json, binary: binary))
        #expect(document.meshes[0].primitives[0].textureCoordinates?.first == SIMD2(1, 0))
    }

    // MARK: Nodes

    @Test func readsANodeMatrix() throws {
        // Column-major translation by (5, 6, 7).
        let matrix: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            5, 6, 7, 1,
        ]
        let document = try GLBParser().parse(
            data: GLBBuilder.triangle(node: ["mesh": 0, "matrix": matrix]))
        #expect(document.nodes[0].transform.columns.3 == SIMD4(5, 6, 7, 1))
    }

    /// Translation · rotation · scale, in the spec's order: a 90° turn about
    /// Z, then a doubling, then a move.
    @Test func composesTranslationRotationScale() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(node: [
            "mesh": 0,
            "translation": [1, 2, 3],
            "rotation": [0, 0, sin(Float.pi / 4), cos(Float.pi / 4)],
            "scale": [2, 2, 2],
        ]))

        let transform = document.nodes[0].transform
        let placed = transform * SIMD4<Float>(1, 0, 0, 1)
        #expect(abs(placed.x - 1) < 1e-5)
        #expect(abs(placed.y - 4) < 1e-5)
        #expect(abs(placed.z - 3) < 1e-5)
    }

    /// A file with no `scenes` still has a hierarchy; the roots are the
    /// nodes nobody claims as a child.
    @Test func fallsBackToUnclaimedNodesAsRoots() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "scenes": NSNull(),
            "scene": NSNull(),
            "nodes": [["children": [1]], ["mesh": 0]],
        ]))
        #expect(document.rootNodeIndices == [0])
        #expect(document.nodes[0].childIndices == [1])
    }

    @Test func dropsOutOfRangeChildAndMeshReferences() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "nodes": [["mesh": 0, "children": [7, 0]], ["mesh": 9]],
        ]))
        // Child 7 doesn't exist and child 0 is the node itself.
        #expect(document.nodes[0].childIndices.isEmpty)
        #expect(document.nodes[1].meshIndex == nil)
    }

    // MARK: Materials

    @Test func readsBaseColorFactor() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0],
            extraJSON: [
                "materials": [[
                    "name": "Red",
                    "pbrMetallicRoughness": [
                        "baseColorFactor": [1, 0, 0, 1],
                        "metallicFactor": 0,
                        "roughnessFactor": 0.5,
                    ],
                ]]
            ]))

        let material = try #require(document.materials.first)
        #expect(material.name == "Red")
        #expect(material.baseColor == GLBColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(material.metallic == 0)
        #expect(material.roughness == 0.5)
        #expect(document.meshes[0].primitives[0].materialIndex == 0)
    }

    @Test func materialWithoutPBRBlockIsOpaqueWhite() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0], extraJSON: ["materials": [["name": "Plain"]]]))
        #expect(document.materials[0].baseColor == .white)
        #expect(document.materials[0].metallic == 1)
    }

    @Test func outOfRangeMaterialFallsBackToTheDefault() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 3], extraJSON: ["materials": [["name": "Only"]]]))
        #expect(document.meshes[0].primitives[0].materialIndex == nil)
    }

    // MARK: Extensions

    @Test func requiredDracoCompressionIsRejected() {
        let data = GLBBuilder.triangle(extraJSON: [
            "extensionsRequired": ["KHR_draco_mesh_compression"]
        ])
        #expect(throws: GLBParseError.unsupportedRequiredExtension("KHR_draco_mesh_compression")) {
            try GLBParser().parse(data: data)
        }
    }

    /// Material-only extensions change how a file looks, not where its
    /// vertices are: previewing it slightly off beats refusing it.
    @Test func requiredMaterialExtensionsAreTolerated() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(extraJSON: [
            "extensionsRequired": ["KHR_materials_unlit", "KHR_texture_transform"]
        ]))
        #expect(document.meshes[0].triangleCount == 1)
    }
}

extension Data {
    fileprivate mutating func append(uint16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(float value: Float) {
        Swift.withUnsafeBytes(of: value.bitPattern.littleEndian) { append(contentsOf: $0) }
    }
}

/// Face culling and alpha handling: the two material facts that decide
/// whether an asset renders as it was authored or as a solid block.
@Suite struct GLBMaterialModeTests {
    @Test func defaultsToSingleSidedOpaque() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0], extraJSON: ["materials": [["name": "Plain"]]]))
        #expect(document.materials[0].isDoubleSided == false)
        #expect(document.materials[0].alphaMode == .opaque)
    }

    @Test func readsDoubleSidedAndCutoutMaterials() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0],
            extraJSON: [
                "materials": [[
                    "doubleSided": true, "alphaMode": "MASK", "alphaCutoff": 0.25,
                ]]
            ]))
        #expect(document.materials[0].isDoubleSided)
        #expect(document.materials[0].alphaMode == .mask(cutoff: 0.25))
    }

    @Test func cutoutWithoutAThresholdUsesTheSpecDefault() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0], extraJSON: ["materials": [["alphaMode": "MASK"]]]))
        #expect(document.materials[0].alphaMode == .mask(cutoff: 0.5))
    }

    @Test func blendModeIsCarried() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0], extraJSON: ["materials": [["alphaMode": "BLEND"]]]))
        #expect(document.materials[0].alphaMode == .blend)
    }

    @Test func unknownAlphaModeFallsBackToOpaque() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0], extraJSON: ["materials": [["alphaMode": "WOBBLY"]]]))
        #expect(document.materials[0].alphaMode == .opaque)
    }
}
