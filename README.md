# 3MF QuickLook

Quick Look previews and Finder thumbnails for `.3mf` files on macOS 15+.
Press Space on a 3MF file and get an interactive 3D preview; folders of models
get real thumbnails instead of blank icons.

- **Preview** — Space on any `.3mf` file opens a real 3D view: drag to orbit,
  scroll or pinch to zoom, secondary-drag to pan.
- **Thumbnails** — Finder icons and grid thumbnails are true offscreen renders
  of the model, with the file's own colors.
- **Slicer Projects** — Bambu Studio / OrcaSlicer projects preview like the
  slicer: parts in their assigned filament colors on a flat plate hint at the
  true plate size, showing the first Build Plate that has objects (plate
  browsing lands with the Plate Filmstrip,
  [issue #6](https://github.com/angusjune/3MFQuickLook/issues/6)).
  PrusaSlicer projects preview as Vanilla-plus.
- **Host app** — a thin viewer: open a `.3mf` file for the same interactive
  view in a window, with first-run onboarding for enabling the extensions.
  It's not a slicer or an editor.

**Status: pre-release.** Vanilla 3MF and Slicer Project previews are
end-to-end (core spec plus the materials and production extensions).
Embedded-thumbnail instant first paint lands next
([issue #5](https://github.com/angusjune/3MFQuickLook/issues/5)).

## Install

1. Download the latest `3MFQuickLook-<version>.dmg` from
   [Releases](https://github.com/angusjune/3MFQuickLook/releases).
2. Open it and drag **3MF QuickLook** to Applications.
3. Launch the app once — that registers the Quick Look extensions with macOS.
   First launch offers onboarding that checks the extensions' status, links to
   the System Settings pane that enables them, and bundles a sample file to
   test with. The app registers only as an *alternate* `.3mf` handler — it
   never takes over your double-click default.

Builds are not notarized (no Apple Developer Program membership yet; see
[docs/adr/0005](docs/adr/0005-unsigned-distribution.md)), so Gatekeeper blocks
the first launch: double-click the app once, then go to **System Settings →
Privacy & Security**, scroll down, and click **Open Anyway**. Alternatively,
before first launch: `xattr -d com.apple.quarantine "/Applications/3MF QuickLook.app"`.
This is a one-time step — later launches and Sparkle auto-updates are
unaffected. The app keeps itself current via [Sparkle](https://sparkle-project.org)
(check manually with **3MF QuickLook → Check for Updates…**).

### If previews don't show up

macOS occasionally needs a nudge to route Quick Look to a new extension:

- Check the extensions are enabled: **System Settings → General → Login Items
  & Extensions → Extensions → Quick Look** — both *3MF QuickLook* entries
  should be on.
- Relaunch Finder (Option-right-click its Dock icon → Relaunch), or log out
  and back in.

## Usage

- Select a `.3mf` file in Finder and press **Space**: interactive preview
  (drag = orbit, scroll/pinch = zoom, secondary drag = pan).
- Icon and gallery views show rendered thumbnails automatically.
- Double-click (or "Open With") to view the model in the app window.

## Building from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The Xcode project is generated, not committed:

```sh
xcodegen generate
xcodebuild -project ThreeMFQuickLook.xcodeproj -scheme ThreeMFQuickLook \
  -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/3MF QuickLook.app"   # registers the extensions
qlmanage -r                                            # reset Quick Look after rebuilds
```

Then press Space on any `.3mf` file in Finder.

### Layout

- `App/`, `PreviewExt/`, `ThumbExt/` — the Host App and the two Quick Look
  extensions, thin adapters over the packages.
- `Packages/ThreeMFKit` — 3MF parsing: package file → `ThreeMFDocument`.
- `Packages/ThreeMFViewer` — scene building and the shared interactive Viewer:
  document → RealityKit entity tree, plus offscreen thumbnail rendering.
- `Packages/HostAppKit` — Host-App-side logic: Quick Look extension status
  probing (via PluginKit elections), onboarding policy, the bundled sample.
- `SmokeTests/` — end-to-end thumbnail smoke test.
- `scripts/`, `.github/workflows/` — the release pipeline
  ([docs/RELEASING.md](docs/RELEASING.md)).
- `appcast.xml` — the Sparkle update feed, appended by the release workflow.
- `CONTEXT.md` — glossary; `docs/adr/` — architecture decisions.

### Tests

```sh
swift test --package-path Packages/ThreeMFKit
swift test --package-path Packages/ThreeMFViewer
swift test --package-path Packages/HostAppKit
xcodebuild -project ThreeMFQuickLook.xcodeproj -scheme ThreeMFQuickLook \
  -configuration Debug -derivedDataPath build test    # end-to-end smoke
```

The smoke test launches the built app to register the extensions, then requests
a thumbnail through the `QLThumbnailGenerator` API — the same path Finder uses.
Never probe thumbnails with `qlmanage -t`; it hangs against extension-based
providers.

### Releasing

Pushing a version tag (`v1.2.3`) produces an ad-hoc-signed, unnotarized DMG on
a GitHub Release and publishes the Sparkle appcast entry — see
[docs/RELEASING.md](docs/RELEASING.md) for the one-time credential setup and
the release checklist.
