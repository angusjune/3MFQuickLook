import Foundation

/// Deep links into System Settings.
public enum SystemSettingsPane {
    /// The pane where Quick Look extensions are toggled
    /// (General → Login Items & Extensions → Quick Look).
    public static let quickLookExtensions = URL(
        string: "x-apple.systempreferences:com.apple.ExtensionsPreferences"
            + "?extensionPointIdentifier=com.apple.quicklook.preview")!
}
