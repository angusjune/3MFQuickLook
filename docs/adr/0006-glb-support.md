# GLB support: a second native parser, one shared Viewer

`.glb` (binary glTF 2.0) is the format 3D assets are actually handed around in, and macOS previews it with nothing — the built-in path fails (see below). We support it with a second native parser, `GLBKit`, for the same reasons the 3MF parser is native (ADR-0002): the container is a header and three integers, the glTF JSON is `Decodable`, and the alternative is a C++ toolkit inside a sandboxed extension with a hard memory ceiling. The parse is deliberately partial — geometry, node hierarchy, base color and its texture — because that is what a preview draws; animation, skinning, cameras and lights are read past, so a skinned mesh previews in its bind pose.

The two formats meet at `ModelDocument` in `ModelViewer` (renamed from `ThreeMFViewer`), which keeps each case whole instead of flattening both into a shared scene type: a 3MF carries plates, filaments and print time a GLB has no notion of, and a GLB carries PBR materials and texture maps a 3MF has none of. Erasing either would cost both formats the facts that make their previews worth looking at. Staging — lighting, backdrop, camera rig, vertex normals — *is* shared (`SceneStaging`), so the two formats do not look like two different apps.

Format is decided by the file's leading bytes, not its extension, matching how Sliced Files are detected.

## Consequences

- Two parsers, two limit types (`ParseLimits`, `GLBParseLimits`) with one Geometry Budget number to keep in step (docs/geometry-budget.md).
- glTF needs no coordinate conversion — it shares RealityKit's right-handed Y-up meters, unlike 3MF's Z-up model units — so the file's transforms are the scene's transforms. Texture coordinates do need a V flip: glTF's UV origin is top-left, RealityKit follows USD's bottom-left.
- Draco and meshopt compression are rejected with a clear error rather than previewed empty; every other required glTF extension is tolerated, since the worst case is a material a shade off.
- External `uri` buffers and images are never followed. A sandboxed preview must read only the file it was handed.

## GLB gets previews but not Finder thumbnails

macOS types `.glb` as `org.khronos.glb`, which conforms to `public.3d-content`. The system's `SceneKitQLThumbnailExtension` claims `public.3d-content` outright and wins the *thumbnail* election for the whole family — then fails, because SceneKit cannot read glTF. Our extension is never consulted. Measured on macOS 26 (2026-09-10), the claim was tested four ways and lost every time: at the exact type (`org.khronos.glb`), at the supertype (`public.3d-content`), with our app set as the type's default role handler, and behind an app-owned exported identifier for the `.glb` extension — a CoreTypes declaration outranks a third-party one, so `.glb` keeps resolving to `org.khronos.glb`.

The *preview* election has no such monopoly: our Preview Extension is elected for `.glb` and renders it.

`.3mf` is unaffected because nothing in macOS declares that extension: it resolves to our own exported `com.angusjune.threemf`, which deliberately stops at `public.data` (ADR-0002's neighbouring note in project.yml), so no system extension is ever a candidate. The same trick is not available for `.glb`.

If a future macOS drops the monopoly, GLB thumbnails start working with no code change: the Thumbnail Extension already declares `org.khronos.glb` and renders GLB correctly when it is asked (proven by routing a GLB through the 3MF type).
