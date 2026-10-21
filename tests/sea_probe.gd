extends SceneTree
## Sea battle balance probe (sea pass 4, "the leeward fleet"; docs/STATUS.md).
##   godot --headless --script res://tests/sea_probe.gd [-- --seeds=24
##       --layouts=ns,we,gauge0,gauge1 --modes=ai,hold --rows --verbose]
## Mirrored fleets (by seed: a frigate duel; frigate + sloop a side; two
## brigantines and a sloop; galleon, frigate and sloop), the water by seed
## (open sea, an island, a coast on one or three sides), the wind about east
## (60-120 deg, 50-95 strong) as the campaign rolls it. Modes: "ai" both
## sides under the battle AI; "hold" side 0 hove to where it starts (a
## player who gives no orders) and the AI (side 1) must come to the fight;
## "order" side 0 is a player who taps the nearest enemy to engage (every
## 10 s for a ship without a target), side 1 the AI.
## Per battle: winner, time to decide, groundings per side and where (lee
## shore / weather shore / side coast / island; shoal or land), time to the
## first broadside per side, the leeward fleet (by the start positions along
## the wind) and the ground it made to windward by its first broadside,
## boardings. Summaries per mode and layout. --rows prints the points of
## sail by ship row (no-go, close-hauled course and drive, speed made good
## to windward). Also (the flight rule, 2026-10-21): ships lost (sunk +
## taken) and escaped per side, the mean battle length, the damage each
## side took (hull % + crew %) and the AI side's (1) exchange; --exch the
## exchange minute by minute; --skill=0|1|2 the AI sides' sea skill.
## Prints only; no pass / fail.

const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const FM := preload("res://sim/fixed_math.gd")

const FLEETS := [["frigate"], ["frigate", "sloop"], ["brigantine", "brigantine", "sloop"], ["galleon", "frigate", "sloop"]]
const COASTS := [[6], [2], [4], [0], [6, 7, 5], [2, 1, 3]]
const COAST_NAMES := ["N", "S", "W", "E", "N3", "S3"]
## "camp": the campaign's waters (cseabattle.gd): a coast in two battles of
## three, its layout "we" when the coast has a west or north side, else "ns".
const CAMP_COASTS := [[4], [6], [2], [0], [6, 5, 4], [2, 3, 4], [6, 7], [4, 3]]
const CAMP_NAMES := ["W", "N", "S", "E", "NW3", "SW3", "NE2", "W2"]

var seeds := 24
var layouts: Array = ["ns", "we", "gauge0", "gauge1", "camp"]
var modes: Array = ["ai", "hold"]
var verbose := false
static var swap := false   # --swap: side 1's ships listed first (an index-order check)
static var skill := -1     # --skill=0|1|2: the AI sides' sea skill (Easy / Average / Skilled; default: none given)
static var exch := false   # --exch: print the exchange by minute (the AI side's damage dealt / taken)


func _initialize() -> void:
	var rows := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--layouts="):
			layouts = Array(a.substr(10).split(","))
		elif a.begins_with("--modes="):
			modes = Array(a.substr(8).split(","))
		elif a == "--rows":
			rows = true
		elif a == "--verbose":
			verbose = true
		elif a == "--swap":
			swap = true
		elif a.begins_with("--skill="):
			skill = int(a.substr(8))
		elif a == "--exch":
			exch = true
	if rows:
		_rows()
	for mode in modes:
		for lay in layouts:
			_layout_run(str(mode), str(lay))
	quit(0)


