import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our exported `.3mf` identifier (declared in the app's Info.plist).
    static let threeMF = UTType(exportedAs: "com.angusjune.threemf")
}

/// Read-only document wrapper: it just holds the package bytes; parsing
/// happens asynchronously in the window so a huge file never stalls the
/// document machinery. There is deliberately no write path — the Host App is
/// a viewer (PRD out-of-scope: editing).
struct ThreeMFFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.threeMF]
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
