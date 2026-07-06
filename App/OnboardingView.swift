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
        .frame(width: 480)
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
            Text("Quick Look for 3MF Files")
                .font(.title2.bold())
            Text("Press Space on a .3mf file in Finder for an interactive 3D preview, and get real thumbnails instead of blank icons.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    title: "Spacebar previews",
                    subtitle: "Preview Extension",
                    state: status?.preview)
                Divider()
                statusRow(
                    title: "Finder thumbnails",
                    subtitle: "Thumbnail Extension",
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

    @ViewBuilder
    private var guidance: some View {
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
