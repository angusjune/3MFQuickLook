# Parse-seam performance baseline

Recorded 2026-07-06 on an Apple M5, macOS 26.5.1, release build
(`swift run -c release threemf-bench <file> <iterations>` from
`Packages/ThreeMFKit`; best-of-N wall time, lifetime peak physical
footprint of the fresh bench process).

| Corpus file | Triangles | Parse time | Peak footprint |
|---|---:|---:|---:|
| `slicer-projects/Civilization-Atlas-Diorama-FanArt-3Dprint.3mf` (143 MB model part) | 1,702,438 | 0.672 s (best of 3) | 67 MB |
| `slicer-projects/FlightScnr.3mf` | 13,824 | 0.005 s (best of 5) | 3 MB |
| `vanilla/cube_gears.3mf` | 25,692 | 0.009 s (best of 5) | 3 MB |

The peak footprint staying at ~half the uncompressed part size confirms the
streaming path (chunked zip extract → libxml2 push parser) never materializes
a whole model part; memory is dominated by the parsed vertex/index arrays.

A coarse regression guard lives in
`ParseSeamCorpusTests.millionTriangleFileParsesWithinBaseline` (10 s debug-mode
ceiling; measured ~5.4 s debug, ~0.7 s release). Re-record this table when the
parser or its dependencies change materially.
