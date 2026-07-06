# Releasing 3MF QuickLook

Per [ADR-0003](adr/0003-direct-distribution-oss-sparkle.md), releases are
Developer ID–signed, notarized, stapled disk images on GitHub Releases, and
installed apps auto-update via Sparkle 2 from an EdDSA-signed appcast
(`appcast.xml` on `main`).

Pushing a version tag does everything:

```sh
git tag v1.0.0
git push origin v1.0.0
```

[`release.yml`](../.github/workflows/release.yml) then builds and archives the
app ([`scripts/release.sh`](../scripts/release.sh)), signs it with the
Developer ID certificate, notarizes and staples both the app and the DMG,
runs Gatekeeper assessments, attaches the DMG to a GitHub Release, EdDSA-signs
the DMG with Sparkle's `sign_update`, and commits the new appcast entry to
`main` ([`scripts/update_appcast.py`](../scripts/update_appcast.py)).

The marketing version is the tag without the leading `v`; the build number
(`CFBundleVersion`, what Sparkle compares) is the commit count, so it
increases monotonically as long as tags are cut from `main`.

## One-time setup

### 1. Developer ID certificate

You need a **Developer ID Application** certificate in your Apple Developer
account (Certificates → create → "Developer ID Application"; generate it in
Keychain Access via a certificate signing request so the private key lands in
your keychain).

Export it: Keychain Access → My Certificates → right-click the certificate →
Export as `.p12` with a password. Then:

```sh
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_CERT_P12
gh secret set DEVELOPER_ID_CERT_PASSWORD   # paste the .p12 password
```

### 2. Notarization API key

App Store Connect → Users and Access → Integrations → App Store Connect API →
Team Keys → generate a key with the **Developer** role. Note the Key ID and
the Issuer ID shown on that page, and download the `.p8` file (downloadable
only once).

```sh
gh secret set NOTARY_KEY_ID                # the key ID, e.g. ABC123DEF4
gh secret set NOTARY_ISSUER_ID             # the issuer UUID
gh secret set NOTARY_PRIVATE_KEY < AuthKey_ABC123DEF4.p8
```

### 3. Sparkle EdDSA update-signing key

Download the [Sparkle distribution](https://github.com/sparkle-project/Sparkle/releases)
(the pipeline pins 2.9.4) and generate the keypair — it is created in your
login keychain, which is its long-term home; guard it well, updates cannot be
signed without it:

```sh
./bin/generate_keys                        # prints the public key
./bin/generate_keys -x sparkle-private.key # exports the private key for CI
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private.key
rm sparkle-private.key
```

Paste the printed public key into `SUPublicEDKey` in `project.yml` and commit.
`scripts/release.sh` refuses to cut a release while `SUPublicEDKey` is empty,
because shipped apps could never verify an update.

### Secrets reference

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 of the Developer ID Application `.p12` (cert + private key) |
| `DEVELOPER_ID_CERT_PASSWORD` | password protecting the `.p12` |
| `NOTARY_KEY_ID` | App Store Connect API key ID |
| `NOTARY_ISSUER_ID` | App Store Connect issuer UUID |
| `NOTARY_PRIVATE_KEY` | contents of the App Store Connect `.p8` API key |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (`generate_keys -x`) |

The workflow fails fast, before building, if any secret is missing.

## Before the repository goes public

- [ ] Add a LICENSE (ADR-0003 says permissive; the exact license is an owner
      decision this pipeline doesn't make).
- [ ] Set all six secrets and `SUPublicEDKey` (above).

## Release verification checklist

CI verifies signatures (`codesign --verify --deep --strict`), notarization
status, stapling, and Gatekeeper assessments (`spctl`) for both the app and
the DMG. The following need a human and real artifacts:

1. **Gatekeeper on a clean account** — on a machine (or fresh user account)
   that never built the project: download the DMG *in a browser* (so it gets
   the quarantine flag), open it, drag the app to Applications, launch it.
   No "unidentified developer" dialog should appear.
2. **Extensions in the notarized build** — with the release app in
   `/Applications` and launched once: Finder shows thumbnails for `.3mf`
   files, and Space opens the interactive preview. (The sandboxed extensions
   run identically under Developer ID signing, but smoke-test the actual
   artifact.)
3. **Sparkle end-to-end** (once, with the first two real releases) — install
   release N, then tag release N+1. After the workflow finishes, open the
   installed app and use "3MF QuickLook → Check for Updates…": it should
   find, download, verify, and install N+1 through Sparkle's standard flow.

## Odds and ends

- **Re-running a failed release** is safe: `update_appcast.py` refuses
  duplicate build numbers, `gh release create` fails if the release exists
  (delete the partial release first: `gh release delete vX.Y.Z`).
- **Local dry run** of the packaging pipeline (no credentials, no signing):
  `scripts/release.sh --dry-run --version 0.0.1` produces an unsigned DMG in
  `dist/`.
- **Release notes** are auto-generated from PRs/commits by
  `gh release create --generate-notes`; edit the release afterwards if wanted.
  The appcast links to the release page rather than embedding notes.
- **Rotating the Sparkle key** effectively strands shipped apps (they verify
  updates against the old public key) — don't, unless compromised, and then
  read Sparkle's key-rotation guidance first.
