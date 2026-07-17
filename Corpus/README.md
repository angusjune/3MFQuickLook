# Test corpus

Real-world and synthetic 3MF files that drive the parse-seam and
scene-seam tests (see the PRD's Testing Decisions, issue #1).

Drop files into the folder matching their flavor (`CONTEXT.md` glossary):

- `vanilla/` — core-spec exports from CAD tools (Fusion 360, Onshape,
  3D Builder…). Include at least one large mesh (1M+ triangles) for the
  performance baseline.
- `slicer-projects/` — Bambu Studio / OrcaSlicer projects (plates,
  filament assignments, plate thumbnails). PrusaSlicer projects too.
- `sliced/` — `.gcode.3mf` files.
- `pathological/` — corrupt, truncated, zip-bomb, image-bomb,
  over-budget, and exotic-extension files. Everything except the two
  hand-collected extension samples regenerates deterministically with
  `python3 Corpus/tools/make_pathological_fixtures.py` (the fixture
  list and each file's expected behavior are documented in that
  script; the assertions live in `PathologicalCorpusTests` and
  `SmokeTests`).

Corpus binaries are not committed to git history yet — the storage
decision (Git LFS vs. a fixtures release asset) is made in issue #3
when the first large file lands.