static func scenario(sd: int, lay: String, mode: String) -> Dictionary:
	var u: Array = []
	var fl: Array = FLEETS[sd % FLEETS.size()]
	for side in 2:
		for k in fl:
			u.append({"side": (1 - side) if swap else side, "t": k})
	var land := {"kind": 0, "mseed": sd * 7919 % 100000}
	var w := sd % 3
	if lay == "camp":
		lay = "ns"
		if w == 0:
			land["kind"] = (sd / 3) % 2
		else:
			land["kind"] = 2
			var cd := 0
			for i in CAMP_COASTS[(sd / 3) % CAMP_COASTS.size()]:
				cd |= 1 << int(i)
			land["dirs"] = cd
			if (cd >> 4) & 1 != 0 or (cd >> 6) & 1 != 0:
				lay = "we"
	elif w == 1:
		land["kind"] = 1
	elif w == 2:
		land["kind"] = 2
		var dirs := 0
		for i in COASTS[(sd / 3) % COASTS.size()]:
			dirs |= 1 << int(i)
		land["dirs"] = dirs
	var wind := 90 + (sd * 53) % 61 - 30
	var wstr := 50 + (sd * 29) % 46
	var scn := {"sea": 1, "wind_deg": wind, "wind_str": wstr, "ai_sides": [1 if mode == "ai" else 0, 1], "land": land,
		"layout": lay, "units": u}
	if skill >= 0:
		scn["ai_skill"] = [skill, skill]
	return scn


static func water_name(scn: Dictionary, sd: int, lay: String) -> String:
	var land: Dictionary = scn["land"]
	match int(land["kind"]):
		1:
			return "island"
		2:
			if lay == "camp":
				return "%s %s" % [str(scn["layout"]), CAMP_NAMES[(sd / 3) % CAMP_COASTS.size()]]
			return "coast " + str(COAST_NAMES[(sd / 3) % COASTS.size()])
	return "open"


## Projection (metres) of side `side`'s fighting ships' centroid on the
## direction the wind comes from (bigger: farther to windward).
func up_proj(sim: SeaSim, side: int, w: int) -> int:
	var n := 0
	var sx := 0
	var sy := 0
	for s in sim.n_units:
		if sim.u_side[s] == side and sim.u_state[s] == SeaSim.S_SAIL:
			n += 1
			sx += sim.s_x[s] / SeaSim.U
			sy += sim.s_y[s] / SeaSim.U
	if n == 0:
		return 0
	return ((sx / n) * FM.cos_a(w) + (sy / n) * FM.sin_a(w)) >> 12


