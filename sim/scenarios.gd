extends RefCounted
## Scenario definitions as plain data (ints only) for BattleSim.setup().
##
## Battles use mixed armies laid out the way the battle AI deploys them:
## pikes in the centre, other infantry outward, cavalry on the wings, missile
## troops in front, bolt throwers at the end of the line (they shoot flat and
## need a clear field of fire), stone throwers behind the centre. Test scenarios are small set pieces with scripted orders
## (player 50) for the enemy; the player commands side 0 and can intervene.

const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const FM := preload("res://sim/fixed_math.gd")

const FACE_UP := 768    # -y
const FACE_DOWN := 256  # +y
const FACE_RIGHT := 0
const FACE_LEFT := 512
const ORDER_ATTACK := 2
const EQ_LADDERS := 1   # BattleSim's siege equipment kinds (scenario "equip")
const EQ_RAM := 2
const EQ_TOWER := 4
const TOWER_WALLS := 2  # siege towers only against walls of this level or more (BattleSim.EQ_WALLS)
const EQ_STAKES := 5    # BattleSim's field works kinds (scenario "field_works")
const EQ_CALTROPS := 6
const EQ_DITCH := 7
const EQ_RAMPART := 8
## A fortified camp (scenario "fortified"; camp()): the rampart this far
## beyond the box of the side's units (room on and behind it), gaps this
## wide for sallies, ditch and rampart this deep (BattleSim.EQ_FW_DEPTH),
## no back face nearer its map edge than CAMP_EDGE.
const CAMP_PAD := 14
const CAMP_GAP := 10
const CAMP_DEPTH := 4
const CAMP_EDGE := 12
const CAMP_SECTION := 20  # palisade sections at most this long (one burnt down opens a gap)
## River crossings (river_units): the camp's front rampart this far from the
## crossing's exit on the bank, and at least this far from the water all
## along it (its ditch dry); units no nearer the water than RIV_KEEP; the
## deployment zones end RIV_ZONE short of the water.
const RIV_CAMP := 14
const RIV_CAMP_DRY := 8
const RIV_KEEP := 10
const RIV_ZONE := 10
## Field works allowance (stakes lines, caltrop fields) by the army's best
## Workshop level (campaign: its faction's; 0 none): a workshop's carpenters
## and smiths, 2 lines at level 1, 4 lines and 2 fields at level 2 ...
const WORKS_BY_WORKSHOP: Array = [[0, 0], [2, 0], [4, 2]]
## ... plus a fortified army's own (cut on the spot, whatever its workshop):
## two lines in front of its gaps and a caltrop field.
const WORKS_FORTIFIED: Array[int] = [2, 1]

const IDS: Array[String] = ["skirmish", "battle_2000", "battle_4000",
	"bench_2000", "bench_4000", "bench_4000_hills",
	"test_pike_front", "test_pike_flank", "test_cav_rear", "test_cav_spears",
	"test_cav_archers", "test_archers_heavy", "test_bolt_pikes", "test_stone_line",
	"test_cav_art", "test_ridge_defend", "test_attack_uphill", "test_archers_hill",
	"test_bolts_crest", "test_woods", "siege_village", "siege_town", "siege_city", "siege_hill",
	"bench_4000_city", "siege_castrum", "siege_polis", "siege_punic", "siege_oppidum",
	"bench_4000_polis", "bench_4000_castrum"]

## Playable battles get generated terrain (random kind from the seed unless
## the menu picks one). The benchmarks stay flat so their timings compare
## with earlier builds; bench_4000_hills is the fixed hilly benchmark
## (rolling, terrain seed 4242, terrain generator version 1).
const PLAYABLE: Array[String] = ["skirmish", "battle_2000", "battle_4000"]
const BENCH_HILLS_TERRAIN := {"kind": Terrain.K_ROLLING, "seed": 4242}

## Default unit sizes and files per type.
## Artillery: soldiers are crews (bolts 4 engines x 4, stones 3 x 6) and
## files are engines.
const SIZE := {UT.HEAVY: 100, UT.LIGHT: 100, UT.SPEAR: 100, UT.PIKE: 120,
	UT.ARCHER: 80, UT.JAVELIN: 60, UT.CAVALRY: 60, UT.BOLT: 16, UT.STONE: 18}
const FILES := {UT.HEAVY: 25, UT.LIGHT: 25, UT.SPEAR: 25, UT.PIKE: 24,
	UT.ARCHER: 20, UT.JAVELIN: 20, UT.CAVALRY: 15, UT.BOLT: 4, UT.STONE: 3}

## Army of ~1,000: main line left to right, then the missile screen.
const ARMY_LINE := [UT.CAVALRY, UT.BOLT, UT.LIGHT, UT.HEAVY, UT.PIKE, UT.PIKE,
	UT.HEAVY, UT.SPEAR, UT.CAVALRY]
const ARMY_SCREEN := [UT.ARCHER, UT.JAVELIN, UT.ARCHER]
## Behind the centre of the line.
const ARMY_REAR := [UT.STONE]
const REAR_BACK := 25
## Army of ~200 for the skirmish.
const SMALL_LINE := [UT.CAVALRY, UT.HEAVY, UT.PIKE]
const SMALL_SCREEN := [UT.ARCHER]
const SMALL_SIZE := {UT.CAVALRY: 40, UT.HEAVY: 60, UT.PIKE: 60, UT.ARCHER: 40}
const NO_REAR := []


static func title(id: String) -> String:
	match id:
		"skirmish":
			return "Small skirmish (400 soldiers)"
		"battle_2000":
			return "Battle: 2,000 soldiers"
		"battle_4000":
			return "Battle: 4,000 soldiers"
		"bench_2000":
			return "AI vs AI benchmark: 2,000"
		"bench_4000":
			return "AI vs AI benchmark: 4,000"
		"test_pike_front":
			return "Test: pikes vs swords, frontal"
		"test_pike_flank":
			return "Test: pikes pinned and flanked"
		"test_cav_rear":
			return "Test: cavalry rear charge"
		"test_cav_spears":
			return "Test: cavalry vs braced spears"
		"test_cav_archers":
			return "Test: cavalry vs archers"
		"test_archers_heavy":
			return "Test: archers vs heavy infantry"
		"test_bolt_pikes":
			return "Test: bolt throwers vs pike block"
		"test_stone_line":
			return "Test: stone throwers vs massed line"
		"test_cav_art":
			return "Test: cavalry raids artillery"
		"bench_4000_hills":
			return "AI vs AI benchmark: 4,000 on hills"
		"test_ridge_defend":
			return "Terrain: defend a ridge"
		"test_attack_uphill":
			return "Terrain: attack a hill"
		"test_archers_hill":
			return "Terrain: archers on a hill"
		"test_bolts_crest":
			return "Terrain: bolts and a crest"
		"test_woods":
			return "Woods: cavalry, archers and pikes"
		"siege_village":
			return "Settlement: open village"
		"siege_town":
			return "Settlement: walled town"
		"siege_city":
			return "Settlement: city, walls 2"
		"siege_hill":
			return "Settlement: hill city, walls 3"
		"bench_4000_city":
			return "AI vs AI benchmark: 4,000 in a city"
		"siege_castrum":
			return "Settlement: castrum on a plain, ditch"
		"siege_polis":
			return "Settlement: coastal polis, acropolis"
		"siege_punic":
			return "Settlement: Punic city on the coast"
		"siege_oppidum":
			return "Settlement: oppidum on a spur"
		"bench_4000_polis":
			return "AI vs AI benchmark: 4,000, coastal polis"
		"bench_4000_castrum":
			return "AI vs AI benchmark: 4,000, castrum"
	return id


