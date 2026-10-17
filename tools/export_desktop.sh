#!/bin/sh
# Export the desktop builds (Windows, Linux, macOS) to build/desktop/<platform>/,
# each with the game server (scserver, cross-built from server/) beside the
# game so "Host a server" works, a build_stamp.txt, and zip them as
#   build/desktop/strategic-command-<platform>-<stamp>.zip
# Needs the Godot 4.7.2 export templates (windows, linux, macos) installed and
# `go` (PATH or ~/.local/go). Never touches build/web. No code signing: on
# Windows SmartScreen and on macOS Gatekeeper warn about an unsigned download
# (macOS: right-click > Open once).
#   tools/export_desktop.sh [windows] [linux] [macos]   (default: all three)
set -e
cd "$(dirname "$0")/.."
export LC_ALL=C
platforms=${*:-windows linux macos}
if ! command -v go >/dev/null 2>&1; then
	PATH="$HOME/.local/go/bin:$PATH"
fi
out=build/desktop
mkdir -p "$out"
touch build/.gdignore  # keep Godot from importing the exported files

# Same stamp as tools/export_web.sh.
src=$(cat project.godot sim/*.gd campaign/*.gd campaign/data/*.gd game/*.gd game/campaign/*.gd game/net/*.gd game/*.gdshader game/*.gdshaderinc | sha1sum | cut -c1-8)
simh=$(cat sim/*.gd | sha1sum | cut -c1-8)
rules=$(ls campaign/*.gd campaign/data/*.gd sim/*.gd | sort | xargs cat | sha1sum | cut -c1-8)
stamp_line="$(date -u +%Y%m%dT%H%M%SZ) src:$src sim:$simh rules:$rules"
echo "$stamp_line" > build_stamp.txt
stamp=${stamp_line%% *}

cross() { # goos goarch outfile
	(cd server && GOOS=$1 GOARCH=$2 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "../$3" ./cmd/scserver)
}

for p in $platforms; do
	dir=$out/$p
	rm -rf "$dir"
	mkdir -p "$dir"
	case $p in
	windows)
		godot --headless --quiet --export-release "Windows Desktop" "$dir/StrategicCommand.exe"
		cross windows amd64 "$dir/scserver.exe"
		;;
	linux)
		godot --headless --quiet --export-release "Linux" "$dir/StrategicCommand.x86_64"
		cross linux amd64 "$dir/scserver"
		chmod +x "$dir/StrategicCommand.x86_64" "$dir/scserver"
		;;
	macos)
		godot --headless --quiet --export-release "macOS" "$dir/StrategicCommand.zip"
		# The server goes inside the app, next to the game's executable
		# (one binary per CPU; the game picks by its own architecture).
		(cd "$dir" && unzip -q StrategicCommand.zip && rm StrategicCommand.zip)
		app=$(ls -d "$dir"/*.app | head -n 1)
		cross darwin arm64 "$app/Contents/MacOS/scserver-arm64"
		cross darwin amd64 "$app/Contents/MacOS/scserver-amd64"
		chmod +x "$app/Contents/MacOS/"*
		;;
	*)
		echo "unknown platform $p" >&2
		exit 1
		;;
	esac
	cp build_stamp.txt "$dir/build_stamp.txt"
	zip_path="$PWD/$out/strategic-command-$p-$stamp.zip"
	rm -f "$zip_path"
	(cd "$dir" && zip -q -r -y "$zip_path" .)
	echo "$p: $zip_path ($(du -h "$zip_path" | cut -f1))"
done
