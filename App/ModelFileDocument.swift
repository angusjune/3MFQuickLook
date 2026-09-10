import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our exported `.3mf` identifier (declared in the app's Info.plist).
    static let threeMF = UTType(exportedAs: "com.angusjune.threemf")
    /// The system's own `.glb` identifier, which CoreTypes declares — so
    /// this resolves to the system type rather than declaring a rival one.
    static let binaryGLTF = UTType("org.khronos.glb")
        ?? UTType(importedAs: "org.khronos.glb")
}

/// Read-only document wrapper: it just holds the file's bytes; parsing —
/// including deciding which format they are — happens asynchronously in the
/// window, so a huge file never stalls the document machinery. There is
/// deliberately no write path — the Host App is a viewer (PRD out-of-scope:
/// editing).
struct ModelFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.threeMF, .binaryGLTF]
    static let writableContentTypes: [UTType] = []

    let data: Data

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)  // never invoked: viewer-only
    }
}
