# CONTEXT — 3MF Quick Look

Glossary of the ubiquitous language for this project. Terms are canonical; use them in code, docs, and discussion.

## Surfaces

- **Host App** — the installable macOS application that contains the two Quick Look extensions. It is a *thin viewer*: opening a 3MF file shows the same interactive 3D view as the preview, plus first-run onboarding. It is explicitly not a slicer or editor.
- **Preview Extension** — the Quick Look preview extension (spacebar in Finder). Carries the full feature set: interactive 3D view, rotate/pan/zoom, build-plate browsing.
- **Thumbnail Extension** — the Quick Look thumbnail extension that supplies Finder icons and grid thumbnails for 3MF files.
- **Viewer** — the shared interactive 3D view component used by both the Host App and the Preview Extension.

## File flavors

- **Vanilla 3MF** — a package conforming to the core 3MF specification (plus standard 3MF extensions), typically exported by CAD tools. Has no build plates; the Viewer shows its entire build as one scene.
- **Slicer Project** — a 3MF package carrying slicer project metadata (plates, filament assignments, plate thumbnails) in the Bambu Studio / OrcaSlicer dialect. PrusaSlicer projects are treated as Vanilla 3MF with extras ("Vanilla-plus"), not as Slicer Projects.
- **Build Plate (Plate)** — a slicer-project concept: one arrangement of objects printed together. Only Slicer Projects have Plates. "Browse all build plates" applies only to files that actually contain more than zero Plates.
- **Sliced File** — a `.gcode.3mf` package: sliced G-code plus plate thumbnails, with mesh geometry stripped. Previewed as its embedded plate thumbnail(s) plus print metadata (printer, filaments, estimated time) — never a 3D scene.

## Viewer concepts

- **Plate Filmstrip** — the horizontal strip of Plate Thumbnails along the bottom of the Viewer used to switch Plates; hidden when a file has one Plate or none.
- **Geometry Budget** — the hard per-plate limit on geometry the Preview Extension will load. Under budget: interactive 3D. Over budget: the preview stays on the Embedded Thumbnail with a hint to open the Host App, which has no budget.
- **Info Line** — the single unobtrusive line of metadata shown in the Viewer: model dimensions, object count, and for Slicer Projects, print time and filament color dots. The only text chrome in the preview.
- **Plate Hint** — the flat outline the Viewer draws beneath a Slicer Project at the true plate size (from the project's printable-area metadata), standing in for the slicer's bed. Slicer Projects only; Vanilla 3MF keeps the plain backdrop.

## Package contents

- **Plate Thumbnail** — the pre-rendered PNG a slicer saved inside the package for one Plate.
- **Package Thumbnail** — the core-spec (OPC) thumbnail image covering the whole package; rare in practice, written by some CAD exporters.
- **Embedded Thumbnail** — collective term for either of the above; preferred over rendering whenever present.
