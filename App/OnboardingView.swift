import AppKit
import HostAppKit
import SwiftUI

/// First-run onboarding (issue #11): live status of the two Quick Look
/// extensions, a shortcut to the System Settings pane that toggles them, and
/// a bundled sample file to verify the preview with.
struct OnboardingView: View {
    let probe: any ExtensionStatusProbing

    @State private var status: QuickLookExtensionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusBox
            guidance
            actions
        }
        .padding(24)
        // Wide enough for the four action buttons to keep their full labels
        // at large system text sizes; at 480 macOS truncated both "Save
        // Sample File…" and "Open System Settings…" down to ellipses.
        .frame(width: 620)
        .task { await refresh() }
        // Coming back from System Settings re-activates the app; re-probe so
        // the rows reflect what the user just toggled.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Look for 3MF and GLB Files")
                .font(.title2.bold())
            Text("Press Space on a .3mf or .glb file in Finder for an interactive 3D preview, and get real thumbnails for 3MF files instead of blank icons.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Which files each extension covers is part of its row, because the
    /// answer differs: macOS reserves .glb icons for its own thumbnail
    /// extension, so no third-party app can draw them (docs/adr/0006).
    /// Someone who enabled both and still sees plain .glb icons should find
    /// that here rather than conclude the app is broken.
    private var statusBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    title: "Spacebar previews",
                    subtitle: "Preview Extension · .3mf and .glb",
                    state: status?.preview)
                Divider()
                statusRow(
                    title: "Finder thumbnails",
                    subtitle: "Thumbnail Extension · .3mf",
                    state: status?.thumbnail)
            }
            .padding(8)
        }
    }

    private func statusRow(title: String, subtitle: String, state: ExtensionEnablement?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let state {
                Label(caption(for: state), systemImage: symbol(for: state))
                    .foregroundStyle(color(for: state))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func caption(for state: ExtensionEnablement) -> String {
        switch state {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .problem: "Needs attention"
        case .notRegistered: "Not registered yet"
        case .unknown: "Unknown"
        }
    }

    private func symbol(for state: ExtensionEnablement) -> String {
        switch state {
        case .enabled: "checkmark.circle.fill"
        case .disabled: "xmark.circle.fill"
        case .problem: "exclamationmark.triangle.fill"
        case .notRegistered: "clock"
        case .unknown: "questionmark.circle"
        }
    }

    private func color(for state: ExtensionEnablement) -> Color {
        switch state {
        case .enabled: .green
        case .disabled: .orange
        case .problem: .orange
        case .notRegistered, .unknown: .secondary
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status, status.allEnabled {
                Label {
                    Text("Quick Look is ready. Save the sample file, then press Space on it in Finder to see it in 3D.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Text("Turn both extensions on under Quick Look in System Settings → General → Login Items & Extensions, then come back here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("GLB files keep their usual Finder icon: macOS draws .glb icons with its own extension. Their spacebar preview is the full 3D view.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack {
            Button("Save Sample File…") { saveSample() }
            Button("View Sample") { openSampleInViewer() }
            Spacer()
            Button("Check Again") {
                Task { await refresh() }
            }
            Button("Open System Settings…") {
                NSWorkspace.shared.open(SystemSettingsPane.quickLookExtensions)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func refresh() async {
        status = await probe.status()
    }

    /// Exports the bundled sample somewhere user-visible and reveals it in
    /// Finder, ready for a spacebar test.
    private func saveSample() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.threeMF]
        panel.nameFieldStringValue = SampleFile.suggestedSavedName
        panel.directoryURL = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = "Save the sample, then press Space on it in Finder to try Quick Look."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try SampleFile.export(to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Opens the bundled sample in a regular document window — proves the
    /// shared Viewer works even before the extensions are enabled.
    private func openSampleInViewer() {
        guard let url = SampleFile.bundledURL else { return }
        NSDocumentController.shared.openDocument(
            withContentsOf: url, display: true) { _, _, _ in }
    }
}
