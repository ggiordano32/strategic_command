#!/bin/sh
# Export the Web build (single-threaded, for iOS Safari) to build/web.
# Writes build_stamp.txt (export time + content hashes of the sources, of
# sim/ alone, and of the game rules campaign/ + sim/) into the pack so
# telemetry can tell builds apart, and a copy next to the export so the
# server can tell clients a newer build is deployed. The rules hash is what
# online campaigns compare between devices (game/net/net.gd computes the
# same from the sources when there is no stamp).
set -e
cd "$(dirname "$0")/.."
export LC_ALL=C
mkdir -p build/web
touch build/.gdignore  # keep Godot from importing the exported files
src=$(cat project.godot sim/*.gd campaign/*.gd campaign/data/*.gd game/*.gd game/campaign/*.gd game/net/*.gd game/*.gdshader game/*.gdshaderinc | sha1sum | cut -c1-8)
simh=$(cat sim/*.gd | sha1sum | cut -c1-8)
rules=$(ls campaign/*.gd campaign/data/*.gd sim/*.gd | sort | xargs cat | sha1sum | cut -c1-8)
# ob: content hash of the oblique sheets and the 3D kit (kept in the stamp for telemetry; they ride in index.pck since 2026-11-09).
ob=$(cat assets/sprites_ob/manifest.json assets/battlekit_ob/manifest.json assets/sprites_ob/*.png assets/battlekit_ob/*.png assets/battlekit_ob/*.res | sha1sum | cut -c1-8)
echo "$(date -u +%Y%m%dT%H%M%SZ) src:$src sim:$simh rules:$rules ob:$ob" > build_stamp.txt
godot --headless --export-release "Web" build/web/index.html
# Install support: manifest + icons (no service worker, so never a stale build).
godot --headless --script res://tools/make_web_icons.gd
cp build_stamp.txt build/web/build_stamp.txt
rm -f build/web/oblique.pck   # (the second pack of earlier builds: one download now)
echo "Pack: index.pck $(wc -c < build/web/index.pck) bytes"
echo "Exported to build/web ($(cat build_stamp.txt)). Serve with: tools/run_server.sh (or python3 tools/serve_web.py)"
