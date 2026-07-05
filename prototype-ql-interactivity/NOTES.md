# PROTOTYPE — throwaway. Delete once the verdict below is filled in.

## Questions this prototype answers

1. **Do mouse interactions reach a third-party Quick Look preview extension?**
   Specifically: does drag-to-orbit via RealityKit `.realityViewCameraControls(.orbit)` work
   inside the QL panel, and do button clicks (→ Plate Filmstrip feasibility), scroll, and
   pinch events arrive? The preview shows live event counters, so the answer is on screen.
2. **Does `RealityRenderer` render offscreen inside a sandboxed Thumbnail Extension?**
   The Finder icon for `.qlproto` files is a RealityRenderer render if it works,
   a red X if it threw.

## How to run

```sh
./run.sh
```

Then press Space on the revealed `Sample.qlproto` in Finder.

- Boxes rotate when you drag → orbit works.
- Counters increment → events arrive even if RealityKit swallows them.
- "Clicks" button increments → in-preview buttons work (filmstrip is viable).
- Finder icon shows 3 colored boxes → RealityRenderer works in the thumbnail appex.

## Verdict (fill in before deleting)

- Drag/orbit in preview: **YES — confirmed 2026-07-05.** Boxes orbit on drag inside the Finder
  Quick Look panel; RealityKit's `.realityViewCameraControls(.orbit)` gesture handling works
  in the sandboxed preview appex.
- Buttons in preview: **YES.** Click events arrive and the SwiftUI button responds
  → Plate Filmstrip in the preview is viable.
- Scroll / pinch in preview: **Events arrive (counters climb) but `.orbit` ignores them —
  expected.** RealityKit `CameraControls` modes each map only a drag gesture; there is no
  built-in scroll/pinch zoom and no combined mode. Consequence: the real Viewer implements
  its own camera rig (drag = orbit, scroll/pinch = zoom, secondary-drag = pan) instead of
  relying on `CameraControls`. Feasible: all required events demonstrably reach the extension.
- RealityRenderer in thumbnail appex: **YES — confirmed 2026-07-05.** Sandboxed ThumbExt rendered
  the scene offscreen via RealityRenderer and returned real pixels (`thumb-probe.png`).
  Caveat: `qlmanage -t` hangs against this extension; probe through the
  `QLThumbnailGenerator` API (what Finder actually uses) instead.
- Consequence for the plan: **The architecture holds as designed.** The Preview Extension
  carries full interactivity (orbit/pan/zoom + clickable Plate Filmstrip); no fallback to
  Host-App-only interactivity is needed. Two adjustments feed the PRD:
  1. The Viewer uses a custom camera rig, not `CameraControls` (see scroll/pinch finding).
  2. Verify thumbnail behavior through `QLThumbnailGenerator`, never `qlmanage -t` (it hangs).
  Reusable scaffold knowledge before deleting this prototype: XcodeGen project.yml shape,
  appex bundle IDs must be prefixed with the parent app's bundle ID, ad-hoc signing +
  `open app` + `qlmanage -r` registration flow, sandbox entitlement on all three targets.
