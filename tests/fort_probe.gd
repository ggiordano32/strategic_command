extends SceneTree
## The fort storm (docs/design/siege_and_towns.md "Poles and a ram storm the fort"): one campaign assault on a town
## fought by the battle sim AI v AI as game/campaign/auto_resolve.gd runs it, over many battle seeds; prints one
## JSON line: battles won, the town taken / the fort holding, the attackers' fort choice (ai_fort 1 / 2), the
## formula's and the shown odds. (From the 2026-11-02 odds probe.)
##   --att=miskito|itza|england --town=key --walls=N --turns=N (siege turns, 0 on arrival) --poles=0|1
##   --mult=N (copies of the army's mix) --gar=PCT --seeds=N --seed0=N --field=1 (field battle) --out=PATH
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")

const MIX := {
	"miskito": [["native_warriors", ""], ["native_warriors", ""], ["native_warriors2", ""], ["native_bowmen", "poison_arrows"],
		["native_bowmen", "poison_arrows"], ["canoe_raiders", ""], ["canoe_raiders2", ""], ["maroon_vets", ""], ["chieftain", ""]],
	"itza": [["native_warriors", ""], ["native_warriors", ""], ["native_warriors2", ""], ["holcan", ""], ["native_bowmen", "fire_arrows"],
		["native_bowmen", "fire_arrows"], ["atlatl", ""], ["w_slingers", ""], ["chieftain", ""]],
	"rome": [["heavy", ""], ["spear", ""], ["heavy", ""], ["archer", ""], ["cav", ""], ["javelin", ""], ["heavy2", ""],
		["spear", ""], ["cav", ""], ["light", ""], ["general", ""]],
	"englandg": [["musketeers", ""], ["musketeers", ""], ["w_pikemen", ""], ["musketeers2", ""], ["grenadiers", ""],
		["light_gun", ""], ["field_gun", ""], ["musketeers", ""], ["general", ""]],
	"england": [["musketeers", ""], ["musketeers", ""], ["w_pikemen", ""], ["musketeers2", ""], ["grenadiers", ""],
		["pistoleers", ""], ["w_pikemen", ""], ["musketeers", ""], ["general", ""]],
}

var args := {"att": "miskito", "town": "cumana", "walls": "1", "turns": "0", "poles": "0", "mult": "1", "gar": "100",
	"seeds": "8", "seed0": "0", "field": "0", "out": "", "def": "tierra_firme", "defarmy": "0", "pack": "west"}


func _fidx(key: String) -> int:
	for i in CData.FACTIONS.size():
		if str(CData.FACTIONS[i]["key"]) == key:
			return i
	return -1


