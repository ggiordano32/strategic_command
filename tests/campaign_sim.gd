extends SceneTree
## AI-only campaign simulation (pacing and economy check).
##   godot --headless --script res://tests/campaign_sim.gd [-- --seeds=4 --turns=60 --every=5 --format=5 --no-sieges --twice]
## Every faction is AI. Reports per seed: regions per faction every N turns,
## eliminations, treasury ranges, army counts, battles and time per turn,
## the sieges (started, assaulted, sallies, reliefs, lifted, surrendered,
## the longest) and, with free movement (format 5), interceptions, raids
## and field battles; at the end a pacing table (largest faction at turns
## 15 / 30 / 60, eliminations, the first turn a faction holds 20 regions
## with 3 key cities). --format=5 plays a format 5 state (region hops: the
## rules before the continuous overworld), --format=4 the rules before free
## movement, --no-sieges (= --format=3) the rules before sieges; --twice
## plays every seed again and compares the final hashes. Format 6 also
## reports contact battles, zone stops are not counted, and the moves
## refused as "mustering" (an army taking recruits that turn). Each seed also
## prints the campaign AI's competency counters (campaign/cai_profile.gd).
## --skill=easy|average|skilled sets every AI faction's campaign skill
## (settings.ai_campaign_skill); --skill-f=<faction>:easy one faction's
## (factions[f].ai_skill; <faction> a key or its first letters, e.g. rome,
## carth); repeatable. Each seed then prints, per faction with a skill set,
## its regions at turns 15 / 30 / 60, when it was eliminated and its
## mistakes, and the end table sums them over the seeds.
## --knob=LEVEL:ID=VALUE (e.g. --knob=s:85=0) overrides one knob of a level
## for the run (ablations; repeatable). --no-beasts: the AI recruits none of
## the lines added since the step-4 goldens, recruited only through the
## mixes (CAI.BEAST_LINES: camels, camel archers, elephants, light horse,
## slingers, generals; CAI.no_beasts). --no-generals: the starting armies
## have no generals and the AI recruits none (CData.no_generals); --old-mp:
## armies march at the pace counted before 2026-10-09 (only CLS_CAV as
## cavalry; CData.old_mp). Both together play as before the general.
## --no-dogs: the AI recruits no war dogs (mix weight 0; CData.no_dogs).
## --no-light-art: nor scorpions or gastraphetes (CData.no_light_art).
## --no-buildup: no military build-up or wagons (CAI.no_buildup).
## Each seed also prints the build-up (docs/AI.md 23): per faction alive at
## the end its regions, best Workshop / Range / Barracks / Stables level,
## wagons, scorpions, gastraphetes, light horse and missile units with a
## special ammunition kind in its armies, and the buildings finished per
## chain; the end table sums them per faction, with how many factions of 4+
## regions at turn 40 had a Range 2 and a Workshop 1.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CRules := preload("res://campaign/crules.gd")
const CP := preload("res://campaign/cai_profile.gd")
const CAI := preload("res://campaign/cai.gd")
const UT := preload("res://sim/unit_types.gd")

