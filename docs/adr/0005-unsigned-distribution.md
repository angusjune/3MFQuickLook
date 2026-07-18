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
- The signed pipeline isn't gone, just dormant: `scripts/release.sh`'s
  no-flag default is still the Developer ID + notarization path, and
  `docs/RELEASING.md` keeps the upgrade instructions. Joining the Developer
  Program later means adding back four secrets and reverting one workflow
  step — no re-keying, because the Sparkle key is unchanged and shipped apps
  keep updating straight through the transition.
