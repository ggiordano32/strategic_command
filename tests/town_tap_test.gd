extends SceneTree
## Tapping inside a modelled town's footprint targets the town like tapping its node (west pack, table style).
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Minis := preload("res://game/campaign/minis_layer.gd")
var cs
var frame := 0

func _initialize() -> void:
	MapView.load_view_pref()
	MapView.set_style("table", false)
	PackView.use_pack("west")
	var st: Dictionary = CState.new_campaign("W", 3, [], {}, [], "west")
	st["humans"] = [CData.faction_index("england")]
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "tap_test")
	root.add_child(cs)

func _process(_d: float) -> bool:
	frame += 1
	if frame < 30:
		return false
	cs.dialog.visible = false
	cs.cover.visible = false
	var r := CData.region_index("havana")
	cs.focus_region(r, 1.4)
	if frame < 45:
		return false
	var fails := 0
	var q: Vector2 = cs.overlay.to_screen(cs.overlay.site_point(r))
	var mr := Minis.model_rect(cs.zoom, r)
	var c := q + mr.position + mr.size * 0.5
	if not Minis.on_sites:
		print("FAIL: miniatures not on")
		quit(1)
		return true
	for d in [Vector2.ZERO, Vector2(mr.size.x * 0.3, 0), Vector2(-mr.size.x * 0.3, 0), Vector2(0, mr.size.y * 0.3)]:
		var got: int = cs.overlay.settlement_at(c + d)
		if got != r:
			fails += 1
			print("FAIL: tap at ", c + d, " hit ", got, " not ", r)
	if cs.overlay.settlement_at(q + Vector2(mr.size.x, 0) + Vector2(300, 0)) == r:
		fails += 1
		print("FAIL: far tap hit the town")
	print("town_tap_test ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)
	return true
