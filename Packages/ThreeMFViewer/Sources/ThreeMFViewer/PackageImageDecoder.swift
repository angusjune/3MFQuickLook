import AppKit
import ImageIO

/// Decodes package-supplied image bytes — Embedded Thumbnails and Plate
/// Thumbnails — with an image-bomb guard (issue #10): the declared pixel
/// dimensions are read from the header alone and images past
/// ``maxPixelDimension`` per side are rejected before any pixel is
/// expanded. Quick Look decodes these images from untrusted downloads
/// automatically; a kilobyte PNG declaring a gigapixel canvas must degrade
/// to "no image", never allocate one.
public enum PackageImageDecoder {
    /// Cap per image side. Real slicer Plate Thumbnails are ~512 px and OPC
    /// Package Thumbnails similar; 4096 px (a 64 MB RGBA bitmap) is far
    /// beyond anything legitimate while staying harmless to decode inside
    /// the extension memory ceiling (docs/geometry-budget.md).
    public static let maxPixelDimension = 4096

    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              width <= maxPixelDimension, height <= maxPixelDimension
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func nsImage(from data: Data) -> NSImage? {
        cgImage(from: data).map { image in
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }
}
