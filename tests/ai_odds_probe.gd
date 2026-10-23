extends SceneTree
## Campaign AI odds probe (docs/AI.md 12.1): AI-only campaigns as
## tests/campaign_sim.gd plays them (same seeds 1000 + 77 n, format 6), with
## the AI's decision log on (CP.log_on: diagnostic, outside the state, the
## campaign is the same). Per skill: attacks launched with the formula's
## predicted win chance by band and what came of them (won / lost / no
## battle), attacks refused that the formula would have won > 70 %, hunts,
## storms, sieges started / taken / lifted, armies destroyed, and the pacing
## (battles, eliminations with the turn, largest faction at 60, Macedon).
##   godot --headless --script res://tests/ai_odds_probe.gd -- [--pack=west] [--seeds=6] [--turns=60]
##       [--skill=easy|average|skilled] [--mixed] [--json=PATH] [--knob=LEVEL:ID=VALUE ...] [--from=N]
## --mixed: per seed, every other faction Skilled, the rest Average (faction
## f Skilled when f + seed index is even), so each faction plays both; the
## end table compares the two skills head to head.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CP := preload("res://campaign/cai_profile.gd")

const BANDS := [0, 20, 35, 45, 55, 65, 80, 95, 101]
const ATTACKS := ["assault", "siege", "rush", "mistake", "idle", "hunt", "storm"]

var seeds := 6
var turns := 60
var pack := "rome"
var skill_all := -1
var mixed := false
var json_path := ""
var agg := {}       # skill -> tallies
var pacing: Array = []
var elim_all := {}  # faction key -> [turns]
var h2h := {}       # skill -> [faction-seeds, regions at 60 summed, eliminated]
var knobs: Array = []  # --knob=: [level, knob id, value]
var first := 0         # --from=N: start at seed index N (seed 1000 + 77 N)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--from="):
			first = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--skill="):
			skill_all = _level(a.get_slice("=", 1))
		elif a == "--mixed":
			mixed = true
		elif a.begins_with("--json="):
			json_path = a.substr(7)
		elif a.begins_with("--knob="):
			# --knob=LEVEL:ID=VALUE as tests/campaign_sim.gd (ablations).
			var v := a.substr(7)
			var lk := v.get_slice("=", 0)
			knobs.append([_level(lk.get_slice(":", 0)), int(lk.get_slice(":", 1)), int(v.get_slice("=", 1))])
	CData.use_pack(pack)
	for kv in knobs:
		CP.set_knob(int(kv[0]), int(kv[1]), int(kv[2]))
	CP.log_on = true
	for sd in range(first, first + seeds):
		_run(sd)
	_print()
	quit(0)


static func _level(v: String) -> int:
	match v.to_lower().substr(0, 1):
		"e", "0":
			return CP.EASY
		"s", "2":
			return CP.SKILLED
	return CP.AVERAGE


func _tal(sk: int) -> Dictionary:
	if not agg.has(sk):
		var bands: Array = []
		for i in BANDS.size() - 1:
			bands.append([0, 0, 0, 0, 0])  # launched, won, lost, no battle, predicted win summed
		agg[sk] = {"bands": bands, "kinds": {}, "refused": 0, "refused70": 0, "hunt_refused": 0, "hunt_refused70": 0,
			"sieges": 0, "sieges_taken": 0, "sieges_lifted": 0, "destroyed": 0, "field_lost": 0, "field_won": 0,
			"faction_turns": 0}
	return agg[sk]


func _band(w: int) -> int:
	for i in BANDS.size() - 1:
		if w < int(BANDS[i + 1]):
			return i
	return BANDS.size() - 2


