extends SceneTree
## A fleet at the shore's shots (windowed, view only; docs/design/battle_sim.md "A fleet at the shore (as built,
## 2026-11-05)", docs/design/art_pipeline.md "(2026-11-05) The ship on the board"): Scenarios.shore_battle with the
## player commanding the defenders (their fleet at the quay), run by the AI on the other side; at --land-at the
## player's ship --ship (0: the frigate) is ordered to Land, at --hold the camera is on her (or on her landing party
## once it is afloat, --on-party) and the screen is saved as a PNG. --select selects her (her card, the Land chip).
##   godot --path . --resolution 1280x720 -s tests/shore_shots.gd -- --out=FILE.png [--view=top|oblique]
##       [--zoom=2.5] [--def=1|2] [--att=0|1|2] [--side=1] [--land-at=30] [--hold=120] [--ship=0] [--select] [--on-party]
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const SIDES := ["england", "tierra_firme"]   # (the shots' factions: their colours and the ships' names)
var battle: Battle
var out := "user://shore.png"
var zoom := 2.5
var df := 1
var af := 0
var side := 1
var land_at := 30
var hold := 120
var ship := 0
var select := false
var on_party := false
var frame := 0
var landed := false


func _initialize() -> void:
	BoardView.force = "top"
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--def="): df = int(v)
		elif a.begins_with("--att="): af = int(v)
		elif a.begins_with("--side="): side = int(v)
		elif a.begins_with("--land-at="): land_at = int(v)
		elif a.begins_with("--hold="): hold = int(v)
		elif a.begins_with("--ship="): ship = int(v)
		elif a == "--select": select = true
		elif a == "--on-party": on_party = true
	CData.use_pack("west")
	battle = Battle.new()
	var sc := Scenarios.shore_battle(df, af, [1 - side])
	var fi := [CData.faction_index(SIDES[0]), CData.faction_index(SIDES[1])]
	var uf: Array = []
	for u in sc["units"]:
		uf.append(int(fi[int(u["side"]) & 1]))
	for e in sc.get("ships", []):
		e["f"] = int(fi[int(e["side"]) & 1])
	battle.unit_faction = uf
	battle.custom_scenario = sc
	battle.player_side = side
	battle.seed_value = 8100
	root.add_child(battle)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 10:
		battle._toggle_pause()
		battle.camera.zoom = Vector2.ONE * zoom
	elif frame > 10:
		var s = battle.sim
		if s.shp_on == 0:
			print("no ships on the map")
			quit(1)
			return true
		var mine: Array = []
		for k in s.sh_side.size():
			if s.sh_side[k] == side:
				mine.append(k)
		var k0: int = mine[clampi(ship, 0, mine.size() - 1)]
		var hu: int = s.sh_unit[k0]
		if s.tick < hold * 10:
			for t in 5:
				if s.tick == land_at * 10 and not landed and land_at >= 0:
					battle._select(hu)
					battle._land()
					landed = true
				s.step()
			battle.soldiers.upload()
			battle.soldiers.set_alpha(1.0)
			battle._view_tick()
		var p: int = s.sh_party[k0]
		var at := Vector2(s.sh_x[k0], s.sh_y[k0])
		if on_party and p >= 0 and s.u_state[p] == BattleSim.U_READY:
			at = Vector2(s.u_cx[p], s.u_cy[p])
		battle._cam_to(at / 1024.0 * Battle.PX_PER_M)
		if s.tick >= hold * 10:
			if select and battle.selection != [hu]:
				battle._select(hu)
			frame = maxi(frame, 0)
			if not has_meta("t0"):
				set_meta("t0", frame)
			if frame - int(get_meta("t0")) >= 8:
				root.get_texture().get_image().save_png(out)
				print("saved ", out, " tick ", s.tick, " land ", s.sh_land, " shots ", s.sh_shots)
				quit(0)
	return false