func _state(seed_v: int) -> Dictionary:
	var fa := _fidx("england" if str(args["att"]) == "englandg" else str(args["att"]))
	var fd := _fidx(str(args["def"]))
	var r := CData.region_index(str(args["town"]))
	var st := CState.new_campaign("b", seed_v, [], {}, [], str(args["pack"]))
	st["armies"] = []
	st["sieges"] = []
	st["regions"][r]["owner"] = fd
	st["regions"][r]["gar"] = int(args["gar"])
	var w := int(args["walls"])
	var got := false
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = w
			got = true
	if not got:
		st["regions"][r]["slots"].append([CData.WALLS, w])
	for r2 in CState.regions_of(st, fa):
		for sl in st["regions"][r2]["slots"]:
			if int(sl[0]) == CData.BARRACKS:
				sl[1] = mini(int(sl[1]), 1)
	if args["poles"] == "1":
		var cap: int = int(CState.regions_of(st, fa)[0])
		var g2 := false
		for sl in st["regions"][cap]["slots"]:
			if int(sl[0]) == CData.BARRACKS:
				sl[1] = 2
				g2 = true
		if not g2:
			st["regions"][cap]["slots"].append([CData.BARRACKS, 2])
	CState.set_dip(st, fa, fd, CState.WAR)
	var units: Array = []
	for m in int(args["mult"]):
		for e in MIX[str(args["att"])]:
			if str(e[0]) in ["chieftain", "general"] and m > 0:
				continue
			var u := {"t": e[0], "n": UT.size_of(UT.index_of(e[0]))}
			if str(e[1]) != "":
				u["ak"] = e[1]
			units.append(u)
	st["armies"].append({"id": 1, "f": fa, "r": r, "units": units, "from": -1, "moved": 1, "busy": 1})
	var defs: Array = []
	if int(args["defarmy"]) > 0:
		var du: Array = []
		for k in int(args["defarmy"]):
			var key: String = ["musketeers", "w_pikemen", "rodeleros"][k % 3]
			du.append({"t": key, "n": UT.size_of(UT.index_of(key))})
		st["armies"].append({"id": 2, "f": fd, "r": r, "units": du, "from": -1, "moved": 1, "busy": 1})
		defs.append(2)
	var field: bool = str(args["field"]) == "1"
	var turn := 5
	st["turn"] = turn
	var b := {"id": 1, "r": r, "turn": turn, "att": [1], "def": defs, "att_f": fa, "def_f": fd, "reinf": [],
		"settlement": 0 if field else 1, "kind": "field" if field else "assault"}
	if not field and int(args["turns"]) > 0:
		st["sieges"] = [{"r": r, "f": fa, "turn": turn - int(args["turns"]), "supply": 3}]
	st["battles"] = [b]
	return st


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	CData.use_pack(str(args["pack"]))
	var wins := 0
	var draws := 0
	var n := int(args["seeds"])
	var shown := -1
	var pm := -1
	var ticks := 0
	var sa := 0
	var sd := 0
	var eq := {}
	var fwins := 0
	var forts := 0
	var choice := [0, 0, 0]
	var ftaken := 0
	var cb := {}
	var shown_take := -1
	for i in n:
		var st := _state(1000 + 77 * (i + int(args["seed0"])))
		var b: Dictionary = st["battles"][0]
		var od := CBattle.battle_odds(st, b)
		shown = int(od["win"])
		pm = int(od["win_pm"])
		sa = int(od["att"])
		sd = int(od["def"])
		eq = CBattle.siege_equipment(st, b)
		if int(CBattle.formula(st.duplicate(true), b)["winner"]) == 0:
			fwins += 1
		cb = CBattle.capture_block(st, b)
		shown_take = int(CBattle.shown_odds(st, b)["take"])
		if str(args.get("nosim", "0")) == "1":
			print(JSON.stringify({"att": args["att"], "walls": args["walls"], "turns": args["turns"], "poles": args["poles"], "mult": args["mult"], "block": cb}))
			break
		var built := CBattle.build(st, b, -1)
		var soldiers := 0
		for u in built["scenario"]["units"]:
			soldiers += int(u["count"])
		if soldiers > 2600:
			built = CBattle.build(st, b, -1, 50)
		var sim := BattleSim.new()
		sim.setup(built["scenario"], int(built["seed"]))
		while sim.ended == 0 and sim.tick < 12000:
			sim.step()
		var out := CBattle.outcome_from_result(built, sim.result(), "auto")
		var asd := 1 - int(sim.city_def)
		if sim.fort_on != 0:
			choice[clampi(int(sim.ai_fort[asd]), 0, 2)] += 1
			if sim.fort_taken > 0:
				ftaken += 1
		if int(out["winner"]) == 0:
			wins += 1
			if int(out.get("fort_holds", 0)) != 0:
				forts += 1
		if int(out.get("draw", 0)) != 0:
			draws += 1
		ticks += sim.tick
	var line := JSON.stringify({"att": args["att"], "def": args["def"], "town": args["town"], "walls": int(args["walls"]), "turns": int(args["turns"]),
		"poles": int(args["poles"]), "mult": int(args["mult"]), "field": int(args["field"]), "defarmy": int(args["defarmy"]),
		"sa": sa, "sd": sd, "shown": shown, "pm": pm, "eq": eq, "n": n, "sim_wins": wins, "fort_holds": forts, "taken": wins - forts, "draws": draws,
		"formula_wins": fwins, "choice": choice, "fort_taken": ftaken, "block": str(cb.get("k", "")), "shown_take": shown_take, "mean_min": float(ticks) / maxi(n, 1) / 600.0})
	print(line)
	if str(args["out"]) != "":
		var fh := FileAccess.open(str(args["out"]), FileAccess.READ_WRITE if FileAccess.file_exists(str(args["out"])) else FileAccess.WRITE)
		fh.seek_end()
		fh.store_line(line)
		fh.close()
	quit(0)