static func make(id: String) -> Dictionary:
	match id:
		"siege_village":
			return siege_test(101, 0, 0, MapGen.PAL_GREEN, Terrain.K_ROLLING, 1)
		"siege_town":
			return siege_test(202, 1, 1, MapGen.PAL_DRY, Terrain.K_ROLLING, 1)
		"siege_city":
			return siege_test(303, 2, 2, MapGen.PAL_ARID, Terrain.K_FLAT, 1)
		"siege_hill":
			return siege_test(404, 2, 3, MapGen.PAL_ROCKY, Terrain.K_HILL, 1)
		"bench_4000_city":
			return bench_city()
		"siege_castrum":
			return siege_test(505, 2, 3, MapGen.PAL_DRY, Terrain.K_FLAT, 1, -1, MapGen.PLAN_CASTRUM, 0)
		"siege_polis":
			return siege_test(606, 2, 2, MapGen.PAL_DRY, Terrain.K_HILL, 1, -1, MapGen.PLAN_POLIS, 1)
		"siege_punic":
			return siege_test(707, 2, 2, MapGen.PAL_ARID, Terrain.K_FLAT, 1, -1, MapGen.PLAN_PUNIC, 1)
		"siege_oppidum":
			return siege_test(808, 1, 1, MapGen.PAL_GREEN, Terrain.K_RIDGE, 1, -1, MapGen.PLAN_OPPIDUM, 0)
		"bench_4000_polis":
			return bench_city(MapGen.PLAN_POLIS, 1, Terrain.K_HILL)
		"bench_4000_castrum":
			return bench_city(MapGen.PLAN_CASTRUM, 0, Terrain.K_FLAT, 3)
	var sc := _make(id)
	if id in PLAYABLE:
		sc["terrain"] = {"kind": Terrain.K_RANDOM}
	elif id == "bench_4000_hills":
		sc["terrain"] = BENCH_HILLS_TERRAIN.duplicate()
	return sc


## Terrain feature shorthand (see sim/terrain.gd).
static func ridge(x_m: int, y_m: int, half_w_m: int, h_m: int, dir: int, half_len_m: int) -> Array:
	return [Terrain.F_RIDGE, x_m, y_m, half_w_m, h_m, dir, half_len_m]


static func hill(x_m: int, y_m: int, r_m: int, h_m: int) -> Array:
	return [Terrain.F_BUMP, x_m, y_m, r_m, h_m]


static func _make(id: String) -> Dictionary:
	match id:
		"skirmish":
			return _battle(1, [1], SMALL_LINE, SMALL_SCREEN, SMALL_SIZE, 440, 440, 80, NO_REAR)
		"battle_2000":
			return _battle(1, [1], ARMY_LINE, ARMY_SCREEN, SIZE, 560, 560, 100, ARMY_REAR)
		"battle_4000":
			return _battle(2, [1], ARMY_LINE, ARMY_SCREEN, SIZE, 560, 600, 100, ARMY_REAR)
		"bench_4000_hills":
			return _battle(2, [0, 1], ARMY_LINE, ARMY_SCREEN, SIZE, 560, 600, 100, ARMY_REAR)
		"test_ridge_defend":
			# Your line holds a ridge crest (12 m, slopes up to ~23%); the
			# enemy climbs it from the far side. Archers shoot from the top.
			return _test_t([unit(0, UT.HEAVY, 100, 105, 200, FACE_UP),
				unit(0, UT.SPEAR, 100, 195, 200, FACE_UP),
				unit(0, UT.ARCHER, 80, 150, 222, FACE_UP),
				unit(1, UT.HEAVY, 100, 95, 60, FACE_DOWN),
				unit(1, UT.HEAVY, 100, 175, 60, FACE_DOWN),
				unit(1, UT.LIGHT, 100, 245, 70, FACE_DOWN),
				unit(1, UT.CAVALRY, 40, 40, 70, FACE_DOWN)],
				[attack(150, 3, 0, 0), attack(150, 4, 1, 0), attack(150, 5, 1, 0),
					attack(400, 6, 2, 1)],
				[ridge(150, 205, 80, 12, 0, 220)])
		"test_attack_uphill":
			# The enemy stands on a round hill (16 m, ~25% at its steepest);
			# take it. Going round to a gentler side pays.
			return _test_t([unit(0, UT.HEAVY, 100, 95, 250, FACE_UP),
				unit(0, UT.HEAVY, 100, 205, 250, FACE_UP),
				unit(0, UT.LIGHT, 100, 150, 265, FACE_UP),
				unit(0, UT.CAVALRY, 60, 40, 255, FACE_UP),
				unit(1, UT.HEAVY, 100, 150, 110, FACE_DOWN),
				unit(1, UT.SPEAR, 80, 90, 105, FACE_DOWN),
				unit(1, UT.ARCHER, 60, 150, 85, FACE_DOWN)],
				[], [hill(150, 95, 100, 16)])
		"test_archers_hill":
			# Your archers on a 15 m hill, theirs on the plain 150 m away:
			# height adds range, so yours reach and theirs fall short until
			# they walk in.
			return _test_t([unit(0, UT.ARCHER, 80, 150, 225, FACE_UP),
				unit(1, UT.ARCHER, 80, 150, 75, FACE_DOWN),
				unit(1, UT.LIGHT, 100, 230, 60, FACE_DOWN)],
				[attack(300, 1, 0, 0)], [hill(150, 235, 85, 15)])
		"test_bolts_crest":
			# A low crest (6 m) lies across the field: the pike block behind
			# it cannot be hit by flat bolts; the light infantry past the end
			# of the crest can. Try ordering the battery to shoot the pikes.
			return _test_t([unit(0, UT.BOLT, 16, 150, 270, FACE_UP),
				unit(0, UT.SPEAR, 100, 150, 285, FACE_UP),
				unit(1, UT.PIKE, 120, 125, 110, FACE_DOWN),
				unit(1, UT.LIGHT, 100, 260, 115, FACE_DOWN)],
				[attack(900, 2, 0, 0), attack(900, 3, 0, 0)],
				[ridge(110, 175, 28, 6, 0, 75)])
		"bench_2000":
			return _battle(1, [0, 1], ARMY_LINE, ARMY_SCREEN, SIZE, 560, 560, 100, ARMY_REAR)
		"bench_4000":
			return _battle(2, [0, 1], ARMY_LINE, ARMY_SCREEN, SIZE, 560, 600, 100, ARMY_REAR)
		"test_pike_front":
			return _test([unit(0, UT.PIKE, 120, 150, 170, FACE_UP),
				unit(1, UT.HEAVY, 100, 150, 120, FACE_DOWN)],
				[attack(0, 1, 0, 0)])
		"test_pike_flank":
			return _test([unit(0, UT.PIKE, 120, 150, 170, FACE_UP),
				unit(1, UT.HEAVY, 100, 150, 130, FACE_DOWN),
				unit(1, UT.LIGHT, 100, 215, 180, FACE_LEFT)],
				[attack(0, 1, 0, 0), attack(150, 2, 0, 0)])
		"test_cav_rear":
			return _test([unit(0, UT.HEAVY, 100, 150, 170, FACE_UP),
				unit(0, UT.CAVALRY, 60, 150, 70, FACE_DOWN),
				unit(1, UT.HEAVY, 100, 150, 140, FACE_DOWN)],
				[attack(0, 2, 0, 0), attack(200, 1, 2, 1)])
		"test_cav_spears":
			return _test([unit(0, UT.CAVALRY, 60, 150, 200, FACE_UP),
				unit(1, UT.SPEAR, 100, 150, 110, FACE_DOWN)], [attack(30, 0, 1, 1)])
		"test_cav_archers":
			return _test([unit(0, UT.CAVALRY, 60, 150, 220, FACE_UP),
				unit(1, UT.ARCHER, 80, 150, 90, FACE_DOWN)], [attack(30, 0, 1, 1)])
		"test_archers_heavy":
			return _test([unit(0, UT.ARCHER, 80, 150, 200, FACE_UP),
				unit(1, UT.HEAVY, 100, 150, 90, FACE_DOWN),
				unit(1, UT.LIGHT, 100, 200, 90, FACE_DOWN)], [])
		"test_bolt_pikes":
			# The block stands in range for 40 s, then advances on the battery.
			return _test([unit(0, UT.BOLT, 16, 150, 270, FACE_UP),
				unit(1, UT.PIKE, 120, 150, 90, FACE_DOWN)], [attack(400, 1, 0, 0)])
		"test_stone_line":
			# A massed line stands under fire for a minute, then attacks.
			return _test([unit(0, UT.STONE, 18, 150, 280, FACE_UP),
				unit(1, UT.HEAVY, 100, 89, 60, FACE_DOWN),
				unit(1, UT.SPEAR, 100, 150, 60, FACE_DOWN),
				unit(1, UT.HEAVY, 100, 211, 60, FACE_DOWN)],
				[attack(600, 1, 0, 0), attack(600, 2, 0, 0), attack(600, 3, 0, 0)])
		"test_woods":
			# Woods on the field: their archers stand in a dense wood for your
			# cavalry to charge, your pikes must cross woods to reach their
			# heavy infantry, and a dense thicket lies between your
			# javelins and theirs.
			var sw := _test([unit(0, UT.CAVALRY, 60, 80, 250, FACE_UP),
				unit(0, UT.PIKE, 120, 200, 255, FACE_UP),
				unit(0, UT.JAVELIN, 60, 140, 260, FACE_UP),
				unit(1, UT.ARCHER, 80, 80, 140, FACE_DOWN),
				unit(1, UT.HEAVY, 100, 200, 80, FACE_DOWN),
				unit(1, UT.JAVELIN, 60, 140, 100, FACE_DOWN)],
				[attack(300, 4, 1, 0), attack(450, 5, 2, 0)])
			sw["terrain"] = {"kind": Terrain.K_FLAT, "woods": [[80, 140, 60, 50, 2], [80, 140, 40, 30, 3],
				[200, 165, 45, 25, 2], [140, 140, 30, 14, 3]]}
			return sw
		"test_cav_art":
			# Enemy batteries guarded by spearmen; your cavalry raids them
			# (light infantry can slog in too).
			return _test([unit(0, UT.CAVALRY, 60, 50, 260, FACE_UP),
				unit(0, UT.CAVALRY, 60, 250, 260, FACE_UP),
				unit(0, UT.LIGHT, 100, 150, 250, FACE_UP),
				unit(1, UT.BOLT, 16, 120, 70, FACE_DOWN),
				unit(1, UT.STONE, 18, 185, 55, FACE_DOWN),
				unit(1, UT.SPEAR, 100, 150, 95, FACE_DOWN)], [])
	push_error("unknown scenario " + id)
	return {}


