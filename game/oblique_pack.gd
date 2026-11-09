extends RefCounted
## The oblique sheets and the 3D kit meshes (assets/sprites_ob, assets/battlekit_ob) are part of the main download on the
## web since 2026-11-09 (stage A of dropping the flat battle views, docs/design/distribution.md "One download"): the web
## export no longer leaves them out and there is no second pack, no progress bar and no Top fallback. This file stays as
## the one place that says whether the sheets are present; `ensure` is trivially satisfied (returns null: nothing to wait
## for). View only: nothing here touches the sim.

const PROBE_FILES: Array[String] = ["res://assets/sprites_ob/manifest.json", "res://assets/battlekit_ob/manifest.json"]


static func sheets_present() -> bool:
	for f in PROBE_FILES:
		if not FileAccess.file_exists(f):
			return false
	return true


## Always false: the sheets ride in the main pack, nothing is fetched.
static func wanted() -> bool:
	return false


## Kept for the callers that asked for the pack's download (the boot, the Options row, the battle's start): nothing runs.
static func ensure(_user := false, _battle := false) -> Node:
	return null
