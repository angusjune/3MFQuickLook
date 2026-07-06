import Testing
import HostAppKit

/// Issue #11: onboarding appears at launch whenever the Quick Look extensions
/// are not verifiably all enabled — so it shows on first launch, stops showing
/// once the user enables them, and returns if they are ever re-disabled.
@Suite struct OnboardingPolicyTests {
    @Test func bothExtensionsEnabledSuppressesOnboarding() {
        let status = QuickLookExtensionStatus(preview: .enabled, thumbnail: .enabled)
        #expect(status.allEnabled)
        #expect(!OnboardingPolicy.shouldPresentAtLaunch(given: status))
    }

    @Test(arguments: [
        ExtensionEnablement.disabled, .problem, .notRegistered, .unknown,
    ])
    func anyNotEnabledExtensionPresentsOnboarding(state: ExtensionEnablement) {
        let previewOff = QuickLookExtensionStatus(preview: state, thumbnail: .enabled)
        let thumbnailOff = QuickLookExtensionStatus(preview: .enabled, thumbnail: state)
        #expect(OnboardingPolicy.shouldPresentAtLaunch(given: previewOff))
        #expect(OnboardingPolicy.shouldPresentAtLaunch(given: thumbnailOff))
        #expect(!previewOff.allEnabled)
        #expect(!thumbnailOff.allEnabled)
    }
}
