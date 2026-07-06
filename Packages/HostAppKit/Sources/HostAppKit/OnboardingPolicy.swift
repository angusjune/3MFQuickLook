/// When the Host App shows onboarding (issue #11): at every launch where the
/// Quick Look extensions are not verifiably all enabled. It therefore appears
/// on first launch, disappears once the user enables the extensions, and
/// returns if they are ever re-disabled — no stored "seen it" flag to go
/// stale.
public enum OnboardingPolicy {
    public static func shouldPresentAtLaunch(given status: QuickLookExtensionStatus) -> Bool {
        !status.allEnabled
    }
}
