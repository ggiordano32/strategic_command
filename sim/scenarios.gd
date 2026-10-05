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
	"test_bolts_crest"]

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
	return id


static func make(id: String) -> Dictionary:
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
