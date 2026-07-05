import SwiftUI
import ThreeMFKit
import ThreeMFViewer

@main
struct ThreeMFQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Launching this app registers the Quick Look extensions. Press Space on a .3mf file in Finder to preview it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
            Viewer(document: ThreeMFDocument())
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
