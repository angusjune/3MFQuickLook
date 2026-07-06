# 3MF QuickLook

Quick Look previews and Finder thumbnails for `.3mf` files on macOS 15+.
Press Space on a 3MF file and get an interactive 3D preview; folders of models
get real thumbnails instead of blank icons.

**Status: vanilla 3MF end-to-end.** Core-spec parsing (plus the materials and
production extensions) renders real geometry with file colors: spacebar
previews are interactive (drag = orbit, scroll/pinch = zoom, secondary
drag = pan) and Finder thumbnails are true offscreen renders. Slicer-project
metadata (plates, filaments) lands next
([issue #4](https://github.com/angusjune/3MFQuickLook/issues/4)).

## Layout

- `App/`, `PreviewExt/`, `ThumbExt/` — the Host App and the two Quick Look
  extensions, thin adapters over the packages.
- `Packages/ThreeMFKit` — 3MF parsing: package file → `ThreeMFDocument`.
- `Packages/ThreeMFViewer` — scene building and the shared interactive Viewer:
  document → RealityKit entity tree, plus offscreen thumbnail rendering.
- `SmokeTests/` — end-to-end thumbnail smoke test.
- `CONTEXT.md` — glossary; `docs/adr/` — architecture decisions.

## Build and run

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

## Tests

```sh
swift test --package-path Packages/ThreeMFKit
swift test --package-path Packages/ThreeMFViewer
xcodebuild -project ThreeMFQuickLook.xcodeproj -scheme ThreeMFQuickLook \
  -configuration Debug -derivedDataPath build test    # end-to-end smoke
```

The smoke test launches the built app to register the extensions, then requests
a thumbnail through the `QLThumbnailGenerator` API — the same path Finder uses.
Never probe thumbnails with `qlmanage -t`; it hangs against extension-based
providers.
