// PROTOTYPE — throwaway host app. See ../NOTES.md
import SwiftUI

@main
struct ProtoQLApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("ProtoQL — Quick Look interactivity probe").font(.title2).bold()
                Text("""
                1. This app exists only to register its Quick Look extensions.
                2. In Finder, select Sample.qlproto (run.sh reveals it) and press Space.
                3. Drag in the preview — if the boxes orbit, interactivity works.
                4. Check the Finder icon — 3 colored boxes = RealityRenderer works; red X = it failed.
                """)
                .font(.body)
            }
            .padding(24)
            .frame(minWidth: 520)
        }
    }
}
