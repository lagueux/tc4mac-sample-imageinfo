#!/bin/bash
# Builds the plugin and assembles ImageInfo.tcplugin — the bundle you install with
# Configuration ▸ Plugins ▸ Install… in tc4mac.
#
#   ./make-plugin.sh            release build (what you would ship)
#   ./make-plugin.sh debug      faster build, for iterating
set -euo pipefail
CONFIG="${1:-release}"
BUNDLE="ImageInfo.tcplugin"

swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/ImageInfoPlugin"
[ -x "$BINARY" ] || { echo "no executable at $BINARY"; exit 1; }

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BINARY" "$BUNDLE/Contents/MacOS/ImageInfo"

# The manifest is read before anything runs: it says what the plugin is and
# what it claims, so the host can refuse it without executing a line of it.
cat > "$BUNDLE/manifest.json" <<JSON
{
  "id": "com.tc4mac.sample.imageinfo",
  "displayName": "Image properties (sample)",
  "version": "1.0.0",
  "minHostVersion": "0.1.0",
  "types": ["content"],
  "fields": ["img.dimensions", "img.orientation", "img.megapixels"]
}
JSON

echo "built $BUNDLE"
echo "install it with Configuration ▸ Plugins ▸ Install…, then switch it on."
