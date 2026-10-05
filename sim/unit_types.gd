extends RefCounted
## Unit type stats as plain integer data. The sim copies these into packed
## arrays at setup, so adding a type is a matter of adding a row here.
##
## Units of measure (all ints):
##   distances in sim units (1 m = 1024), speeds in sim units per tick (10 Hz),
##   chances in percent, hp/damage in hit points, cooldown in ticks,
##   morale on a 0..1000 scale, angles in 1/1024 of a turn.
##
## Fields:
##   cls          CLS_* behaviour class (infantry, pike, missile, cavalry)
##   sprite       view-only sprite index (see game/soldier_layer.gd)
##   attack/defence/armour/shield/damage/reach   melee stats; shield is the %
##                chance to block a frontal melee hit
##   mshield      % chance to block a missile arriving from the frontal arc
##   m_vuln       % damage taken from missiles (horses are big, exposed targets)
##   m_down       % of missile hits that bring the soldier down outright (horses)
##   ranks_reach  ranks that can strike to the front from formation (pikes)
##   mass         used by cavalry impact (rider and horse together)
##   file_sp/rank_sp  formation spacing
##   turn         max formation turn per tick (0 = turns at once)
##   brace        impact turned back on cavalry charging the braced front
##   vs_cav       melee attack and damage bonus against cavalry
##   charge       cavalry impact power at full momentum
##   sec_*        secondary weapon (pikes once disordered or hit in the flank)
##   m_*          missiles: range, damage, armour piercing %, ammunition per
##                soldier, reload ticks, scatter (per mille of distance, plus
##                m_spread0), flight speed per tick, arc (1 = over friends)
##   skirm        skirmish mode on by default
##   m_lead       % of a moving target's movement over the flight that the
##                shooters lead by (stone throwers lead a little short)
##   m_long       % of the along-flight error kept when it is long (stones
##                land short rather than over: a short stone ploughs into the
##                front ranks)
##   cost         recruitment cost per soldier (balance bookkeeping)
## Artillery (cls CLS_ART; the unit's soldiers are the crews, "count" in a
## scenario is crews x engines, files = engines):
##   crew         crew per engine at full strength
##   crew_min     an engine with fewer crew at it falls silent
##   m_kind       1 bolt (flat, pierces along its line), 2 stone (lobbed,
##                blast plus plough along the flight direction)
##   m_ammo       shots per ENGINE (not per soldier)
##   m_reload     ticks per shot at full crew (slower with fewer crew)
##   m_min        minimum range
##   m_damage     energy of the shot; each victim takes what is left of it
##                (bolt: less shield absorption and armour; stone: armour x
##                (100 - m_ap)%), and absorbs some of it
##   m_pierce     at most this many victims per shot
##   m_plough     bolt: flight on past the aim point; stone: plough length
##   m_blast      stone: radius of the direct hit at the landing point
##   m_fear       fright per shot that hits a unit (short-lived morale loss)
##   arc          firing arc either side of the battery's facing (angle units)
##   traverse     engine traverse per tick (angle units)
##   deploy       ticks to set up (packing up takes half as long)
##   e_hp         engine hit points (wrecked at 0: melee next to it, stones)
##   m_reserve    shots per engine carried in the baggage: the Refill order
##                brings them up (one full reload)
##   m_refill     ticks of work per shot refilled at full crew
## Terrain (see docs/DESIGN.md "Terrain"):
##   climb        % of speed lost per 10% of uphill grade (cavalry and
##                packed artillery suffer most)
##   m_hgain      missile range gained per metre the shooter stands above the
##                target, in % of a metre (lost shooting uphill)
##   m_apex       flat weapons (m_arc 0): how high the missile rises at
##                mid-flight above the straight line, in % of the distance;
##                ground above that line blocks the shot

## Display only (never read by the sim, not hashed): icon (marker / card
## symbol, see game/unit_icons.gd), role, desc, good_vs, weak_vs (unit book).

const CLS_INF := 0
const CLS_PIKE := 1
const CLS_MISSILE := 2
const CLS_CAV := 3
const CLS_ART := 4