## One unit as scenario data. x_m/y_m is the front centre in metres.
static func unit(side: int, ty: int, count: int, x_m: int, y_m: int, face: int,
		files: int = -1) -> Dictionary:
	if files < 0:
		var b := UT.base_of(ty)  # tier types form up like their base type
		if UT.stat(ty, "files0") > 0:
			files = UT.stat(ty, "files0") * count / maxi(UT.size_of(ty), 1)  # (rows that say so: camels, elephants)
		else:
			files = int(FILES.get(b, 4)) * count / maxi(int(SIZE.get(b, count)), 1)
		files = maxi(files, 4)
	return {"side": side, "type": ty, "count": count, "x_m": x_m, "y_m": y_m,
		"facing": face, "files": files}


static func attack(tick: int, u: int, target: int, run: int) -> Dictionary:
	return {"tick": tick, "type": ORDER_ATTACK, "unit": u, "target": target, "run": run}


## Small 300 x 300 m test field; the enemy acts only through scripted orders.
static func _test(units: Array, orders: Array) -> Dictionary:
	return {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units,
		"orders": orders}


## Test field with hand-placed terrain features (fixed: no seed dependence).
static func _test_t(units: Array, orders: Array, features: Array) -> Dictionary:
	var sc := _test(units, orders)
	sc["terrain"] = {"kind": Terrain.K_CUSTOM, "features": features}
	return sc


## Two mixed armies facing each other. `armies` armies per side, the second
## one 45 m behind the first. `front` is the distance of the first line from
## the centre line in metres.
static func _battle(armies: int, ai_sides: Array, line: Array, screen: Array,
		sizes: Dictionary, width_m: int, height_m: int, front: int, rear: Array) -> Dictionary:
	# Side 0 at the bottom facing up; side 1 is its exact 180-degree mirror
	# image (x -> width - x, y -> height - y), so neither side gains from
	# rounding in the layout (laying both out with the same integer maths left
	# the top army's line 1 m and its screen 6 m off the mirror image).
	var units: Array = []
	var cx := width_m / 2
	var cy := height_m / 2
	for a in armies:
		var back := front + a * 45
		units.append_array(_row(line, sizes, cx, cy + back, 4))
		# Missile screen 15 m in front, rear row (stone throwers) behind.
		units.append_array(_row(screen, sizes, cx, cy + back - 15, 6))
		units.append_array(_row(rear, sizes, cx, cy + back + REAR_BACK, 6))
	var n0 := units.size()
	for k in n0:
		var u: Dictionary = units[k]
		units.append(unit(1, int(u["type"]), int(u["count"]), width_m - int(u["x_m"]),
			height_m - int(u["y_m"]), FACE_DOWN))
	return {"width_m": width_m, "height_m": height_m, "ai_sides": ai_sides, "units": units}


