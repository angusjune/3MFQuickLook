import GLBKit
import ThreeMFKit

/// A parsed model file, whichever format it came from — the currency the
/// Viewer, the preview, and the Thumbnail Extension deal in.
///
/// The two cases stay whole rather than being flattened into a common scene
/// type: a 3MF package carries plates, filaments and print time that a GLB
/// has no notion of, and a GLB carries PBR materials and texture maps that a
/// 3MF has none of. Erasing either into a shared shape would cost both
/// formats the facts that make their previews worth looking at.
public enum ModelDocument: Equatable, Sendable {
    case threeMF(ThreeMFDocument)
    case glb(GLBDocument)

    /// Whether this document previews as an image and metadata rather than a
    /// 3D scene — true only for a Sliced File (CONTEXT.md), whose geometry
    /// its slicer stripped.
    public var isSlicedFile: Bool {
        switch self {
        case .threeMF(let document): document.isSlicedFile
        case .glb: false
        }
    }

    /// The 3MF document inside, for the surfaces that are 3MF-only — the
    /// Plate Filmstrip and the Sliced File view.
    public var threeMF: ThreeMFDocument? {
        switch self {
        case .threeMF(let document): document
        case .glb: nil
        }
    }
}
