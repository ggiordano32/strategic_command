extends SceneTree
## The 3D art ships in the main download (game/oblique_pack.gd, docs/design/distribution.md "One download"): there is no
## second pack to fetch and no Top fallback. Checks that the sheets and kit resources are present in the project, that
## `ensure` is trivially satisfied (no node, nothing to wait for), that `wanted` is never true, that the export keeps them
## (the Web preset does not exclude them, no "Web oblique pack" preset, the export script writes no second pack) and that a
## battle never sets `BoardView.web_top`:
##   godot --headless --script res://tests/oblique_pack_test.gd
## Exits 0 on success, 1 on failure.

const ObliquePack := preload("res://game/oblique_pack.gd")
const BoardView := preload("res://game/board_view.gd")

var fails := 0
var checks := 0


func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _init() -> void:
	_check(ObliquePack.sheets_present(), "the oblique sheets' manifests are in the project")
	for f in ["res://assets/battlekit_ob/kit3d.res", "res://assets/battlekit_ob/kit3d_albedo.png",
			"res://assets/sprites_ob/atlas_mask.png", "res://assets/sprites_ob/atlas_shade.png",
			"res://assets/battlekit_ob/atlas_albedo.png", "res://assets/battlekit_ob/atlas_nrm.png", "res://assets/battlekit_ob/atlas_low.png"]:
		_check(FileAccess.file_exists(f) or ResourceLoader.exists(f), "present: " + f)
	_check(not ObliquePack.wanted(), "wanted() is never true (nothing to fetch)")
	_check(ObliquePack.ensure() == null and ObliquePack.ensure(true, true) == null, "ensure() returns null (nothing to wait for)")
	_check(root.get_node_or_null("ObliquePack") == null, "ensure() adds no node")
	_check(not BoardView.web_top, "web_top is false")
	# the export: one download
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(cfg != "", "export_presets.cfg readable")
	_check(not cfg.contains("Web oblique pack"), "no second pack preset")
	var web := cfg.substr(0, cfg.find("[preset.1]"))
	_check(web.contains('name="Web"'), "the Web preset is first")
	_check(not web.contains("sprites_ob") and not web.contains("battlekit_ob"), "the Web preset leaves the oblique sheets and kit in the pack")
	var sh := FileAccess.get_file_as_string("res://tools/export_web.sh")
	_check(sh != "" and not sh.contains("--export-pack"), "export_web.sh writes no second pack")
	print("oblique pack test: %d checks, %d failed" % [checks, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
