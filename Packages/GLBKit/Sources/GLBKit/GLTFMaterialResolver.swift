import Foundation

/// Resolves glTF materials down to what a preview paints with: a base color
/// factor and, when the file carries a usable one, a base-color image.
///
/// Textures are garnish, and treated the way the 3MF path treats Embedded
/// Thumbnails: anything unusable — an unsupported codec, a texture that
/// would push the file past ``GLBParseLimits/maxTextureBytes`` — costs the
/// material its map, never the file its preview.
struct GLTFMaterialResolver {
    let json: GLTFJSON
    let buffers: [Data?]
    let limits: GLBParseLimits

    /// The materials, plus the deduplicated images they reference.
    func resolve() -> (materials: [GLBMaterial], images: [GLBImage]) {
        var images: [GLBImage] = []
        /// glTF image index → index into `images`, so two materials sharing
        /// a map carry it once.
        var imageIndexByGLTFIndex: [Int: Int] = [:]
        var carriedBytes = 0

        let materials = (json.materials ?? []).map { material -> GLBMaterial in
            let pbr = material.pbrMetallicRoughness
            var imageIndex: Int?
            if let source = baseColorImageIndex(of: pbr) {
                if let existing = imageIndexByGLTFIndex[source] {
                    imageIndex = existing
                } else if let image = image(at: source),
                          fits(image.data.count, carried: carriedBytes) {
                    carriedBytes += image.data.count
                    imageIndex = images.count
                    imageIndexByGLTFIndex[source] = images.count
                    images.append(image)
                }
            }
            return GLBMaterial(
                name: material.name,
                baseColor: color(from: pbr?.baseColorFactor),
                baseColorImageIndex: imageIndex,
                metallic: pbr?.metallicFactor ?? 1,
                roughness: pbr?.roughnessFactor ?? 1)
        }
        return (materials, images)
    }

    /// The glTF image index a material's base-color texture resolves to.
    /// Only TEXCOORD_0 is honored — a second UV set would need a second
    /// coordinate stream the mesh resolver deliberately doesn't carry.
    private func baseColorImageIndex(of pbr: GLTFJSON.PBRMetallicRoughness?) -> Int? {
        guard let reference = pbr?.baseColorTexture,
              (reference.texCoord ?? 0) == 0,
              let texture = json.textures?[safe: reference.index],
              let source = texture.source
        else { return nil }
        return source
    }

    /// The encoded bytes of an image, from the BIN chunk or a `data:` URI.
    /// Nil when the image lives outside the file, or in a codec ImageIO
    /// can't decode (KTX2/Basis, most often, via KHR_texture_basisu).
    private func image(at index: Int) -> GLBImage? {
        guard let image = json.images?[safe: index] else { return nil }

        let data: Data?
        if let viewIndex = image.bufferView {
            data = bytes(ofBufferView: viewIndex)
        } else if let uri = image.uri {
            data = Self.decodeDataURI(uri)
        } else {
            data = nil
        }
        guard let data, Self.isDecodableImage(data, mimeType: image.mimeType) else { return nil }
        return GLBImage(data: data, mimeType: image.mimeType)
    }

    private func bytes(ofBufferView index: Int) -> Data? {
        guard let view = json.bufferViews?[safe: index],
              let buffer = buffers[safe: view.buffer] ?? nil
        else { return nil }
        let start = view.byteOffset ?? 0
        guard start >= 0, view.byteLength >= 0, start + view.byteLength <= buffer.count else {
            return nil
        }
        return buffer[
            buffer.index(buffer.startIndex, offsetBy: start)
                ..< buffer.index(buffer.startIndex, offsetBy: start + view.byteLength)]
    }

    private func fits(_ byteCount: Int, carried: Int) -> Bool {
        guard let maxTextureBytes = limits.maxTextureBytes else { return true }
        return carried + byteCount <= maxTextureBytes
    }

    private func color(from factor: [Float]?) -> GLBColor {
        guard let factor, factor.count >= 3 else { return .white }
        return GLBColor(
            red: factor[0], green: factor[1], blue: factor[2],
            alpha: factor.count > 3 ? factor[3] : 1)
    }

    // MARK: Bytes

    /// PNG and JPEG only — the two codecs glTF 2.0 actually specifies, and
    /// the two the renderer's bomb-guarded decoder handles. A declared
    /// `mimeType` decides when present; otherwise the magic bytes do, since
    /// exporters routinely omit it for `bufferView` images.
    static func isDecodableImage(_ data: Data, mimeType: String?) -> Bool {
        switch mimeType {
        case "image/png", "image/jpeg": return true
        case .some: return false
        case nil: break
        }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        return data.starts(with: png) || data.starts(with: jpeg)
    }

    /// The payload of a base64 `data:` URI. Other URI schemes name a file
    /// beside the GLB, which a sandboxed preview extension must never reach
    /// for — those images are simply absent.
    static func decodeDataURI(_ uri: String) -> Data? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let header = uri[uri.startIndex..<comma]
        guard header.hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...]))
    }
}