## A river crossing battle (docs/DESIGN.md "River crossings"; tests,
## probes): bench_2000's two armies on a 560 x 560 field with the crossing
## of `seed` (kind 0 ford / 1 bridge) between them, side 1 holding the far
## bank (fortified if `fort`); rolling ground; ai_sides as given.
static func crossing(kind: int, seed_v: int, fort: bool, ai_sides: Array = [0, 1]) -> Dictionary:
	var sc := _battle(1, ai_sides, ARMY_LINE, ARMY_SCREEN, SIZE, 560, 560, 100, ARMY_REAR)
	sc["terrain"] = {"kind": Terrain.K_ROLLING, "seed": seed_v, "forest": 15, "ground": MapGen.PAL_GREEN}
	sc["river"] = {"id": seed_v, "kind": kind, "seed": seed_v, "bank": 1}
	if fort:
		sc["fortified"] = 1
	return sc


## One row of side-0 units (facing up), left to right, centred on x = cx,
## front at y, `gap` metres apart.
static func _row(types: Array, sizes: Dictionary, cx: int, y: int, gap: int) -> Array:
	var out: Array = []
	if types.is_empty():
		return out
	var total := -gap
	for ty in types:
		total += _width_m(ty, int(sizes[ty])) + gap
	var x := cx - total / 2
	for ty in types:
		var w := _width_m(ty, int(sizes[ty]))
		out.append(unit(0, ty, int(sizes[ty]), x + w / 2, y, FACE_UP))
		x += w + gap
	return out


## Frontage in metres of a unit of `count` soldiers of type ty at default files.
static func _width_m(ty: int, count: int) -> int:
	var b := UT.base_of(ty)
	var files := maxi(int(FILES.get(b, 4)) * count / maxi(int(SIZE.get(b, count)), 1), 4)
	if UT.stat(ty, "files0") > 0:
		files = maxi(UT.stat(ty, "files0") * count / maxi(UT.size_of(ty), 1), 4)
	return files * UT.stat(ty, "file_sp") / 1024


# ----------------------------------------------------- the fortified camp ---

## Field works allowance [stakes lines, caltrop fields] of an army with
## Workshop level `workshop` (0-2), fortified (true) or not.
static func works_allowance(workshop: int, fortified: bool) -> Array[int]:
	var w: Array = WORKS_BY_WORKSHOP[clampi(workshop, 0, WORKS_BY_WORKSHOP.size() - 1)]
	var out: Array[int] = [int(w[0]), int(w[1])]
	if fortified:
		out[0] += WORKS_FORTIFIED[0]
		out[1] += WORKS_FORTIFIED[1]
	return out


## The ditch and rampart of a fortified camp round side `side`'s units
## (scenario "fortified": BattleSim builds it at setup; docs/DESIGN.md
## "Field works and the fortified camp"): a rampart CAMP_PAD m beyond the
## box of its units on the front and both flanks, and behind them when
## there is room before its map edge; open sally gaps (no gates: two in the
## front, one in the back if there is a back); the rampart (a wooden
## palisade on an earth bank) in sections of at most CAMP_SECTION m, each
## of which can burn down on its own; the ditch just outside it (round the
## front corners). Returns [[kind (BattleSim EQ_*), side, x_m, y_m, facing,
## len_m], ...] (the scenario's "field_works" form); integers only, the
## units in order.
## river: the crossing's geometry (MapGen.river_geom) when the camp stands
## at a crossing (the side holds the far bank; river_units brought its line
## up to the mouth): no sally gaps in the front facing the water, one in
## each flank instead.
static func camp(units: Array, w_m: int, h_m: int, side: int, river: Dictionary = {}) -> Array:
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var y0 := 1 << 30
	var y1 := -(1 << 30)
	var sy := 0
	var cnt := 0
	for ud in units:
		if int(ud["side"]) != side:
			continue
		var b := unit_box(ud)
		x0 = mini(x0, b[0])
		x1 = maxi(x1, b[2])
		y0 = mini(y0, b[1])
		y1 = maxi(y1, b[3])
		sy += int(ud["y_m"])
		cnt += 1
	var out: Array = []
	if cnt == 0:
		return out
	var bottom := sy / cnt > h_m / 2
	var lx := maxi(x0 - CAMP_PAD, CAMP_EDGE)
	var rx := mini(x1 + CAMP_PAD, w_m - CAMP_EDGE)
	var fy := maxi(y0 - CAMP_PAD, CAMP_EDGE) if bottom else mini(y1 + CAMP_PAD, h_m - CAMP_EDGE)
	var by := y1 + CAMP_PAD if bottom else y0 - CAMP_PAD
	var back := by <= h_m - CAMP_EDGE if bottom else by >= CAMP_EDGE
	if not back:
		by = h_m - CAMP_EDGE if bottom else CAMP_EDGE
	var ff := FACE_UP if bottom else FACE_DOWN
	var fb := FACE_DOWN if bottom else FACE_UP
	var dn := -1 if bottom else 1  # the front's outward direction along y
	var at_river := not river.is_empty() and int(river["bank"]) == side
	# Front (the ditch round the corners), flanks, back.
	_camp_face(out, side, lx, fy, rx, fy, ff, 0, dn, 0 if at_river else 2, CAMP_DEPTH)
	_camp_face(out, side, lx, fy, lx, by, FACE_LEFT, -1, 0, 1 if at_river else 0, 0)
	_camp_face(out, side, rx, fy, rx, by, FACE_RIGHT, 1, 0, 1 if at_river else 0, 0)
	if back:
		_camp_face(out, side, lx, by, rx, by, fb, 0, -dn, 1, CAMP_DEPTH)
	return out


## The box a scenario unit stands in (m): [x0, y0, x1, y1].
static func unit_box(ud: Dictionary) -> Array:
	var ty := int(ud["type"])
	var n := maxi(int(ud["count"]), 1)
	var x := int(ud["x_m"])
	var y := int(ud["y_m"])
	var files := clampi(int(ud.get("files", 20)), 1, n)
	var hw := files * UT.stat(ty, "file_sp") / 2048 + 1
	var dep := (n + files - 1) / files * UT.stat(ty, "rank_sp") / 1024 + 1
	var face := int(ud.get("facing", FACE_UP))
	var ya := y
	var yb := y + dep
	if face == FACE_DOWN:
		ya = y - dep
		yb = y
	elif face != FACE_UP:
		hw = maxi(hw, dep)
		ya = y - hw
		yb = y + hw
	return [x - hw, ya, x + hw, yb]


