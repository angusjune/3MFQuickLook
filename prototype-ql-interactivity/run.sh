#!/bin/zsh
# PROTOTYPE runner — generate, build, register, open. See NOTES.md
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Generating Xcode project"
xcodegen generate --quiet

echo "==> Building (ad-hoc signed)"
xcodebuild -project ProtoQL.xcodeproj -scheme ProtoQL -configuration Debug \
  -derivedDataPath build build 2>&1 | tail -5

APP="build/Build/Products/Debug/ProtoQL.app"

echo "==> Launching app once to register extensions"
open "$APP"
sleep 2

echo "==> Registered QL extensions matching 'protoql':"
pluginkit -m 2>/dev/null | grep -i protoql || echo "   (none found yet — may take a moment)"

echo "==> Resetting Quick Look"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "==> Creating and revealing sample file"
echo "prototype payload" > Sample.qlproto
open -R "$PWD/Sample.qlproto"

echo ""
echo "NOW: press Space on Sample.qlproto in Finder."
echo " - Boxes rotate on drag  -> preview interactivity WORKS"
echo " - Counters increment    -> events reach the extension"
echo " - Finder icon = 3 boxes -> RealityRenderer works in thumbnail appex (red X = failed)"
echo ""
echo "Thumbnail probe via qlmanage (writes Sample.qlproto.png here):"
echo "  qlmanage -t -s 512 -o . Sample.qlproto"
