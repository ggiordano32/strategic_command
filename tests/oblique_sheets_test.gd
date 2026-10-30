extends SceneTree
## Tabletop pass 3, the oblique sheets (art_pipeline.md "Pass 3, the oblique sheets"):
##   godot --headless --script res://tests/oblique_sheets_test.gd
## Loads assets/sprites_ob/manifest.json and assets/kit_ob/manifest.json and checks them against the
## top-down ones: every unit key of assets/sprites/manifest.json is present with the same actions, fps,
## loop and palettes, every action lists the 8 compass directions (or 5 rendered + "mirror": true for SE,
## E, NE), each with the same frame count, frame rects inside the atlas, the anchor inside the frame, one
## size and one anchor per action, the elevation in the header; the generated sprite_atlas_ob.gd table has
## the right length; every top-down kit piece (the minis atlas "p_<piece>__y0", and __y4 where it has
## one) is in the kit manifest with its rect inside the atlas, the anchor inside the rect and a
## footprint that holds the anchor; every piece of the battle kit's own atlases (battlekit_atlas.gd / 2, as
## `<piece>__y0` and `__y4`) in assets/battlekit_ob/manifest.json likewise. The atlas images exist and have the manifest's size.
## Exits 0 on success, 1 on failure.

const SpriteAtlasOb := preload("res://game/sprite_atlas_ob.gd")
const MinisAtlas := preload("res://game/minis_atlas.gd")
const BattleKitAtlas := preload("res://game/battlekit_atlas.gd")
const BattleKitAtlas2 := preload("res://game/battlekit_atlas2.gd")
const DIRS: Array[String] = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]

var fails := 0
var checks := 0


func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails <= 40:
			print("FAIL: ", msg)


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_check(false, "cannot open " + path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		_check(false, "not a JSON object: " + path)
		return {}
	return d


func _rect_ok(r: Array, size: Array) -> bool:
	if r.size() != 4:
		return false
	return r[0] >= 0 and r[1] >= 0 and r[2] > 0 and r[3] > 0 and r[0] + r[2] <= size[0] and r[1] + r[3] <= size[1]


func _units() -> void:
	var td := _load("res://assets/sprites/manifest.json")
	var ob := _load("res://assets/sprites_ob/manifest.json")
	if td.is_empty() or ob.is_empty():
		return
	_check(int(ob.get("elevation_deg", 0)) == 40, "header elevation_deg 40")
	_check(int(ob.get("px_per_m", 0)) == int(td["px_per_m"]), "px_per_m equals the top-down sheet's")
	_check(ob.get("directions", []) == DIRS, "header directions in compass order from S")
	_check(ob["palettes"] == td["palettes"], "palettes equal the top-down ones")
	var mirror: bool = ob.get("mirror", false) == true
	var tdu: Dictionary = td["units"]
	var obu: Dictionary = ob["units"]
	var n_frames := 0
	for uid in tdu:
		_check(obu.has(uid), "unit key " + uid)
		if not obu.has(uid):
			continue
		var tu: Dictionary = tdu[uid]
		var ou: Dictionary = obu[uid]
		_check(int(ou.get("set", -1)) == int(tu.get("set", -2)), uid + " set id")
		var size: Array = ou["sheet_size"]
		for act in tu["actions"]:
			_check(ou["actions"].has(act), "%s action %s" % [uid, act])
			if not ou["actions"].has(act):
				continue
			var ta: Dictionary = tu["actions"][act]
			var oa: Dictionary = ou["actions"][act]
			_check(oa["fps"] == ta["fps"] and oa["loop"] == ta["loop"], "%s/%s fps and loop" % [uid, act])
			var fr: Dictionary = oa["frames"]
			var cnt := (ta["frames"] as Array).size()
			var anchor: Array = oa["anchor"]
			var fw := 0
			var fh := 0
			for dn in DIRS:
				_check(fr.has(dn), "%s/%s direction %s" % [uid, act, dn])
				if not fr.has(dn):
					continue
				var lst: Array = fr[dn]
				_check(lst.size() == cnt, "%s/%s/%s frame count %d vs %d" % [uid, act, dn, lst.size(), cnt])
				for r: Array in lst:
					n_frames += 1
					_check(_rect_ok(r, size), "%s/%s/%s rect inside the atlas %s" % [uid, act, dn, str(r)])
					if fw == 0:
						fw = int(r[2]); fh = int(r[3])
					_check(int(r[2]) == fw and int(r[3]) == fh, "%s/%s one frame size" % [uid, act])
			_check(anchor[0] >= 0 and anchor[1] >= 0 and anchor[0] <= fw and anchor[1] <= fh,
				"%s/%s anchor %s inside the %dx%d frame" % [uid, act, str(anchor), fw, fh])
			if mirror:
				for pair in [["SE", "SW"], ["E", "W"], ["NE", "NW"]]:
					_check(fr[pair[0]] == fr[pair[1]], "%s/%s mirrored %s" % [uid, act, pair[0]])
	var atlas_size: Array = ob["atlas"]["size"]
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path("res://assets/sprites_ob/atlas_shade.png"))
	_check(err == OK and img.get_width() == int(atlas_size[0]) and img.get_height() == int(atlas_size[1]), "shade atlas image size")
	var m := Image.new()
	err = m.load(ProjectSettings.globalize_path("res://assets/sprites_ob/atlas_mask.png"))
	_check(err == OK and m.get_width() == int(atlas_size[0]) and m.get_height() == int(atlas_size[1]), "mask atlas image size")
	# the generated GDScript table: sets x actions x 8 directions x 2 entries
	var sets: int = SpriteAtlasOb.SETS.size()
	_check(SpriteAtlasOb.TABLE.size() == sets * SpriteAtlasOb.ACTIONS * 8 * 2, "TABLE length %d" % SpriteAtlasOb.TABLE.size())
	_check(sets == (td["atlas"]["sets"] as Array).size(), "sets equal the top-down count")
	_check(SpriteAtlasOb.SIZE == Vector2i(int(atlas_size[0]), int(atlas_size[1])), "SIZE matches the manifest")
	for k in SpriteAtlasOb.TABLE.size():
		var v: Vector4 = SpriteAtlasOb.TABLE[k]
		if k % 2 == 0:
			_check(v.x >= 0.0 and v.y >= 0.0 and v.z > 0.0 and v.w > 0.0 and v.x + v.z <= atlas_size[0] and v.y + v.w <= atlas_size[1], "table rect %d" % k)
		else:
			_check(v.x >= 0.0 and v.y >= 0.0 and v.x <= SpriteAtlasOb.TABLE[k - 1].z and v.y <= SpriteAtlasOb.TABLE[k - 1].w and v.w >= 1.0, "table anchor %d" % k)
	print("units: %d, %d frames, mirror %s" % [tdu.size(), n_frames, str(mirror)])