## A river crossing (scenario "river"; geometry `g`, MapGen.river_geom, on
## a w_m x h_m field): the units as they stand at setup. The side holding
## the far bank (g "bank") is moved along its bank to face the crossing
## (its middle on the mouth, kept on the field); fortified there (`fort`
## is that side) its line is also brought up so the camp's front rampart
## (CAMP_PAD beyond its box) stands RIV_CAMP m from the crossing's exit (or
## RIV_CAMP_DRY clear of the water anywhere along the camp, if further).
## Then any unit (either side) whose box comes within RIV_KEEP of the water
## is moved straight back onto its own bank (side 0 the bottom, 1 the top).
## Returns a new list (changed units are copies); integers only, units in
## order.
static func river_units(units: Array, w_m: int, _h_m: int, g: Dictionary, fort: int) -> Array:
	var out: Array = []
	for ud in units:
		out.append(ud)
	var hs := int(g["bank"])
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var sx := 0
	var cnt := 0
	for ud in out:
		if int(ud["side"]) != hs:
			continue
		var b := unit_box(ud)
		x0 = mini(x0, b[0])
		x1 = maxi(x1, b[2])
		sx += int(ud["x_m"])
		cnt += 1
	if cnt > 0:
		var mouth := MapGen.river_mouth(g, hs)
		var dx := clampi(mouth.x - sx / cnt, RIV_KEEP - x0, w_m - RIV_KEEP - x1)
		var dy := 0
		if fort == hs:
			var y0 := 1 << 30
			var y1 := -(1 << 30)
			for ud in out:
				if int(ud["side"]) == hs:
					var b := unit_box(ud)
					y0 = mini(y0, b[1])
					y1 = maxi(y1, b[3])
			var reach := MapGen.river_reach(g, x0 + dx - CAMP_PAD - CAMP_DEPTH, x1 + dx + CAMP_PAD + CAMP_DEPTH, hs)
			var exit_y := mouth.y + (-MapGen.RIV_MOUTH if hs == 0 else MapGen.RIV_MOUTH)
			if hs == 0:
				var fy := maxi(exit_y + RIV_CAMP, reach + RIV_CAMP_DRY)
				dy = fy + CAMP_PAD - y0
			else:
				var fy2 := mini(exit_y - RIV_CAMP, reach - RIV_CAMP_DRY)
				dy = fy2 - CAMP_PAD - y1
		for k in out.size():
			var ud: Dictionary = out[k]
			if int(ud["side"]) != hs or (dx == 0 and dy == 0):
				continue
			var c := ud.duplicate()
			c["x_m"] = int(ud["x_m"]) + dx
			c["y_m"] = int(ud["y_m"]) + dy
			out[k] = c
	for k in out.size():
		var ud: Dictionary = out[k]
		var s := clampi(int(ud["side"]), 0, 1)
		var b := unit_box(ud)
		var e := MapGen.river_reach(g, b[0], b[2], s)
		var push := 0
		if s == 0 and b[1] < e + RIV_KEEP:
			push = e + RIV_KEEP - b[1]
		elif s == 1 and b[3] > e - RIV_KEEP:
			push = e - RIV_KEEP - b[3]
		if push != 0:
			var c2 := ud.duplicate()
			c2["y_m"] = int(ud["y_m"]) + push
			out[k] = c2
	return out


## One face of a camp from (ax, ay) to (bx, by) (m, axis-aligned), facing
## `face` (outward unit (nx, ny)), with `gaps` sally gaps evenly spaced: the
## rampart's runs between them and the ditch's CAMP_DEPTH m further out
## (its outer runs `ext` m longer at the ends).
static func _camp_face(out: Array, side: int, ax: int, ay: int, bx: int, by: int, face: int,
		nx: int, ny: int, gaps: int, ext: int) -> void:
	var horiz := ay == by
	var a := ax if horiz else ay
	var b := bx if horiz else by
	if b < a:
		var t := a
		a = b
		b = t
	var cuts: Array = [a]
	for k in gaps:
		var g := a + (b - a) * (k + 1) / (gaps + 1)
		cuts.append(g - CAMP_GAP / 2)
		cuts.append(g + CAMP_GAP / 2)
	cuts.append(b)
	var line := ay if horiz else ax
	for k in range(0, cuts.size(), 2):
		var r0: int = cuts[k]
		var r1: int = cuts[k + 1]
		if r1 - r0 < CAMP_DEPTH:
			continue
		var d0 := r0 - (ext if k == 0 else 0)
		var d1 := r1 + (ext if k + 2 >= cuts.size() else 0)
		var dmid := (d0 + d1) / 2
		# The palisade in sections (each burns on its own), then the ditch.
		var ns := (r1 - r0 + CAMP_SECTION - 1) / CAMP_SECTION
		for j in ns:
			var s0 := r0 + (r1 - r0) * j / ns
			var s1 := r0 + (r1 - r0) * (j + 1) / ns
			var sm := (s0 + s1) / 2
			if horiz:
				out.append([EQ_RAMPART, side, sm, line, face, s1 - s0])
			else:
				out.append([EQ_RAMPART, side, line, sm, face, s1 - s0])
		if horiz:
			out.append([EQ_DITCH, side, dmid, line + ny * CAMP_DEPTH, face, d1 - d0])
		else:
			out.append([EQ_DITCH, side, line + nx * CAMP_DEPTH, dmid, face, d1 - d0])


# ------------------------------------------------------------ settlements ---

## Lay out one army (side-0 coordinates: x from the centre, "back" metres
## behind the front line) the way the campaign does: cavalry on the wings,
## bolt throwers at the line ends, infantry inside with pikes in the
## centre, missile troops 15 m ahead, stone throwers 25 m behind, a second
## line past 12 units; ammunition wagons in a row behind all that, war
## elephants (rows with a body) in a row 30 m ahead of the line. units:
## Array of [type, count]. Returns {"placed": [{"i", "x", "back"}], "width",
## "depth"}.
static func army_layout(units: Array) -> Dictionary:
	var inf: Array = []
	var pikes: Array = []
	var cav: Array = []
	var screen: Array = []
	var bolts: Array = []
	var rear: Array = []
	var wagons: Array = []
	var beasts: Array = []
	for i in units.size():
		var ty: int = units[i][0]
		if UT.stat(ty, "wagon") >= 0:
			wagons.append(i)
			continue
		if UT.stat(ty, "body_r") > 0:
			beasts.append(i)
			continue
		if UT.stat(ty, "cmd_r") > 0:
			rear.append(i)  # the general behind the centre
			continue
		match UT.cls(ty):
			UT.CLS_PIKE:
				pikes.append(i)
			UT.CLS_CAV:
				cav.append(i)
			UT.CLS_MISSILE:
				screen.append(i)
			UT.CLS_ART:
				if UT.base_of(ty) == UT.STONE:
					rear.append(i)
				else:
					bolts.append(i)
			_:
				inf.append(i)
	var centre: Array = []
	var left_n := inf.size() / 2
	for k in left_n:
		centre.append(inf[k])
	centre.append_array(pikes)
	for k in range(left_n, inf.size()):
		centre.append(inf[k])
	var room := maxi(12 - cav.size() - bolts.size(), 2)
	var second: Array = []
	while centre.size() > room:
		second.append(centre.pop_back())
	var line: Array = []
	for k in (cav.size() + 1) / 2:
		line.append(cav[k])
	for k in (bolts.size() + 1) / 2:
		line.append(bolts[k])
	line.append_array(centre)
	for k in range((bolts.size() + 1) / 2, bolts.size()):
		line.append(bolts[k])
	for k in range((cav.size() + 1) / 2, cav.size()):
		line.append(cav[k])
	var placed: Array = []
	var width := 0
	width = maxi(width, _lay_row(units, line, 0, 4, placed))
	width = maxi(width, _lay_row(units, screen, -15, 6, placed))
	width = maxi(width, _lay_row(units, second, 45, 6, placed))
	var rb := 70 if not second.is_empty() else 25
	width = maxi(width, _lay_row(units, rear, rb, 8, placed))
	width = maxi(width, _lay_row(units, beasts, -30, 8, placed))
	var depth := 20
	if not rear.is_empty():
		depth = rb + 20
	elif not second.is_empty():
		depth = 60
	if not wagons.is_empty():
		width = maxi(width, _lay_row(units, wagons, depth + 10, 10, placed))
		depth += 25
	return {"placed": placed, "width": width, "depth": depth}