const HEAVY := 0
const LIGHT := 1
const SPEAR := 2
const PIKE := 3
const ARCHER := 4
const JAVELIN := 5
const CAVALRY := 6
const BOLT := 7
const STONE := 8

## Defaults for every field a row may leave out.
const DEFAULTS := {
	"cls": CLS_INF, "sprite": 0, "mshield": 0, "ranks_reach": 1,
	"file_sp": 1126, "rank_sp": 1331, "turn": 0, "brace": 0, "vs_cav": 0,
	"charge": 0, "sec_attack": 0, "sec_defence": 0, "sec_damage": 0,
	"sec_reach": 0, "m_range": 0, "m_damage": 0, "m_ap": 0, "m_ammo": 0,
	"m_reload": 0, "m_spread": 0, "m_spread0": 0, "m_speed": 1, "m_arc": 0,
	"skirm": 0, "cost": 5, "icon": 0, "m_vuln": 100, "m_down": 0, "m_lead": 100, "m_long": 100,
	"crew": 0, "crew_min": 0, "m_kind": 0, "m_min": 0, "m_pierce": 0, "m_plough": 0,
	"m_blast": 0, "m_fear": 0, "arc": 0, "traverse": 0, "deploy": 0, "e_hp": 0,
	"climb": 15, "m_hgain": 0, "m_apex": 0, "m_reserve": 0, "m_refill": 0,
}

