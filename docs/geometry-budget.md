# Geometry Budget

The Geometry Budget (CONTEXT.md) is the hard limit on geometry the Quick Look
extensions will load: **4,000,000 geometry elements** (vertices + triangles,
summed across every model part of the package), set in
`ParseLimits.quickLookExtension` alongside the zip-bomb caps. Over budget, the
parse aborts with `ThreeMFParseError.overGeometryBudget` and the preview stays
on the Embedded Thumbnail with an "Open in 3MF QuickLook" hint; the Host App
parses `ParseLimits.unlimited` and loads everything.

The budget counts vertices *and* triangles because both allocate memory —
a vertex flood with no triangles must spend budget too. Real meshes run
~1 vertex per 2 triangles, so 4M elements ≈ a 2.7M-triangle model.

## Why the whole package, not literally per Plate

The panel shows one Plate at a time, but geometry memory is committed at
parse time for the whole package — Plates resolve only after the configs are
read. A package-wide cap upper-bounds every Plate's staged geometry, so
enforcing at the parse seam is both the honest memory defense and the
cheapest correct interpretation of "per-plate limit": no Plate can ever
exceed it.

## Profiling (2026-07-17, Apple M5, macOS 26.5.1)

### The ceiling

RunningBoard assigns both extensions a **1324 MB** soft memory limit
(`runningboardd` log: `Memory Limits: active 1324 inactive 1324`, observed
for `…ThumbExt` under ThumbnailsAgent and `…PreviewExt` under Finder). The
limit is machine-dependent policy, so the budget targets a comfortable
fraction of it, not the number itself.

### Parse-only cost (release `threemf-bench`, best of 2)

| Triangles | Vertices | Elements | Parse time | Peak footprint |
|---:|---:|---:|---:|---:|
| 1.0M | 0.50M | 1.5M | 0.37 s | 39 MB |
| 2.0M | 1.00M | 3.0M | 0.72 s | 72 MB |
| 4.0M | 2.00M | 6.0M | 1.50 s | 142 MB |
| 8.0M | 4.00M | 12.0M | 2.93 s | 282 MB |

Linear: ~23.5 MB per million elements.

### End-to-end Thumbnail Extension cost (Debug appex, fresh process per file,
`QLThumbnailGenerator` + `proc_pid_rusage` lifetime peak)

| File | Elements | ThumbExt peak | Wall time (debug) |
|---|---:|---:|---:|
| cube_gears.3mf (floor) | 0.04M | 262 MB | 1.2 s |
| synthetic 1M tri | 1.5M | 340 MB | 4.0 s |
| synthetic 2M tri | 3.0M | 385 MB | 10.2 s |
| **synthetic 2.66M tri (= budget)** | **4.0M** | **496 MB** | **13.9 s** |
| synthetic 4M tri | 6.0M | 722 MB | 16.5 s |
| synthetic 8M tri | 12.0M | 1398 MB | 36.4 s |

The ~262 MB floor is RealityKit/Metal, paid regardless of the file. Beyond
the floor, cost grows superlinearly (~50 B/element at 1.5M, ~95 B/element at
12M — RealityKit normal generation and staging buffers dominate the parsed
arrays).

### The choice

**4M elements → 496 MB peak, 37% of the measured ceiling.** Margins it buys:

- 2.7× headroom to the 1324 MB soft limit, absorbing pathological
  vertex-heavy meshes (worst case all-vertices costs more per element than
  the 1:2 profile measured here) and smaller limits on other machines.
- 1.6× over the biggest real corpus file (Civilization Atlas, 2.55M
  elements, 1.7M triangles) — locked by
  `ParseLimitsTests.extensionPresetPassesTheRealCorpusFlagship`, so the
  budget can never regress below the flagship.
- Time stays honest: ~1 s release-mode parse at budget; the 12M-element file
  took 36 s debug end-to-end — far past Finder's patience — so files that
  large are better served instantly by their Embedded Thumbnail anyway.

### Instrumented result

With the limits wired in,
`RobustnessSmokeTests.pathologicalCorpusResolvesGracefullyWithinTheMemoryCeiling`
drives the whole pathological corpus (zip bombs, image bomb, both
over-budget files, all the corrupt shapes) through `QLThumbnailGenerator`
and reads the extension's lifetime peak via `proc_pid_rusage`:
**281 MB** — the budget abort fires before render buffers ever allocate,
so hostile files cost *less* than legitimate ones. The smoke assertion
trips at 700 MB — the design-point peak (496 MB) plus margin — not at the
RunningBoard ceiling, so a memory regression fails long before jetsam
territory.

The Preview Extension has no headless driver (`QLThumbnailGenerator`
reaches only the Thumbnail Extension; the panel needs real Finder), so its
number comes from instrumenting the live process after a Finder session
covering the over-budget preview and a normal 3D preview: **314 MB** peak.
The smoke test reads any live PreviewExt process opportunistically and
holds it to the same bound.

## Zip-bomb caps (same preset)

- `maxStreamedPartBytes` = 512 MB decompressed per model part. Streaming
  parse means this bounds decompression *work*, not memory; 3.6× the biggest
  real corpus part (143 MB), and a real part at budget stays under ~250 MB.
- `maxMaterializedPartBytes` = 64 MB per fully-loaded part (Embedded
  Thumbnails, slicer configs). Real plate PNGs are ≤1 MB, configs ≤5 MB;
  oversized parts are treated as absent (lenient), never loaded.

Re-record this file when the parser, RealityKit usage, or the extension
process class changes materially.
