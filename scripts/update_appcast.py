#!/usr/bin/env python3
"""Insert one release item into the Sparkle appcast (appcast.xml).

Called by .github/workflows/release.yml after a release DMG is built and
EdDSA-signed. The new item is inserted newest-first; the enclosure attributes
come verbatim from Sparkle's `sign_update` output, passed unparsed via
--signature-fragment so the workflow never has to pick the fragment apart.

Runs on the stock python3 (stdlib only). Refuses to add a build number that
is already in the feed, so re-running a failed workflow is safe.

Example:
    python3 scripts/update_appcast.py \
        --appcast appcast.xml \
        --version 214 \
        --short-version 1.0.0 \
        --url https://github.com/angusjune/3MFQuickLook/releases/download/v1.0.0/3MFQuickLook-1.0.0.dmg \
        --link https://github.com/angusjune/3MFQuickLook/releases/tag/v1.0.0 \
        --signature-fragment 'sparkle:edSignature="..." length="1234"'
"""

import argparse
import email.utils
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def sparkle(name: str) -> str:
    """Qualified tag/attribute name in the Sparkle namespace."""
    return f"{{{SPARKLE_NS}}}{name}"


def parse_signature_fragment(fragment: str) -> tuple[str, str]:
    """Extract (edSignature, length) from sign_update's output fragment."""
    match = re.search(
        r'sparkle:edSignature="([A-Za-z0-9+/=]+)"\s+length="([0-9]+)"', fragment
    )
    if not match:
        sys.exit(
            "error: --signature-fragment does not look like sign_update output "
            '(expected: sparkle:edSignature="..." length="...")'
        )
    return match.group(1), match.group(2)


def build_item(args: argparse.Namespace, signature: str, length: str) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.title or args.short_version
    ET.SubElement(item, "pubDate").text = args.pub_date or email.utils.formatdate(
        usegmt=True
    )
    if args.link:
        ET.SubElement(item, "link").text = args.link
    ET.SubElement(item, sparkle("version")).text = args.version
    ET.SubElement(item, sparkle("shortVersionString")).text = args.short_version
    ET.SubElement(
        item, sparkle("minimumSystemVersion")
    ).text = args.minimum_system_version
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            "type": "application/octet-stream",
            sparkle("edSignature"): signature,
            "length": length,
        },
    )
    return item


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Insert a release item into a Sparkle appcast."
    )
    parser.add_argument("--appcast", required=True, help="path to appcast.xml")
    parser.add_argument(
        "--version",
        required=True,
        help="build number (CFBundleVersion) — what Sparkle compares",
    )
    parser.add_argument(
        "--short-version", required=True, help="marketing version (X.Y.Z)"
    )
    parser.add_argument("--url", required=True, help="enclosure URL of the DMG")
    parser.add_argument(
        "--signature-fragment",
        required=True,
        help="verbatim sign_update output: sparkle:edSignature=\"...\" length=\"...\"",
    )
    parser.add_argument(
        "--minimum-system-version", default="15.0", help="default: %(default)s"
    )
    parser.add_argument("--link", help="release page URL (optional)")
    parser.add_argument("--title", help="item title (default: the short version)")
    parser.add_argument(
        "--pub-date", help="RFC 2822 date (default: now, UTC; for testing)"
    )
    args = parser.parse_args()

    signature, length = parse_signature_fragment(args.signature_fragment)

    ET.register_namespace("sparkle", SPARKLE_NS)
    tree = ET.parse(args.appcast)
    channel = tree.getroot().find("channel")
    if channel is None:
        sys.exit(f"error: {args.appcast} has no <channel> element")

    for existing in channel.findall("item"):
        if existing.findtext(sparkle("version")) == args.version:
            sys.exit(
                f"error: build {args.version} is already in {args.appcast}; "
                "refusing to add a duplicate item"
            )

    item = build_item(args, signature, length)
    existing_items = channel.findall("item")
    if existing_items:
        channel.insert(list(channel).index(existing_items[0]), item)
    else:
        channel.append(item)

    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    with open(args.appcast, "a", encoding="utf-8") as fh:
        fh.write("\n")
    print(
        f"added {args.short_version} (build {args.version}) to {args.appcast}: "
        f"{args.url}"
    )


if __name__ == "__main__":
    main()
