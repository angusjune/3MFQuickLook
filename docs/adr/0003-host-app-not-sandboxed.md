# Host App runs without the app sandbox

Issue #11 requires onboarding to reflect the actual enablement of the two
Quick Look extensions, and the only public way to read those elections is
PluginKit (`pluginkit -m`). Empirically (macOS 15/26), pkd refuses discovery
to sandboxed callers — `pluginkit -m -i <id>` run from an app-sandboxed
process fails with `match: unauthorized discovery flag (PKDiscoverAll)`
regardless of the caller's bundle identity, and the public
`AppExtensionIdentity.matching` API only surfaces extension points the caller
itself declares, so it cannot see `com.apple.quicklook.*`. The Host App
therefore ships unsandboxed so its status probe stays truthful; both Quick
Look extensions keep their own sandboxes, and the app remains a plain viewer
with no network or privileged entitlements.

## Considered options

- **Keep the sandbox, degrade detection** — probe thumbnails functionally via
  `QLThumbnailGenerator` and give up on the Preview Extension's state.
  Rejected: onboarding could then never verify the preview toggle, so it
  either nags forever or lies; both violate the issue's acceptance criteria.
- **Keep the sandbox, add a helper** — a non-sandboxed XPC helper just to ask
  pkd. Rejected: same App Store ineligibility as unsandboxing, plus a whole
  helper to maintain.

## Consequences

- The Host App is not Mac App Store-eligible as-is. If MAS distribution is
  ever wanted, re-enable the sandbox in project.yml and accept degraded
  detection (this decision documents exactly what breaks: the probe reports
  `.unknown` and onboarding shows on every launch).
