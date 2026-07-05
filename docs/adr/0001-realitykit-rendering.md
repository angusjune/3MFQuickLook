# RealityKit for all 3D rendering, minimum macOS 15

Every existing third-party 3D Quick Look plugin we know of uses SceneKit, but SceneKit was deprecated at WWDC 2025 and this is a new codebase in 2026. We render the Viewer with RealityKit (`RealityView` + built-in `CameraControls` orbit/pan/dolly) and generate thumbnails offscreen with `RealityRenderer` — all of which require macOS 15, so that becomes the deployment floor. We accept losing macOS 13/14 users in exchange for not building a preview app on a sunsetting framework and for matching the stack Apple's own previews are moving to.

## Considered options

- **SceneKit** — free arcball camera, trivial offscreen snapshots, runs on macOS 13+. Rejected: deprecated; guaranteed rewrite later.
- **Custom Metal** — no deprecation risk, best control over huge meshes. Rejected: hand-rolling cameras, lighting, and thumbnail rendering is weeks of work RealityKit provides for free.