var seeds := 4
var turns := 60
var every := 5
var no_sieges := false
var fmt := 6
var twice := false
var pacing: Array = []
var sg := {}
var short: Array = []
var skill_all := -1           # --skill=: campaign skill of every AI faction (-1 not set)
var skill_f := {}             # --skill-f=: faction -> campaign skill
var watch: Array = []         # [faction, [regions at 15, 30, 60], eliminated at turn] per seed
var knobs: Array = []         # --knob=: [level, knob id, value]
var dg := {}                  # watched faction -> battle / capture tallies (this seed)
var dg_all := {}              # the same summed over the seeds, per watched faction
var bu_all := {}              # faction -> build-up sums over the seeds (_buildup)
var built := []               # buildings finished per chain (this seed)
var at40 := [0, 0, 0]         # over the seeds: factions with 4+ regions at turn 40, with a Range 2, with a Workshop 1
const DG_KEYS: Array[String] = ["field_att_won", "field_att_lost", "field_def_won", "field_def_lost", "town_att_won",
	"town_att_lost", "town_def_won", "town_def_lost", "siege_fights_won", "siege_fights_lost", "gained", "gained_surrender",
	"lost", "lost_surrender", "lost_within_3_turns_of_taking", "armies_destroyed"]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--every="):
			every = int(a.get_slice("=", 1))
		elif a == "--no-sieges":
			no_sieges = true
			fmt = 3
		elif a.begins_with("--format="):
			fmt = int(a.get_slice("=", 1))
			no_sieges = fmt <= 3
		elif a == "--twice":
			twice = true
		elif a == "--no-beasts":
			CAI.no_beasts = true  # (the AI recruits none of CAI.BEAST_LINES)
		elif a == "--no-buildup":
			CAI.no_buildup = true  # (no military build-up or wagons; docs/AI.md 23)
		elif a == "--no-generals":
			CData.no_generals = true  # (no starting generals, none recruited)
		elif a == "--no-dogs":
			CData.no_dogs = true  # (war dogs at mix weight 0)
		elif a == "--no-light-art":
			CData.no_light_art = true  # (scorpions / gastraphetes at mix weight 0)
		elif a == "--old-mp":
			CData.old_mp = true  # (light horse / camel archers at the foot's pace)
		elif a.begins_with("--skill="):
			skill_all = _level(a.get_slice("=", 1))
		elif a.begins_with("--skill-f="):
			var v := a.get_slice("=", 1)
			skill_f[_faction(v.get_slice(":", 0))] = _level(v.get_slice(":", 1))
		elif a.begins_with("--knob="):
			# --knob=LEVEL:ID=VALUE: override one campaign AI knob for the run.
			var v := a.substr(7)
			var lk := v.get_slice("=", 0)
			knobs.append([_level(lk.get_slice(":", 0)), int(lk.get_slice(":", 1)), int(v.get_slice("=", 1))])
	for f in CData.FACTIONS:
		short.append(str(f["key"]).substr(0, 4))
	for kv in knobs:
		CP.set_knob(int(kv[0]), int(kv[1]), int(kv[2]))
	var ok := true
	for sd in seeds:
		var h1 := _run(sd, true)
		if twice and _run(sd, false) != h1:
			print("NOT DETERMINISTIC: seed %d" % (1000 + sd * 77))
			ok = false
	print("\npacing (format %d): seed | largest at 15 / 30 / 60 | eliminated by 60 | first win (20 regions, 3 key cities) | battles | field | mustering refusals | ms/turn mean max" % fmt)
	for row in pacing:
		print("  " + str(row))
	if not watch.is_empty():
		print("\nfactions with a skill set: seed | faction skill | regions at 15 / 30 / 60 | eliminated at turn")
		for w in watch:
			print("  " + str(w))
		var fk: Array = dg_all.keys()
		fk.sort()
		for f in fk:
			var parts: Array = []
			for key in DG_KEYS:
				parts.append("%s %d" % [key, int(dg_all[f].get(key, 0))])
			print("battles and captures of %s over the seeds: %s" % [short[int(f)], ", ".join(parts)])
	print("\nbuild-up over the seeds (alive at the end): faction | seeds alive | regions | best W / R / B / S summed | W1+ R2+ seeds | wagons scorpions gastraphetes light-horse kind-units")
	for f in CData.FACTIONS.size():
		if bu_all.has(f):
			var b: Array = bu_all[f]
			print("  %s | %d | %d | %d / %d / %d / %d | %d %d | %d %d %d %d %d" % [short[f], b[0], b[1], b[2], b[3], b[4], b[5],
				b[6], b[7], b[8], b[9], b[10], b[11], b[12]])
	print("turn 40: factions with 4+ regions %d, with a Range 2 %d, with a Workshop 1 %d" % at40)
	if twice:
		print("determinism (each seed twice): %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)


func _run(sd: int, verbose: bool) -> String:
	sg = {"started": 0, "assault": 0, "sally": 0, "relief": 0, "lifted": 0, "surrendered": 0, "longest": 0,
		"field_won": 0, "assault_won": 0, "field": 0, "intercepted": 0, "raided": 0, "mustering": 0}
	var largest := [0, 0, 0]
	var first_win := -1
	CP.reset_counters()
	built = []
	for c in CData.CHAINS.size():
		built.append(0)
	if true:
		var settings := {}
		if skill_all >= 0:
			settings["ai_campaign_skill"] = skill_all
		var st := CState.new_campaign("sim", 1000 + sd * 77, [], settings)
		var keys: Array = skill_f.keys()
		keys.sort()
		for f in keys:
			st["factions"][int(f)]["ai_skill"] = int(skill_f[f])
		var w_reg := {}  # faction -> regions at 15 / 30 / 60
		var w_dead := {}  # faction -> turn eliminated
		dg = {}
		for f in keys:
			w_reg[f] = [0, 0, 0]
			w_dead[f] = -1
			dg[int(f)] = {}
		if fmt < CState.VERSION:
			st = CState.as_format(st, fmt)
		if verbose:
			print("\n=== seed %d" % (1000 + sd * 77))
			print("turn  " + "  ".join(short) + "  indep | armies units | treasury min..max | battles | wars | ms/turn")
		var tr_min := 1 << 30
		var tr_max := -(1 << 30)
		var t_total := 0
		var t_max := 0
		for t in turns:
			var t0 := Time.get_ticks_usec()
			st = CTurn.resolve_turn(st, [])
			var us := Time.get_ticks_usec() - t0
			t_total += us
			t_max = maxi(t_max, us)
			for f in CState.nf():
				if CState.alive(st, f):
					tr_min = mini(tr_min, int(st["factions"][f]["treasury"]))
					tr_max = maxi(tr_max, int(st["factions"][f]["treasury"]))
			_count_sieges(st, t)
			_tally(st, t)
			var big := 0
			for f in CState.nf():
				var n := CState.regions_of(st, f).size()
				big = maxi(big, n)
				if first_win < 0 and n >= 20:
					var caps := 0
					for r in CState.regions_of(st, f):
						if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])):
							caps += 1
					if caps >= 3:
						first_win = int(st["turn"])
			for k in 3:
				if int(st["turn"]) == [15, 30, 60][k]:
					largest[k] = big
					for f in keys:
						w_reg[f][k] = CState.regions_of(st, int(f)).size()
			if verbose and int(st["turn"]) == 40:
				for f in CState.nf():
					if CState.alive(st, f) and CState.regions_of(st, f).size() >= 4:
						at40[0] += 1
						at40[1] += 1 if _best(st, f, CData.RANGE) >= 2 else 0
						at40[2] += 1 if _best(st, f, CData.WORKSHOP) >= 1 else 0
			for f in keys:
				if int(w_dead[f]) < 0 and not CState.alive(st, int(f)):
					w_dead[f] = int(st["turn"])
			if verbose and ((t + 1) % every == 0 or t == 0):
				_report(st, us)
		var elim := []
		for f in CState.nf():
			if not CState.alive(st, f):
				elim.append(short[f])
		if not verbose:
			return CState.hash_text(st)
		print("eliminated: %s | treasury range %d..%d | battles %d | turn time mean %.1f ms max %.1f ms | hash %s" % [
			str(elim), tr_min, tr_max, int(st["stats"]["battles"]), t_total / 1000.0 / turns, t_max / 1000.0,
			CState.hash_text(st)])
		_buildup(st)
		var open_now: Array = []
		for x in st.get("sieges", []):
			open_now.append("%s %d turns" % [CData.REGIONS[int(x["r"])]["city"], int(st["turn"]) - int(x["turn"])])
		print("sieges: started %d, assaulted %d (won %d), sallies %d, reliefs %d (sally/relief won by the besieged %d), lifted %d, surrendered %d, longest %d turns; open at the end: %s" % [
			int(sg["started"]), int(sg["assault"]), int(sg["assault_won"]), int(sg["sally"]), int(sg["relief"]),
			int(sg["field_won"]), int(sg["lifted"]), int(sg["surrendered"]), int(sg["longest"]), str(open_now)])
		print("free movement: field battles %d (interceptions %d), turns ending with a region raided %d, moves refused as mustering %d" % [
			int(sg["field"]), int(sg["intercepted"]), int(sg["raided"]), int(sg["mustering"])])
		var ct := CP.totals()
		print("AI counters (docs/AI.md 6, all factions): attacks at bad odds %d, threatened cities left empty %d, faction-turns at war on two fronts %d, armies trickled in %d" % [
			ct[0], ct[1], ct[2], ct[3]])
		print("AI mistakes (all factions): city left empty %d, attack at bad odds %d, over-recruiting %d, unwise war %d, conquest not garrisoned %d" % [
			ct[4], ct[5], ct[6], ct[7], ct[8]])
		for f in keys:
			var mk: Array = []
			for key in CP.COUNTER_KEYS:
				mk.append("%s %d" % [key, CP.counter(key, int(f))])
			print("%s (%s): regions at 15 / 30 / 60: %s, eliminated at %s | %s" % [short[int(f)], CP.SKILL_NAMES[int(skill_f[f])],
				str(w_reg[f]), str(w_dead[f]) if int(w_dead[f]) >= 0 else "-", ", ".join(mk)])
			if not dg_all.has(int(f)):
				dg_all[int(f)] = {}
			for key in DG_KEYS:
				dg_all[int(f)][key] = int(dg_all[int(f)].get(key, 0)) + int(dg[int(f)].get(key, 0))
			watch.append("%d | %s %s | %d / %d / %d | %s" % [1000 + sd * 77, short[int(f)], CP.SKILL_NAMES[int(skill_f[f])],
				w_reg[f][0], w_reg[f][1], w_reg[f][2], str(w_dead[f]) if int(w_dead[f]) >= 0 else "-"])
		pacing.append("%d | %d / %d / %d | %d %s | %s | %d | %d | %d | %.1f %.1f" % [1000 + sd * 77, largest[0], largest[1], largest[2],
			elim.size(), str(elim), str(first_win) if first_win >= 0 else "-", int(st["stats"]["battles"]), int(sg["field"]),
			int(sg["mustering"]), t_total / 1000.0 / turns, t_max / 1000.0])
		return CState.hash_text(st)
	return ""


