#!/bin/sh
# Parse every script with all default-on GDScript warnings raised to errors.
# Exit 1 on any problem.
#
# The warnings-as-errors settings go into an override.cfg of a scratch copy
# of the project (a temporary directory holding project.godot and symlinks
# to the source directories), never into the real project: an override.cfg
# there would turn warnings into errors for every other Godot process
# running in this checkout meanwhile (tests, other agents).
set -e
cd "$(dirname "$0")/.."
root=$(pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sc_check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cp project.godot "$tmp/"
for d in sim campaign game tests tools data; do
	[ -e "$d" ] && ln -s "$root/$d" "$tmp/$d"
done
{
	echo "[debug]"
	godot --headless --path "$tmp" --script res://tools/list_warnings.gd 2>/dev/null | grep '^gdscript/warnings/' | sed 's/=.*/=2/'
} > "$tmp/override.cfg"
fail=0
for f in sim/*.gd campaign/*.gd game/*.gd game/campaign/*.gd game/net/*.gd game/custom/*.gd tests/*.gd tools/*.gd; do
	out=$(godot --headless --path "$tmp" --check-only --script "res://$f" 2>&1 | grep -v '^Godot Engine' | grep -v '^$' || true)
	if [ -n "$out" ]; then
		echo "== $f"
		echo "$out"
		fail=1
	fi
done
[ $fail -eq 0 ] && echo "All scripts clean (warnings as errors)."
exit $fail
