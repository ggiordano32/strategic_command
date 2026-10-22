extends SceneTree
## Banners at towns (map_overlay.gd "Banners at towns"; owner 2026-10-22: a garrison's banner drew far west of
## Veracruz on the besiegers of Orizaba). For every settlement of the pack, at two zooms: a garrison of three armies
## and, in turn, besiegers on one, three and all eight ring cells (its siege, an enemy faction); the garrison's
## banners stay within the town's footprint and a banner's reach, the besiegers within the siege ring, and no two
## banners overlap.
## godot --path . --resolution 1400x900 -s tests/banner_test.gd -- --pack=west|rome   (windowed: the west's table
## style models exist only with a window)
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CRules := preload("res://campaign/crules.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const Minis := preload("res://game/campaign/minis_layer.gd")
const Overlay := preload("res://game/campaign/map_overlay.gd")
var cs
var frame := 0
var pack := "west"
var base: Dictionary
var fo := 0   # the garrison's faction
var fb := 1   # the besiegers'
var jobs: Array = []   # [region, zoom, besiegers]
var ji := 0
var wait := 0
var fails := 0
var checked := 0
var shown := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
	FogView.all_seeing = true
	MapView.load_view_pref()
	MapView.set_style("table" if pack == "west" else "relief", false)
	PackView.use_pack(pack)
	base = CState.new_campaign("B", 5, [0], {}, [], pack)
	base["humans"] = [0]
	fo = 0
	fb = 1
	cs = CampaignScreen.new()
	cs.open({"state": base, "session": {"subs": [], "plans": {}, "seen": {}}}, "banner_test")
	root.add_child(cs)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	for z in [0.8, 1.6]:
		for r in CData.region_count():
			if only != "" and str(CData.REGIONS[r]["key"]) != only:
				continue
			for nb in [1, 3, 8]:
				jobs.append([r, z, nb])


func _state_for(r: int, nb: int) -> Dictionary:
	var st := CState.copy(base)
	var proto: Array = (CState.armies_of(base, fo)[0]["units"] as Array).duplicate(true)
	st["armies"] = []
	st["sieges"] = []
	st["regions"][r]["owner"] = fo
	var site := CGrid.site(r)
	for i in 3:
		_army(st, fo, site, proto)
	var ring: Array = []
	for d in CGrid.disc(site, 1):
		if d != site and CGrid.region(d) >= 0:
			ring.append(d)
	var made := 0
	var first: Dictionary = {}
	for c in ring:
		if made >= nb:
			break
		var a := _army(st, fb, c, proto)
		if first.is_empty():
			first = a
		made += 1
	if made > 0:
		CState.set_dip(st, fb, fo, CState.WAR)
		CRules.start_siege(st, r, first, -1)
		for a in CState.armies_of(st, fb):
			CRules._set_from(CState.siege_at(st, r), int(a["id"]), -1)
	return st


func _army(st: Dictionary, f: int, c: int, proto: Array) -> Dictionary:
	var id := CRules.new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var a := {"id": id, "f": f, "r": CGrid.region(c), "units": proto.duplicate(true), "from": -1, "moved": 0, "busy": 0}
	CState.place(a, c)
	CRules._insert_army(st, a)
	return a


func _process(_d: float) -> bool:
	frame += 1
	if frame < 40:
		return false
	if frame == 40:
		cs.dialog.visible = false
		cs.cover.visible = false
	if wait > 0:
		wait -= 1
		return false
	if ji >= jobs.size():
		print("banner_test ", pack, " ", "PASS" if fails == 0 else "FAIL", " (", checked, " cases, ", fails, " failures)")
		quit(1 if fails > 0 else 0)
		return true
	var job: Array = jobs[ji]
	ji += 1
	var r: int = job[0]
	var z: float = job[1]
	cs.focus_region(r, z)
	var st := _state_for(r, int(job[2]))
	cs.overlay.state = st
	cs.overlay._epoch += 1
	if pack == "west" and not Minis.on_sites:
		wait = 2
		ji -= 1
		return false
	_check(r, z, int(job[2]), st)
	return false


func _check(r: int, z: float, nb: int, st: Dictionary) -> void:
	var ov = cs.overlay
	var pos: Dictionary = ov.army_positions()
	var m: float = ov.mk()
	var rects: Array = []
	var ids: Array = []
	for a in st["armies"]:
		var id := int(a["id"])
		if not pos.has(id):
			fails += 1
			print("FAIL ", CData.REGIONS[r]["key"], " z", z, ": army ", id, " has no position")
			continue
		var c: Vector2 = pos[id]
		rects.append(Rect2(c - Vector2(Overlay.ARMY_W, Overlay.ARMY_H) * 0.5 * m, Vector2(Overlay.ARMY_W, Overlay.ARMY_H) * m))
		ids.append(a)
	checked += 1
	if OS.get_cmdline_user_args().has("--dump"):
		print("DUMP ", CData.REGIONS[r]["key"], " z", z, " nb ", nb, " m ", m, " cellpx ", CGrid.cell_px(), " site ", ov.to_screen(ov.site_point(r)))
		for i in rects.size():
			print("   f", int(ids[i]["f"]), " ", (rects[i] as Rect2).get_center())
	var tag := "%s %s z%.1f besiegers %d (%s)" % [pack, CData.REGIONS[r]["key"], z, nb, "models" if Minis.on_sites else "relief"]
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				fails += 1
				print("FAIL ", tag, ": banners overlap, armies ", int(ids[i]["id"]), " (f", int(ids[i]["f"]), ") and ", int(ids[j]["id"]), " (f", int(ids[j]["f"]), ")")
	var reach: Rect2 = ov.banner_reach(r)
	var site: Vector2 = ov.to_screen(ov.site_point(r))
	var ring: float = ov.siege_ring_radius(r)
	var gar := Rect2()
	var has_gar := false
	for i in rects.size():
		var rc: Rect2 = rects[i]
		var a: Dictionary = ids[i]
		if int(a["f"]) == fo:
			gar = rc if not has_gar else gar.merge(rc)
			has_gar = true
		else:
			# a besieger: on the ring of the besieged town, or pushed out along up to three outer rings
			var d := rc.get_center().distance_to(site)
			if d > ring + 6.0 * m + 3.0 * (Overlay.ARMY_H * m * 0.9 + 2.0) + Overlay.ARMY_W * m or d < ring * 0.5:
				fails += 1
				print("FAIL ", tag, ": a besieger at ", d, " px from the town, ring ", ring)
	# the garrison: its banners touch the town's footprint and a margin (a banner stands just outside the footprint)
	if has_gar and not gar.intersects(reach):
		fails += 1
		print("FAIL ", tag, ": the garrison's banners ", gar, " are away from the town ", reach)
