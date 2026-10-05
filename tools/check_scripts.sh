#!/bin/sh
# Parse every script with all default-on GDScript warnings raised to errors.
# Writes a temporary override.cfg (removed on exit). Exit 1 on any problem.
set -e
cd "$(dirname "$0")/.."
trap 'rm -f override.cfg' EXIT
{
	echo "[debug]"
	godot --headless --script res://tools/list_warnings.gd 2>/dev/null | grep '^gdscript/warnings/' | sed 's/=.*/=2/'
} > override.cfg
fail=0
for f in sim/*.gd campaign/*.gd game/*.gd game/campaign/*.gd tests/*.gd tools/*.gd; do
	out=$(godot --headless --check-only --script "res://$f" 2>&1 | grep -v '^Godot Engine' | grep -v '^$' || true)
	if [ -n "$out" ]; then
		echo "== $f"
		echo "$out"
		fail=1
	fi
done
[ $fail -eq 0 ] && echo "All scripts clean (warnings as errors)."
exit $fail
