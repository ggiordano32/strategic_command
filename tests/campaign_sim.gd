extends SceneTree
## AI-only campaign simulation (pacing and economy check).
##   godot --headless --script res://tests/campaign_sim.gd [-- --seeds=4 --turns=60 --every=5 --format=4 --no-sieges --twice]
## Every faction is AI. Reports per seed: regions per faction every N turns,
## eliminations, treasury ranges, army counts, battles and time per turn,
## the sieges (started, assaulted, sallies, reliefs, lifted, surrendered,
## the longest) and, with free movement (format 5), interceptions, raids
## and field battles; at the end a pacing table (largest faction at turns
## 15 / 30 / 60, eliminations, the first turn a faction holds 20 regions
## with 3 key cities). --format=4 plays a format 4 state (the rules before
## free movement), --no-sieges (= --format=3) the rules before sieges;
## --twice plays every seed again and compares the final hashes.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CRules := preload("res://campaign/crules.gd")

var seeds := 4
var turns := 60
var every := 5
var no_sieges := false
var fmt := 5
var twice := false
var pacing: Array = []
var sg := {}
var short: Array = []


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
	if twice:
		print("determinism (each seed twice): %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)


func _run(sd: int, verbose: bool) -> String:
	sg = {"started": 0, "assault": 0, "sally": 0, "relief": 0, "lifted": 0, "surrendered": 0, "longest": 0,
		"field_won": 0, "assault_won": 0, "field": 0, "intercepted": 0, "raided": 0}
	var largest := [0, 0, 0]
	var first_win := -1
	if true:
		var st := CState.new_campaign("sim", 1000 + sd * 77, [])
		if fmt <= 4:
			for a in st["armies"]:
				for k in ["mp", "dest", "mode", "stance", "idle"]:
					(a as Dictionary).erase(k)
			st["version"] = 4
		if no_sieges:
			st.erase("sieges")
			st["version"] = 3
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
		pacing.append("%d | %d / %d / %d | %d %s | %s | %d | %d | %.1f %.1f" % [1000 + sd * 77, largest[0], largest[1], largest[2],
			elim.size(), str(elim), str(first_win) if first_win >= 0 else "-", int(st["stats"]["battles"]), int(sg["field"]),
			t_total / 1000.0 / turns, t_max / 1000.0])
		return CState.hash_text(st)
	return ""


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
