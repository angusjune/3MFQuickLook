import Testing
import HostAppKit

@Suite struct PluginKitProbeTests {
    /// Integration through the real `pluginkit` binary (a read-only query):
    /// identifiers that were never registered come back `.notRegistered`.
    @Test func unregisteredIdentifiersReportNotRegistered() async {
        let probe = PluginKitProbe(
            previewExtensionIdentifier: "com.example.hostappkit-tests.never-registered-preview",
            thumbnailExtensionIdentifier: "com.example.hostappkit-tests.never-registered-thumbnail")

        let status = await probe.status()

        #expect(status.preview == .notRegistered)
        #expect(status.thumbnail == .notRegistered)
        #expect(!status.allEnabled)
    }

    private let id = "com.angusjune.ThreeMFQuickLook.PreviewExt"

    /// `pluginkit -m` exits 0 with no output for an unregistered identifier.
    @Test func cleanExitWithNoOutputMeansNotRegistered() {
        #expect(PluginKitProbe.interpret(exitStatus: 0, output: "", forIdentifier: id) == .notRegistered)
    }

    /// pkd refuses discovery to sandboxed callers ("unauthorized discovery
    /// flag (PKDiscoverAll)", exit 1, empty stdout — captured empirically).
    /// That must read as "couldn't determine", never as "not registered".
    @Test func failureExitMeansUnknown() {
        #expect(PluginKitProbe.interpret(exitStatus: 1, output: "", forIdentifier: id) == .unknown)
    }

    @Test func cleanExitWithMatchOutputIsParsed() {
        let output = "+    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)\n"
        #expect(PluginKitProbe.interpret(exitStatus: 0, output: output, forIdentifier: id) == .enabled)
    }
}
