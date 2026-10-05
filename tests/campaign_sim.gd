extends SceneTree
## AI-only campaign simulation (pacing and economy check).
##   godot --headless --script res://tests/campaign_sim.gd [-- --seeds=4 --turns=60 --every=5]
## Every faction is AI. Reports per seed: regions per faction every N turns,
## eliminations, treasury ranges, army counts, battles and time per turn.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CRules := preload("res://campaign/crules.gd")

var seeds := 4
var turns := 60
var every := 5


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--every="):
			every = int(a.get_slice("=", 1))
	var short := []
	for f in CData.FACTIONS:
		short.append(str(f["key"]).substr(0, 4))
	for sd in seeds:
		var st := CState.new_campaign("sim", 1000 + sd * 77, [])
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
			if (t + 1) % every == 0 or t == 0:
				_report(st, us)
		var elim := []
		for f in CState.nf():
			if not CState.alive(st, f):
				elim.append(short[f])
		print("eliminated: %s | treasury range %d..%d | battles %d | turn time mean %.1f ms max %.1f ms | hash %s" % [
			str(elim), tr_min, tr_max, int(st["stats"]["battles"]), t_total / 1000.0 / turns, t_max / 1000.0,
			CState.hash_text(st)])
	quit(0)


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