## "easy" / "average" / "skilled" (or 0 / 1 / 2) to a skill level.
static func _level(v: String) -> int:
	match v.to_lower().substr(0, 1):
		"e", "0":
			return CP.EASY
		"s", "2":
			return CP.SKILLED
	return CP.AVERAGE


## A faction index by its key or the first letters of it (-1 none).
static func _faction(v: String) -> int:
	for f in CData.FACTIONS.size():
		if str(CData.FACTIONS[f]["key"]).begins_with(v.to_lower()):
			return f
	push_error("campaign_sim: no faction %s" % v)
	return 0


## Battles and captures of the watched factions in the turn just resolved
## (events of turn t).
func _tally(st: Dictionary, t: int) -> void:
	for e in st["events"]:
		if int(e["turn"]) != t:
			continue
		var k := str(e["k"])
		for f in dg:
			var d: Dictionary = dg[f]
			if k == "battle":
				var side := 0 if (e["att"] as Array).has(int(f)) else (1 if (e["def"] as Array).has(int(f)) else -1)
				if side < 0:
					continue
				var won := int(e["winner"]) == side
				var kind := str(e.get("kind", ""))
				var cat := "town" if kind == "assault" or kind == "" else ("field" if kind == "field" else "siege_fights")
				var key := cat + ("_" if cat == "siege_fights" else ("_att_" if side == 0 else "_def_")) + ("won" if won else "lost")
				d[key] = int(d.get(key, 0)) + 1
			elif k == "captured":
				var sur := str(e.get("how", "")) == "surrendered"
				if int(e["f"]) == int(f):
					d["gained"] = int(d.get("gained", 0)) + 1
					if sur:
						d["gained_surrender"] = int(d.get("gained_surrender", 0)) + 1
					d["took_%d" % int(e["r"])] = t
				elif int(e.get("from", -1)) == int(f):
					d["lost"] = int(d.get("lost", 0)) + 1
					if t - int(d.get("took_%d" % int(e["r"]), -100)) <= 3:
						d["lost_within_3_turns_of_taking"] = int(d.get("lost_within_3_turns_of_taking", 0)) + 1
					if sur:
						d["lost_surrender"] = int(d.get("lost_surrender", 0)) + 1
			elif k == "destroyed" and int(e["f"]) == int(f):
				d["armies_destroyed"] = int(d.get("armies_destroyed", 0)) + 1


