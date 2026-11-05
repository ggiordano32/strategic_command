extends RefCounted
## The battle AI's ships (docs/AI.md 62; docs/design/battle_sim.md "A fleet at the shore (as built, 2026-11-05)").
## BattleAI.think and SiegeAI.think hand it every ready unit of an AI side that is a ship's hull or her landing party
## (BattleSim u_ship) before their own rules; like them it only queues the orders a player can give (fire at will, an
## attack, ORDER_LAND), and its memory is the hashed sh_idle. Knobs: AP.SH_* (ai_profile.gd).
##   guns      fire at will; with SH_FOCUS, an enemy ship in reach first, then a battery, by the line of fire.
##   land      a defending ship's party goes ashore once the town is stormed (an attacker in its streets or on its
##             walls) or her guns have had nothing to shoot at for SH_IDLE_T (a hull with no guns: from the
##             battle's start); an attacking ship's once her side storms (SiegeAI's assault phase; the field: the
##             engagement) while its strength is under SH_LAND_ATT_PCT % of the enemy's. Easy never lands.
##   party     a party sent ashore keeps paddling to its landing until it is there, then the side's usual rules
##             take it (out of the harbour's canoe rules: it landed already).

const UT := preload("res://sim/unit_types.gd")
const AP := preload("res://sim/ai_profile.gd")
const MapGen := preload("res://sim/mapgen.gd")
const FM := preload("res://sim/fixed_math.gd")

const M := 1024
const AI_PLAYER_BASE := 100        # (BattleAI.AI_PLAYER_BASE)
const U_READY := 0                 # (BattleSim)
const O_NONE := 0
const O_MOVE := 1
const O_ATTACK := 2
const ORDER_ATTACK := 2
const ORDER_FIRE := 5
const ORDER_LAND := 29
const SP_ASSAULT := 11             # (SiegeAI)
const P_ENGAGE := 2                # (BattleAI)
const LANDED_R := 25 * M           # a party within this of its landing, not afloat, has landed


## Unit u (ready, of an AI side, BattleSim u_ship >= 0): true when the ships' rules took it this think.
static func think(sim, u: int, kn: PackedInt32Array) -> bool:
	var s: int = sim.u_ship[u]
	if sim.sh_unit[s] == u:
		_hull(sim, u, s, kn)
		return true
	# A landing party: on its way in until it is ashore at its landing.
	if sim.sh_land[s] < 0:
		return true
	if sim.afloat(u):
		return true
	var d := FM.approx_len(sim.u_ax[u] - sim.sh_lx[s], sim.u_ay[u] - sim.sh_ly[s])
	return sim.u_order[u] == O_MOVE and d > LANDED_R and sim.u_dx[u] == sim.sh_lx[s] and sim.u_dy[u] == sim.sh_ly[s]


static func _order(sim, u: int, o: Dictionary, k: int) -> void:
	o["tick"] = sim.tick
	o["unit"] = u
	o["player"] = AI_PLAYER_BASE + sim.u_side[u]
	o["seq"] = u * 32 + k
	sim.queue_order(o)


static func _hull(sim, u: int, s: int, kn: PackedInt32Array) -> void:
	var side: int = sim.u_side[u]
	var guns: bool = sim.u_neng[u] > 0
	if guns:
		if sim.u_fire[u] == 0 and sim.u_ammo[u] > 0:
			_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		if sim.u_ftarget[u] >= 0 or (sim.u_order[u] == O_ATTACK and sim.u_target[u] >= 0):
			sim.sh_idle[s] = sim.tick
		if kn[AP.SH_FOCUS] != 0 and sim.u_ammo[u] > 0:
			_focus(sim, u)
	if sim.sh_party[s] < 0 or sim.sh_land[s] >= 0 or sim.land_refusal(sim, u) != "":
		return
	var go := false
	if side == sim.city_def:
		if kn[AP.SH_LAND_DEF] != 0:
			go = _stormed(sim, side) or not guns or sim.tick - sim.sh_idle[s] >= kn[AP.SH_IDLE_T]
	elif kn[AP.SH_LAND_ATT_PCT] > 0:
		var storm: bool = sim.ai_phase[side] == (SP_ASSAULT if sim.city_on != 0 else P_ENGAGE)
		go = storm and _strength(sim, side) * 100 < _strength(sim, 1 - side) * kn[AP.SH_LAND_ATT_PCT]
	if go:
		_order(sim, u, {"type": ORDER_LAND}, 22)


## The town of the defending side `side` is stormed: an attacker (not a ship) in its streets or on its walls.
static func _stormed(sim, side: int) -> bool:
	if sim.city_on == 0:
		return false
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.is_ship(o) or sim.afloat(o):
			continue
		if sim.u_wall[o] > 0:
			return true
		if (sim.veg_bits(sim.u_cx[o], sim.u_cy[o]) & MapGen.V_URBAN) != 0 \
				and (sim.nav_at(sim.u_cx[o], sim.u_cy[o]) & MapGen.NAV_GROUND) != 0:
			return true
	return false


## A side's fighting strength (men x cost; the ships' parties aboard and the hulls left out).
static func _strength(sim, side: int) -> int:
	var t := 0
	for o in sim.n_units:
		if sim.u_side[o] == side and sim.u_state[o] == U_READY and not sim.is_ship(o):
			t += sim.u_alive[o] * UT.stat(sim.u_type[o], "cost")
	return t


## SH_FOCUS: the guns at an enemy ship in reach, else an enemy battery in reach (nearest first, with a line of fire);
## else fire at will.
static func _focus(sim, u: int) -> void:
	var ty: int = sim.u_type[u]
	var mn := UT.stat(ty, "m_min")
	var rng := UT.stat(ty, "m_range")
	var best := -1
	var bs := 0
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_alive[o] <= 0 \
				or sim.hidden_from(o, sim.u_side[u]):
			continue
		var cls := 0
		if sim.is_ship(o) and sim.u_neng[o] > 0:
			cls = 2
		elif sim.u_cls[o] == UT.CLS_ART:
			cls = 1
		if cls == 0:
			continue
		var sc := cls * 100000 - FM.approx_len(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u]) / M
		if best >= 0 and sc <= bs:
			continue
		if not sim._art_in_range(u, o, mn, rng) or not sim.art_safe(u, o):
			continue
		best = o
		bs = sc
	if best >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != best:
			_order(sim, u, {"type": ORDER_ATTACK, "target": best, "run": 0}, 0)
	elif sim.u_order[u] == O_ATTACK:
		_order(sim, u, {"type": 3}, 5)  # (nothing to focus on: halt, fire at will)
