extends RefCounted
## Scenario definitions as plain data (ints only) for BattleSim.setup().

const UT := preload("res://sim/unit_types.gd")

const FACE_UP := 768    # -y
const FACE_DOWN := 256  # +y

const IDS: Array[String] = ["skirmish", "battle_2000", "battle_4000",
	"bench_2000", "bench_4000"]


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
	return id


static func make(id: String) -> Dictionary:
	match id:
		"skirmish":
			return _armies(2, 1, 100, [1])
		"battle_2000":
			return _armies(10, 1, 100, [1])
		"battle_4000":
			return _armies(10, 2, 100, [1])
		"bench_2000":
			return _armies(10, 1, 100, [0, 1])
		"bench_4000":
			return _armies(10, 2, 100, [0, 1])
	push_error("unknown scenario " + id)
	return {}


## Two armies facing each other across the field. `per_line` units side by
## side, `lines` lines deep, `count` soldiers per unit.
static func _armies(per_line: int, lines: int, count: int, ai_sides: Array) -> Dictionary:
	var width_m := 480
	var height_m := 400
	var files := 25
	var unit_w := 28 + 6  # frontage in metres plus a gap
	var pattern := [UT.SPEAR, UT.HEAVY, UT.LIGHT, UT.HEAVY, UT.SPEAR,
		UT.HEAVY, UT.LIGHT, UT.HEAVY, UT.SPEAR, UT.HEAVY]
	var units: Array = []
	var cx := width_m / 2
	var cy := height_m / 2
	for side in 2:
		for line in lines:
			for k in per_line:
				var x := cx + (2 * k - (per_line - 1)) * unit_w / 2
				# Side 0 at the bottom facing up, side 1 at the top facing down.
				var front := 60 + line * 30
				var y := cy + front if side == 0 else cy - front
				var ty: int = pattern[(k + line * 3 + side) % pattern.size()]
				units.append({
					"side": side,
					"type": ty,
					"count": count,
					"x_m": x,
					"y_m": y,
					"facing": FACE_UP if side == 0 else FACE_DOWN,
					"files": files,
				})
	return {
		"width_m": width_m,
		"height_m": height_m,
		"ai_sides": ai_sides,
		"units": units,
	}
