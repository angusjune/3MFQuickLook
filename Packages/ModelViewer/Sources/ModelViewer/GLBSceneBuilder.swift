import AppKit
import GLBKit
import RealityKit
import simd

/// Builds the RealityKit entity tree for a GLB, under the same lighting and
/// backdrop as the 3MF path (``SceneStaging``) so the two formats look like
/// one app.
///
/// No coordinate conversion happens here, and that is the point worth
/// knowing: glTF and RealityKit share a convention — right-handed, Y-up,
/// meters — so the file's own transforms are the scene's transforms. The 3MF
/// path has to convert; this one must not.
enum GLBSceneBuilder {
    @MainActor
    static func makeScene(for document: GLBDocument) -> Entity {
        let root = Entity()
        root.name = "Scene"

        let model = makeModelSubtree(for: document)
        root.addChild(model)
        root.addChild(SceneStaging.makeLighting())
        // No plate hint: a GLB is an asset, not a print job — there is no bed
        // to stand it on.
        if let backdrop = SceneStaging.makeBackdrop(beneath: model) {
            root.addChild(backdrop)
        }
        return root
    }

    @MainActor
    private static func makeModelSubtree(for document: GLBDocument) -> Entity {
        let model = Entity()
        model.name = "Model"

        let resources = ResourceCache(document: document)
        // The node hierarchy arrives already flattened into world transforms
        // — the same walk the Info Line measures, so the two can't disagree.
        for placement in document.placements() {
            guard let (mesh, materials) = resources.mesh(at: placement.meshIndex) else { continue }
            let entity = ModelEntity(mesh: mesh, materials: materials)
            entity.name = placement.name ?? ""
            entity.transform = Transform(matrix: placement.transform)
            model.addChild(entity)
        }
        return model
    }

    /// Mesh and texture resources, built once and shared across every
    /// placement. Instancing is how glTF scenes are usually authored — the
    /// same tree node placed forty times — and rebuilding its buffers forty
    /// times is exactly the allocation the Geometry Budget is trying to
    /// prevent.
    @MainActor
    private final class ResourceCache {
        private let document: GLBDocument
        private var meshes: [Int: (MeshResource, [any RealityKit.Material])?] = [:]
        private var textures: [Int: TextureResource?] = [:]

        init(document: GLBDocument) {
            self.document = document
        }

        func mesh(at index: Int) -> (MeshResource, [any RealityKit.Material])? {
            if let cached = meshes[index] { return cached }
            let built = build(meshAt: index)
            meshes[index] = built
            return built
        }

        /// One `MeshResource` per glTF mesh, with each primitive as its own
        /// part carrying its own material — the arrangement RealityKit draws
        /// in a single entity.
        private func build(meshAt index: Int) -> (MeshResource, [any RealityKit.Material])? {
            guard let mesh = document.mesh(at: index) else { return nil }

            var descriptors: [MeshDescriptor] = []
            var materials: [any RealityKit.Material] = []
            for primitive in mesh.primitives {
                guard !primitive.positions.isEmpty, !primitive.indices.isEmpty else { continue }
                var descriptor = MeshDescriptor(name: mesh.name ?? "mesh")
                descriptor.positions = MeshBuffer(primitive.positions)
                descriptor.normals = MeshBuffer(
                    primitive.normals
                        ?? SceneStaging.computedNormals(
                            positions: primitive.positions, indices: primitive.indices))
                if let coordinates = primitive.textureCoordinates {
                    // glTF puts UV (0, 0) at the image's top-left corner;
                    // RealityKit follows USD and puts it at the bottom-left,
                    // so every map arrives upside down without this flip.
                    descriptor.textureCoordinates = MeshBuffer(
                        coordinates.map { SIMD2($0.x, 1 - $0.y) })
                }
                descriptor.primitives = .triangles(primitive.indices)
                descriptor.materials = .allFaces(UInt32(materials.count))
                descriptors.append(descriptor)
                materials.append(material(for: primitive.materialIndex))
            }

            guard !descriptors.isEmpty,
                  let resource = try? MeshResource.generate(from: descriptors)
            else { return nil }
            return (resource, materials)
        }

        /// A glTF metallic-roughness material as RealityKit's own PBR
        /// material — the one place the two models line up almost term for
        /// term.
        private func material(for index: Int?) -> any RealityKit.Material {
            let source = index.flatMap { document.material(at: $0) } ?? .default
            var material = PhysicallyBasedMaterial()

            let components = source.baseColor.sRGBComponents
            let tint = NSColor(
                srgbRed: CGFloat(components.red),
                green: CGFloat(components.green),
                blue: CGFloat(components.blue),
                alpha: 1)
            if let imageIndex = source.baseColorImageIndex, let texture = texture(at: imageIndex) {
                material.baseColor = .init(tint: tint, texture: .init(texture))
            } else {
                material.baseColor = .init(tint: tint)
            }
            material.metallic = .init(floatLiteral: source.metallic)
            material.roughness = .init(floatLiteral: source.roughness)
            // Thin-shell assets (foliage, cloth, low-poly scenery) are full of
            // holes when their back faces are culled.
            material.faceCulling = source.isDoubleSided ? .none : .back

            switch source.alphaMode {
            case .opaque:
                break
            case .mask(let cutoff):
                // Alpha testing: the cutout shape the file intends, without
                // the sorting cost — and without a transparent pass that a
                // thumbnail render has no background to blend against.
                material.opacityThreshold = cutoff
            case .blend:
                material.blending = .transparent(
                    opacity: .init(floatLiteral: components.alpha))
            }
            return material
        }

        /// The decoded base-color map, through the same bomb-guarded decoder
        /// the Embedded Thumbnail path uses: a texture declaring gigapixel
        /// dimensions costs the material its map, never the extension its
        /// memory.
        private func texture(at index: Int) -> TextureResource? {
            if let cached = textures[index] { return cached }
            let resource = document.images[safe: index]
                .flatMap { PackageImageDecoder.cgImage(from: $0.data) }
                .flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
            textures[index] = resource
            return resource
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
