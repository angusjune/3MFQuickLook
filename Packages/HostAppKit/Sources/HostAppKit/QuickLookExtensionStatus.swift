/// How macOS currently treats one of the Host App's Quick Look extensions.
public enum ExtensionEnablement: Equatable, Sendable {
    /// Elected for use (explicitly, or by the default election policy) —
    /// Quick Look will invoke it.
    case enabled
    /// Explicitly disabled (System Settings toggle turned off).
    case disabled
    /// Registered but flagged with a problem by PluginKit.
    case problem
    /// Not registered with PluginKit yet — registration happens when the app
    /// first launches and can lag by a moment.
    case notRegistered
    /// The election could not be determined (the PluginKit query failed).
    case unknown
}

/// The enablement of both Quick Look extensions the Host App ships
/// (CONTEXT.md: Preview Extension and Thumbnail Extension).
public struct QuickLookExtensionStatus: Equatable, Sendable {
    public var preview: ExtensionEnablement
    public var thumbnail: ExtensionEnablement

    public init(preview: ExtensionEnablement, thumbnail: ExtensionEnablement) {
        self.preview = preview
        self.thumbnail = thumbnail
    }

    public var allEnabled: Bool {
        preview == .enabled && thumbnail == .enabled
    }
}

/// A source of the extensions' current enablement; the UI takes the protocol
/// so previews and tests can substitute fixed statuses.
public protocol ExtensionStatusProbing: Sendable {
    func status() async -> QuickLookExtensionStatus
}