## Siege events of the turn just resolved (turn t; events carry the turn they
## happened in).
func _count_sieges(st: Dictionary, t: int) -> void:
	for e in st["events"]:
		if int(e["turn"]) != t:
			continue
		match str(e["k"]):
			"siege":
				sg["started"] += 1
			"siege_lifted":
				sg["lifted"] += 1
			"captured":
				if str(e.get("how", "")) == "surrendered":
					sg["surrendered"] += 1
			"battle":
				var kind := str(e.get("kind", ""))
				if kind == "assault":
					sg["assault"] += 1
					if int(e["winner"]) == 0:
						sg["assault_won"] += 1
				elif kind == "sally" or kind == "relief":
					sg[kind] += 1
					if int(e["winner"]) == 1:
						sg["field_won"] += 1
				elif kind == "field":
					sg["field"] += 1
			"intercepted":
				sg["intercepted"] += 1
			"built":
				built[int(e["chain"])] += 1
			"move_failed":
				if str(e.get("why", "")) == "mustering":
					sg["mustering"] += 1
	for x in st.get("sieges", []):
		sg["longest"] = maxi(int(sg["longest"]), int(st["turn"]) - int(x["turn"]))
	for r in CData.region_count():
		if CRules.raider(st, r) >= 0:
			sg["raided"] += 1


