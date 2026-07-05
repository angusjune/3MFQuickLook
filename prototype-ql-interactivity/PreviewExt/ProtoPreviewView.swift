// PROTOTYPE — throwaway. RealityKit scene + on-screen event counters. See ../NOTES.md
import SwiftUI
import RealityKit
import AppKit

/// Counts every input event delivered to this extension process, independent of
/// whether RealityKit's gesture recognizers consume it.
final class EventCounter: ObservableObject {
    @Published var counts: [String: Int] = [:]
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .rightMouseDragged,
            .scrollWheel, .magnify, .keyDown,
        ]) { [weak self] event in
            self?.bump(Self.label(for: event.type))
            return event
        }
    }

    private func bump(_ key: String) {
        DispatchQueue.main.async { self.counts[key, default: 0] += 1 }
    }

    static func label(for type: NSEvent.EventType) -> String {
        switch type {
        case .leftMouseDown: return "click"
        case .leftMouseDragged: return "drag"
        case .rightMouseDragged: return "right-drag"
        case .scrollWheel: return "scroll"
        case .magnify: return "pinch"
        case .keyDown: return "key"
        default: return "other"
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

struct ProtoPreviewView: View {
    let fileName: String
    @StateObject private var events = EventCounter()
    @State private var buttonClicks = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.camera = .virtual
                content.add(Self.makeScene())
            }
            .realityViewCameraControls(.orbit)

            VStack(alignment: .leading, spacing: 8) {
                Text(fileName).font(.headline)
                Text("proc: \(ProcessInfo.processInfo.processName)")
                Text(counterLine)
                Text("Drag to orbit. Boxes rotate → interactivity works.")
                Button("Clicks: \(buttonClicks)") { buttonClicks += 1 }
            }
            .font(.system(.body, design: .monospaced))
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
    }

    private var counterLine: String {
        let keys = ["click", "drag", "scroll", "pinch", "key"]
        return keys.map { "\($0): \(events.counts[$0, default: 0])" }.joined(separator: "  ")
    }

    static func makeScene() -> Entity {
        let root = Entity()

        let colors: [(NSColor, Bool)] = [
            (.systemOrange, false),  // lit — tests default lighting
            (.systemBlue, false),
            (.systemGreen, true),    // unlit — visible even if lighting is broken
        ]
        for (i, (color, unlit)) in colors.enumerated() {
            let material: any RealityKit.Material = unlit
                ? UnlitMaterial(color: color)
                : SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)
            let box = ModelEntity(
                mesh: .generateBox(size: 0.4, cornerRadius: 0.04),
                materials: [material]
            )
            box.position = [Float(i - 1) * 0.55, 0, 0]
            root.addChild(box)
        }

        let light = Entity()
        light.components.set(DirectionalLightComponent(color: .white, intensity: 3000))
        light.look(at: .zero, from: [1.0, 1.5, 1.5], relativeTo: nil)
        root.addChild(light)

        return root
    }
}
