extends SceneTree
## AI-only campaign simulation (pacing and economy check).
##   godot --headless --script res://tests/campaign_sim.gd [-- --seeds=4 --turns=60 --every=5 --format=5 --no-sieges --twice --pack=west]
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
## --no-water: amphibious armies plan by the land fields only (CAI.no_water).
## --seed0=N: start at seed index N (seeds 1000 + 77 n; shards a long run).
## --trace-faction=KEY: per turn, that faction's wars, peace, trade, alliances,
## calls, cities gained and lost, and a status line (regions, treasury, armies,
## strength, repute, each enemy's strength / bloc strength, allies; docs/AI.md
## 41). --ai-alliances=0|1: the creation setting ai_alliances (format 10).
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
const CChars := preload("res://campaign/cchars.gd")
const CAI := preload("res://campaign/cai.gd")
const CDip := preload("res://campaign/cdip.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const UT := preload("res://sim/unit_types.gd")

var seeds := 4
var seed0 := 0               # --seed0=N: the first seed index (shards a long run: seeds 1000 + 77 n for n in seed0 .. seed0 + seeds - 1)
var turns := 60
var every := 5
var no_sieges := false
var fmt := 6
var twice := false
var pack := "rome"             # --pack=west: the content pack played (CData.use_pack)
var pacing: Array = []
var sg := {}
var short: Array = []
var skill_all := -1           # --skill=: campaign skill of every AI faction (-1 not set)
var skill_f := {}             # --skill-f=: faction -> campaign skill
var watch: Array = []         # [faction, [regions at 15, 30, 60], eliminated at turn] per seed
var knobs: Array = []         # --knob=: [level, knob id, value]
var dg := {}                  # watched faction -> battle / capture tallies (this seed)
var dg_all := {}              # the same summed over the seeds, per watched faction
var ship_kinds := {}          # "faction:ship" -> ships launched this seed (the SHIPS_JSON line)
var bu_all := {}              # faction -> build-up sums over the seeds (_buildup)
var built := []               # buildings finished per chain (this seed)
var char_ev := {}             # heroes and agents (this seed): raised / wounded / captured / ransom gold
var elim_all := {}
var land_all := {}            # faction key -> [landings, units landed (the army's units at the end of its turn)] over the seeds
var sea_bat_all := 0          # sea battles over the seeds
const TIER_COUNT := ["native_warriors", "native_warriors2", "canoe_raiders", "canoe_raiders2", "maroons", "maroon_vets", "holcan"]
var tier_all := {}            # "faction:unit key" -> recruits over the seeds (the tribes' tier rows; docs/design/battle_sim.md "The tribes' tier-2 rows")            # faction -> turns it was eliminated, over the seeds
var trace := -1              # --trace-faction=KEY: print that faction's diplomacy, losses and treasury per turn
var ai_alliances := -1
var vetm := {}               # this seed's veterancy tallies (the --json line's "vet"): units by level per faction at turns 30 and 60, retrains; and its end ("end": eliminated turn per faction, battles, field)
var bldm := {}               # (2026-11-09, docs/AI.md 76) this seed's build order and roster (the --json line's "bld"): best chain levels per faction at turns 20 / 40 / 60, recruits per unit row, the first turn each roster row's buildings stood in a region of the faction, retrains, the siege-guns counters
var rtm := {}                # (2026-11-09, the overland retreat) this seed's retreats in the --json line "rt": by how (land, far, fleet, held; "sea" an old-rule retreat that changed landmass), destroyed, army-turns with the cell outside the region ("mismatch"), army-turns on a landmass where the faction owns nothing and no own fleet is beside ("stranded"), the longest such run
var dipm := {}               # this seed's diplomacy tallies (wars, calls, alliances, trust gains), in the --json line
var lanem := {}              # (2026-11-09, lanes trade by agreement) this seed's lane trade (the --json line's "lane"): per faction key [lane income, total income, turns alive, lane income from ports of another owner at peace without a treaty (paid), its potential (the halves), paying lanes] summed over the turns; trade agreements and alliances standing at turns 20 / 40 / 60; trade agreements made and ended; the AI's trade proposals and acceptances (CP counters)
var _tr_allies: Array = []   # trace: the traced faction's allies at the end of the last turn
var _tr_landed := {}         # trace: "f:r" -> turn of the last landing (a fleet's army put ashore) there
var _trace_key := ""        # --ai-alliances=0|1: the creation setting (format 10; -1 the default)
var at40 := [0, 0, 0]         # over the seeds: factions with 4+ regions at turn 40, with a Range 2, with a Workshop 1
const DG_KEYS: Array[String] = ["field_att_won", "field_att_lost", "field_def_won", "field_def_lost", "town_att_won",
	"town_att_lost", "town_def_won", "town_def_lost", "siege_fights_won", "siege_fights_lost", "gained", "gained_surrender",
	"lost", "lost_surrender", "lost_within_3_turns_of_taking", "armies_destroyed"]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--seed0="):
			seed0 = int(a.get_slice("=", 1))
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
		elif a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a == "--twice":
			twice = true
		elif a == "--lanes-at-peace":
			CLanes.at_peace = true  # (2026-11-09 ablation) the lanes pay at mere peace and the AI seeks no lane treaty: as before lanes traded by agreement
			for lv in 3:
				for kk in [CP.LANE_TREATY_MIN, CP.LANE_TREATY_ASK, CP.LANE_TREATY_TRUST]:
					knobs.append([lv, kk, 0])
		elif a == "--no-beasts":
			CAI.no_beasts = true  # (the AI recruits none of CAI.BEAST_LINES)
		elif a == "--no-buildup":
			CAI.no_buildup = true  # (no military build-up or wagons; docs/AI.md 23)
		elif a == "--no-water":
			CAI.no_water = true  # (amphibious armies plan by the land fields only; docs/AI.md 34)
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
		elif a.begins_with("--trace-faction="):
			_trace_key = a.get_slice("=", 1)
		elif a.begins_with("--ai-alliances="):
			ai_alliances = int(a.get_slice("=", 1))
		elif a.begins_with("--knob="):
			# --knob=LEVEL:ID=VALUE: override one campaign AI knob for the run.
			var v := a.substr(7)
			var lk := v.get_slice("=", 0)
			knobs.append([_level(lk.get_slice(":", 0)), int(lk.get_slice(":", 1)), int(v.get_slice("=", 1))])
	CData.use_pack(pack)
	if _trace_key != "":
		trace = _faction(_trace_key)
	for f in CData.FACTIONS:
		short.append(str(f["key"]).substr(0, 4))
	for kv in knobs:
		CP.set_knob(int(kv[0]), int(kv[1]), int(kv[2]))
	var ok := true
	var jf: FileAccess = null  # --json=PATH: one JSON line a seed with its final state hash (tools/balance), default off
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			jf = FileAccess.open(a.substr(7), FileAccess.WRITE)
	for sd in range(seed0, seed0 + seeds):
		var h1 := _run(sd, true)
		if jf != null:
			jf.store_line(JSON.stringify({"probe": "campaign_sim", "pack": pack, "seed": 1000 + sd * 77, "hash": h1, "fmt": fmt, "dip": dipm, "vet": vetm, "bld": bldm, "lane": lanem, "rt": rtm}))
			jf.flush()
		if twice and _run(sd, false) != h1:
			print("NOT DETERMINISTIC: seed %d" % (1000 + sd * 77))
			ok = false
	print("\npacing (format %d): seed | largest at 15 / 30 / 60 | eliminated by 60 | first win (20 regions, 3 key cities) | battles | field | mustering refusals | ms/turn mean max" % fmt)
	for row in pacing:
		print("  " + str(row))
	var tks: Array = tier_all.keys()
	tks.sort()
	print("\nrecruits of the tribes' lines over the seeds (faction:unit n): " + ", ".join(tks.map(func(k): return "%s %d" % [k, int(tier_all[k])])))
	var lks: Array = land_all.keys()
	lks.sort()
	print("\nLANDINGS_JSON " + JSON.stringify({"sea_battles": sea_bat_all, "landings": lks.map(func(k): return [k, land_all[k][0], land_all[k][1]])}))
	print("\nsurvival over the seeds: faction | eliminated in N of %d seeds | at turns (sorted)" % seeds)
	for f in CState.nf():
		var ts: Array = elim_all.get(f, [])
		ts.sort()
		print("  %s | %d | %s" % [short[f], ts.size(), str(ts)])
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


## (2026-11-09, docs/AI.md 76) The build order and the roster, per turn t (bldm): each faction's recruits per unit
## row ("recruited" events) and retrains ("retrained": "from>to"); the first turn every roster row's buildings (CRules.needs
## and UNIT_NEEDS, and a treaty line's treaty) stood in a region of the faction; and at turns 20 / 40 / 60 each faction
## alive's best level of every chain. A summary, never state.
func _build_tally(st: Dictionary, t: int) -> void:
	for e in st["events"]:
		if int(e["turn"]) != t or (str(e["k"]) != "recruited" and str(e["k"]) != "retrained") or int(e.get("f", -1)) < 0:
			continue
		var fk := str(CData.FACTIONS[int(e["f"])]["key"])
		if str(e["k"]) == "recruited":
			if not bldm["rec"].has(fk):
				bldm["rec"][fk] = {}
			for uk in e["units"]:
				bldm["rec"][fk][str(uk)] = int(bldm["rec"][fk].get(str(uk), 0)) + 1
		elif str(e["k"]) == "retrained":
			if not bldm["ret"].has(fk):
				bldm["ret"][fk] = {}
			var rk := "%s>%s" % [str(e["from"]), str(e["t"])]
			bldm["ret"][fk][rk] = int(bldm["ret"][fk].get(rk, 0)) + 1
	for f in CState.nf():
		if not CState.alive(st, f):
			continue
		var fk := str(CData.FACTIONS[f]["key"])
		if not bldm["avail"].has(fk):
			bldm["avail"][fk] = {}
		var av: Dictionary = bldm["avail"][fk]
		var ro: Dictionary = CData.roster(f)
		for line in CData.LINE_ORDER:
			if not ro.has(line):
				continue
			for key in ro[line]:
				var k := str(key)
				if k == "" or av.has(k) or CDip.line_why(st, f, line) != "":
					continue
				for r in CState.regions_of(st, f):
					if CAI._has_buildings(st, r, k):
						av[k] = int(st["turn"])
						break
		if [20, 40, 60].has(int(st["turn"])):
			var tk := "t%d" % int(st["turn"])
			if not bldm["lv"].has(tk):
				bldm["lv"][tk] = {}
			var lv: Array = []
			for c in CData.CHAINS.size():
				lv.append(_best(st, f, c))
			bldm["lv"][tk][fk] = lv


## (2026-11-09, lanes trade by agreement) The lane trade of the turn just resolved (turn t; lanem): per faction alive
## its lane income and total income (CRules.income), the lane income its ports draw from a port of another owner at
## mere peace (dip PEACE, not one team: paid before the rule, nothing after) and that income's potential (the lane's
## halves), its paying lanes; the trade agreements and alliances standing at turns 20 / 40 / 60; agreements made and
## ended this turn; per faction key (fx) its trade partners and allies at turns 20 / 40 / 60, the wars declared on
## it and by it, its regions at turn 60; every war [by, on, turn, why]; lane raids "raider>owner" (the lane_raided rows, each
## end owner); per faction [lane gold lost to raids, blockades and sieges, its raiders' take, lanes it raids] summed
## over the turns. A summary, never state.
func _lane_tally(st: Dictionary, t: int) -> void:
	for e in st["events"]:
		if int(e["turn"]) != t:
			continue
		if str(e["k"]) == "war" and int(e.get("a", -1)) >= 0 and int(e.get("b", -1)) >= 0:
			lanem["wars"].append([str(CData.FACTIONS[int(e["a"])]["key"]), str(CData.FACTIONS[int(e["b"])]["key"]), t + 1, str(e.get("why", ""))])
			for side in 2:
				var wk := str(CData.FACTIONS[int(e["b" if side == 0 else "a"])]["key"])
				var wx: Array = lanem["fx"].get(wk, [0, 0, 0, 0, 0, 0])
				wx[3 + side] = int(wx[3 + side]) + 1
				lanem["fx"][wk] = wx
		if str(e["k"]) == "trade":
			lanem["trade_made"] = int(lanem["trade_made"]) + 1
		if str(e["k"]) == "lane_raided":
			for side in ["from", "to"]:
				if int(e.get(side, -1)) >= 0 and int(e["f"]) >= 0:
					var rk := "%s>%s" % [str(CData.FACTIONS[int(e["f"])]["key"]), str(CData.FACTIONS[int(e[side])]["key"])]
					lanem["raids"][rk] = int(lanem["raids"].get(rk, 0)) + 1
		elif str(e["k"]) == "trade_end":
			lanem["trade_end"] = int(lanem["trade_end"]) + 1
	var n := CState.nf()
	var peace_paid: Array = []
	var peace_pot: Array = []
	for f in n:
		peace_paid.append(0)
		peace_pot.append(0)
	if CState.grid_on(st) and not CData.SEA_LANES.is_empty():
		var rt := CLanes.raiders(st)
		for id in CLanes.count():
			var ls := CLanes.lane_state(st, id, rt)
			var oa := int(ls["oa"])
			var ob := int(ls["ob"])
			if oa < 0 or ob < 0 or oa == ob or CState.same_team(st, oa, ob) or CState.dip(st, oa, ob) != CState.PEACE:
				continue
			var v := int(ls["v"])
			peace_paid[oa] = int(peace_paid[oa]) + int(ls["pa"])
			peace_paid[ob] = int(peace_paid[ob]) + int(ls["pb"])
			peace_pot[oa] = int(peace_pot[oa]) + v / 2
			peace_pot[ob] = int(peace_pot[ob]) + v - v / 2
	for f in n:
		if not CState.alive(st, f):
			continue
		var fk := str(CData.FACTIONS[f]["key"])
		var inc := CRules.income(st, f)
		var row: Array = lanem["f"].get(fk, [0, 0, 0, 0, 0, 0])
		row[0] = int(row[0]) + int(inc.get("lanes", 0))
		row[1] = int(row[1]) + int(inc["total"])
		row[2] = int(row[2]) + 1
		row[3] = int(row[3]) + int(peace_paid[f])
		row[4] = int(row[4]) + int(peace_pot[f])
		row[5] = int(row[5]) + int(inc.get("lanes_n", 0))
		lanem["f"][fk] = row
		var lr: Array = lanem["lost"].get(fk, [0, 0, 0])
		lr[0] = int(lr[0]) + int(inc.get("lanes_lost", 0))
		lr[1] = int(lr[1]) + int(inc.get("lane_take", 0))
		lr[2] = int(lr[2]) + int(inc.get("lane_raided", 0))
		lanem["lost"][fk] = lr
	var tix := [20, 40, 60].find(int(st["turn"]))
	if tix >= 0:
		for f in n:
			if not CState.alive(st, f):
				continue
			var fk2 := str(CData.FACTIONS[f]["key"])
			var fx: Array = lanem["fx"].get(fk2, [0, 0, 0, 0, 0, 0])
			for g in n:
				if g != f and CState.alive(st, g) and not CState.same_team(st, f, g) and CState.dip(st, f, g) >= CState.TRADE:
					fx[tix] = int(fx[tix]) + 1
			if tix == 2:
				fx[5] = CState.regions_of(st, f).size()
			lanem["fx"][fk2] = fx
		for f in n:
			for g in range(f + 1, n):
				if not CState.alive(st, f) or not CState.alive(st, g) or CState.same_team(st, f, g):
					continue
				var d := CState.dip(st, f, g)
				if d == CState.TRADE:
					lanem["trade_t"][tix] = int(lanem["trade_t"][tix]) + 1
				elif d == CState.ALLIED:
					lanem["allied_t"][tix] = int(lanem["allied_t"][tix]) + 1


## Veterancy: per faction key, its army units by level [0, 1, 2, 3] (xp 300 / 700 / 1,200; read inline so the
## script runs on a build without veterancy too).
func _vet_hist(st: Dictionary) -> Dictionary:
	var out := {}
	for a in st["armies"]:
		var f := int(a["f"])
		if f < 0:
			continue
		var k := str(CData.FACTIONS[f]["key"])
		if not out.has(k):
			out[k] = [0, 0, 0, 0]
		for u in a["units"]:
			var xp := int(u.get("xp", 0))
			var lv := 3 if xp >= 1200 else (2 if xp >= 700 else (1 if xp >= 300 else 0))
			out[k][lv] = int(out[k][lv]) + 1
	return out


func _run(sd: int, verbose: bool) -> String:
	sg = {"started": 0, "assault": 0, "sally": 0, "relief": 0, "lifted": 0, "surrendered": 0, "longest": 0,
		"field_won": 0, "assault_won": 0, "field": 0, "intercepted": 0, "raided": 0, "mustering": 0,
		"captured": 0, "fort_holds": 0, "town_battles": 0, "town_won": 0, "nat_assault": 0, "nat_assault_won": 0, "nat_taken": 0, "nat_taken_storm": 0}
	var largest := [0, 0, 0]
	var first_win := -1
	CP.reset_counters()
	built = []
	char_ev = {}
	for c in CData.CHAINS.size():
		built.append(0)
	if true:
		var settings := {}
		if skill_all >= 0:
			settings["ai_campaign_skill"] = skill_all
		if ai_alliances >= 0:
			settings["ai_alliances"] = ai_alliances
		var st := CState.new_campaign("sim", 1000 + sd * 77, [], settings, [], pack)
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
		var dead_at := {}  # faction -> turn eliminated (every faction)
		var crossings := 0  # armies that ended a turn on another landmass (sea lanes, or landed from a fleet)
		var last_land := _army_lands(st)  # army id -> landmass last seen on land (aboard a fleet: kept)
		ship_kinds = {}
		var fl_ev := {"ship_built": 0, "sea_battle": 0, "landed": 0, "embarked": 0, "army_sunk": 0, "fmove_failed": 0, "canoes_sunk": 0,
			"landing_contested": 0, "fleet_to_sea": 0, "fleet_taken": 0}
		var amph := [0, 0, 0]  # army-turns amphibious, afloat at the end of a turn, captures by an army that was afloat the turn before
		# (2026-11-05, support the shore) the seed's landings contested by how, the supports chosen, the battles supported
		# (fleets, men landed, lost, shots), the battles fought away from the water
		var shore := {"contested": {}, "set": 0, "support": 0, "landed": 0, "lost": 0, "fired": 0, "inland": 0, "none": 0}
		var was_afloat := {}  # army id -> 1: afloat at the end of the last turn
		vetm = {"retrains": 0, "retrain_f": {}, "rt_why": {}}
		lanem = {"f": {}, "trade_t": [0, 0, 0], "allied_t": [0, 0, 0], "trade_made": 0, "trade_end": 0, "elim_t": {}, "fx": {}, "wars": [], "raids": {}, "lost": {}}
		bldm = {"lv": {}, "rec": {}, "avail": {}, "ret": {}, "aic": {}}
		dipm = {"wars": 0, "wars_called": 0, "calls_answered": 0, "calls_refused": 0, "calls_sat_out": 0, "alliances_made": 0,
			"alliances_left": 0, "kept_faith": 0, "town_gain": 0, "battle_gain": 0}
		rtm = {"land": 0, "far": 0, "fleet": 0, "held": 0, "sea": 0, "destroyed": 0, "mismatch": 0, "stranded": 0, "stranded_run": 0, "position_fixed": 0}
		var strand_run := {}
		for t in turns:
			var t0 := Time.get_ticks_usec()
			st = CTurn.resolve_turn(st, [])
			_retreat_tally(st, t, strand_run)
			for e in st["events"]:
				if int(e["turn"]) != t:
					continue
				match str(e["k"]):
					"war":
						dipm["wars"] += 1
						if str(e.get("why", "")) == "called":
							dipm["wars_called"] += 1
					"call_answered":
						dipm["calls_answered" if int(e["accept"]) != 0 else "calls_refused"] += 1
					"call_sat_out":
						dipm["calls_sat_out"] += 1
					"alliance":
						dipm["alliances_made"] += 1
					"alliance_left":
						dipm["alliances_left"] += 1
					"regard":
						var wy := str(e["why"])
						if wy == "kept_faith":
							dipm["kept_faith"] += 1
						elif wy == "took_from_enemy" or wy == "took_from_common_enemy":
							dipm["town_gain"] += 1
						elif wy == "won_vs_enemy":
							dipm["battle_gain"] += 1
			var us := Time.get_ticks_usec() - t0
			t_total += us
			t_max = maxi(t_max, us)
			for f in CState.nf():
				if CState.alive(st, f):
					tr_min = mini(tr_min, int(st["factions"][f]["treasury"]))
					tr_max = maxi(tr_max, int(st["factions"][f]["treasury"]))
			_count_sieges(st, t)
			_tally(st, t)
			_build_tally(st, t)
			_lane_tally(st, t)
			if t + 1 == 30 or t + 1 == 60:
				vetm["t%d" % (t + 1)] = _vet_hist(st)
			if CRules.vet_on(st):
				# Retrain's blocks: every Seasoned+ unit at the end of a turn, by what retrain_info says (unit-turns).
				for a in st["armies"]:
					for k in CState.unit_count(a):
						if CState.vet_level(a["units"][k]) >= CRules.RETRAIN_LEVEL:
							var why := str(CRules.retrain_info(st, int(a["f"]), int(a["id"]), k).get("why", "ok"))
							if why.begins_with("needs "):
								why = "needs a building"
							vetm["rt_why"][why] = int(vetm["rt_why"].get(why, 0)) + 1
			for e in st["events"]:
				if int(e["turn"]) == t and str(e["k"]) == "retrained":
					vetm["retrains"] = int(vetm["retrains"]) + 1
					var rk := str(CData.FACTIONS[int(e["f"])]["key"])
					vetm["retrain_f"][rk] = int(vetm["retrain_f"].get(rk, 0)) + 1
			if verbose and trace >= 0:
				_trace(st, t)
			var land1 := _army_lands(st)
			for id in land1:
				if last_land.has(id) and int(land1[id]) != int(last_land[id]):
					crossings += 1
				last_land[id] = land1[id]
			for e in st["events"]:
				if int(e["turn"]) == t and str(e["k"]) == "ship_built":
					var bk := "%s:%s" % [str(CData.FACTIONS[int(e["f"])]["key"]) if int(e["f"]) >= 0 else "indep", str(e.get("ship", ""))]
					ship_kinds[bk] = int(ship_kinds.get(bk, 0)) + 1
				if int(e["turn"]) == t and str(e["k"]) == "recruited" and int(e["f"]) >= 0:
					for uk in e["units"]:
						if TIER_COUNT.has(str(uk)):
							var tk := "%s:%s" % [str(CData.FACTIONS[int(e["f"])]["key"]), str(uk)]
							tier_all[tk] = int(tier_all.get(tk, 0)) + 1
				if int(e["turn"]) == t and str(e["k"]) == "landed" and int(e["f"]) >= 0:
					var lk := str(CData.FACTIONS[int(e["f"])]["key"])
					var la: Array = land_all.get(lk, [0, 0])
					la[0] = int(la[0]) + 1
					la[1] = int(la[1]) + CState.unit_count(CState.army(st, int(e["army"])))
					land_all[lk] = la
				if int(e["turn"]) == t and str(e["k"]) == "sea_battle":
					sea_bat_all += 1
				if int(e["turn"]) == t and fl_ev.has(str(e["k"])):
					fl_ev[str(e["k"])] = int(fl_ev[str(e["k"])]) + 1
				if int(e["turn"]) == t:
					match str(e["k"]):
						"landing_contested":
							var hw := str(e.get("how", ""))
							shore["contested"][hw] = int(shore["contested"].get(hw, 0)) + 1
						"shore_set":
							shore["set"] += 1
						"shore_inland":
							shore["inland"] += 1
						"shore_support":
							shore["support"] += 1
							shore["landed"] += int(e.get("landed", 0))
							shore["lost"] += int(e.get("lost", 0))
							shore["fired"] += int(e.get("fired", 0))
							shore["none"] += int(e.get("none", 0))
				if int(e["turn"]) == t and str(e["k"]) == "captured" and CData.ships_on():
					for a in CState.armies_of(st, int(e["f"])):
						if was_afloat.has(int(a["id"])) and int(a["r"]) == int(e["r"]):
							amph[2] += 1
							break
			if CData.ships_on():
				was_afloat = {}
				for a in st["armies"]:
					if CRules.amphibious(st, a):
						amph[0] += 1
						if CRules.afloat(a):
							amph[1] += 1
							was_afloat[int(a["id"])] = 1
			for f in CState.nf():
				if not dead_at.has(f) and not CState.alive(st, f):
					dead_at[f] = int(st["turn"])
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
		var standing := 0
		for f in CState.nf():
			for g in range(f + 1, CState.nf()):
				if CState.alive(st, f) and CState.alive(st, g) and CDip.allied(st, f, g):
					standing += 1
		var ek: Array = []
		for f in CState.nf():
			if dead_at.has(f):
				ek.append(str(CData.FACTIONS[f]["key"]))
		dipm["alliances_t60"] = standing
		for f in CState.nf():
			if dead_at.has(f):
				lanem["elim_t"][str(CData.FACTIONS[f]["key"])] = int(dead_at[f])
		for ck in [CP.C_TRADE_ASKS, CP.C_TRADE_DEALS, CP.C_LANE_ASKS, CP.C_LANE_DEALS]:
			lanem[ck] = int(CP.totals()[CP.COUNTER_KEYS.find(ck)])
		dipm["elim"] = ek
		dipm["battles"] = int(st["stats"]["battles"])
		dipm["field"] = int(sg["field"])
		# (2026-11-02, a landing is contested; a fleet puts to sea when its port falls) the sea tallies of the seed
		for fk in ["sea_battle", "landed", "landing_contested", "fleet_to_sea", "fleet_taken"]:
			dipm[fk] = int(fl_ev[fk])
		# (2026-11-05, the formula knows the fort and the walls) the seed's sieges: captures by storm / starved, the
		# fort holding, the natives' assaults and captures
		dipm["sg"] = sg.duplicate()
		dipm["shore"] = shore
		if not verbose:
			return CState.hash_text(st)
		print("eliminated: %s | treasury range %d..%d | battles %d | turn time mean %.1f ms max %.1f ms | hash %s" % [
			str(elim), tr_min, tr_max, int(st["stats"]["battles"]), t_total / 1000.0 / turns, t_max / 1000.0,
			CState.hash_text(st)])
		var dl: Array = []
		for f in CState.nf():
			if dead_at.has(f):
				dl.append("%s %d" % [short[f], int(dead_at[f])])
				if not elim_all.has(f):
					elim_all[f] = []
				elim_all[f].append(int(dead_at[f]))
		print("eliminated at turn: %s | sea crossings (an army ended a turn on another landmass): %d" % [", ".join(dl), crossings])
		if st.has("fleets"):
			var ships := 0
			for fl in st["fleets"]:
				ships += (fl["ships"] as Array).size()
			print("fleets: ships launched %d, sea battles %d, embarkations %d, landings %d, armies sunk %d, voyages refused %d; at the end %d fleets, %d ships" % [
				int(fl_ev["ship_built"]), int(fl_ev["sea_battle"]), int(fl_ev["embarked"]), int(fl_ev["landed"]),
				int(fl_ev["army_sunk"]), int(fl_ev["fmove_failed"]), (st["fleets"] as Array).size(), ships])
			print("amphibious: army-turns %d, afloat at a turn's end %d, towns taken from the water %d, canoes sunk %d" % [
				amph[0], amph[1], amph[2], int(fl_ev["canoes_sunk"])])
			# N2: trade, blockades, the flota, pirates.
			var sx: Dictionary = st["stats"]
			var pl: Array = []
			for f in CState.nf():
				if int(st["factions"][f].get("plunder", 0)) > 0:
					pl.append("%s %d" % [short[f], int(st["factions"][f]["plunder"])])
			var pir: Array = []
			for f in CState.nf():
				if int(CData.FACTIONS[f].get("pirate", 0)) != 0:
					pir.append("%s %s, %d regions, %d ships, infamy %d" % [short[f], "alive" if CState.alive(st, f) else "dead",
						CState.regions_of(st, f).size(), _ships_of(st, f), int(st["factions"][f].get("infamy", 0))])
			print("sea (N2): plunder %d [%s] | blockade turns %d | flotas %d, arrived %d (%d gold), treasure galleons taken %d | sacks %d | letters of marque %d | pirates: %s" % [
				int(sx.get("plunder", 0)), ", ".join(pl), int(sx.get("blockade_turns", 0)), int(sx.get("flotas", 0)),
				int(sx.get("flota_arrived", 0)), int(sx.get("flota_gold", 0)), int(sx.get("treasure_taken", 0)),
				int(sx.get("sacks", 0)), int(sx.get("marques", 0)), "; ".join(pir)])
			# N2b: hurricanes, captains, named galleons.
			var caps: Array = []
			for cp in st.get("captains", []):
				caps.append("%s %d%s" % [str(cp["nm"]), int(cp["fame"]), "" if int(cp["fl"]) >= 0 else " ashore"])
			print("N2b: hurricanes %d (ships sunk %d, ports hit %d, men lost %d) | captains born %d, killed %d, hanged %d, ransomed %d, drowned %d, escaped %d, max fame %d, bounties %d, alive [%s] | galleons named %d, taken %d, sunk %d (treasure sunk %d)" % [
				int(sx.get("storms", 0)), int(sx.get("storm_ships", 0)), int(sx.get("storm_ports", 0)), int(sx.get("storm_men", 0)),
				int(sx.get("captains", 0)), int(sx.get("capt_killed", 0)), int(sx.get("capt_hanged", 0)), int(sx.get("capt_ransomed", 0)),
				int(sx.get("capt_drowned", 0)), int(sx.get("capt_escaped", 0)), int(sx.get("max_fame", 0)), int(sx.get("bounties", 0)),
				", ".join(caps), int(sx.get("galleons_named", 0)), int(sx.get("galleons_taken", 0)), int(sx.get("galleons_lost", 0)),
				int(sx.get("treasure_sunk", 0))])
		if st.has("fleets"):
			# Native vessels (2026-11-01): per seed one JSON line, ships launched by faction:kind over the
			# run, ships afloat by faction:kind at the end, the natives alive and their best Shipyard level.
			var afloat := {}
			for fl in st["fleets"]:
				var fkk := str(CData.FACTIONS[int(fl["f"])]["key"]) if int(fl["f"]) >= 0 else "indep"
				for sh in fl["ships"]:
					var ak := "%s:%s" % [fkk, str(sh["t"])]
					afloat[ak] = int(afloat.get(ak, 0)) + 1
			var nat := {}
			for nk in ["itza", "miskito"]:
				var nf := CData.faction_index(nk)
				if nf >= 0:
					nat[nk] = {"alive": 1 if CState.alive(st, nf) else 0, "regions": CState.regions_of(st, nf).size(),
						"yard": _best(st, nf, CData.SHIPYARD)}
			var kl: Array = ship_kinds.keys()
			kl.sort()
			var built_s := {}
			for k in kl:
				built_s[k] = ship_kinds[k]
			var al: Array = afloat.keys()
			al.sort()
			var afl_s := {}
			for k in al:
				afl_s[k] = afloat[k]
			print("SHIPS_JSON " + JSON.stringify({"seed": 1000 + sd * 77, "built": built_s, "afloat": afl_s, "natives": nat,
				"sea_battles": int(fl_ev["sea_battle"])}))
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
		print("AI sea counters (all factions): sea garrisons %d, ferries refused %d, sorties %d" % [
			ct[CP.COUNTER_KEYS.find(CP.C_SEA_HOLD)], ct[CP.COUNTER_KEYS.find(CP.C_FERRY_REFUSED)], ct[CP.COUNTER_KEYS.find(CP.C_SORTIES)]])
		print("AI wars called off, a region of ours open to the enemy (docs/AI.md 43): %d" % ct[CP.COUNTER_KEYS.find(CP.C_WAR_UNCOVERED)])
		print("AI siege guns (docs/AI.md 75): marches held a turn for guns %d, storms put off for want of guns or a ram %d" % [
			ct[CP.COUNTER_KEYS.find(CP.C_SIEGE_GUNS)], ct[CP.COUNTER_KEYS.find(CP.C_SIEGE_WAIT)]])
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
		for f in CState.nf():
			var gk := str(CData.FACTIONS[f]["key"])
			bldm["aic"][gk] = [CP.counter(CP.C_SIEGE_GUNS, f), CP.counter(CP.C_SIEGE_WAIT, f)]
		var endm := {}
		for f in CState.nf():
			endm[str(CData.FACTIONS[f]["key"])] = int(dead_at.get(f, -1))
		vetm["end"] = {"elim": endm, "battles": int(st["stats"]["battles"]), "field": int(sg["field"])}
		pacing.append("%d | %d / %d / %d | %d %s | %s | %d | %d | %d | %.1f %.1f" % [1000 + sd * 77, largest[0], largest[1], largest[2],
			elim.size(), str(elim), str(first_win) if first_win >= 0 else "-", int(st["stats"]["battles"]), int(sg["field"]),
			int(sg["mustering"]), t_total / 1000.0 / turns, t_max / 1000.0])
		return CState.hash_text(st)
	return ""


## Ships of faction f's fleets.
static func _ships_of(st: Dictionary, f: int) -> int:
	var n := 0
	for fl in st.get("fleets", []):
		if int(fl["f"]) == f:
			n += (fl["ships"] as Array).size()
	return n


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
## Army id -> landmass of its region (sea crossings in the report).
func _retreat_tally(st: Dictionary, t: int, run: Dictionary) -> void:
	if not CState.grid_on(st):
		return
	for e in st["events"]:
		if int(e["turn"]) != t:
			continue
		var k := str(e["k"])
		if k == "retreat":
			var how := str(e.get("how", ""))
			if how == "":
				var l0 := int(CData.REGIONS[int(e["r"])]["land"])
				var l1 := int(CData.REGIONS[maxi(int(e["to"]), 0)]["land"])
				how = "land" if l0 == l1 else "sea"
			rtm[how] = int(rtm.get(how, 0)) + 1
		elif k == "destroyed" or k == "position_fixed":
			rtm[k] += 1
	var owns := {}  # "f:land" -> 1
	for r in CData.region_count():
		var o := CState.owner(st, r)
		if o >= 0:
			owns["%d:%d" % [o, int(CData.REGIONS[r]["land"])]] = 1
	var now := {}
	for a in st["armies"]:
		var c := CState.cell(a)
		var r := CGrid.region(c)
		if r < 0:
			continue
		if r != int(a["r"]):
			rtm["mismatch"] += 1
		var f := int(a["f"])
		if owns.has("%d:%d" % [f, int(CData.REGIONS[r]["land"])]):
			continue
		var boat := false
		for fl in CFleet.fleets_of(st, f):
			if CFleet.near_fleet(a, fl):
				boat = true
				break
		if boat:
			continue
		rtm["stranded"] += 1
		var id := int(a["id"])
		now[id] = int(run.get(id, 0)) + 1
		rtm["stranded_run"] = maxi(int(rtm["stranded_run"]), int(now[id]))
	run.clear()
	for id in now:
		run[id] = now[id]


func _army_lands(st: Dictionary) -> Dictionary:
	var out := {}
	for a in st["armies"]:
		out[int(a["id"])] = int(CData.REGIONS[int(a["r"])]["land"])
	return out


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
				sg["captured"] += 1
				if str(e.get("how", "")) == "surrendered":
					sg["surrendered"] += 1
				if CData.POLE_FACTIONS.has(str(CData.FACTIONS[int(e["f"])]["key"])):
					sg["nat_taken"] += 1
					if str(e.get("how", "")) != "surrendered":
						sg["nat_taken_storm"] += 1
			"battle":
				var kind := str(e.get("kind", ""))
				if kind == "assault":
					sg["assault"] += 1
					if int(e["winner"]) == 0:
						sg["assault_won"] += 1
				if kind == "assault" or kind == "":
					sg["town_battles"] += 1
					if int(e["winner"]) == 0:
						sg["town_won"] += 1
					if int(e.get("fort_holds", 0)) != 0:
						sg["fort_holds"] += 1
					var natv := false
					for fa in e.get("att", []):
						if int(fa) >= 0 and CData.POLE_FACTIONS.has(str(CData.FACTIONS[int(fa)]["key"])):
							natv = true
					if natv:
						sg["nat_assault"] += 1
						if int(e["winner"]) == 0:
							sg["nat_assault_won"] += 1
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
			"char_recruited", "char_wounded", "char_captured":
				char_ev[str(e["k"])] = int(char_ev.get(str(e["k"]), 0)) + 1
			"ransom":
				char_ev["ransom_gold"] = int(char_ev.get("ransom_gold", 0)) + int(e["gold"])
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
	print("characters: raised %d, wounded %d, captured %d, ransom %d gold; alive at the end %d" % [int(char_ev.get("char_recruited", 0)),
		int(char_ev.get("char_wounded", 0)), int(char_ev.get("char_captured", 0)), int(char_ev.get("ransom_gold", 0)), CChars.all(st).size()])
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
		var tc := {}  # unit type -> units of it in f's armies at the end
		for a in CState.armies_of(st, f):
			for u in a["units"]:
				var tk := str(u["t"])
				tc[tk] = int(tc.get(tk, 0)) + 1
		var tks: Array = tc.keys()
		tks.sort()
		var tparts: Array = []
		for tk in tks:
			tparts.append("%s %d" % [tk, int(tc[tk])])
		print("    units: " + ", ".join(tparts))
		if not bu_all.has(f):
			bu_all[f] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		var b: Array = bu_all[f]
		var add := [1, nr, lv[0], lv[1], lv[2], lv[3], 1 if lv[0] >= 1 else 0, 1 if lv[1] >= 2 else 0,
			n[0], n[1], n[2], n[3], n[4]]
		for k in add.size():
			b[k] += int(add[k])


## --trace-faction: the traced faction's diplomacy events of turn t (wars,
## peace, trade, alliances, calls), its region gains and losses, and a status
## line: regions, treasury, armies, strength, wars and allies (with each
## enemy's strength and bloc strength against it).
func _trace(st: Dictionary, t: int) -> void:
	var f := trace
	if t == 0:
		_tr_landed = {}
		_tr_allies = []
		for g in CState.nf():
			if g != f and CState.alive(st, g) and CState.dip(st, f, g) == CState.ALLIED:
				_tr_allies.append(g)
	var ev: Array = []
	for e in st["events"]:
		if int(e["turn"]) != t:
			continue
		var k := str(e["k"])
		var who: Array = []
		for key in ["a", "b", "f", "from", "to", "vs", "with"]:
			if e.has(key) and typeof(e[key]) != TYPE_STRING:
				who.append(int(e[key]))
		if k == "landed":
			_tr_landed["%d:%d" % [int(e["f"]), int(e["r"])]] = t
			continue
		if not who.has(f) and not (k == "alliance" or k == "war"):
			continue
		match k:
			"war", "peace", "trade", "trade_end", "alliance", "alliance_left", "alliance_notice", "call_answered", "call_sat_out", "eliminated":
				var d := {}
				for key in e.keys():
					if key != "turn":
						d[key] = short[int(e[key])] if (typeof(e[key]) == TYPE_INT or typeof(e[key]) == TYPE_FLOAT) and ["a", "b", "f", "from", "to", "vs", "with"].has(key) and int(e[key]) >= 0 else e[key]
				if who.has(f) or k == "alliance":
					ev.append("%s %s" % [k, str(d)])
			"captured":
				if int(e["f"]) != f and int(e["from"]) != f:
					continue
				var lt: int = int(_tr_landed.get("%d:%d" % [int(e["f"]), int(e["r"])], -100))
				var route := "sea" if t - lt <= 8 else "land"
				ev.append("captured %s %s<-%s route %s" % [CData.REGIONS[int(e["r"])]["city"], short[int(e["f"])] if int(e["f"]) >= 0 else "-",
					short[int(e["from"])] if int(e["from"]) >= 0 else "-", route])
	var ws: Array = []
	for g in CAI.wars(st, f):
		ws.append("%s(%d/%d)" % [short[g], CAI.faction_strength(st, g), CAI.bloc_strength(st, f, g)])
	var al: Array = []
	for g in CState.nf():
		if g != f and CState.alive(st, g) and CState.dip(st, f, g) == CState.ALLIED:
			al.append(short[g])
	# Alliance changes of f against last turn's, with the cause read from the events.
	var al_now: Array = []
	for g in CState.nf():
		if g != f and CState.alive(st, g) and CState.dip(st, f, g) == CState.ALLIED:
			al_now.append(g)
	for g in _tr_allies:
		if not al_now.has(g):
			var why := "?"
			if not CState.alive(st, g):
				why = "ally eliminated"
			elif CState.dip(st, f, g) == CState.WAR:
				why = "war"
				for e in st["events"]:
					if int(e["turn"]) == t and str(e["k"]) == "war" and ((int(e.get("a", -1)) == f and int(e.get("b", -1)) == g) or (int(e.get("a", -1)) == g and int(e.get("b", -1)) == f)):
						why = "war declared by %s (%s)" % [short[int(e["a"])], str(e.get("why", ""))]
			else:
				for e in st["events"]:
					if int(e["turn"]) == t and str(e["k"]) == "alliance_left" and ((int(e["f"]) == f and int(e["with"]) == g) or (int(e["f"]) == g and int(e["with"]) == f)):
						why = "left by %s (%s)" % [short[int(e["f"])], str(e["why"])]
			ev.append("ALLIANCE LOST %s: %s" % [short[g], why])
	_tr_allies = al_now
	var na := CState.armies_of(st, f).size()
	print("  [trace %s t%d] regions %d treasury %d armies %d strength %d repute %d | wars %s | allies %s%s" % [short[f], int(st["turn"]),
		CState.regions_of(st, f).size(), int(st["factions"][f]["treasury"]) if CState.alive(st, f) else 0, na,
		CAI.faction_strength(st, f), CDip.repute(st, f), str(ws), str(al), ("\n    " + "\n    ".join(ev)) if not ev.is_empty() else ""])


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
