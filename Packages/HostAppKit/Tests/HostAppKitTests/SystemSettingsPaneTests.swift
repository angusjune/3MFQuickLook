import Testing
import HostAppKit

@Suite struct SystemSettingsPaneTests {
    /// Onboarding must land the user on the pane where Quick Look extensions
    /// are toggled (General → Login Items & Extensions → Quick Look).
    @Test func quickLookExtensionsURLTargetsTheExtensionsPane() {
        let url = SystemSettingsPane.quickLookExtensions
        #expect(url.scheme == "x-apple.systempreferences")
        #expect(url.absoluteString.contains("com.apple.ExtensionsPreferences"))
        #expect(url.absoluteString.contains("com.apple.quicklook"))
    }
}
