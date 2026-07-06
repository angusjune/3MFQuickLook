import HostAppKit
import SwiftUI

/// The Host App (CONTEXT.md): a thin viewer around the shared Viewer, plus
/// first-run onboarding for the Quick Look extensions. Explicitly not a
/// slicer or editor.
@main
struct ThreeMFQuickLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: ThreeMFFileDocument.self) { file in
            DocumentView(data: file.document.data)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Quick Look Setup…") {
                    OnboardingWindowController.shared.show()
                }
            }
            UpdaterCommands()  // Sparkle auto-update; see CheckForUpdates.swift
        }
    }
}
