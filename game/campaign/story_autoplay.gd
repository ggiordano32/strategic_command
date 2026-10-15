extends RefCounted
## Testing aid for the story campaign (campaign/cstory.gd): plays a story
## headless with a simple captain, for tests/story_test.gd and main.gd's
## --story=seed[:turns] (--story-path=...). Not game rules: it only answers
## choices, gives fleet orders and resolves battles through the pure
## functions every client uses (CStory.answer, CTurn.resolve_turn,
## CTurn.apply_battle).
##
## Paths: "first" (the first allowed choice), "random" (a random allowed
## choice, from `rng_seed`; battles by the formula), and the scripted ones
## "republic", "pardon", "legend" (choices by event id that head for that
## ending; the captain wins every battle, but the Legend loses the finale).
## The captain: every fleet of ours sails for the great raid's target, else
## a prize the story has us hunting (or the flota) when we are a quarter
## stronger, else the haven.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CStory := preload("res://campaign/cstory.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CGrid := preload("res://campaign/cgrid.gd")

## Scripted choices by event id (each path; a choice not allowed falls to the
## next allowed one; a list: the first of them allowed).
const COMMON := {"chase": 0, "hungry": 1, "lindo_letter": [1, 0], "boucher": 2, "hurricane": 0, "warning": 0, "bargain": 2,
	"mendoza": 1, "commission": 0, "flota_news": 1, "pinos": 0, "miskito": 1, "captains_offer": 0, "flota_gathers": 1,
	"armada_blockade": 1, "escape": 1, "lindo_test": [0, 1], "boucher_cruelty": 1, "boucher_rival": 2, "vane_pages": 1,
	"haven_retake": 0, "council": [1, 0], "great_raid": 0, "raid_cartagena_at": [1, 0], "raid_portobelo_at": [1, 0], "pardon": 2,
	"eve": 0, "eve_homeless": 0}
const PATHS := {"republic": {}, "pardon": {"pardon": 0}, "legend": {"eve": 1}}


static func _rt() -> GDScript:
	return load("res://campaign/cturn.gd")


static func _cb() -> GDScript:
	return load("res://campaign/cbattle.gd")


## The choice for pending entry pe on `path` (an allowed one; -1 none allowed).
static func choose(st: Dictionary, pe: Dictionary, path: String, rng: RandomNumberGenerator) -> int:
	var f := int(pe["f"])
	var n := (CStory.event_def(st, str(pe["e"])).get("choices", []) as Array).size()
	var allowed: Array = []
	for i in n:
		if CStory.answer_check(st, f, int(pe["id"]), i) == "":
			allowed.append(i)
	if allowed.is_empty():
		return -1
	if path == "random":
		return int(allowed[rng.randi() % allowed.size()])
	if PATHS.has(path):
		var want = (PATHS[path] as Dictionary).get(str(pe["e"]), COMMON.get(str(pe["e"]), -1))
		for w in (want if want is Array else [want]):
			if allowed.has(int(w)):
				return int(w)
		if not want is Array and int(want) >= 0:
			for k in n:
				var i := (int(want) + k) % n
				if allowed.has(i):
					return i
	return int(allowed[0])


## The outcome of pending battle b: on a scripted path the captain wins
## every battle (a strong player), except the Legend's finale (lost); on the
## others, the formula.
static func outcome(st: Dictionary, b: Dictionary, path: String) -> Dictionary:
	var want := -1
	if PATHS.has(path):
		want = 1
		if path == "legend":
			for bt in CStory.S(st)["bt"]:
				if int(bt[0]) == int(b["id"]) and (str(bt[1]) == "finale" or str(bt[1]) == "fsea"):
					want = 0
	if want < 0:
		return _cb().formula(st, b)
	var side := int(CStory.before_battle(st, int(b["id"]))["side"])
	var w := side if want == 1 else 1 - side
	if b.has("sea"):
		return {"sea": 1, "mode": "fought", "winner": w, "ships": []}
	var o: Dictionary = _cb().formula(st, b)
	if int(o["winner"]) == w:
		return o
	# The other side won by the formula: the winner's losses and the loser's swapped round.
	o["winner"] = w
	var arm: Array = (load("res://campaign/crules.gd") as GDScript).call("battle_armies", st, b)
	var side_of := {}
	for k in 2:
		for a in arm[k]:
			side_of[int(a["id"])] = k
	for u in o["units"]:
		var n := int(u["killed"]) + int(u["routed"]) + int(u["remaining"]) + int(u["withdrawn"])
		if int(side_of.get(int(u["army"]), -1)) == w:
			u["killed"] = n * 15 / 100
			u["routed"] = 0
		else:
			u["killed"] = n * 55 / 100
			u["routed"] = n * 20 / 100
		u["withdrawn"] = 0
		u["remaining"] = n - int(u["killed"]) - int(u["routed"])
	if str(b.get("kind", "")) != "field":
		o["garrison_pct"] = int(st["regions"][int(b["r"])]["gar"]) * 85 / 100 if w == 1 else 0
	return o