## Best level of chain c in any region of faction f.
static func _best(st: Dictionary, f: int, c: int) -> int:
	var b := 0
	for r in CState.regions_of(st, f):
		b = maxi(b, CState.building(st, r, c))
	return b


## The build-up at the end of a seed (per faction alive) and the buildings
## finished per chain; summed into bu_all.
func _buildup(st: Dictionary) -> void:
	var parts: Array = []
	for c in CData.CHAINS.size():
		parts.append("%s %d" % [CData.CHAINS[c]["key"], int(built[c])])
	print("buildings finished: " + ", ".join(parts))
	for f in CState.nf():
		if not CState.alive(st, f):
			continue
		var n := [0, 0, 0, 0, 0]  # wagons, scorpions, gastraphetes, light horse, missile units with a kind
		for a in CState.armies_of(st, f):
			for u in a["units"]:
				var ty := CState.unit_type(u)
				var line := UT.line_of(ty)
				if UT.stat(ty, "wagon") >= 0:
					n[0] += 1
				if line == "light_art":
					n[1] += 1
				if line == "belly_bow":
					n[2] += 1
				if line == "cav_missile":
					n[3] += 1
				if str(u.get("ak", "")) != "":
					n[4] += 1
		var lv := [_best(st, f, CData.WORKSHOP), _best(st, f, CData.RANGE), _best(st, f, CData.BARRACKS), _best(st, f, CData.STABLES)]
		var nr := CState.regions_of(st, f).size()
		print("  %s: regions %d | best W %d R %d B %d S %d | wagons %d scorpions %d gastraphetes %d light horse %d kind units %d" % [
			short[f], nr, lv[0], lv[1], lv[2], lv[3], n[0], n[1], n[2], n[3], n[4]])
		if not bu_all.has(f):
			bu_all[f] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		var b: Array = bu_all[f]
		var add := [1, nr, lv[0], lv[1], lv[2], lv[3], 1 if lv[0] >= 1 else 0, 1 if lv[1] >= 2 else 0,
			n[0], n[1], n[2], n[3], n[4]]
		for k in add.size():
			b[k] += int(add[k])


func _report(st: Dictionary, us: int) -> void:
	var line := "%4d  " % int(st["turn"])
	var indep := 0
	for r in CData.region_count():
		if CState.owner(st, r) < 0:
			indep += 1
	var cells := []
	for f in CState.nf():
		cells.append("%4d" % CState.regions_of(st, f).size())
	line += "  ".join(cells) + "  %5d" % indep
	var na := (st["armies"] as Array).size()
	var nu := 0
	for a in st["armies"]:
		nu += CState.unit_count(a)
	var tmin := 1 << 30
	var tmax := -(1 << 30)
	for f in CState.nf():
		if CState.alive(st, f):
			tmin = mini(tmin, int(st["factions"][f]["treasury"]))
			tmax = maxi(tmax, int(st["factions"][f]["treasury"]))
	var wars := 0
	for a in CState.nf():
		for b in range(a + 1, CState.nf()):
			if CState.alive(st, a) and CState.alive(st, b) and CState.dip(st, a, b) == CState.WAR:
				wars += 1
	line += " | %6d %5d | %6d..%6d | %6d | %4d | %.1f" % [na, nu, tmin, tmax, int(st["stats"]["battles"]), wars, us / 1000.0]
	print(line)
