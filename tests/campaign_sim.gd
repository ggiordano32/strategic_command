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
## reports contact battles, zone stops are not counted. Each seed also
## prints the campaign AI's competency counters (campaign/cai_profile.gd).
## --skill=easy|average|skilled sets every AI faction's campaign skill
## (settings.ai_campaign_skill); --skill-f=<faction>:easy one faction's
## (factions[f].ai_skill; <faction> a key or its first letters, e.g. rome,
## carth); repeatable. Each seed then prints, per faction with a skill set,
## its regions at turns 15 / 30 / 60, when it was eliminated and its
## mistakes, and the end table sums them over the seeds.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CRules := preload("res://campaign/crules.gd")
const CP := preload("res://campaign/cai_profile.gd")

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
		elif a.begins_with("--skill="):
			skill_all = _level(a.get_slice("=", 1))
		elif a.begins_with("--skill-f="):
			var v := a.get_slice("=", 1)
			skill_f[_faction(v.get_slice(":", 0))] = _level(v.get_slice(":", 1))
	for f in CData.FACTIONS:
		short.append(str(f["key"]).substr(0, 4))
	var ok := true
	for sd in seeds:
		var h1 := _run(sd, true)
		if twice and _run(sd, false) != h1:
			print("NOT DETERMINISTIC: seed %d" % (1000 + sd * 77))
			ok = false
	print("\npacing (format %d): seed | largest at 15 / 30 / 60 | eliminated by 60 | first win (20 regions, 3 key cities) | battles | field | ms/turn mean max" % fmt)
	for row in pacing:
		print("  " + str(row))
	if not watch.is_empty():
		print("\nfactions with a skill set: seed | faction skill | regions at 15 / 30 / 60 | eliminated at turn")
		for w in watch:
			print("  " + str(w))
	if twice:
		print("determinism (each seed twice): %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)


func _run(sd: int, verbose: bool) -> String:
	sg = {"started": 0, "assault": 0, "sally": 0, "relief": 0, "lifted": 0, "surrendered": 0, "longest": 0,
		"field_won": 0, "assault_won": 0, "field": 0, "intercepted": 0, "raided": 0}
	var largest := [0, 0, 0]
	var first_win := -1
	CP.reset_counters()
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
		for f in keys:
			w_reg[f] = [0, 0, 0]
			w_dead[f] = -1
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
		var open_now: Array = []
		for x in st.get("sieges", []):
			open_now.append("%s %d turns" % [CData.REGIONS[int(x["r"])]["city"], int(st["turn"]) - int(x["turn"])])
		print("sieges: started %d, assaulted %d (won %d), sallies %d, reliefs %d (sally/relief won by the besieged %d), lifted %d, surrendered %d, longest %d turns; open at the end: %s" % [
			int(sg["started"]), int(sg["assault"]), int(sg["assault_won"]), int(sg["sally"]), int(sg["relief"]),
			int(sg["field_won"]), int(sg["lifted"]), int(sg["surrendered"]), int(sg["longest"]), str(open_now)])
		print("free movement: field battles %d (interceptions %d), turns ending with a region raided %d" % [
			int(sg["field"]), int(sg["intercepted"]), int(sg["raided"])])
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
			watch.append("%d | %s %s | %d / %d / %d | %s" % [1000 + sd * 77, short[int(f)], CP.SKILL_NAMES[int(skill_f[f])],
				w_reg[f][0], w_reg[f][1], w_reg[f][2], str(w_dead[f]) if int(w_dead[f]) >= 0 else "-"])
		pacing.append("%d | %d / %d / %d | %d %s | %s | %d | %d | %.1f %.1f" % [1000 + sd * 77, largest[0], largest[1], largest[2],
			elim.size(), str(elim), str(first_win) if first_win >= 0 else "-", int(st["stats"]["battles"]), int(sg["field"]),
			t_total / 1000.0 / turns, t_max / 1000.0])
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
	for x in st.get("sieges", []):
		sg["longest"] = maxi(int(sg["longest"]), int(st["turn"]) - int(x["turn"]))
	for r in CData.region_count():
		if CRules.raider(st, r) >= 0:
			sg["raided"] += 1


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
