extends SceneTree
## Shots of a unit's special arrow (docs/design/ui.md "A unit's special arrow is marked"): the overworld army bar and the
## battle HUD with plain and poisoned bowmen side by side.
##   godot --path . --resolution 393x851 -s tests/bows_shot.gd -- --w=393 --h=851 --px=2 --shots=DIR [--mode=camp|battle|panel|book|all]
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Tips := preload("res://game/campaign/tips.gd")
var shots := ""
var crop := 0   # keep only the bottom `crop` logical px of each shot


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	Saves.subdir = "bows_shot/"
	Tips.in_tests = true
	_run.call_deferred()


func _run() -> void:
	var w := 393
	var h := 851
	var mode := "all"
	var fac := "miskito"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w="): w = int(a.get_slice("=", 1))
		if a.begins_with("--h="): h = int(a.get_slice("=", 1))
		if a.begins_with("--shots="): shots = a.get_slice("=", 1)
		if a.begins_with("--mode="): mode = a.get_slice("=", 1)
		if a.begins_with("--fac="): fac = a.get_slice("=", 1)
		if a.begins_with("--crop="): crop = int(a.get_slice("=", 1))
	Kit.anim_override = 0
	UiScale._dpr_override = 3.0
	UiScale._touch_override = 1
	var px := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--px="): px = int(a.get_slice("=", 1))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w * px, h * px))
	root.size = Vector2i(w * px, h * px)
	await _frames(6)
	UiScale.apply(root)
	await _frames(4)
	if mode == "camp" or mode == "all":
		await _camp(w, h, fac)
	if mode == "battle" or mode == "all":
		await _battle(w, h)
	quit(0)


func _camp(w: int, h: int, fac: String) -> void:
	PackView.use_pack("west")
	var mk := CData.faction_index(fac)
	var st := CState.new_campaign("Bows", 3, [mk], {}, [], "west")
	var cs := CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "bows_shot")
	root.add_child(cs)
	await _frames(20)
	cs.close_dialog()
	cs.cover.visible = false
	var a: Dictionary = {}
	for x in CState.armies_of(cs.st, cs.f):
		if (x["units"] as Array).size() >= 3:
			a = x
			break
	if a.is_empty():
		a = CState.armies_of(cs.st, cs.f)[0]
	for rr in CData.region_count():
		if int(cs.st["regions"][rr]["owner"]) == cs.f:
			CState._add_building(cs.st["regions"][rr], CData.RANGE, 2, 99)
	var ty_key := "native_bowmen" if fac == "miskito" else "archer"
	var units: Array = a["units"]
	units.push_front({"t": ty_key, "n": UT.size_of(UT.index_of(ty_key))})
	var rr0 := -1
	for rr in CData.region_count():
		if int(cs.st["regions"][rr]["owner"]) == cs.f and rr0 < 0:
			rr0 = rr
	var u2: Dictionary = CRules.new_unit(cs.st, cs.f, rr0, ty_key)
	print("new unit ", u2)
	units.insert(1, u2)
	cs._replan()
	cs.select_army(int(a["id"]))
	await _frames(6)
	_save("%s/camp_bar_%dx%d.png" % [shots, w, h])
	cs.open_details()
	await _frames(8)
	_save("%s/camp_panel_%dx%d.png" % [shots, w, h])
	cs.close_details()
	cs.close_dialog()
	cs.panels.show_army_recruit(int(a["id"]))
	await _frames(6)
	_save("%s/camp_recruit_%dx%d.png" % [shots, w, h])
	cs.close_dialog()
	cs.open_unit_page(UT.index_of(ty_key), Callable(), "", cs.f, int(UT.ammo_index(str(u2.get("ak", "")))))
	await _frames(6)
	_save("%s/camp_page_%dx%d.png" % [shots, w, h])
	cs.queue_free()
	await _frames(3)


func _battle(w: int, h: int) -> void:
	var ba := UT.index_of("native_bowmen")
	var units: Array = []
	units.append(Scenarios.unit(0, ba, UT.size_of(ba), 100, 150, 0))
	var pk := Scenarios.unit(0, ba, UT.size_of(ba), 130, 150, 0)
	pk["ak"] = UT.ammo_index("poison_arrows")
	units.append(pk)
	units.append(Scenarios.unit(0, UT.index_of("native_warriors"), 60, 160, 150, 0))
	var fa := UT.index_of("archer")
	var fk := Scenarios.unit(0, fa, UT.size_of(fa), 190, 150, 0)
	fk["ak"] = UT.ammo_index("fire_arrows")
	units.append(fk)
	units.append(Scenarios.unit(1, UT.index_of("spear"), 80, 150, 40, 512))
	var sc := Scenarios._test(units, [])
	sc["ai_sides"] = [1]
	var b := Battle.new()
	b.custom_scenario = sc
	b.player_side = 0
	b.seed_value = 5
	root.add_child(b)
	await _frames(8)
	b._set_paused(true)
	var us: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0:
			us.append(u)
	b.selection.clear()
	b.selection.append(us[1])
	b.selected = us[1]
	b._selection_changed()
	await _frames(6)
	_save("%s/battle_hud_%dx%d.png" % [shots, w, h])
	b.queue_free()
	await _frames(3)


func _save(path: String) -> void:
	var im := root.get_texture().get_image()
	if crop > 0:
		var k := float(im.get_height()) / float(root.content_scale_size.y)
		var hh := mini(int(crop * k), im.get_height())
		im = im.get_region(Rect2i(0, im.get_height() - hh, im.get_width(), hh))
	im.save_png(path)