## Where ship s ran aground: the nearest blocked cell's bearing against the
## wind (lee / weather / side), island or coast, shoal or land.
func ground_kind(sim: SeaSim, s: int, scn: Dictionary) -> String:
	var best := -1
	var bd := 1 << 40
	var bx := 0
	var by := 0
	var cx := sim.s_x[s] / SeaSim.U
	var cy := sim.s_y[s] / SeaSim.U
	for dy in range(-80, 81, 10):
		for dx in range(-80, 81, 10):
			var v := sim.land_at_m(cx + dx, cy + dy)
			if v == 0 or (v == 1 and ST.stat(sim.s_type[s], "draft") == 0):
				continue
			var d := dx * dx + dy * dy
			if d < bd:
				bd = d
				best = v
				bx = dx
				by = dy
	if best < 0:
		return "?"
	var b := FM.atan2_a(by, bx)
	var down := (sim.w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
	var off := absi(FM.angle_diff(b, down))
	var rel := "side"
	if off <= 128:
		rel = "lee"
	elif off >= 384:
		rel = "weather"
	var what := "island" if int((scn["land"] as Dictionary)["kind"]) == 1 else "coast"
	return "%s %s %s" % [rel, what, "shoal" if best == 1 else "land"]


## Damage side `side` has taken: hull lost % + crew lost % summed over its
## ships (a sunk ship counts her hull and crew as at the end).
func damage(sim: SeaSim, side: int) -> int:
	var d := 0
	for s in sim.n_units:
		if sim.u_side[s] == side:
			d += (sim.s_hull0[s] - sim.s_hull[s]) * 100 / maxi(sim.s_hull0[s], 1)
			d += (sim.s_crew0[s] - sim.s_crew[s]) * 100 / maxi(sim.s_crew0[s], 1)
	return d


func run_one(sd: int, lay: String, mode: String) -> Dictionary:
	var scn := scenario(sd, lay, mode)
	var sim := SeaSim.new()
	sim.setup(scn, sd * 101 + 7)
	var w := sim.w_base
	var p0 := [up_proj(sim, 0, w), up_proj(sim, 1, w)]
	var lee := -1
	if absi(int(p0[0]) - int(p0[1])) >= 200:
		lee = 0 if int(p0[0]) < int(p0[1]) else 1
	if mode == "hold":
		for s in sim.n_units:
			if sim.u_side[s] == 0:
				sim.queue_order({"type": SeaSim.O_SAILS, "unit": s, "on": 0, "tick": 0})
	var first := [-1, -1]
	var gr := [0, 0]
	var per := PackedInt32Array()
	per.resize(sim.n_units)
	per.fill(0)
	var where: Array[String] = []
	var made := 0
	var made_max := -(1 << 30)
	var seen := 0
	var stop := -1
	var dmg_min: Array = []   # per minute: [side 0's damage, side 1's damage] (cumulative, % points)
	for t in 9200:
		if mode == "order" and t % 100 == 0 and sim.decided_tick < 0:
			_player_orders(sim)
		sim.step()
		while seen < sim.ev_n:
			var i := seen % SeaSim.EV_CAP
			seen += 1
			var k := sim.ev_k[i]
			var a := sim.ev_a[i]
			if k == SeaSim.EV_BROADSIDE:
				var sd2 := sim.u_side[a]
				if first[sd2] < 0:
					first[sd2] = sim.ev_t[i]
					if sd2 == lee:
						made = up_proj(sim, lee, w) - int(p0[lee])
			elif k == SeaSim.EV_GROUND:
				gr[sim.u_side[a]] += 1
				per[a] += 1
				where.append("s%d %s %s" % [sim.u_side[a], ST.row(sim.s_type[a])["key"], ground_kind(sim, a, scn)])
		if lee >= 0 and first[lee] < 0 and sim.decided_tick < 0:
			made_max = maxi(made_max, up_proj(sim, lee, w) - int(p0[lee]))
		if t % 600 == 599 and sim.decided_tick < 0:
			dmg_min.append([damage(sim, 0), damage(sim, 1)])
		if sim.ended != 0 and stop < 0:
			stop = t
		if stop >= 0:
			break
	if lee >= 0 and first[lee] < 0:
		made = made_max
	var r := sim.result()
	var ships := [0, 0]
	var stuck := [0, 0]
	for s in sim.n_units:
		if per[s] > 0:
			ships[sim.u_side[s]] += 1
		if per[s] >= 4:
			stuck[sim.u_side[s]] += 1
	return {"ships": ships, "stuck": stuck, "seed": sd, "water": water_name(scn, sd, lay), "fleet": "+".join(PackedStringArray(FLEETS[sd % FLEETS.size()])),
		"winner": int(r["winner"]), "dt": int(r["decided_tick"]), "first": first, "gr": gr, "where": where, "lee": lee,
		"made": made, "boardings": int(sim.stats["boardings"]), "dmg": dmg_min, "dmg_end": [damage(sim, 0), damage(sim, 1)],
		"deck": [int(sim.stats["deck_taken"]), int(sim.stats["deck_repelled"]), int(sim.stats["deck_spent"])], "sides": r["sides"], "wind": int(scn["wind_deg"])}


static func _t(ticks: int) -> String:
	if ticks < 0:
		return "-"
	return "%d:%02d" % [ticks / 600, (ticks / 10) % 60]


static func _median(a: Array) -> int:
	if a.is_empty():
		return -1
	var b := a.duplicate()
	b.sort()
	return int(b[b.size() / 2])


func _layout_run(mode: String, lay: String) -> void:
	var wins := [0, 0]
	var gr_side: Array = [[], []]
	var gr_lee: Array = []
	var fb_lee: Array = []
	var fb_wind: Array = []
	var fb_side: Array = [[], []]
	var made_lee: Array = []
	var dts: Array = []
	var never := [0, 0]
	var boards := 0
	var deck := [0, 0, 0]
	var kinds := {}
	var ships_g := [0, 0]
	var stuck_g := [0, 0]
	var lee_ships: Array = []
	var lost := [0, 0]
	var esc := [0, 0]
	var dsum := 0
	var ex_d: Array = []   # per minute: AI side (1) damage dealt, taken
	var ex_t: Array = []
	var ex_end := [0, 0]
	for m in 15:
		ex_d.append(0)
		ex_t.append(0)
	print("== mode %s layout %s" % [mode, lay])
	for sd in range(1, seeds + 1):
		var r := run_one(sd, lay, mode)
		var f: Array = r["first"]
		var g: Array = r["gr"]
		wins[int(r["winner"])] += 1
		dts.append(int(r["dt"]) if int(r["dt"]) >= 0 else 9000)
		boards += int(r["boardings"])
		dsum += int(r["dt"]) if int(r["dt"]) >= 0 else 9000
		for s in 2:
			var sdd: Dictionary = r["sides"][s]
			lost[s] += int(sdd["sunk"]) + int(sdd["taken"])
			esc[s] += int(sdd["fled"])
		var prev := [0, 0]
		var dm: Array = r["dmg"]
		for m in mini(dm.size(), 15):
			ex_d[m] = int(ex_d[m]) + int(dm[m][0]) - int(prev[0])
			ex_t[m] = int(ex_t[m]) + int(dm[m][1]) - int(prev[1])
			prev = dm[m]
		ex_end[0] += int(r["dmg_end"][0])
		ex_end[1] += int(r["dmg_end"][1])
		for k in 3:
			deck[k] += int(r["deck"][k])
		for s in 2:
			(gr_side[s] as Array).append(int(g[s]))
			if int(f[s]) >= 0:
				(fb_side[s] as Array).append(int(f[s]))
			else:
				never[s] += 1
		var lee := int(r["lee"])
		for s in 2:
			ships_g[s] += int(r["ships"][s])
			stuck_g[s] += int(r["stuck"][s])
		if lee >= 0:
			lee_ships.append(int(r["ships"][lee]))
			gr_lee.append(int(g[lee]))
			made_lee.append(int(r["made"]))
			fb_lee.append(int(f[lee]) if int(f[lee]) >= 0 else 9999)
			fb_wind.append(int(f[1 - lee]) if int(f[1 - lee]) >= 0 else 9999)
		for wtxt in r["where"]:
			var key := str(wtxt).substr(str(wtxt).find(" ", 3) + 1)
			kinds[key] = int(kinds.get(key, 0)) + 1
		if verbose:
			print("  seed %2d %-26s %-8s wind %3d  win s%d %5s  first %5s / %5s  ground %d / %d  lee %s made %4d  board %d  %s" % [
				sd, str(r["fleet"]), str(r["water"]), int(r["wind"]), int(r["winner"]), _t(int(r["dt"])), _t(int(f[0])),
				_t(int(f[1])), int(g[0]), int(g[1]), ("s%d" % lee) if lee >= 0 else "--", int(r["made"]),
				int(r["boardings"]), ", ".join(PackedStringArray(r["where"]))])
	print("  wins side 0 / 1: %d / %d   decided median %s   boardings %d (deck taken %d, thrown back %d, spent %d)" % [
		wins[0], wins[1], _t(_median(dts)), boards, deck[0], deck[1], deck[2]])
	print("  ships lost (sunk + taken) s0 %d s1 %d; escaped s0 %d s1 %d; mean battle %s; damage taken (hull %% + crew %%) s0 %d s1 %d, AI (s1) exchange %d %%" % [
		lost[0], lost[1], esc[0], esc[1], _t(dsum / maxi(seeds, 1)), ex_end[0], ex_end[1], ex_end[0] * 100 / maxi(ex_end[1], 1)])
	if exch:
		var line := "  exchange by minute (AI dealt / taken %%, battles still on):"
		for m in 15:
			if int(ex_d[m]) + int(ex_t[m]) > 0:
				line += " %d:%d" % [m + 1, int(ex_d[m]) * 100 / maxi(int(ex_t[m]), 1)]
		print(line)
	print("  groundings median s0 %d s1 %d, total s0 %d s1 %d; leeward fleet median %d" % [_median(gr_side[0]),
		_median(gr_side[1]), _sum(gr_side[0]), _sum(gr_side[1]), _median(gr_lee)])
	print("  ships grounded s0 %d s1 %d (stuck, 4+ times: s0 %d s1 %d); leeward fleet ships grounded a battle median %d, battles with any %d" % [
		ships_g[0], ships_g[1], stuck_g[0], stuck_g[1], _median(lee_ships), lee_ships.filter(func(v): return int(v) > 0).size()])
	print("  first broadside median s0 %s s1 %s (never: s0 %d s1 %d)" % [_t(_median(fb_side[0])), _t(_median(fb_side[1])),
		never[0], never[1]])
	if not fb_lee.is_empty():
		var ml := _median(fb_lee)
		var mw := _median(fb_wind)
		print("  leeward fleet first broadside median %s, windward %s (ratio %d %%); leeward made good to windward median %d m" % [
			_t(ml), _t(mw), ml * 100 / maxi(mw, 1), _median(made_lee)])
	if not kinds.is_empty():
		print("  groundings where: ", kinds)


## The "order" mode's player: every ship of side 0 without a live target
## is sent at the nearest enemy (as a tap on it would).
func _player_orders(sim: SeaSim) -> void:
	for s in sim.n_units:
		if sim.u_side[s] != 0 or sim.u_state[s] != SeaSim.S_SAIL:
			continue
		var t := sim.s_tgt[s]
		if sim.s_mode[s] == SeaSim.M_ENGAGE and t >= 0 and sim.u_state[t] == SeaSim.S_SAIL:
			continue
		var best := -1
		var bd := 1 << 40
		for e in sim.n_units:
			if sim.u_side[e] == 1 and sim.u_state[e] == SeaSim.S_SAIL:
				var d := FM.approx_len(sim.s_x[e] - sim.s_x[s], sim.s_y[e] - sim.s_y[s])
				if d < bd:
					bd = d
					best = e
		if best >= 0:
			sim.queue_order({"type": SeaSim.O_TARGET, "unit": s, "target": best})


static func _sum(a: Array) -> int:
	var n := 0
	for v in a:
		n += int(v)
	return n


## The points of sail by ship row at wind 80.
func _rows() -> void:
	var sim := SeaSim.new()
	var u: Array = []
	for i in ST.ROWS.size():
		u.append({"side": i % 2, "t": str(ST.ROWS[i]["key"]), "x": 300 + i * 200, "y": 800})
	sim.setup({"sea": 1, "wind_deg": 90, "wind_str": 80, "ai_sides": [0, 0], "units": u}, 1)
	print("| Row | No-go | Tack at | Close-hauled | Drive there | Speed m/s | Made good to windward m/s | Turn deg/s |")
	print("|---|---|---|---|---|---|---|---|")
	for s in sim.n_units:
		var ty := sim.s_type[s]
		if ST.stat(ty, "oars") != 0:
			continue
		var ch := sim._sailable(s, sim.w_from)
		var off := sim.off_wind(ch)
		var dr := sim.drive(s, ch)
		var v := ST.stat(ty, "vmax") * dr / 100 * mini(450 + 80 * 7, 1100) / 1000
		var vmg := v * FM.cos_a(off) / FM.TRIG_ONE
		print("| %s | %d deg | %d %% | %d deg | %d %% | %d.%d | %d.%d | %d |" % [ST.row(ty)["key"], ST.stat(ty, "irons"),
			ST.stat(ty, "tack"), off * 360 / 1024, dr, v / 10, v % 10, vmg / 10, vmg % 10, ST.stat(ty, "turn") / 10])
