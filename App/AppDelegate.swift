import AppKit
import HostAppKit

extension PluginKitProbe {
    /// The Host App's two Quick Look extensions (identifiers per project.yml).
    static let hostApp = PluginKitProbe(
        previewExtensionIdentifier: "com.angusjune.ThreeMFQuickLook.PreviewExt",
        thumbnailExtensionIdentifier: "com.angusjune.ThreeMFQuickLook.ThumbExt")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let status = await PluginKitProbe.hostApp.status()
            guard OnboardingPolicy.shouldPresentAtLaunch(given: status) else { return }
            // When the app was launched to show a document, onboarding appears
            // without stealing focus from it.
            let hasDocuments = !NSDocumentController.shared.documents.isEmpty
            OnboardingWindowController.shared.show(takingFocus: !hasDocuments)
        }
    }
}
