#!/usr/bin/env python3
"""Update the pinned version and SHA-256 in the 3MF QuickLook Homebrew cask.

The release workflow calls this after building the exact DMG attached to the
GitHub Release. The updater is intentionally strict: it only accepts X.Y.Z
versions and requires exactly one canonical `version` and `sha256` stanza, so
a future cask layout change fails the release instead of silently editing the
wrong text.
"""

import argparse
import hashlib
import re
from pathlib import Path

VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
CASK_VERSION_RE = re.compile(r'^  version "[^"]+"$', re.MULTILINE)
CASK_SHA256_RE = re.compile(r'^  sha256 "[0-9a-f]{64}"$', re.MULTILINE)


def artifact_sha256(path: Path) -> str:
    """Return the lowercase SHA-256 digest of an artifact."""
    if not path.is_file():
        raise ValueError(f"artifact does not exist or is not a file: {path}")

    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_exactly_once(
    content: str, pattern: re.Pattern[str], replacement: str, stanza: str
) -> str:
    """Replace one canonical cask stanza, rejecting missing or duplicate lines."""
    updated, count = pattern.subn(replacement, content)
    if count != 1:
        raise ValueError(
            f"expected exactly one canonical {stanza} stanza, found {count}"
        )
    return updated


def update_cask(cask: Path, version: str, artifact: Path) -> bool:
    """Update the cask and return True when its contents changed."""
    if not VERSION_RE.fullmatch(version):
        raise ValueError(f"version must use X.Y.Z numeric form, got: {version}")
    if not cask.is_file():
        raise ValueError(f"cask does not exist or is not a file: {cask}")

    checksum = artifact_sha256(artifact)
    original = cask.read_text(encoding="utf-8")
    updated = replace_exactly_once(
        original, CASK_VERSION_RE, f'  version "{version}"', "version"
    )
    updated = replace_exactly_once(
        updated, CASK_SHA256_RE, f'  sha256 "{checksum}"', "sha256"
    )

    if updated == original:
        print(f"{cask} is already current at {version} ({checksum})")
        return False

    cask.write_text(updated, encoding="utf-8")
    print(f"updated {cask} to {version} ({checksum})")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Update a Homebrew cask from a built release artifact."
    )
    parser.add_argument("--cask", required=True, type=Path, help="cask file to update")
    parser.add_argument("--version", required=True, help="marketing version (X.Y.Z)")
    parser.add_argument(
        "--artifact", required=True, type=Path, help="release artifact to checksum"
    )
    args = parser.parse_args()

    try:
        update_cask(args.cask, args.version, args.artifact)
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
