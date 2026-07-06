import AppKit
import HostAppKit
import SwiftUI

/// The single onboarding window. Shown automatically at launch when
/// `OnboardingPolicy` says so, and on demand from the app menu
/// ("Quick Look Setup…").
@MainActor
final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private init() {
        let hosting = NSHostingController(
            rootView: OnboardingView(probe: PluginKitProbe.hostApp))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to 3MF QuickLook"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OnboardingWindowController is code-only")
    }

    /// Orders the window in; with `takingFocus` false it appears without
    /// stealing key status from a document the user just opened.
    func show(takingFocus: Bool = true) {
        guard let window else { return }
        if !window.isVisible { window.center() }
        if takingFocus {
            showWindow(nil)
            NSApp.activate()
        } else {
            window.orderFront(nil)
        }
    }
}