func _run(sd: int) -> void:
	var settings := {}
	if skill_all >= 0:
		settings["ai_campaign_skill"] = skill_all
	var st := CState.new_campaign("sim", 1000 + sd * 77, [], settings, [], pack)
	if mixed:
		for f in CState.nf():
			st["factions"][f]["ai_skill"] = CP.SKILLED if (f + sd) % 2 == 0 else CP.AVERAGE
	if 6 < CState.VERSION:
		st = CState.as_format(st, 6)
	var sieges := []  # [r, f, open 1 / taken 2 / lifted 3]
	var dead_at := {}
	var big60 := 0
	for t in turns:
		CP.dlog = []
		var t0 := int(st["turn"])
		st = CTurn.resolve_turn(st, [])
		var evs: Array = []
		for e in st["events"]:
			if int(e["turn"]) == t0:
				evs.append(e)
		for f in CState.nf():
			_tal(CP.skill(st, f))["faction_turns"] += 1 if CState.alive(st, f) else 0
		for rec in CP.dlog:
			var sk := int(rec["skill"])
			var T := _tal(sk)
			var k := str(rec["k"])
			var w := int(rec["win"])
			if k == "refused":
				T["refused"] += 1
				if w > 70:
					T["refused70"] += 1
				continue
			if k == "hunt_refused":
				T["hunt_refused"] += 1
				if w > 70:
					T["hunt_refused70"] += 1
				continue
			if not ATTACKS.has(k):
				continue
			var kd: Dictionary = T["kinds"]
			if not kd.has(k):
				kd[k] = [0, 0, 0, 0, 0]
			var res := 3
			for e in evs:
				if str(e["k"]) == "battle" and int(e["r"]) == int(rec["t"]) and (e["att"] as Array).has(int(rec["f"])):
					res = 1 if int(e["winner"]) == 0 else 2
					break
			if k == "siege" and res == 3:
				continue  # laid siege without a battle: counted with the sieges
			var b: Array = T["bands"][_band(w)]
			b[0] += 1
			b[res] += 1
			b[4] += w
			var kk: Array = kd[k]
			kk[0] += 1
			kk[res] += 1
			kk[4] += w
		for e in evs:
			var k := str(e["k"])
			if k == "siege":
				sieges.append([int(e["r"]), int(e["f"]), 1])
				_tal(CP.skill(st, int(e["f"])))["sieges"] += 1
			elif k == "captured" or k == "siege_lifted":
				for x in sieges:
					if int(x[0]) == int(e["r"]) and int(x[2]) == 1:
						if k == "captured" and int(e["f"]) == int(x[1]):
							x[2] = 2
							_tal(CP.skill(st, int(x[1])))["sieges_taken"] += 1
						elif k == "siege_lifted":
							x[2] = 3
							_tal(CP.skill(st, int(x[1])))["sieges_lifted"] += 1
						else:
							x[2] = 4
			elif k == "destroyed" and int(e["f"]) >= 0:
				_tal(CP.skill(st, int(e["f"])))["destroyed"] += 1
			elif k == "battle" and str(e.get("kind", "")) == "field":
				for side in 2:
					for g in (e["att"] if side == 0 else e["def"]):
						if int(g) >= 0:
							_tal(CP.skill(st, int(g)))["field_won" if int(e["winner"]) == side else "field_lost"] += 1
		for f in CState.nf():
			if not dead_at.has(f) and not CState.alive(st, f):
				dead_at[f] = int(st["turn"])
	for f in CState.nf():
		big60 = maxi(big60, CState.regions_of(st, f).size())
	var dl: Array = []
	var early := 0
	for f in CState.nf():
		if dead_at.has(f):
			var key := str(CData.FACTIONS[f]["key"]).substr(0, 4)
			dl.append("%s %d" % [key, int(dead_at[f])])
			if not elim_all.has(key):
				elim_all[key] = []
			elim_all[key].append(int(dead_at[f]))
			if int(dead_at[f]) < 10:
				early += 1
	if mixed:
		for f in CState.nf():
			var sk := CP.skill(st, f)
			if not h2h.has(sk):
				h2h[sk] = [0, 0, 0]
			h2h[sk][0] += 1
			h2h[sk][1] += CState.regions_of(st, f).size()
			h2h[sk][2] += 1 if dead_at.has(f) else 0
	pacing.append({"seed": 1000 + sd * 77, "battles": int(st["stats"]["battles"]), "elim": dl, "early": early,
		"largest60": big60, "hash": CState.hash_text(st)})


func _print() -> void:
	print("\n== ai_odds_probe pack %s, %d seeds x %d turns, skill %s%s" % [pack, seeds, turns,
		"mixed" if mixed else ("Average" if skill_all < 0 else CP.SKILL_NAMES[skill_all]), ""])
	var nb := 0
	var hashes: Array = []
	for p in pacing:
		nb += int(p["battles"])
		hashes.append(str(p["hash"]))
		print("  seed %d | battles %d | largest at 60 %d | eliminated %s" % [p["seed"], p["battles"], p["largest60"], str(p["elim"])])
	print("  hashes " + " ".join(hashes))
	var ek: Array = elim_all.keys()
	ek.sort()
	var el: Array = []
	for k in ek:
		el.append("%s %d %s" % [k, (elim_all[k] as Array).size(), str(elim_all[k])])
	print("  battles a campaign %.1f | eliminations: %s" % [float(nb) / maxi(seeds, 1), "; ".join(el)])
	var sks: Array = agg.keys()
	sks.sort()
	for sk in sks:
		var T: Dictionary = agg[sk]
		print("  -- %s (faction-turns alive %d)" % [CP.SKILL_NAMES[int(sk)], int(T["faction_turns"])])
		print("     predicted win band | battles | won | lost | no battle | mean predicted | actual won %")
		for i in BANDS.size() - 1:
			var b: Array = T["bands"][i]
			if int(b[0]) == 0:
				continue
			var fought := int(b[1]) + int(b[2])
			print("     %3d-%3d | %4d | %4d | %4d | %4d | %5.1f | %5.1f" % [BANDS[i], int(BANDS[i + 1]) - 1, b[0], b[1], b[2], b[3],
				float(b[4]) / maxi(int(b[0]), 1), 100.0 * int(b[1]) / maxi(fought, 1)])
		var kk: Array = (T["kinds"] as Dictionary).keys()
		kk.sort()
		var parts: Array = []
		for k in kk:
			var x: Array = T["kinds"][k]
			parts.append("%s %d (won %d lost %d none %d, mean %d %%)" % [k, x[0], x[1], x[2], x[3], int(x[4]) / maxi(int(x[0]), 1)])
		print("     by kind: " + ", ".join(parts))
		print("     refused %d (formula > 70 %%: %d), hunts refused %d (> 70 %%: %d) | sieges %d, taken %d, lifted %d | armies destroyed %d | field battles won %d lost %d" % [
			T["refused"], T["refused70"], T["hunt_refused"], T["hunt_refused70"], T["sieges"], T["sieges_taken"], T["sieges_lifted"],
			T["destroyed"], T["field_won"], T["field_lost"]])
	if mixed:
		for sk in [CP.AVERAGE, CP.SKILLED]:
			if h2h.has(sk):
				var x: Array = h2h[sk]
				print("  head to head %s: %d faction-seeds, regions at the end %.2f, eliminated %d" % [CP.SKILL_NAMES[sk], x[0],
					float(x[1]) / maxi(int(x[0]), 1), x[2]])
	if json_path != "":
		var jf := FileAccess.open(json_path, FileAccess.WRITE)
		jf.store_string(JSON.stringify({"pack": pack, "skill": skill_all, "mixed": mixed, "pacing": pacing, "agg": agg,
			"h2h": h2h, "elim": elim_all}))
		jf.close()