static func _lay_row(units: Array, row: Array, back: int, gap: int, placed: Array) -> int:
	if row.is_empty():
		return 0
	var total := -gap
	for i in row:
		total += _width_m(int(units[i][0]), int(units[i][1])) + gap
	var x := -total / 2
	for i in row:
		var w := _width_m(int(units[i][0]), int(units[i][1]))
		placed.append({"i": i, "x": x + w / 2, "back": back})
		x += w + gap
	return total


## A settlement battle (city map): `city` {seed, level, walls, bld},
## `terr` the region's ground (kind, seed, forest, ground palette), att /
## dfn Arrays of [type, count], def_side the defenders' sim side.
## Attackers stand MapGen.APPROACH metres out from the main gate facing it;
## defenders: missile troops on the wall stretches nearest the gates (main
## gate first), one solid foot unit (spears, pikes, heavy, light) just
## inside each gate, the rest round the plaza and down the main street;
## an open town (walls 0) is held at its street mouths. Returns
## {"scenario", "order": [[0 attacker / 1 defender, index], ...] in sim unit
## order, "layout": the generator's layout (metres, final frame)}.
## equip: the attackers' siege equipment (docs/DESIGN.md "Siege equipment
## and wall towers"): {"ladders": sets of ladders, "ram": rams, "towers":
## siege towers}, objects on the ground behind the middle of the attackers'
## line, 12 m apart (the rams in the middle), the siege towers in a row of
## their own 14 m further back (at the attackers' edge), in the scenario's
## "equip" list (BattleSim EQ_LADDERS / EQ_RAM / EQ_TOWER, x_m, y_m); only
## against walls, siege towers only against walls 2-3 (TOWER_WALLS).
## "mantlets": that many mantlets for the attackers (the scenario's
## "mantlets" key: the sim stands them before their missile and artillery
## units). The walls-2/3 city's tower engines are added by the sim.
static func settlement(city: Dictionary, terr: Dictionary, att: Array, dfn: Array, def_side: int,
		ai_sides: Array, equip: Dictionary = {}) -> Dictionary:
	var c := MapGen.city_params(city)
	c["def"] = def_side
	var al := army_layout(att)
	var fs := MapGen.city_field(c, int(al["width"]) + 40, int(al["depth"]) + 30)
	var t2: Dictionary = terr.duplicate(true)
	t2["city"] = c
	if int(t2.get("seed", -1)) < 0:
		t2["seed"] = int(c["seed"])
	var tt := Terrain.build(t2, 0, fs.x * 1024, fs.y * 1024)
	var mf := MapGen.build(t2, 0, fs.x, fs.y, tt)
	var lay: Dictionary = mf["city"]
	var w := fs.x
	var h := fs.y
	var att_side := 1 - def_side
	var sgn := 1 if def_side == 1 else -1  # attackers' "back" direction in y
	var units: Array = []
	var order: Array = []
	# Attackers: centred on the main gate, kept inside the field.
	var ax: int = lay["att_x"]
	var hw := int(al["width"]) / 2 + 8
	ax = clampi(ax, hw, w - hw)
	var ay: int = lay["att_y"]
	var aface := FACE_UP if def_side == 1 else FACE_DOWN
	var walled := int(c["walls"]) > 0
	for p in al["placed"]:
		var i: int = p["i"]
		var x := ax + int(p["x"]) * sgn
		var y := ay + int(p["back"]) * sgn
		units.append(unit(att_side, int(att[i][0]), int(att[i][1]), x, y, aface))
		order.append([0, i])
	# Defenders.
	var gates: Array = []
	for gd in lay["gates"]:
		if int(gd.get("cit", 0)) == 0:
			gates.append(gd)  # the outer gates (a citadel's is not held from inside the town)
	var mouths: Array = lay.get("mouths", [])
	var pl: Array = lay.get("agora", lay["plaza"])
	var mx: int = pl[0]
	var my: int = pl[1]
	var main_x: int = int(gates[0]["x"]) if not gates.is_empty() else (int(mouths[0][0]) if not mouths.is_empty() else mx)
	var main_y: int = int(gates[0]["y"]) if not gates.is_empty() else (int(mouths[0][1]) if not mouths.is_empty() else my + 40)
	var missiles: Array = []
	var solid: Array = []
	var rest: Array = []
	for i in dfn.size():
		var ty: int = dfn[i][0]
		var cl := UT.cls(ty)
		if cl == UT.CLS_MISSILE:
			missiles.append(i)
		elif cl == UT.CLS_INF or cl == UT.CLS_PIKE:
			solid.append(i)
		else:
			rest.append(i)
	# Solid units: spears first for the gates, then pikes, heavy, light.
	solid.sort_custom(func(a, b):
		var ka := _gate_rank(int(dfn[a][0]))
		var kb := _gate_rank(int(dfn[b][0]))
		return ka < kb or (ka == kb and a < b))
	var placed_def := {}
	# Wall stretches, nearest a gate first (the main gate's before the others').
	var segs: Array = lay["segs"]
	var seg_order: Array = []
	for k in segs.size():
		var sg: Array = segs[k]
		if sg.size() > 17 and (int(sg[17]) & (MapGen.SEG_SEA | MapGen.SEG_CIT)) != 0:
			continue  # the land side of the outer wall only
		var smx := (int(sg[0]) + int(sg[2])) / 2
		var smy := (int(sg[1]) + int(sg[3])) / 2
		var best := 1 << 30
		for g in gates.size():
			var d := FM.approx_len(smx - int(gates[g]["x"]), smy - int(gates[g]["y"])) + g * 25
			best = mini(best, d)
		seg_order.append([best, k])
	seg_order.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var seg_used := 0
	for i in missiles:
		if seg_used >= seg_order.size():
			break
		var k: int = seg_order[seg_used][1]
		seg_used += 1
		var sg: Array = segs[k]
		var ty: int = dfn[i][0]
		var cnt: int = dfn[i][1]
		var sdx := int(sg[2]) - int(sg[0])
		var sdy := int(sg[3]) - int(sg[1])
		var l := FM.isqrt(sdx * sdx + sdy * sdy)
		var fsp_m := UT.stat(ty, "file_sp")
		var files := clampi(maxi((cnt + 2) / 3, 4), 1, maxi(l * 1024 / fsp_m, 1))
		files = mini(files, cnt)
		var ranks := (cnt + files - 1) / files
		var depth := maxi(ranks - 1, 0) * UT.stat(ty, "rank_sp") / 1024
		var dir: int = sg[4]
		var x := (int(sg[0]) + int(sg[2])) / 2 + FM.cos_a(dir) * depth / 2 / FM.TRIG_ONE
		var y := (int(sg[1]) + int(sg[3])) / 2 + FM.sin_a(dir) * depth / 2 / FM.TRIG_ONE
		var ud := unit(def_side, ty, cnt, x, y, dir, files)
		ud["wall"] = k + 1
		units.append(ud)
		order.append([1, i])
		placed_def[i] = true
	# Gate guards (walled) or street-mouth holders (open town).
	var holds: Array = []  # [x, y, facing]
	if not gates.is_empty():
		for gd in gates:
			var dir: int = gd["dir"]
			holds.append([int(gd["ix"]) - FM.cos_a(dir) * 5 / FM.TRIG_ONE,
				int(gd["iy"]) - FM.sin_a(dir) * 5 / FM.TRIG_ONE, dir])
	else:
		var r0: int = lay["r0"]
		for mo in mouths:
			var a: Array = mo
			var dx := int(a[0]) - mx
			var dy := int(a[1]) - my
			var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
			var t := r0 * 80 / 100
			holds.append([mx + dx * t / l, my + dy * t / l, FM.atan2_a(dy, dx)])
	var n_hold := mini(holds.size(), maxi(solid.size() - (1 if solid.size() > 2 else 0), 0))
	if solid.size() == 1:
		n_hold = 1
	for k in n_hold:
		var i: int = solid[k]
		var hd: Array = holds[k]
		var ty: int = dfn[i][0]
		var files := mini(8 if not gates.is_empty() else 14, int(dfn[i][1]))
		units.append(unit(def_side, ty, int(dfn[i][1]), int(hd[0]), int(hd[1]), int(hd[2]), files))
		order.append([1, i])
		placed_def[i] = true
	# Everyone else: the plaza, then down the main street toward the main
	# gate, 22 m apart (missile troops that found no wall at the back).
	var face_main := FM.atan2_a(main_y - my, main_x - mx)
	var mdx := main_x - mx
	var mdy := main_y - my
	var mlen := maxi(FM.isqrt(mdx * mdx + mdy * mdy), 1)
	var slot := 0
	var others: Array = []
	for i in solid:
		if not placed_def.has(i):
			others.append(i)
	others.append_array(rest)
	for i in missiles:
		if not placed_def.has(i):
			others.append(i)
	for i in others:
		var ty: int = dfn[i][0]
		var along := mini(slot * 22, mlen * 60 / 100)
		var side_off := 0
		if slot * 22 > mlen * 60 / 100:
			side_off = ((slot % 2) * 2 - 1) * 14
		var x := mx + mdx * along / mlen - mdy * side_off / mlen
		var y := my + mdy * along / mlen + mdx * side_off / mlen
		var files := mini(10, int(dfn[i][1]))
		if UT.cls(ty) == UT.CLS_ART:
			files = -1
		units.append(unit(def_side, ty, int(dfn[i][1]), x, y, face_main, files))
		order.append([1, i])
		slot += 1
	# Deployment zones (used when the battle has a deployment phase): the
	# attackers the approach band (from 40 m ahead of their front to their
	# edge), the defenders inside the walls and on the walkways (an open
	# town: the square round it).
	var zones: Array = []
	var att_front: int = lay["att_y"]
	if def_side == 1:
		zones.append([att_side, 0, 0, clampi(att_front - 40, 0, h), w, h])
	else:
		zones.append([att_side, 0, 0, 0, w, clampi(att_front + 40, 0, h)])
	if int(lay.get("walls", 0)) > 0 and not segs.is_empty():
		var x0 := w
		var y0 := h
		var x1 := 0
		var y1 := 0
		for sg in segs:
			x0 = mini(x0, mini(int(sg[0]), int(sg[2])))
			y0 = mini(y0, mini(int(sg[1]), int(sg[3])))
			x1 = maxi(x1, maxi(int(sg[0]), int(sg[2])))
			y1 = maxi(y1, maxi(int(sg[1]), int(sg[3])))
		zones.append([def_side, 1, maxi(x0 - 4, 0), maxi(y0 - 4, 0), mini(x1 + 4, w), mini(y1 + 4, h)])
	else:
		var r0: int = int(lay.get("r0", 80)) + 10
		var tcx: int = lay["cx"]
		var tcy: int = lay["cy"]
		zones.append([def_side, 0, maxi(tcx - r0, 0), maxi(tcy - r0, 0), mini(tcx + r0, w), mini(tcy + r0, h)])
	var sc := {"width_m": w, "height_m": h, "ai_sides": ai_sides, "units": units, "terrain": t2,
		"deploy_zones": zones}
	if walled:
		var eq_l := clampi(int(equip.get("ladders", 0)), 0, 8)
		var eq_r := clampi(int(equip.get("ram", 0)), 0, 2)
		var eq_t := clampi(int(equip.get("towers", 0)), 0, 3)
		if int(c["walls"]) < TOWER_WALLS:
			eq_t = 0
		if eq_l + eq_r + eq_t > 0:
			# Behind the middle of the attackers' line, in a row 12 m apart.
			var row: Array = []
			for k in eq_l / 2 + eq_l % 2:
				row.append(EQ_LADDERS)
			for k in eq_r:
				row.append(EQ_RAM)
			for k in eq_l / 2:
				row.append(EQ_LADDERS)
			var back := int(al["depth"]) + 12
			var ey := clampi(ay + back * sgn, 10, h - 10)
			var eqs: Array = []
			var n_e := row.size()
			for k in n_e:
				var ex := clampi(ax + (k * 2 - (n_e - 1)) * 6, 10, w - 10)
				eqs.append([int(row[k]), ex, ey])
			# Index order: the ladder sets first (left to right), then the rams.
			var out_eq: Array = []
			for e in eqs:
				if int(e[0]) == EQ_LADDERS:
					out_eq.append(e)
			for e in eqs:
				if int(e[0]) == EQ_RAM:
					out_eq.append(e)
			# Siege towers last, in a row of their own behind (18 m apart).
			var ty := clampi(ay + (back + 14) * sgn, 10, h - 10)
			for k in eq_t:
				out_eq.append([EQ_TOWER, clampi(ax + (k * 2 - (eq_t - 1)) * 9, 10, w - 10), ty])
			sc["equip"] = out_eq
		var eq_m := clampi(int(equip.get("mantlets", 0)), 0, 8)
		if eq_m > 0:
			var mt := [0, 0]
			mt[att_side] = eq_m
			sc["mantlets"] = mt
	return {"scenario": sc, "order": order, "layout": lay}


