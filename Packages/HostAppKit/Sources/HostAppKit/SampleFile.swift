import Foundation

/// The bundled sample model offered during onboarding so the user can verify
/// the preview works: save it somewhere visible, press Space on it in Finder.
public enum SampleFile {
    /// The name the save panel suggests for the exported copy.
    public static let suggestedSavedName = "3MF Sample.3mf"

    /// The sample shipped in this package's resource bundle: a small
    /// multi-colored icosahedral gem (millimeters, 20 triangles).
    public static var bundledURL: URL? {
        Bundle.module.url(forResource: "SampleGem", withExtension: "3mf")
    }

    /// Copies the bundled sample to `destination`, replacing any existing
    /// file — the save panel has already confirmed overwrites.
    public static func export(to destination: URL) throws {
        guard let source = bundledURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