const TYPES: Array[Dictionary] = [
	{
		"name": "Heavy Swords",
		"short": "Heavy",
		"icon": 0,
		"role": "Line infantry",
		"desc": "Armoured swordsmen with large shields, the backbone of the line. They win most straight fights and shrug off arrows from the front.",
		"good_vs": "Light infantry, missile troops that let them close, cavalry charging their front; about even with spearmen.",
		"weak_vs": "Pike blocks from the front, attacks on their flank or rear, cavalry charging their back.",
		"attack": 40,        # melee attack skill
		"defence": 35,       # melee defence skill
		"armour": 14,        # subtracted from weapon damage
		"shield": 40,        # % chance to block a frontal hit
		"mshield": 70,       # big shields stop most frontal missiles
		"damage": 42,        # weapon damage per hit
		"reach": 1331,       # 1.3 m
		"mass": 90,
		"walk": 133,         # 1.3 m/s
		"run": 369,          # 3.6 m/s
		"hp": 100,
		"cooldown": 11,      # ticks between swings
		"morale": 900,
		"cost": 6,
	},
	{
		"name": "Light Infantry",
		"short": "Light",
		"icon": 1,
		"role": "Fast infantry",
		"desc": "Fast, lightly armoured fighters. Cheap and quick to reach a flank, but they lose a fair fight and suffer badly from arrows.",
		"good_vs": "Archers caught in melee, the flank and rear of engaged units, skirmishers they can run down.",
		"weak_vs": "Heavy infantry, any formed pike front, cavalry, archers at range.",
		"attack": 36,
		"defence": 26,
		"armour": 4,
		"shield": 15,
		"mshield": 40,
		"damage": 36,
		"reach": 1229,       # 1.2 m
		"mass": 70,
		"walk": 164,         # 1.6 m/s
		"run": 451,          # 4.4 m/s
		"hp": 85,
		"cooldown": 9,
		"morale": 600,
		"cost": 4,
		"climb": 13,
	},
	{
		"name": "Spearmen",
		"short": "Spear",
		"icon": 2,
		"role": "Anti-cavalry infantry",
		"desc": "Steady spearmen whose second rank can also reach. Standing still in formation they brace: cavalry charging their front is thrown back.",
		"good_vs": "Cavalry (a charge into the braced front costs the riders dearly), light infantry; about even with heavy swords.",
		"weak_vs": "Pike blocks, archers and javelins, charges into their flank or rear.",
		"sprite": 1,
		"attack": 15,
		"defence": 30,
		"armour": 9,
		"shield": 35,
		"mshield": 55,
		"damage": 30,
		"reach": 2253,       # 2.2 m
		"mass": 80,
		"walk": 133,
		"run": 369,
		"hp": 90,
		"cooldown": 11,
		"morale": 780,
		"brace": 55,         # hp of impact turned back on a frontal charge
		"vs_cav": 20,
		"cost": 5,
	},
	{
		"name": "Pikemen",
		"short": "Pike",
		"icon": 3,
		"role": "Phalanx",
		"desc": "A dense block whose first four ranks all strike with 5.5 m pikes. While formed and facing the enemy, attackers are held off the points and ground down. Slow to turn; once disordered or flanked they fall back on short swords and fight poorly.",
		"good_vs": "Anything attacking its front: swords, spears, light infantry, cavalry.",
		"weak_vs": "Flank and rear attacks (pin the front, hit the side), archers, being made to turn or run, steep ground (the wall breaks up).",
		"cls": CLS_PIKE,
		"sprite": 2,
		"attack": 34,        # with the pike, formed and facing the enemy
		"defence": 40,
		"armour": 8,
		"shield": 20,        # small shield slung on the arm
		"mshield": 30,
		"damage": 30,
		"reach": 5632,       # 5.5 m: ranks 1-4 strike past the front
		"ranks_reach": 4,
		"mass": 80,
		"walk": 123,         # 1.2 m/s
		"run": 307,          # 3.0 m/s
		"hp": 90,
		"cooldown": 12,
		"morale": 820,
		"file_sp": 1024,     # dense: 1.0 m files
		"rank_sp": 1126,     # 1.1 m ranks
		"turn": 3,           # ~1 degree per tick: 90 degrees in ~8.5 s
		"brace": 80,
		"vs_cav": 20,
		"sec_attack": 18,    # short sword once disordered / flanked
		"sec_defence": 16,
		"sec_damage": 24,
		"sec_reach": 1024,
		"cost": 5,
		"climb": 17,         # a dense block keeps its order with effort
	},
	{
		"name": "Archers",
		"short": "Archer",
		"icon": 4,
		"role": "Missile infantry",
		"desc": "Long-range bowmen who shoot over friendly units and hills and lead moving targets. Deadly to light troops, to cavalry caught in the open and to anything shot in the flank or rear; big shields stop most arrows from the front. From a hill they outrange archers below. They keep shooting their chosen target, so cavalry can slip in while they are busy. Weak in melee.",
		"good_vs": "Light infantry, pikemen, cavalry in the open, exposed flanks.",
		"weak_vs": "Cavalry that reaches them while they shoot at something else, heavy infantry from the front, any melee unit that closes.",
		"cls": CLS_MISSILE,
		"sprite": 3,
		"attack": 18,
		"defence": 16,
		"armour": 3,
		"shield": 0,
		"mshield": 0,
		"damage": 24,
		"reach": 1024,
		"mass": 65,
		"walk": 154,
		"run": 410,
		"hp": 75,
		"cooldown": 11,
		"morale": 640,
		"file_sp": 1331,
		"rank_sp": 1638,
		"m_range": 140 * 1024,
		"m_damage": 30,
		"m_ap": 25,
		"m_ammo": 40,
		"m_reload": 40,       # one arrow per soldier every 4 s
		"m_spread": 45,       # 4.5% of the distance ...
		"m_spread0": 1024,    # ... plus 1 m
		"m_speed": 4608,      # 45 m/s
		"m_arc": 1,
		"cost": 5,
		"climb": 14,
		"m_hgain": 150,     # +15 m of range from 10 m higher
	},
	{
		"name": "Javelinmen",
		"short": "Javelin",
		"icon": 5,
		"role": "Skirmishers",
		"desc": "Loose-order skirmishers throwing armour-piercing javelins at short range. By default they fall back from approaching melee troops, and they need a clear line past friendly units and over the ground: they cannot throw through a crest.",
		"good_vs": "Light infantry and archers, standing cavalry, the flanks of engaged units.",
		"weak_vs": "Heavy infantry, spearmen and pikes that close, cavalry that catches them.",
		"cls": CLS_MISSILE,
		"sprite": 4,
		"attack": 28,
		"defence": 22,
		"armour": 3,
		"shield": 20,
		"mshield": 35,
		"damage": 28,
		"reach": 1229,
		"mass": 70,
		"walk": 170,
		"run": 430,          # 4.2 m/s: light infantry (4.4) can catch them
		"hp": 80,
		"cooldown": 10,
		"morale": 500,
		"file_sp": 1843,     # loose order
		"rank_sp": 2048,
		"m_range": 40 * 1024,
		"m_damage": 42,
		"m_ap": 60,
		"m_ammo": 6,         # was 4 (8 let skirmishers kite spearmen to death too)
		"m_reload": 28,
		"m_spread": 40,
		"m_spread0": 717,
		"m_speed": 2253,      # 22 m/s
		"m_arc": 0,           # thrown flat: needs a clear line past friends
		"skirm": 1,
		"cost": 4,
		"climb": 13,
		"m_hgain": 100,
		"m_apex": 10,       # thrown in a low arc: clears a man-high bump, not a crest
	},
	{
		"name": "Shock Cavalry",
		"short": "Cav",
		"icon": 6,
		"role": "Shock cavalry",
		"desc": "Heavy horsemen. A charge at full speed rolls on rider by rider until the whole front rank has struck, knocking soldiers down and killing them; devastating into a flank or rear, into missile troops and artillery. Into the front of steady, shielded infantry a charge hurts but does not win: the shields take much of it, the ranks behind hold the men up and they strike back at the horses. Once stuck in melee the charge is spent: pull out (turning away costs a few riders) and charge again after a good run-up. Horses are big targets for archers.",
		"good_vs": "Missile troops, artillery, light infantry, skirmishers, the flanks and rear of engaged units, routers.",
		"weak_vs": "Braced spears and pike fronts (the charge is turned back), the front of heavy infantry (a costly grind), charging uphill, archers shooting at them in the open, long melee with heavy infantry.",
		"cls": CLS_CAV,
		"sprite": 5,
		"attack": 36,
		"defence": 28,
		"armour": 10,
		"shield": 20,
		"mshield": 15,
		"damage": 32,
		"reach": 1638,       # 1.6 m
		"mass": 400,
		"walk": 215,         # 2.1 m/s
		"run": 840,          # 8.2 m/s
		"hp": 150,
		"cooldown": 10,
		"morale": 760,
		"file_sp": 2048,
		"rank_sp": 3072,
		"charge": 70,
		"turn": 16,          # ~5.6 degrees per tick: 90 degrees in 1.6 s
		"m_vuln": 120,       # arrows find the horse ...
		"m_down": 9,         # ... and 9% of hits bring it down
		"cost": 10,
		"climb": 24,         # horses labour uphill
	},
	{
		"name": "Bolt Throwers",
		"short": "Bolts",
		"icon": 7,
		"role": "Light artillery (scorpions)",
		"desc": "Four torsion bolt throwers with their crews. They shoot flat, far and accurately; a bolt flies on along its line and can skewer several men in a row, so deep, dense formations such as pike blocks suffer most, while big shields and armour soak up much of it. Because the bolt flies flat it needs a clear line: friends in the way stop it or are hit, and a crest between engine and target stops it. Site them on a rise. Cannot shoot while moving; packing up and setting up take time, and dragging them uphill is very slow. When the engines run low the crews can refill them from the baggage (one more full load), standing still and silent for a minute or more. Crews are poor fighters.",
		"good_vs": "Pike blocks and other deep formations shot along their depth, units standing in range, enemy artillery crews.",
		"weak_vs": "Cavalry and any melee troops that reach them, archers, targets behind their own line or behind a crest (blocked).",
		"cls": CLS_ART,
		"sprite": 6,
		"attack": 14,
		"defence": 14,
		"armour": 3,
		"shield": 0,
		"mshield": 0,
		"damage": 22,
		"reach": 1024,
		"mass": 70,
		"walk": 82,          # 0.8 m/s with the engines on the move
		"run": 400,          # crews running away (routing) are faster
		"hp": 75,
		"cooldown": 12,
		"morale": 450,       # gun crews break easily when attacked
		"file_sp": 7 * 1024, # engine spacing
		"rank_sp": 1229,
		"turn": 2,           # the battery turns ~0.7 degrees per tick
		"crew": 4,
		"crew_min": 2,
		"m_kind": 1,
		"m_range": 230 * 1024,
		"m_min": 15 * 1024,
		"m_damage": 120,
		"m_ap": 80,
		"m_ammo": 11,        # bolts per engine
		"m_reserve": 11,     # one more full load in the baggage (Refill)
		"m_refill": 65,      # 6.5 s per bolt brought up at full crew (~70 s a load)
		"m_reload": 75,      # 7.5 s per bolt at full crew
		"m_spread": 10,
		"m_spread0": 300,
		"m_speed": 5632,     # 55 m/s
		"m_arc": 0,
		"m_pierce": 5,
		"m_plough": 25 * 1024,
		"m_fear": 15,
		"arc": 71,           # +-25 degrees
		"traverse": 3,       # ~1 degree per tick
		"deploy": 60,        # 6 s to set up, 3 s to pack up
		"e_hp": 160,
		"cost": 25,
		"climb": 40,         # dragging engines uphill is slow
		"m_hgain": 60,
		"m_apex": 2,        # flat: any crest between engine and target stops it
	},
	{
		"name": "Stone Throwers",
		"short": "Stones",
		"icon": 8,
		"role": "Heavy artillery (onagers)",
		"desc": "Three onagers lobbing heavy stones over friendly troops and hills at very long range. They aim at the near face of the target and land short rather than over, so a stone that misses still bounces on into the front ranks, knocking soldiers down, and the unit hit is shaken for a few seconds. They lead a steadily moving target a little, but small or loose targets are mostly missed. Slow to reload; when they run low the crews can refill them from the baggage (one more full load), standing still and silent for a minute or more. Cannot shoot at close range or while moving; packing up and setting up take time. Crews are poor fighters.",
		"good_vs": "Large, dense units, standing or marching steadily, enemy artillery, wavering units (the fright can tip them).",
		"weak_vs": "Cavalry and any melee troops that reach them, small, loose or fast-moving targets, anything inside the minimum range.",
		"cls": CLS_ART,
		"sprite": 6,
		"attack": 14,
		"defence": 14,
		"armour": 3,
		"shield": 0,
		"mshield": 0,
		"damage": 22,
		"reach": 1024,
		"mass": 70,
		"walk": 72,          # 0.7 m/s with the engines on the move
		"run": 400,
		"hp": 75,
		"cooldown": 12,
		"morale": 450,
		"file_sp": 10 * 1024,
		"rank_sp": 1229,
		"turn": 2,
		"crew": 6,
		"crew_min": 3,
		"m_kind": 2,
		"m_range": 290 * 1024,
		"m_min": 60 * 1024,
		"m_damage": 130,
		"m_ap": 50,
		"m_ammo": 15,        # stones per engine
		"m_reserve": 15,     # one more full load in the baggage (Refill)
		"m_refill": 60,      # 6 s per stone brought up at full crew (~90 s a load)
		"m_reload": 150,     # 15 s per stone at full crew
		"m_spread": 48,      # 4.8% of the distance ...
		"m_spread0": 1536,   # ... plus 1.5 m
		"m_speed": 2867,     # 28 m/s: up to ~10 s in the air
		"m_arc": 1,
		"m_lead": 90,        # leads a steadily moving target, a little short
		"m_long": 50,        # long errors halved: stones fall short rather than over
		"m_pierce": 6,
		"m_plough": 9 * 1024,
		"m_blast": 900,
		"m_fear": 60,
		"arc": 57,           # +-20 degrees
		"traverse": 2,
		"deploy": 120,       # 12 s to set up, 6 s to pack up
		"e_hp": 260,
		"cost": 30,
		"climb": 45,
		"m_hgain": 150,
	},
]


static func count() -> int:
	return TYPES.size()


## Field of a type row, falling back to DEFAULTS.
static func stat(ty: int, key: String) -> int:
	var row: Dictionary = TYPES[ty]
	if row.has(key):
		return int(row[key])
	return int(DEFAULTS[key])


## Display text of a type row ("" if missing). View only.
static func text(ty: int, key: String) -> String:
	return str(TYPES[ty].get(key, ""))


static func cls(ty: int) -> int:
	return stat(ty, "cls")