## Where the captain's fleets sail this turn (a cell, -1 stay).
static func target(st: Dictionary) -> int:
	for tg in CStory._c(st, "TARGETS", []):
		if CStory.flag(st, str(tg[0])) and not CStory.flag(st, str(tg[1])):
			var r := CData.region_index(str(tg[2]))
			if r >= 0:
				return CFleet.dock(r)
	var mine := 0
	for fl in CStory.player_fleets(st):
		mine += CFleet.power(fl)
	for a in CStory.S(st)["actors"]:
		if CStory.flag(st, "hunt_" + str(a["k"])):
			var fl := CStory.actor_fleet(st, str(a["k"]))
			if not fl.is_empty() and CFleet.power(fl) * 5 < mine * 4:
				return CFleet.cell(fl)
	if CStory.flag(st, "hunt_flota"):
		for fl in CStory._flotas(st):
			if CFleet.power(fl) * 5 < mine * 4:
				return CFleet.cell(fl)
	return CFleet.dock(CData.region_index(str(CStory._c(st, "HAVEN", ""))))


## The captain's orders: fleets to target() (a voyage the story set, such
## as running west, is kept while the target is only the haven); at the
## haven, a sloop when we have no ship and companies of buccaneers while the
## chest allows (keeping 400 for the story's choices).
static func orders(st: Dictionary, f: int) -> Array:
	var out: Array = []
	var c := target(st)
	var hr := CData.region_index(str(CStory._c(st, "HAVEN", "")))
	var home := hr >= 0 and c == CFleet.dock(hr)
	var nships := 0
	for fl in CFleet.fleets_of(st, f):
		nships += (fl["ships"] as Array).size()
		if c < 0 or fl.has("busy") or (fl["ships"] as Array).is_empty() or CGrid.cheb(CFleet.cell(fl), c) <= 1:
			continue
		if home and fl.has("dest_x"):
			continue
		out.append({"t": "fmove", "fleet": int(fl["id"]), "x": CGrid.cx(c), "y": CGrid.cy(c), "persist": 1})
	if hr < 0 or CState.owner(st, hr) != f:
		return out
	var gold := int(st["factions"][f]["treasury"])
	var ship := "brigantine" if nships > 0 else "sloop"
	if nships < 4 and gold >= int(CData.ship_row(ship)["cost"]) + (400 if nships > 0 else 0) \
			and CFleet.ship_check(st, f, hr, ship) == "":
		out.append({"t": "ship", "r": hr, "ship": ship})
		gold -= int(CData.ship_row(ship)["cost"])
	var men := 0
	for a in st["armies"]:
		if int(a["f"]) == f and CGrid.cheb(CState.cell(a), CGrid.site(hr)) <= 1:
			men += CState.unit_count(a)
	var rc: GDScript = load("res://campaign/crules.gd")
	if men < 8 and gold >= 350 and str(rc.call("recruit_check", st, f, hr, "buccaneers")) == "":
		out.append({"t": "recruit", "r": hr, "unit": "buccaneers"})
	return out


## Battles and choices until the turn can resolve (or the game is over).
static func settle(st: Dictionary, path: String, rng: RandomNumberGenerator) -> Dictionary:
	var pf := CStory.player(st)
	for guard in 40:
		var pb: Array = _rt().pending_for(st)
		if not pb.is_empty():
			st = _rt().apply_battle(st, int(pb[0]["id"]), outcome(st, pb[0], path))
			continue
		if not CStory.blocked(st):
			break
		var pe: Dictionary = CStory.pending_for(st)[0]
		var k := choose(st, pe, path, rng)
		if k < 0:
			push_warning("story autoplay: no choice allowed for %s" % str(pe["e"]))
			break
		st = CStory.answer(st, pf, int(pe["id"]), k)
	return st


## A new story played for `turns` turns on `path`. `round_trip`: through
## JSON before every turn (the state must survive it unchanged). `settle_end`:
## the last turn's battles and choices are dealt with too (else left waiting,
## for the screen).
static func play(sd: int, turns: int, path: String = "first", rng_seed: int = 1, round_trip: bool = false,
		settle_end: bool = true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var st := CStory.new_story("Story test", sd)
	var pf := CStory.player(st)
	for t in turns:
		if round_trip:
			st = CState.from_json(CState.to_json(st))
		st = settle(st, path, rng)
		if str(st["phase"]) == "over" or CStory.blocked(st):
			break
		st = _rt().resolve_turn(st, [_rt().submission(st, pf, orders(st, pf))])
	return settle(st, path, rng) if settle_end else st
