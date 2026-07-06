#!/bin/bash
# Build, Developer ID-sign, notarize, staple, and package 3MF QuickLook as a
# distributable DMG (ADR-0003). Run by .github/workflows/release.yml on every
# version tag; runnable locally with --dry-run and no credentials.
#
#   scripts/release.sh --version 1.0.0 [--build-number N] [--dry-run] [--output-dir DIR]
#
#   --version        Marketing version = the tag without the leading "v".
#   --build-number   CFBundleVersion; what Sparkle compares. Defaults to the
#                    commit count (monotonically increasing across releases —
#                    CI checks out with full history for this).
#   --dry-run        Build Release and produce an UNSIGNED DMG. Skips
#                    codesign/notarytool/stapler/spctl entirely; needs no
#                    credentials. For pipeline verification only.
#   --output-dir     Working/output directory (default: <repo>/dist).
#
# Environment (real mode only; see docs/RELEASING.md):
#   NOTARY_KEY_ID          App Store Connect API key ID
#   NOTARY_ISSUER_ID       App Store Connect issuer UUID
#   NOTARY_KEY_FILE        path to the API key .p8 file
#   DEVELOPER_ID_IDENTITY  optional; defaults to the first "Developer ID
#                          Application" identity in the keychain search list
#   APPLE_TEAM_ID          optional; defaults to the team ID parsed from the
#                          signing identity name
#
# Outputs (in --output-dir):
#   3MFQuickLook-<version>.dmg   the release artifact
#   release-info.env             VERSION/BUILD_NUMBER/APP_PATH/DMG_PATH for CI
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="ThreeMFQuickLook"
APP_NAME="3MF QuickLook"
ARTIFACT_BASENAME="3MFQuickLook"

VERSION=""
BUILD_NUMBER=""
OUTPUT_DIR="$REPO_ROOT/dist"
DRY_RUN=0

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    # Print the header comment block (everything between the shebang and the
    # first non-comment line) as the help text.
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --build-number) BUILD_NUMBER="${2:?--build-number needs a value}"; shift 2 ;;
        --output-dir) OUTPUT_DIR="${2:?--output-dir needs a value}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ -n "$VERSION" ]] || die "--version is required (the tag without the leading 'v')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "--version must look like 1.2.3 (got: $VERSION)"
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(git -C "$REPO_ROOT" rev-list --count HEAD)"
fi
command -v xcodegen > /dev/null || die "xcodegen is required (brew install xcodegen)"

notary_args=()
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
if [[ "$DRY_RUN" -eq 0 ]]; then
    [[ -n "${NOTARY_KEY_ID:-}" ]] || die "NOTARY_KEY_ID is not set (see docs/RELEASING.md)"
    [[ -n "${NOTARY_ISSUER_ID:-}" ]] || die "NOTARY_ISSUER_ID is not set (see docs/RELEASING.md)"
    [[ -f "${NOTARY_KEY_FILE:-}" ]] || die "NOTARY_KEY_FILE does not point at a .p8 file (see docs/RELEASING.md)"
    notary_args=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

    if [[ -z "$DEVELOPER_ID_IDENTITY" ]]; then
        identity_line="$(security find-identity -v -p codesigning | grep -m1 'Developer ID Application')" \
            || die "no 'Developer ID Application' identity in the keychain (run scripts/ci_keychain.sh setup)"
        DEVELOPER_ID_IDENTITY="$(sed -E 's/^[^"]*"(.+)"[^"]*$/\1/' <<< "$identity_line")"
    fi
    if [[ -z "$APPLE_TEAM_ID" ]]; then
        [[ "$DEVELOPER_ID_IDENTITY" =~ \(([A-Z0-9]+)\)$ ]] \
            || die "cannot parse a team ID from '$DEVELOPER_ID_IDENTITY'; set APPLE_TEAM_ID"
        APPLE_TEAM_ID="${BASH_REMATCH[1]}"
    fi
    log "Signing as: $DEVELOPER_ID_IDENTITY (team $APPLE_TEAM_ID)"
fi

# notarytool exits 0 for some non-Accepted terminal states, so check the
# status field explicitly and dump the notary log on failure.
notarize_file() {
    local file="$1" result submission_id status
    log "Notarizing $(basename "$file") (this waits on Apple)"
    result="$(xcrun notarytool submit "$file" "${notary_args[@]}" --wait --output-format json)"
    submission_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<< "$result")"
    status="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<< "$result")"
    if [[ "$status" != "Accepted" ]]; then
        warn "notarization status: ${status:-unknown} (submission: ${submission_id:-unknown})"
        [[ -n "$submission_id" ]] && xcrun notarytool log "$submission_id" "${notary_args[@]}" >&2 || true
        die "notarization was not accepted"
    fi
    log "Notarization accepted (submission: $submission_id)"
}

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

