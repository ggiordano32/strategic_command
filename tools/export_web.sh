#!/bin/sh
# Export the Web build (single-threaded, for iOS Safari) to build/web.
# Writes build_stamp.txt (export time + content hashes of the sources and of
# sim/ alone) into the pack so telemetry can tell builds apart.
set -e
cd "$(dirname "$0")/.."
mkdir -p build/web
touch build/.gdignore  # keep Godot from importing the exported files
src=$(cat project.godot sim/*.gd campaign/*.gd game/*.gd game/campaign/*.gd game/*.gdshader | sha1sum | cut -c1-8)
simh=$(cat sim/*.gd | sha1sum | cut -c1-8)
echo "$(date -u +%Y%m%dT%H%M%SZ) src:$src sim:$simh" > build_stamp.txt
godot --headless --export-release "Web" build/web/index.html
# Install support: manifest + icons (no service worker, so never a stale build).
godot --headless --script res://tools/make_web_icons.gd
echo "Exported to build/web ($(cat build_stamp.txt)). Serve with: python3 tools/serve_web.py"
