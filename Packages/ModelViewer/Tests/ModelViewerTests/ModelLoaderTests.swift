import Foundation
import Testing
@testable import ModelViewer

/// The routing seam: which parser a file's bytes call for. Decided by
/// content, so a renamed download still previews as what it is.
@Suite struct ModelLoaderTests {
    private static let glbMagic = Data([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0])
    private static let zipMagic = Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0])

    @Test func recognizesGLBByItsMagic() {
        #expect(ModelLoader.format(of: Self.glbMagic) == .glb)
    }

    @Test func recognizesAnOPCPackageByItsZipMagic() {
        #expect(ModelLoader.format(of: Self.zipMagic) == .threeMF)
    }

    @Test func unrecognizedBytesHaveNoFormat() {
        #expect(ModelLoader.format(of: Data("hello".utf8)) == nil)
    }

    /// Content wins over the name: a GLB saved as `.3mf` still previews.
    @Test func contentOutranksTheFileExtension() throws {
        let url = try write(Self.glbMagic, extension: "3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ModelLoader.format(ofFileAt: url) == .glb)
    }

    /// A file too short to identify falls back to its extension, so an empty
    /// placeholder still reaches the parser that can explain it.
    @Test func fallsBackToTheExtensionForUnidentifiableBytes() throws {
        let url = try write(Data(), extension: "glb")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ModelLoader.format(ofFileAt: url) == .glb)
    }

    @Test func unrecognizedFilesFailToLoad() throws {
        let url = try write(Data("not a model".utf8), extension: "bin")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ModelLoader.LoadError.unrecognizedFormat) {
            try ModelLoader.load(fileAt: url, policy: .quickLookExtension)
        }
    }

    /// glTF has no thumbnail convention, so a GLB never has a first-paint
    /// image to hold — it goes straight to the loading state.
    @Test func glbFilesHaveNoEmbeddedThumbnail() throws {
        let url = try write(Self.glbMagic, extension: "glb")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ModelLoader.embeddedThumbnailData(fileAt: url, policy: .unlimited) == nil)
    }

    private func write(_ data: Data, extension pathExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
        try data.write(to: url)
        return url
    }
}
