# Native 3MF parser instead of lib3mf

lib3mf is the official 3MF Consortium library and the obvious choice, but it cannot parse the slicer dialect (Bambu/Orca plates, filament colors in `Metadata/*.config`) — that code must be custom regardless — and its monolithic parse model fights Quick Look's need for progressive loading and hard time budgets on huge files. We parse natively: ZIPFoundation for the OPC container, libxml2 SAX (ships with macOS) for geometry, custom Swift for slicer metadata. We implement core spec + materials + production extensions ourselves; beam-lattice and slice extensions degrade gracefully rather than fail.

## Consequences

- We own spec-conformance bugs; a curated corpus of sample files from many exporters is a required test asset.
- No C++ dependency inside the sandboxed extensions.
- Quirky slicer-generated files that violate strict validation still preview (lenient-by-design parsing).
