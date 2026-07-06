import Sparkle
import SwiftUI

/// Sparkle 2 auto-update wiring (ADR-0003). The Host App is the only surface
/// that updates; the Quick Look extensions ship inside it and update with it.
///
/// `UpdaterCommands` is the app's entire integration point: attach it via
/// `.commands { UpdaterCommands() }`. Constructing it starts the shared
/// updater, which schedules Sparkle's standard background checks (permission
/// prompt on second launch, EdDSA-verified installs from the appcast at
/// SUFeedURL — both configured in project.yml).
struct UpdaterCommands: Commands {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updaterController.updater)
        }
    }
}

// "Check for Updates…" menu item, following Sparkle's documented SwiftUI
// setup (https://sparkle-project.org/documentation/programmatic-setup/). The
// intermediate view model keeps the menu item's disabled state live. Sparkle
// 2.9 marks `canCheckForUpdates` @MainActor, and Swift 6 forbids key paths to
// actor-isolated properties, so this observes via string-based KVO instead of
// the documented `publisher(for:)` key-path form. Sparkle only mutates the
// property on the main thread, so the @Published assignment publishes there.
private final class CheckForUpdatesViewModel: NSObject, ObservableObject {
    @Published var canCheckForUpdates = false

    private static let observedKey = "canCheckForUpdates"
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        super.init()
        updater.addObserver(
            self, forKeyPath: Self.observedKey, options: [.initial, .new], context: nil)
    }

    deinit {
        updater.removeObserver(self, forKeyPath: Self.observedKey)
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.observedKey else {
            super.observeValue(
                forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        canCheckForUpdates = change?[.newKey] as? Bool ?? false
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
