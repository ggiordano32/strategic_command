extends SceneTree
## Fog memory of a settlement's level and walls (campaign/csight.gd update_memory, "lvl" / "wl"), and what the
## town layer draws for a region out of sight (game/campaign/fog_view.gd town_facts): the last-seen owner's
## culture, level and walls; a never-seen region has no model.
##   godot --headless --script res://tests/sight_mem_test.gd
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CSight := preload("res://campaign/csight.gd")
const CTown := preload("res://campaign/ctown.gd")
const FogView := preload("res://game/campaign/fog_view.gd")

var fails := 0


func _check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	for pack in ["rome", "west"]:
		_run(pack)
	print("sight_mem_test: %s (%d failures)" % ["FAIL" if fails > 0 else "PASS", fails])
	quit(1 if fails > 0 else 0)


func _run(pack: String) -> void:
	print("pack ", pack)
	CData.use_pack(pack)
	var me := CData.faction_index("rome" if pack == "rome" else "england")
	var st := CState.new_campaign("mem", 4242, [me], {}, [], pack)
	var nr := CData.region_count()
	var mem: Dictionary = st["factions"][me]["mem"]
	_check((mem["lvl"] as Array).size() == nr and (mem["wl"] as Array).size() == nr, "memory has lvl / wl, one per region")
	# a region in sight: written at once
	var own_r := -1
	for r in nr:
		if CState.owner(st, r) == me:
			own_r = r
	_check(own_r >= 0, "the player holds a region")
	_check(int(mem["lvl"][own_r]) == int(st["regions"][own_r]["level"]) and int(mem["wl"][own_r]) == CState.walls(st, own_r),
		"an owned region's level and walls are in the memory from the start")
	# the first foreign region in sight and one never seen
	var vis := CSight.visible(st, me)
	var seen_f := -1
	var never_r := -1
	for r in nr:
		if CState.owner(st, r) != me and CSight.region_visible(st, me, r, vis) and seen_f < 0:
			seen_f = r
		if int(mem["turn"][r]) < 0 and never_r < 0:
			never_r = r
	_check(never_r >= 0, "some region was never seen")
	_check(int(mem["lvl"][never_r]) == -1 and int(mem["wl"][never_r]) == -1, "a never-seen region has lvl / wl -1")
	# darken: all but one of our regions go to another faction and no pieces are left, so the target is out of sight
	var other := (me + 1) % CData.faction_count()
	var dark: Dictionary = {}
	var target := -1
	var keep := -1
	for t in nr:
		if int(mem["turn"][t]) < 0 or target >= 0:
			continue
		for k in nr:
			if CState.owner(st, k) != me or k == t:
				continue
			var cand := CState.copy(st)
			for r in nr:
				if CState.owner(cand, r) == me and r != k:
					(cand["regions"][r] as Dictionary)["owner"] = other
			if CState.owner(cand, t) == me:
				continue
			cand["armies"] = []
			if cand.has("fleets"):
				cand["fleets"] = []
			cand["chars"] = []
			if not CSight.region_visible(cand, me, t, CSight.compute(cand, me)):
				dark = cand
				target = t
				keep = k
				break
	_check(target >= 0, "a region seen at the start can be put out of sight (target %d, keep %d)" % [target, keep])
	if target < 0:
		return
	var seen_lvl := int(st["regions"][target]["level"])
	var seen_wl := CState.walls(st, target)
	var seen_own := CState.owner(st, target)
	var vd := CSight.compute(dark, me)
	# the memory written while it was in sight carries over
	dark["factions"][me]["mem"] = (st["factions"][me]["mem"] as Dictionary).duplicate(true)
	# the true level and walls change while dark
	(dark["regions"][target] as Dictionary)["level"] = (seen_lvl + 1) % 3
	var changed_wl := false
	for s in dark["regions"][target]["slots"]:
		if int(s[0]) == CData.WALLS:
			s[1] = (int(s[1]) + 1) % 4
			changed_wl = true
	CSight.update_memory(dark)
	var m2: Dictionary = dark["factions"][me]["mem"]
	_check(int(m2["lvl"][target]) == seen_lvl, "dark: the remembered level stays (%d)" % seen_lvl)
	_check(int(m2["wl"][target]) == seen_wl, "dark: the remembered walls stay (%d)%s" % [seen_wl, "" if changed_wl else " (no walls slot to change)"])
	_check(CSight.known_level(dark, me, target) == seen_lvl and CSight.known_walls(dark, me, target) == seen_wl, "known_level / known_walls answer from memory")
	_check(int(dark["regions"][target]["level"]) != seen_lvl, "the true level did change")
	# the town layer's inputs
	FogView.update(dark, me)
	_check(FogView.on, "fog applies to the planner")
	var tf := FogView.town_facts(dark, target)
	_check(not tf.is_empty() and int(tf["lvl"]) == seen_lvl and int(tf["walls"]) == seen_wl, "town facts of a dark region come from the memory")
	_check(int(tf["siege"]) == -1 and int(tf["sack"]) == 0 and int(tf["yard"]) == 0 and int(tf["market"]) == 0, "nothing else of the true state leaks into them")
	_check(tf["style"] == CTown.facts_known(dark, target, seen_own, seen_lvl, seen_wl)["style"], "its style is the last-seen owner's culture")
	var nv := -1
	for r in nr:
		if int(m2["turn"][r]) < 0 and not CSight.region_visible(dark, me, r, vd):
			nv = r
			break
	if nv >= 0:
		_check(FogView.town_facts(dark, nv).is_empty() and FogView.never(nv), "a never-seen region has no model")
	# in sight again: the true facts
	FogView.update(st, me)
	_check(FogView.town_facts(st, own_r) == CTown.facts(st, own_r), "in sight: the true facts")
	# a memory written before lvl / wl existed is filled on the next update
	var old := CState.copy(st)
	(old["factions"][me]["mem"] as Dictionary).erase("lvl")
	(old["factions"][me]["mem"] as Dictionary).erase("wl")
	CSight.update_memory(old)
	_check(int(old["factions"][me]["mem"]["lvl"][own_r]) == int(st["regions"][own_r]["level"]) and int(old["factions"][me]["mem"]["lvl"][never_r]) == -1,
		"an old memory without lvl / wl is filled for what is in sight, unknown (-1) elsewhere")
