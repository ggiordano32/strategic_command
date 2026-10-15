extends SceneTree
## No moored ship (whole hull) and no in-port fleet spot of any town plan lies on land, West and Rome packs;
## at most two ships a port, none heading due north / south (bow-on slivers).
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const TownPlan := preload("res://game/campaign/town_plan.gd")

func _initialize() -> void:
	var fails := 0
	var ships := 0
	var spots := 0
	var lens := {"ship_sloop": 17.0, "ship_brigantine": 22.0, "ship_frigate": 30.0, "ship_galleon": 36.0}
	for pack in ["west", "rome"]:
		PackView.use_pack(pack)
		var st: Dictionary = CState.new_campaign("T", 3, [], {}, [], pack)
		for r in CData.region_count():
			for lv in [1, 2]:
				st["regions"][r]["level"] = lv
			for g in [false, true]:
				var pl := TownPlan.plan(st, r, g)
				var w: Vector2 = pl["water"]
				if w != Vector2.ZERO:
					spots += 1
					if TownPlan.depth(w) > -1.0:
						fails += 1
						print("FAIL ", pack, " ", CData.REGIONS[r]["key"], " fleet spot on land")
				var n := 0
				for it in pl["items"]:
					var nm: String = it[1]
					if not nm.begins_with("ship_"):
						continue
					n += 1
					ships += 1
					if int(it[2]) == 2 or int(it[2]) == 6 or not TownPlan._hull_wet(it[0], int(it[2]), float(lens.get(nm, 20.0)), 1.0):
						fails += 1
						print("FAIL ", pack, " ", CData.REGIONS[r]["key"], " ship ", nm, " yaw ", it[2], " on land or bow-on")
					if w != Vector2.ZERO and (it[0] as Vector2).distance_to(w) < 20.0:
						fails += 1
						print("FAIL ", pack, " ", CData.REGIONS[r]["key"], " ship on the fleet spot")
				if n > 2:
					fails += 1
					print("FAIL ", pack, " ", CData.REGIONS[r]["key"], " ", n, " ships")
	print("town_plan_test ships=", ships, " spots=", spots, " ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)