## Deployment zones for a field battle (metres): each side's part of the
## field from `gap` m beyond the centre line to its own edge, plus a box of
## `pad` m round every unit of that side standing outside it (armies that
## arrive on a flank). [[side, 0 (BattleSim.DZ_RECT), x0, y0, x1, y1], ...].
static func field_zones(sc: Dictionary, gap: int = 30, pad: int = 40) -> Array:
	var w := int(sc["width_m"])
	var h := int(sc["height_m"])
	var zones: Array = []
	var rg := {}
	if sc.get("river") is Dictionary:
		# A river crossing: each side's zone ends RIV_ZONE short of the water
		# (side 0 below it, side 1 above), never across it.
		rg = MapGen.river_geom(sc["river"], w, h)
	for s in 2:
		var sy := 0
		var cnt := 0
		for ud in sc["units"]:
			if int(ud["side"]) == s:
				sy += int(ud["y_m"])
				cnt += 1
		var bottom := cnt == 0 and s == 0 or cnt > 0 and sy / cnt > h / 2
		if not rg.is_empty():
			bottom = s == 0
		var band := [s, 0, 0, h / 2 + gap, w, h] if bottom else [s, 0, 0, 0, w, h / 2 - gap]
		if not rg.is_empty():
			if bottom:
				band[3] = maxi(int(band[3]), MapGen.river_reach(rg, 0, w, 0) + RIV_ZONE)
			else:
				band[5] = mini(int(band[5]), MapGen.river_reach(rg, 0, w, 1) - RIV_ZONE)
		zones.append(band)
		for ud in sc["units"]:
			if int(ud["side"]) != s:
				continue
			var x := int(ud["x_m"])
			var y := int(ud["y_m"])
			if y >= int(band[3]) and y <= int(band[5]):
				continue
			zones.append([s, 0, maxi(x - pad, 0), maxi(y - pad, 0), mini(x + pad, w), mini(y + pad, h)])
	return zones


