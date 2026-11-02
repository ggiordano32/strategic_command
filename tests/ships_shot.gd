extends SceneTree
## Shots and a cost probe of the lane traders (docs/design/overworld_view.md "Lane traders, the ambient ships retired"):
## trade flowing on the lanes, one raided and one blockaded.
##   godot --path . --resolution 393x851 -s tests/ships_shot.gd -- --pack=west|rome --shots=DIR [--px=2] [--zoom=0.7] [--prof]
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CLanes := preload("res://campaign/clanes.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Tips := preload("res://game/campaign/tips.gd")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	Saves.subdir = "ships_shot/"
	Tips.in_tests = true
	_run.call_deferred()


func _run() -> void:
	var w := 393
	var h := 851
	var pack := "west"
	var shots := ""
	var px := 1
	var zoom := 0.7
	var prof := false
	var at := ""
	var crop := ""
	var before := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="): pack = a.get_slice("=", 1)
		if a.begins_with("--shots="): shots = a.get_slice("=", 1)
		if a.begins_with("--px="): px = int(a.get_slice("=", 1))
		if a.begins_with("--zoom="): zoom = float(a.get_slice("=", 1))
		if a.begins_with("--at="): at = a.get_slice("=", 1)
		if a.begins_with("--crop="): crop = a.get_slice("=", 1)
		if a == "--before": before = true
		if a == "--prof": prof = true
	UiScale._dpr_override = 3.0
	UiScale._touch_override = 1
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w * px, h * px))
	root.size = Vector2i(w * px, h * px)
	await _frames(6)
	UiScale.apply(root)
	await _frames(4)
	PackView.use_pack(pack)
	var mk := 0
	var st := CState.new_campaign("Ships", 3, [mk], {}, [], pack)
	var nf := CState.nf()
	for i in nf:
		for j in range(i + 1, nf):
			CState.set_dip(st, i, j, CState.TRADE)
	# a raided lane: a hostile fleet on the middle cell of the first lane whose ends have different owners
	var raided := -1
	var blockaded := -1
	var rf := -1
	for id in CData.SEA_LANES.size():
		var e: Array = CLanes.ends(id)
		var oa := CState.owner(st, int(e[0]))
		var ob := CState.owner(st, int(e[1]))
		if oa >= 0 and ob >= 0 and oa != ob and raided < 0:
			raided = id
			rf = ob if ob != oa else (oa + 1) % nf
			CState.set_dip(st, rf, oa, CState.WAR)
			var cells := CLanes.sea_cells(id)
			var c := int(cells[cells.size() / 2])
			var ships: Array = [{"t": CData.ship_const("START_FLEETS", [["", "", ["brigantine"]]])[0][2][0], "h": 100, "c": 100}]
			CFleet._new_fleet(st, rf, c, ships)
		elif oa >= 0 and ob >= 0 and oa == ob and blockaded < 0 and id > 6:
			blockaded = id
			st["regions"][int(e[0])]["bk"] = (oa + 1) % nf
	print("lane raided=", raided, " blockaded=", blockaded, " raider f=", rf)
	var cs := CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "ships_shot")
	root.add_child(cs)
	await _frames(20)
	cs.close_dialog()
	cs.cover.visible = false
	var key := at
	if key == "":
		key = "havana" if pack == "west" else "roma"
	cs.focus_region(CData.region_index(key), zoom)
	cs._refresh_map()
	await _frames(30)
	var trd = cs.overlay.traders if "overlay" in cs else null
	if before:
		trd.visible = false
		trd.set_process(false)
		await _frames(3)
	print("traders node ", trd, " lanes ", (trd._lanes.size() if trd else -1), " sails ", (trd.count if trd else -1))
	print("zoom ", cs.overlay.zoom, " mk ", cs.overlay.mk())
	if shots != "":
		_save("%s/%s_%s%s.png" % [shots, pack, "z" + str(zoom), ("_crop" if crop != "" else "") + ("_before" if before else "")], crop)
	if prof:
		await _prof(trd)
	quit(0)


func _prof(trd) -> void:
	# frame cost: the traders' _draw time and the whole frame, with them on and off
	for mode in ["on", "off"]:
		trd.set_process(mode == "on")
		trd.visible = mode == "on"
		await _frames(20)
		var t0 := Time.get_ticks_usec()
		var n := 200
		for i in n:
			await process_frame
		var dt := float(Time.get_ticks_usec() - t0) / float(n) / 1000.0
		print("PROF ", mode, " frame ms ", snappedf(dt, 0.01))
	trd.set_process(true)
	trd.visible = true
	var t1 := Time.get_ticks_usec()
	for i in 500:
		trd._draw()
	print("PROF _draw alone ms ", snappedf(float(Time.get_ticks_usec() - t1) / 500.0 / 1000.0, 0.001), " sails ", trd.count)


func _save(path: String, crop := "") -> void:
	var im := root.get_texture().get_image()
	if crop != "":   # x,y,w,h in shot px, shown 2x
		var c := crop.split(",")
		im = im.get_region(Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
		im.resize(im.get_width() * 2, im.get_height() * 2, Image.INTERPOLATE_NEAREST)
	im.save_png(path)
