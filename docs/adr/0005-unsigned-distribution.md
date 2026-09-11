# Unsigned distribution

ADR-0003 assumed Developer ID–signed, notarized builds, but the owner has no
Apple Developer Program membership, and the $99/yr isn't justified before the
project has users. We ship ad-hoc-signed (`CODE_SIGN_IDENTITY=-`), unnotarized
DMGs instead; Sparkle's EdDSA signature becomes the sole trust root for
updates, a configuration Sparkle 2 explicitly supports for ad-hoc-signed apps.
The README documents the one-time Gatekeeper "Open Anyway" flow a first
install now requires.

## Consequences

- First install has more friction: on macOS 15+ the right-click→Open
  Gatekeeper bypass no longer works for unsigned/unnotarized apps, so users
  hit a "Not Opened" dialog and must go through System Settings → Privacy &
  Security → "Open Anyway". Sparkle-installed updates don't re-trigger
  Gatekeeper, so this only affects the very first browser-downloaded install.
- The hardened runtime has to stay off while we ad-hoc sign
  (`ENABLE_HARDENED_RUNTIME: NO` in project.yml). It enables library
  validation, which requires every library a process loads to carry the same
  Team ID as the process, and an ad-hoc signature has no Team ID — so dyld
  kills the app at launch as soon as it reaches the embedded
  Sparkle.framework ("mapping process and mapped file (non-platform) have
  different Team IDs"). 0.1.1 and 0.2.0 shipped that way and could not be
  opened at all; `codesign --verify` passes on such a bundle, so
  `scripts/release.sh` checks the CodeDirectory flags directly
  (`assert_frameworks_loadable`). Turning it back on is part of the Developer
  ID upgrade, not a separate decision: notarization requires the hardened
  runtime, and a real Team ID is what makes it survivable.
- The signed pipeline isn't gone, just dormant: `scripts/release.sh`'s
  no-flag default is still the Developer ID + notarization path, and
  `docs/RELEASING.md` keeps the upgrade instructions. Joining the Developer
  Program later means adding back four secrets and reverting one workflow
  step — no re-keying, because the Sparkle key is unchanged and shipped apps
  keep updating straight through the transition.