func _kit() -> void:
	var kit := _load("res://assets/kit_ob/manifest.json")
	if kit.is_empty():
		return
	_check(int(kit.get("elevation_deg", 0)) == 40, "kit elevation_deg 40")
	var pieces: Dictionary = kit["pieces"]
	var size: Array = kit["size"]
	var tdk: Dictionary = MinisAtlas.SETS["big"]
	var spec := _load("res://tools/structures/spec.json")
	var buildable: Dictionary = spec.get("structures", {})
	var want := 0
	var stale := 0
	for key: String in tdk:
		if not key.begins_with("p_"):
			continue
		# the oblique pass renders yaw 0 and the 180 degree flip (y4)
		if not (key.ends_with("__y0") or key.ends_with("__y4")):
			continue
		if not buildable.has(key):
			stale += 1      # in the minis atlas from an older build, no longer in spec.json: nothing to render
			continue
		want += 1
		_check(pieces.has(key), "kit piece " + key)
		if not pieces.has(key):
			continue
		var p: Dictionary = pieces[key]
		var r: Array = p["rect"]
		_check(_rect_ok(r, size), "%s rect inside the atlas" % key)
		var a: Array = p["anchor"]
		_check(a[0] >= 0 and a[1] >= 0 and a[0] <= r[2] and a[1] <= r[3], "%s anchor inside the rect" % key)
		var fp: Array = p["footprint_m"]
		var holds: bool = fp[0] <= 0.0 and fp[2] >= 0.0 and fp[1] <= 0.0 and fp[3] >= 0.0 and fp[2] > fp[0] and fp[3] > fp[1]
		_check(holds, "%s footprint holds the anchor" % key)
		_check(float(p["px_per_m"]) == 8.0, "%s px_per_m" % key)
	_check(pieces.has("white"), "white block")
	for key: String in pieces:
		var r2: Array = pieces[key]["rect"]
		_check(_rect_ok(r2, size), "%s rect" % key)
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path("res://assets/kit_ob/atlas_shade.png"))
	_check(err == OK and img.get_width() == int(size[0]) and img.get_height() == int(size[1]), "kit shade atlas size")
	print("kit pieces wanted %d (+%d stale in the minis atlas), in the manifest %d" % [want, stale, pieces.size()])


func _battlekit() -> void:
	# the battle's own kit (tools/battlekit): every piece of the top-down atlases (game/battlekit_atlas.gd and
	# battlekit_atlas2.gd NAMES) at yaw 0 and yaw 180 (y4) in assets/battlekit_ob/manifest.json
	var kit := _load("res://assets/battlekit_ob/manifest.json")
	if kit.is_empty():
		return
	_check(int(kit.get("elevation_deg", 0)) == 40, "battlekit_ob elevation_deg 40")
	var pieces: Dictionary = kit["pieces"]
	var size: Array = kit["size"]
	var names: Array = []
	names.append_array(BattleKitAtlas.NAMES)
	names.append_array(BattleKitAtlas2.NAMES)
	for n: String in names:
		for y in ["__y0", "__y4"]:
			var key: String = n + y
			_check(pieces.has(key), "battlekit_ob piece " + key)
			if not pieces.has(key):
				continue
			var p: Dictionary = pieces[key]
			var r: Array = p["rect"]
			_check(_rect_ok(r, size), "%s rect inside the atlas" % key)
			var a: Array = p["anchor"]
			_check(a[0] >= 0 and a[1] >= 0 and a[0] <= r[2] and a[1] <= r[3], "%s anchor inside the rect" % key)
			var fp: Array = p["footprint_m"]
			var holds: bool = fp[0] <= 0.0 and fp[2] >= 0.0 and fp[1] <= 0.0 and fp[3] >= 0.0 and fp[2] > fp[0] and fp[3] > fp[1]
			_check(holds, "%s footprint holds the anchor" % key)
			_check(float(p["px_per_m"]) == 8.0, "%s px_per_m" % key)
	for f in ["atlas_albedo", "atlas_nrm"]:
		var img := Image.new()
		var err := img.load(ProjectSettings.globalize_path("res://assets/battlekit_ob/%s.png" % f))
		_check(err == OK and img.get_width() == int(size[0]) and img.get_height() == int(size[1]), "battlekit_ob %s size" % f)
	print("battlekit_ob: %d top-down pieces, %d sprites in the manifest" % [names.size(), pieces.size()])


func _init() -> void:
	_units()
	_kit()
	_battlekit()
	print("checks: %d, failures: %d" % [checks, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
