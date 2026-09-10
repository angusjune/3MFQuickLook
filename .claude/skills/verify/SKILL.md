---
name: verify
description: Build, launch, and drive 3MF QuickLook to observe a change at its real surfaces (Host App window and Finder Quick Look panel). Use before committing changes with runtime surface.
---

# Verifying 3MF QuickLook changes

The surfaces are GUIs: the Host App document window and the Finder
spacebar Quick Look panel (Preview Extension). Both render the shared
`Viewer` from ModelViewer. Thumbnails (ThumbExt) are a third surface;
check those via a `QLThumbnailGenerator` harness, never `qlmanage -t`
(CLAUDE.md).

## Build + register

```bash
xcodebuild -scheme ThreeMFQuickLook -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/3MF QuickLook.app"   # once, re-registers appexes
```

Never build in worktrees/scratch dirs — those registrations poison the
extension election (CLAUDE.md).

## Drive the Host App

```bash
open -a "$(pwd)/build/Build/Products/Debug/3MF QuickLook.app" "Corpus/slicer-projects/synthetic_multiplate.3mf"
```

Screenshot/click via the computer-use MCP (request access to
"3MF QuickLook" and "Finder"). Useful fixtures:

- `Corpus/slicer-projects/synthetic_multiplate.3mf` — 3 plates: 1 empty,
  2 = 20 mm cube (sliced: 1h 31m prediction, filament 1), 3 = pyramid +
  topper (unsliced, extruders 2 and 1). Ground truth by construction:
  `Corpus/tools/make_slicer_fixtures.py`.
- `Corpus/vanilla/box.3mf` — 10 × 20 × 30 mm box, no slicer metadata.
- `Corpus/sliced/synthetic_single.gcode.3mf` — Sliced File: blue plate
  image, "Bambu Lab P1S · 1h 2m", green filament dot, no filmstrip.
- `Corpus/glb/*.glb` — GLB assets. Preview only: `.glb` never gets a
  Finder thumbnail (CLAUDE.md — SceneKit monopolizes the thumbnail
  election for `public.3d-content`). To exercise the GLB *render* path
  through the thumbnail harness, copy one to a `.3mf` filename; format
  is sniffed from the bytes.
- `Corpus/sliced/synthetic_multiplate.gcode.3mf` — Sliced File, 2 plates:
  red image "1h" red dot / green image "2h 1m" blue dot, filmstrip,
  "Bambu Lab X1 Carbon". Both must NEVER show a 3D scene.

## Drive the Quick Look panel

Kill stale workers first or the panel may serve the previous build:

```bash
pkill -f "PreviewExt|ThumbExt"; killall QuickLookUIService com.apple.quicklook.ThumbnailsAgent
```

Then in Finder: select a corpus file, press Space (bring Finder
frontmost with open_application first — hidden non-allowlisted windows
can intercept clicks at stale coordinates). The panel is the real
extension surface; `qlmanage -p` is not.

Pass/fail on registration questions comes from the Finder log, not
eyeballs — see CLAUDE.md for the `log show` predicate and the
lsregister ghost-record fix.
