import Foundation
import Testing
import HostAppKit
import ThreeMFKit

@Suite struct SampleFileTests {
    /// The bundled sample is load-bearing for onboarding ("verify the preview
    /// works"), so it must be a real, colored, well-formed 3MF.
    @Test func bundledSampleIsAValidColored3MF() throws {
        let url = try #require(SampleFile.bundledURL)
        let document = try ThreeMFParser().parse(fileAt: url)

        #expect(document.unit == .millimeter)
        #expect(document.buildItems.count == 1)
        let object = try #require(document.objects.first)
        guard case .mesh(let mesh) = object.content else {
            Issue.record("sample object should be a mesh")
            return
        }
        #expect(mesh.triangleCount == 20)
        let colors = try #require(mesh.triangleColors)
        #expect(Set(colors).count > 1, "the sample should be visibly multi-colored")
    }

    @Test func exportWritesTheSampleToTheDestination() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-export-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        defer { try? FileManager.default.removeItem(at: destination) }

        try SampleFile.export(to: destination)

        let bundled = try Data(contentsOf: #require(SampleFile.bundledURL))
        #expect(try Data(contentsOf: destination) == bundled)
    }

    /// The save panel confirms overwrites, so export must replace, not fail.
    @Test func exportReplacesAnExistingFile() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-export-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        defer { try? FileManager.default.removeItem(at: destination) }
        try Data("stale contents".utf8).write(to: destination)

        try SampleFile.export(to: destination)

        let bundled = try Data(contentsOf: #require(SampleFile.bundledURL))
        #expect(try Data(contentsOf: destination) == bundled)
    }
}
