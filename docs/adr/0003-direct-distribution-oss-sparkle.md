# Direct distribution, open source, Sparkle updates

The obvious channel for a consumer Quick Look utility is the Mac App Store (discovery, trust, free updates). We ship Developer ID–signed, notarized builds via GitHub Releases instead, with the repo public (permissive license) and a Homebrew cask once eligible. Open-sourcing replaces the store as the trust-and-discovery engine — QL plugins are found via GitHub — and the community can contribute the slicer-dialect sample corpus ADR-0002 depends on. Sparkle 2 (EdDSA-signed appcast hosted in the repo) provides the native-feeling auto-update flow, which matters because the parser will need updates as slicer dialects evolve. No App Review also means we can ship parser fixes same-day.

## Consequences

- We own the download page, appcast, and signing/notarization pipeline (CI).
- The App Store channel can still be added later; the sandboxed-viewer architecture doesn't preclude it.