log "Generating Xcode project"
(cd "$REPO_ROOT" && xcodegen generate)

version_settings=(
    "MARKETING_VERSION=$VERSION"
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
)

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] Building Release (ad-hoc signed, no notarization)"
    xcodebuild -project "$REPO_ROOT/ThreeMFQuickLook.xcodeproj" \
        -scheme "$SCHEME" -configuration Release \
        -derivedDataPath "$OUTPUT_DIR/DerivedData" \
        "${version_settings[@]}" build | tail -5
    APP_PATH="$OUTPUT_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
else
    log "Archiving (Developer ID, hardened runtime, secure timestamp)"
    xcodebuild -project "$REPO_ROOT/ThreeMFQuickLook.xcodeproj" \
        -scheme "$SCHEME" -configuration Release \
        archive -archivePath "$OUTPUT_DIR/$ARTIFACT_BASENAME.xcarchive" \
        "${version_settings[@]}" \
        CODE_SIGN_STYLE=Manual \
        "CODE_SIGN_IDENTITY=$DEVELOPER_ID_IDENTITY" \
        "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" \
        "OTHER_CODE_SIGN_FLAGS=--timestamp" | tail -5

    log "Exporting with the developer-id method"
    cat > "$OUTPUT_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$DEVELOPER_ID_IDENTITY</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive \
        -archivePath "$OUTPUT_DIR/$ARTIFACT_BASENAME.xcarchive" \
        -exportOptionsPlist "$OUTPUT_DIR/ExportOptions.plist" \
        -exportPath "$OUTPUT_DIR/export" | tail -5
    APP_PATH="$OUTPUT_DIR/export/$APP_NAME.app"
fi

[[ -d "$APP_PATH" ]] || die "expected app at $APP_PATH"

log "Sanity-checking the bundle"
for appex in PreviewExt ThumbExt; do
    [[ -d "$APP_PATH/Contents/PlugIns/$appex.appex" ]] \
        || die "missing Quick Look extension: $appex.appex"
done
[[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] \
    || die "Sparkle.framework is not embedded"
ed_key="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP_PATH/Contents/Info.plist" 2> /dev/null || true)"
if [[ -z "$ed_key" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "SUPublicEDKey is empty; fine for a dry run, fatal for a release (docs/RELEASING.md)"
    else
        die "SUPublicEDKey is empty in project.yml — Sparkle could not verify updates. Generate the EdDSA keypair first (docs/RELEASING.md)."
    fi
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
    log "Verifying code signature"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"

    ZIP_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME-$VERSION.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    notarize_file "$ZIP_PATH"
    log "Stapling the app"
    xcrun stapler staple "$APP_PATH"
    log "Gatekeeper assessment (app)"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

log "Building the DMG"
STAGING_DIR="$OUTPUT_DIR/dmg-root"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
DMG_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [[ "$DRY_RUN" -eq 0 ]]; then
    log "Signing, notarizing, and stapling the DMG"
    codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG_PATH"
    notarize_file "$DMG_PATH"
    xcrun stapler staple "$DMG_PATH"
    log "Gatekeeper assessment (DMG)"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi

cat > "$OUTPUT_DIR/release-info.env" <<ENV
VERSION=$VERSION
BUILD_NUMBER=$BUILD_NUMBER
APP_PATH=$APP_PATH
DMG_PATH=$DMG_PATH
ENV

log "Done"
if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  DMG (UNSIGNED, dry run): %s\n' "$DMG_PATH"
else
    printf '  DMG (signed, notarized, stapled): %s\n' "$DMG_PATH"
fi
printf '  version %s, build %s\n' "$VERSION" "$BUILD_NUMBER"
