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
}
