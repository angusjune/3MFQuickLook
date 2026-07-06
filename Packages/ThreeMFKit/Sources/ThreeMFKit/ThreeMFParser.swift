import Foundation

/// Parses a 3MF package file into a ``ThreeMFDocument``.
///
/// Walking-skeleton placeholder: reads the file (so unreadable paths throw)
/// and returns an empty document. Issue #3 replaces the body with real
/// OPC-container + SAX parsing per ADR-0002.
public struct ThreeMFParser: Sendable {
    public init() {}

    public func parse(fileAt url: URL) throws -> ThreeMFDocument {
        _ = try Data(contentsOf: url)
        return ThreeMFDocument()
    }
}
