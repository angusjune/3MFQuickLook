#!/bin/bash
# Import the Developer ID certificate into a throwaway CI keychain.
#
#   scripts/ci_keychain.sh setup     # requires DEVELOPER_ID_CERT_P12 (+ password)
#   scripts/ci_keychain.sh cleanup   # always safe; run in an `if: always()` step
#
# Environment (setup):
#   DEVELOPER_ID_CERT_P12       base64-encoded .p12 with the "Developer ID
#                               Application" certificate and private key
#   DEVELOPER_ID_CERT_PASSWORD  password protecting the .p12
#
# The keychain lives in $RUNNER_TEMP with a random single-use password, is
# added to the user search list so codesign/xcodebuild find the identity, and
# is deleted again by `cleanup`. See docs/RELEASING.md for how to produce the
# secrets.
set -euo pipefail

KEYCHAIN_PATH="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/release-signing.keychain-db"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

setup() {
    [[ -n "${DEVELOPER_ID_CERT_P12:-}" ]] || die "DEVELOPER_ID_CERT_P12 is not set (see docs/RELEASING.md)"
    [[ -n "${DEVELOPER_ID_CERT_PASSWORD:-}" ]] || die "DEVELOPER_ID_CERT_PASSWORD is not set (see docs/RELEASING.md)"

    local keychain_password cert_dir cert_path
    keychain_password="$(uuidgen)"
    cert_dir="$(mktemp -d)"
    cert_path="$cert_dir/developer-id.p12"
    trap 'rm -rf "$cert_dir"' EXIT

    printf '%s' "$DEVELOPER_ID_CERT_P12" | base64 --decode > "$cert_path" \
        || die "DEVELOPER_ID_CERT_P12 is not valid base64"

    log "Creating keychain at $KEYCHAIN_PATH"
    security create-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"

    log "Importing Developer ID certificate"
    security import "$cert_path" -k "$KEYCHAIN_PATH" \
        -P "$DEVELOPER_ID_CERT_PASSWORD" -f pkcs12 \
        -T /usr/bin/codesign -T /usr/bin/security
    # Allow Apple's signing tools to use the key without a UI prompt.
    security set-key-partition-list -S "apple-tool:,apple:,codesign:" \
        -s -k "$keychain_password" "$KEYCHAIN_PATH" > /dev/null
    security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

    log "Signing identities now available:"
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
        | grep "Developer ID Application" \
        || die "the .p12 contains no 'Developer ID Application' identity"
}

cleanup() {
    if [[ -f "$KEYCHAIN_PATH" ]]; then
        log "Deleting keychain $KEYCHAIN_PATH"
        security delete-keychain "$KEYCHAIN_PATH"
    fi
    security list-keychains -d user -s login.keychain-db
}

case "${1:-}" in
    setup) setup ;;
    cleanup) cleanup ;;
    *) die "usage: $0 setup|cleanup" ;;
esac
