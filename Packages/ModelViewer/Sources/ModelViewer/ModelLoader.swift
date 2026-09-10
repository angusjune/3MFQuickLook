import AppKit
import Foundation
import GLBKit
import ThreeMFKit

/// The one place a file becomes a ``ModelDocument``: which parser to run,
/// under which limits, and what to paint before it finishes.
///
/// Format is decided by the file's own first bytes, not its name — the same
/// rule the 3MF path uses to recognize a Sliced File. A `.glb` that is
/// really a zip, or a `.3mf` a browser renamed, still previews as what it
/// actually is.
public enum ModelLoader {
    /// A format this app previews.
    public enum Format: Equatable, Sendable {
        case threeMF
        case glb
    }

    /// The parse-time resource policy, in the terms the surfaces think in.
    /// It fans out to each parser's own limits so a caller never has to hold
    /// two of them.
    public enum Policy: Equatable, Sendable {
        /// The Preview and Thumbnail Extensions: the Geometry Budget and the
        /// bomb caps (CONTEXT.md, docs/geometry-budget.md).
        case quickLookExtension
        /// The Host App: user-initiated, no budget.
        case unlimited

        var threeMF: ParseLimits {
            switch self {
            case .quickLookExtension: .quickLookExtension
            case .unlimited: .unlimited
            }
        }

        var glb: GLBParseLimits {
            switch self {
            case .quickLookExtension: .quickLookExtension
            case .unlimited: .unlimited
            }
        }
    }

    public enum LoadError: Error, Equatable, Sendable {
        /// The bytes are neither an OPC package nor a binary glTF.
        case unrecognizedFormat
    }

    // MARK: Format

    /// The format of the file at `url`, from its leading bytes — falling
    /// back to its path extension only when the file is too short to
    /// identify (an empty placeholder, a download still in flight).
    public static func format(ofFileAt url: URL) -> Format? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return format(ofPathExtension: url)
        }
        defer { try? handle.close() }
        let magic = (try? handle.read(upToCount: 4)) ?? Data()
        return format(ofMagic: magic) ?? format(ofPathExtension: url)
    }

    /// The format of bytes already in memory — the Host App's document path.
    public static func format(of data: Data) -> Format? {
        format(ofMagic: data.prefix(4))
    }

    private static func format(ofMagic magic: Data) -> Format? {
        if magic.starts(with: [0x67, 0x6C, 0x54, 0x46]) { return .glb }  // "glTF"
        if magic.starts(with: [0x50, 0x4B]) { return .threeMF }  // "PK": a zip
        return nil
    }

    private static func format(ofPathExtension url: URL) -> Format? {
        switch url.pathExtension.lowercased() {
        case "glb": .glb
        case "3mf": .threeMF
        default: nil
        }
    }

    // MARK: Loading

    public static func load(fileAt url: URL, policy: Policy) throws -> ModelDocument {
        switch format(ofFileAt: url) {
        case .threeMF:
            .threeMF(try ThreeMFParser(limits: policy.threeMF).parse(fileAt: url))
        case .glb:
            .glb(try GLBParser(limits: policy.glb).parse(fileAt: url))
        case nil:
            throw LoadError.unrecognizedFormat
        }
    }

    public static func load(data: Data, policy: Policy) throws -> ModelDocument {
        switch format(of: data) {
        case .threeMF:
            .threeMF(try ThreeMFParser(limits: policy.threeMF).parse(data: data))
        case .glb:
            .glb(try GLBParser(limits: policy.glb).parse(data: data))
        case nil:
            throw LoadError.unrecognizedFormat
        }
    }

    // MARK: First paint

    /// The Embedded Thumbnail (CONTEXT.md) to paint before geometry parses,
    /// extracted cheaply without touching geometry. Always nil for GLB:
    /// glTF has no thumbnail convention, so those files go straight to the
    /// neutral loading state and then the 3D scene.
    public static func embeddedThumbnailData(fileAt url: URL, policy: Policy) -> Data? {
        guard format(ofFileAt: url) == .threeMF else { return nil }
        return (try? ThreeMFParser(limits: policy.threeMF).embeddedThumbnail(fileAt: url))?.data
    }

    /// The Embedded Thumbnail of a file held in memory.
    public static func embeddedThumbnailData(data: Data, policy: Policy) -> Data? {
        guard format(of: data) == .threeMF else { return nil }
        return (try? ThreeMFParser(limits: policy.threeMF).embeddedThumbnail(data: data))?.data
    }

    /// The Embedded Thumbnail, decoded through the bomb-guarded decoder.
    public static func embeddedImage(fileAt url: URL, policy: Policy) -> NSImage? {
        embeddedThumbnailData(fileAt: url, policy: policy)
            .flatMap(PackageImageDecoder.nsImage(from:))
    }

    /// The Embedded Thumbnail of a file held in memory, decoded.
    public static func embeddedImage(data: Data, policy: Policy) -> NSImage? {
        embeddedThumbnailData(data: data, policy: policy)
            .flatMap(PackageImageDecoder.nsImage(from:))
    }

    // MARK: Errors

    /// Whether a parse failure was the Geometry Budget rather than a broken
    /// file — the one failure the surfaces answer with "open it in the Host
    /// App" instead of "can't read this". Both parsers report it in their
    /// own error type.
    public static func isOverGeometryBudget(_ error: any Error) -> Bool {
        switch error {
        case ThreeMFParseError.overGeometryBudget, GLBParseError.overGeometryBudget: true
        default: false
        }
    }
}
