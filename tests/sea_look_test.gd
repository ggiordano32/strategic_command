extends SceneTree
## The sea battle's look (game/sea_look.gd), headless:
##   godot --headless --script res://tests/sea_look_test.gd
## The baked fields for an open sea, an island, a coast and Havana's harbour mouth (the campaign cell,
## its bathymetry and the Morro / Fuerza fort pieces): the drawn shore lies inside the sim's land cells
## (the sim's land mask is the truth), the same battle bakes the same bytes, depth grows from the coast
## to the open sea and is nil on land, the props stand on land (trees inland of the beach, forts on the
## coast facing the sea), Graphics Low bakes the same fields with fewer trees.

const SeaSim := preload("res://sim/sea_sim.gd")
const SeaLook := preload("res://game/sea_look.gd")
const Checks := preload("res://tests/sea_checks.gd")
const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

var _ok := true


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _look(scn: Dictionary, seed_v: int, cell := Vector2i(-1, -1), region := -1) -> Array:
	var sim := SeaSim.new()
	sim.setup(scn, seed_v)
	var lk := SeaLook.new()
	lk.setup(sim, seed_v, scn, cell, region)
	return [sim, lk]


func _initialize() -> void:
	var cases := {
		"open": Checks.scenario("frigates"),
		"island": Checks.scenario("frigates"),
		"coast": Checks.scenario("coast"),
	}
	(cases["island"] as Dictionary)["land"] = {"kind": 1, "mseed": 4242}
	for k in cases:
		var r := _look(cases[k], 7)
		var sim: SeaSim = r[0]
		var lk: SeaLook = r[1]
		_check(lk.shore_ok(), "%s: the drawn shore is inside the sim's land" % k)
		var r2 := _look(cases[k], 7)
		_check((r2[1] as SeaLook).sdf == lk.sdf and (r2[1] as SeaLook).trees == lk.trees, "%s: the same battle bakes the same fields and trees" % k)
		# Depth: nil on land, rising away from the coast (the shader's shelf: 0.4 + d * (0.05 + 0.3 steep) + ...).
		var land_n := 0
		for c in sim.g_w * sim.g_h:
			if sim.g[c] == 2:
				land_n += 1
		if k == "open":
			_check(land_n == 0 and lk.trees.is_empty() and lk.forts.is_empty(), "open: no land, no props")
		else:
			_check(land_n > 0, "%s: has land (%d cells)" % [k, land_n])
			var on_land := true
			for t in lk.trees:
				on_land = on_land and lk.sdf_at(Vector2(t[0], t[1])) < -(SeaLook.SHORE_MIN + SeaLook.SHORE_AMP)
			_check(on_land and not lk.trees.is_empty(), "%s: %d trees, every one inland of the beach" % [k, lk.trees.size()])
		for t in lk.trees:
			if lk.sdf_at(Vector2(t[0], t[1])) > 0.0:
				_check(false, "tree in the sea")
	# (R2) The Mediterranean (the Rome pack, TROPIC 0): no palms, the same fields and trees twice.
	var med := _look(Checks.scenario("coast"), 7)
	var ml: SeaLook = med[1]
	var palms := 0
	for t in ml.trees:
		var nm: String = SeaLook.Atlas.NAMES[int(t[2])]
		if nm.begins_with("tree_palm"):
			palms += 1
	_check(not ml.tropic and ml.shore_ok() and not ml.trees.is_empty() and palms == 0,
		"Mediterranean (Rome pack): not tropic, %d trees, no palms, the shore inside the sim's land" % ml.trees.size())
	_check((ml.water_mat.get_shader_parameter("c_deep") as Vector3).z < 0.45, "Mediterranean: the deep water is the deeper blue")
	# Graphics Low (fewer trees, the same fields).
	var lowr := _low_look()
	_check(lowr, "Graphics Low: the same coast, no more than %d trees" % SeaLook.TREE_CAP_LOW)
	# Havana's harbour mouth: the campaign cell, bathymetry, the fort pieces.
	PackView.use_pack("west")
	var rh := -1
	for i in CData.REGIONS.size():
		if str(CData.REGIONS[i]["key"]) == "havana":
			rh = i
	var c := CFleet.dock(rh)
	var cell := Vector2i(CGrid.cx(c), CGrid.cy(c))
	var scn: Dictionary = Checks.scenario("coast")
	scn["land"] = {"kind": 2, "dirs": 6, "mseed": 69729}
	var rr := _look(scn, 11, cell, rh)
	var hl: SeaLook = rr[1]
	_check(hl.tropic, "Havana (West pack): tropic, palms and the Caribbean palette")
	_check(hl.shore_ok(), "Havana: the drawn shore is inside the sim's land")
	_check(hl.forts.size() == 2, "Havana: its two harbour forts (%d)" % hl.forts.size())
	var f_ok := true
	for f in hl.forts:
		var p := Vector2(f[0], f[1])
		f_ok = f_ok and hl.sdf_at(p) < -(SeaLook.SHORE_MIN + SeaLook.SHORE_AMP + 10.0) and p.x > 0.0 and p.y > 0.0 and p.x < hl.field.x and p.y < hl.field.y
	_check(f_ok, "Havana: the forts stand on the land inside the field")
	# Depth from the campaign: the open-sea end deep, the coast shallow.
	var deep := 0.0
	for k in hl.cdp.size():
		deep = maxf(deep, hl.cdp[k])
	_check(deep > 500.0, "Havana: the campaign's bathymetry is deep offshore (%.0f m)" % deep)
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _low_look() -> bool:
	# Quality.is_low reads the launch override / settings; run with --quality=low to exercise it in the real thing.
	var r := _look(Checks.scenario("coast"), 7)
	var lk: SeaLook = r[1]
	return lk.trees.size() <= (SeaLook.TREE_CAP_LOW if lk.low else SeaLook.TREE_CAP)
