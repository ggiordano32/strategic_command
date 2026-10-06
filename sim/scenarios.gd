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
		files = int(FILES[b]) * count / maxi(int(SIZE[b]), 1)
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
	var files := maxi(int(FILES[b]) * count / maxi(int(SIZE[b]), 1), 4)
	return files * UT.stat(ty, "file_sp") / 1024


# ------------------------------------------------------------ settlements ---

## Lay out one army (side-0 coordinates: x from the centre, "back" metres
## behind the front line) the way the campaign does: cavalry on the wings,
## bolt throwers at the line ends, infantry inside with pikes in the
## centre, missile troops 15 m ahead, stone throwers 25 m behind, a second
## line past 12 units. units: Array of [type, count]. Returns {"placed":
## [{"i", "x", "back"}], "width", "depth"}.
static func army_layout(units: Array) -> Dictionary:
	var inf: Array = []
	var pikes: Array = []
	var cav: Array = []
	var screen: Array = []
	var bolts: Array = []
	var rear: Array = []
	for i in units.size():
		var ty: int = units[i][0]
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
	var depth := 20
	if not rear.is_empty():
		depth = rb + 20
	elif not second.is_empty():
		depth = 60
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
static func settlement(city: Dictionary, terr: Dictionary, att: Array, dfn: Array, def_side: int,
		ai_sides: Array) -> Dictionary:
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
	return {"scenario": {"width_m": w, "height_m": h, "ai_sides": ai_sides, "units": units, "terrain": t2},
		"order": order, "layout": lay}


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
		def_side: int = 1, forest: int = -1, plan: int = MapGen.PLAN_RING, coast: int = 0) -> Dictionary:
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
	var r := settlement(city, terr, att, dfn, def_side, [1])
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