static func _gate_rank(ty: int) -> int:
	var b := UT.base_of(ty)
	if b == UT.SPEAR:
		return 0
	if b == UT.PIKE:
		return 1
	if b == UT.HEAVY:
		return 2
	return 3


## Standard attacking army for the settlement tests (12 units, ~1,000 men).
const SIEGE_ARMY := [[UT.CAVALRY, 60], [UT.BOLT, 16], [UT.LIGHT, 100], [UT.HEAVY, 100],
	[UT.PIKE, 120], [UT.HEAVY, 100], [UT.SPEAR, 100], [UT.CAVALRY, 60], [UT.ARCHER, 80],
	[UT.JAVELIN, 60], [UT.ARCHER, 80], [UT.STONE, 18]]
## Garrison units in order (a settlement has 2 + level + walls of them, like
## the campaign's, at 60 men).
const SIEGE_GARRISON := [UT.SPEAR, UT.ARCHER, UT.HEAVY, UT.ARCHER, UT.SPEAR, UT.HEAVY, UT.ARCHER,
	UT.PIKE, UT.SPEAR]


## Sandbox settlement battle: the player (side 0) attacks, or defends
## (def_side 0), a settlement of this seed, level and wall level held by a
## campaign-like garrison and a small field army (AI on the other side).
static func siege_test(city_seed: int, level: int, walls: int, ground: int, kind: int,
		def_side: int = 1, forest: int = -1, plan: int = MapGen.PLAN_RING, coast: int = 0,
		equip: Dictionary = {}) -> Dictionary:
	var dfn: Array = []
	var n_gar := 2 + level + walls + (1 if level == 2 else 0)
	for k in n_gar:
		dfn.append([SIEGE_GARRISON[k % SIEGE_GARRISON.size()], 60])
	for e in [[UT.HEAVY, 100], [UT.SPEAR, 100], [UT.ARCHER, 80], [UT.CAVALRY, 40]]:
		dfn.append(e)
	if forest < 0:
		forest = MapGen.PALETTE_FOREST[ground]
	var terr := {"kind": kind, "seed": city_seed * 7 + 3, "forest": forest, "ground": ground}
	# The player is side 0 (attacking or defending); the AI side 1.
	var att: Array = SIEGE_ARMY.duplicate(true)
	var city := {"seed": city_seed, "level": level, "walls": walls, "bld": [1, 2, 4]}
	if plan != MapGen.PLAN_RING:
		city["plan"] = plan
		city["coast"] = coast
	var r := settlement(city, terr, att, dfn, def_side, [1], equip)
	return r["scenario"]


## The fair siege (tests/matchups.gd --only=fair-sieges): a city (level 2)
## of this seed, walls and plan on flat ground, defended by its garrison
## (2 + level + walls + 1 units of 60, as siege_test) and a field army,
## attacked by SIEGE_ARMY; the defenders' field army is SIEGE_ARMY less the
## garrison's strength (count x cost per man, campaign CState.strength)
## taken from its end, so both sides are equally strong. equip: the
## attackers' siege equipment (settlement()); its optional key "extra"
## ([[type, men], ...]) adds units to the attackers' end (light artillery
## in the "full kit" row), so the defenders' field army leaves out the same
## strength and both sides stay equal. Both sides AI.
static func fair_siege(city_seed: int, walls: int, plan: int, equip: Dictionary) -> Dictionary:
	var att: Array = SIEGE_ARMY.duplicate(true)
	att.append_array(equip.get("extra", []).duplicate(true))
	var level := 2
	var gar: Array = []
	var n_gar := 2 + level + walls + 1
	var g_str := 0
	for k in n_gar:
		var ty: int = SIEGE_GARRISON[k % SIEGE_GARRISON.size()]
		gar.append([ty, 60])
		g_str += 60 * UT.stat(ty, "cost")
	var field: Array = att.duplicate(true)
	var left := g_str
	while left > 0 and not field.is_empty():
		var e: Array = field[field.size() - 1]
		var c := UT.stat(int(e[0]), "cost")
		var s := int(e[1]) * c
		if s <= left:
			left -= s
			field.pop_back()
		else:
			e[1] = int(e[1]) - (left + c - 1) / c
			left = 0
	var dfn: Array = gar.duplicate()
	dfn.append_array(field)
	var terr := {"kind": Terrain.K_FLAT, "seed": city_seed * 7 + 3, "forest": MapGen.PALETTE_FOREST[MapGen.PAL_DRY],
		"ground": MapGen.PAL_DRY}
	var city := {"seed": city_seed, "level": level, "walls": walls, "bld": [1, 2, 4], "plan": plan, "coast": 0}
	var r := settlement(city, terr, att, dfn, 1, [0, 1], equip)
	return r["scenario"]


## bench_4000_city: two armies storm a walled city (walls 2) held by a large
## garrison and a field army; AI against AI. Fixed seeds (map generator
## version 1) so timings compare between builds.
static func bench_city(plan: int = MapGen.PLAN_RING, coast: int = 0, kind: int = Terrain.K_ROLLING,
		walls: int = 2) -> Dictionary:
	var att: Array = SIEGE_ARMY.duplicate(true)
	att.append_array(SIEGE_ARMY.duplicate(true))
	var dfn: Array = []
	for k in 8:
		dfn.append([SIEGE_GARRISON[k % SIEGE_GARRISON.size()], 70])
	var army := [[UT.HEAVY, 100], [UT.SPEAR, 100], [UT.PIKE, 120], [UT.HEAVY, 100], [UT.LIGHT, 100],
		[UT.ARCHER, 80], [UT.ARCHER, 80], [UT.JAVELIN, 60], [UT.CAVALRY, 60], [UT.SPEAR, 100],
		[UT.HEAVY, 100], [UT.LIGHT, 100], [UT.ARCHER, 80], [UT.STONE, 18], [UT.BOLT, 16],
		[UT.SPEAR, 100], [UT.PIKE, 120], [UT.HEAVY, 100]]
	dfn.append_array(army)
	var terr := {"kind": kind, "seed": 4243, "forest": 20, "ground": MapGen.PAL_DRY}
	var city := {"seed": 4242, "level": 2, "walls": walls, "bld": [1, 2, 3, 4, 5]}
	if plan != MapGen.PLAN_RING:
		city["plan"] = plan
		city["coast"] = coast
	var r := settlement(city, terr, att, dfn, 1, [0, 1])
	return r["scenario"]
