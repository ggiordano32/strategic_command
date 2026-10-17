#!/bin/sh
# Push the builds to itch.io with butler (https://itch.io/docs/butler/).
# Not run by anything automatic: you run it, after tools/export_web.sh and
# tools/export_desktop.sh. Needs `butler` on PATH and BUTLER_API_KEY (itch.io
# > Settings > API keys), or `butler login` done once.
#   ITCH_TARGET=user/game tools/itch_push.sh [web] [windows] [linux] [mac]
# Channels: web (HTML5, build/web), windows, linux, mac (build/desktop/<p>).
# The web channel is the game page itch hosts; set it to "This file will be
# played in the browser" on the itch page after the first push.
set -e
cd "$(dirname "$0")/.."
target=${ITCH_TARGET:-ggior32/strategic-command}
channels=${*:-web windows linux mac}
if ! command -v butler >/dev/null 2>&1; then
	echo "butler is not installed: https://itch.io/docs/butler/installing.html" >&2
	exit 1
fi
if [ -z "$BUTLER_API_KEY" ] && [ ! -f "$HOME/.config/itch/butler_creds" ]; then
	echo "Set BUTLER_API_KEY (or run: butler login)." >&2
	exit 1
fi
version=$(cut -d' ' -f1 build_stamp.txt 2>/dev/null || date -u +%Y%m%dT%H%M%SZ)
for c in $channels; do
	case $c in
	web) dir=build/web ;;
	windows) dir=build/desktop/windows ;;
	linux) dir=build/desktop/linux ;;
	mac) dir=build/desktop/macos ;;
	*) echo "unknown channel $c" >&2; exit 1 ;;
	esac
	if [ ! -d "$dir" ]; then
		echo "$dir is missing: export first" >&2
		exit 1
	fi
	echo "Pushing $dir to $target:$c (version $version)"
	butler push "$dir" "$target:$c" --userversion "$version"
done
