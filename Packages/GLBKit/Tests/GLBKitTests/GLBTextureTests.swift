import Foundation
import Testing
@testable import GLBKit

/// Base-color textures: carried when they are usable, dropped — never fatal
/// — when they aren't. Only the maps a material actually paints with are
/// carried, so a file's normal and roughness maps cost the preview nothing.
@Suite struct GLBTextureTests {
    /// A file with a base-color map plus two other maps carries exactly one
    /// image.
    @Test func carriesOnlyBaseColorImages() throws {
        let document = try GLBParser().parse(data: texturedTriangle(
            materials: [[
                "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]],
                "normalTexture": ["index": 1],
                "occlusionTexture": ["index": 2],
            ]],
            textures: [["source": 0], ["source": 1], ["source": 2]],
            imageCount: 3))

        #expect(document.images.count == 1)
        #expect(document.images[0].data == GLBBuilder.pngPixel)
        #expect(document.materials[0].baseColorImageIndex == 0)
    }

    /// Two materials sharing one map carry it once.
    @Test func deduplicatesASharedImage() throws {
        let document = try GLBParser().parse(data: texturedTriangle(
            materials: [
                ["pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]],
                ["pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]],
            ],
            textures: [["source": 0]],
            imageCount: 1))

        #expect(document.images.count == 1)
        #expect(document.materials.map(\.baseColorImageIndex) == [0, 0])
    }

    /// KHR_texture_basisu territory: a codec ImageIO can't read costs the
    /// material its map, not the file its preview.
    @Test func undecodableImageCodecIsDropped() throws {
        let document = try GLBParser().parse(data: texturedTriangle(
            materials: [["pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]]],
            textures: [["source": 0]],
            imageCount: 1,
            mimeType: "image/ktx2"))

        #expect(document.images.isEmpty)
        #expect(document.materials[0].baseColorImageIndex == nil)
        #expect(document.meshes[0].triangleCount == 1)
    }

    /// Past the texture budget the material keeps its base color factor and
    /// loses its map — garnish, exactly like an oversized Embedded Thumbnail
    /// on the 3MF path.
    @Test func imagePastTheTextureBudgetIsDropped() throws {
        let limits = GLBParseLimits(maxTextureBytes: 4)
        let document = try GLBParser(limits: limits).parse(data: texturedTriangle(
            materials: [["pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]]],
            textures: [["source": 0]],
            imageCount: 1))

        #expect(document.images.isEmpty)
        #expect(document.materials[0].baseColorImageIndex == nil)
    }

    /// A texture sampling TEXCOORD_1 has no coordinates in the document —
    /// the mesh resolver carries only set 0 — so it is not carried either.
    @Test func secondUVSetTextureIsDropped() throws {
        let document = try GLBParser().parse(data: texturedTriangle(
            materials: [[
                "pbrMetallicRoughness": ["baseColorTexture": ["index": 0, "texCoord": 1]]
            ]],
            textures: [["source": 0]],
            imageCount: 1))
        #expect(document.materials[0].baseColorImageIndex == nil)
    }

    @Test func readsAnImageFromADataURI() throws {
        let uri = "data:image/png;base64,\(GLBBuilder.pngPixel.base64EncodedString())"
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0],
            extraJSON: [
                "materials": [[
                    "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]
                ]],
                "textures": [["source": 0]],
                "images": [["uri": uri]],
            ]))
        #expect(document.images.first?.data == GLBBuilder.pngPixel)
    }

    /// An image beside the file is never opened — same rule as an external
    /// buffer, but garnish, so it degrades instead of failing.
    @Test func externalImageURIIsNotFollowed() throws {
        let document = try GLBParser().parse(data: GLBBuilder.triangle(
            primitive: ["material": 0],
            extraJSON: [
                "materials": [[
                    "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]
                ]],
                "textures": [["source": 0]],
                "images": [["uri": "albedo.png"]],
            ]))
        #expect(document.images.isEmpty)
        #expect(document.meshes[0].triangleCount == 1)
    }

    @Test func mimeTypeIsInferredFromMagicBytesWhenAbsent() {
        #expect(GLTFMaterialResolver.isDecodableImage(GLBBuilder.pngPixel, mimeType: nil))
        #expect(!GLTFMaterialResolver.isDecodableImage(Data("nope".utf8), mimeType: nil))
    }

    // MARK: Fixture

    /// A textured triangle whose images all live in the BIN chunk, after the
    /// geometry.
    private func texturedTriangle(
        materials: [[String: Any]],
        textures: [[String: Any]],
        imageCount: Int,
        mimeType: String? = "image/png"
    ) -> Data {
        // The triangle builder lays out 36 bytes of positions then 6 bytes of
        // indices, padded to 44; the images follow.
        let geometryLength = 44
        let png = GLBBuilder.pngPixel
        var binary = Data()
        var imageViews: [[String: Any]] = []
        for index in 0..<imageCount {
            imageViews.append([
                "buffer": 0,
                "byteOffset": geometryLength + index * png.count,
                "byteLength": png.count,
            ])
            binary.append(png)
        }

        var images: [[String: Any]] = []
        for index in 0..<imageCount {
            var image: [String: Any] = ["bufferView": 2 + index]
            if let mimeType { image["mimeType"] = mimeType }
            images.append(image)
        }

        return GLBBuilder.triangle(
            primitive: ["material": 0],
            extraJSON: [
                "materials": materials,
                "textures": textures,
                "images": images,
                "bufferViews": [
                    ["buffer": 0, "byteOffset": 0, "byteLength": 36],
                    ["buffer": 0, "byteOffset": 36, "byteLength": 6],
                ] + imageViews,
            ],
            trailingBinary: binary)
    }
}
