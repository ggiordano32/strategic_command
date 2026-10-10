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
##   m_spen       % of the target's missile shield its missiles go through
##                (a javelin's weight drives through a shield: pilum-style)
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
## scenario is crews x engines, files = engines). The engines are equipment
## (docs/DESIGN.md "Artillery"): any foot unit that takes them up works them
## with these stats (its men keep their own melee, armour and morale), and a
## battery that leaves them fights on with its own body stats at light
## infantry's pace and formation:
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
## Siege (special types, never recruited: see SPECIAL):
##   fixed        1: an engine mounted on a wall tower (garrison artillery):
##                it never moves, packs, refills or loses heart; the sim
##                places it on a tower of a walls-2/3 city (BattleSim
##                _siege_towers) and it is gone when its crew is dead or its
##                engine wrecked
## Ammunition (docs/DESIGN.md "Ammunition kinds"):
##   m_ak         the standard ammunition kind its weapon shoots (a row of
##                AMMO, -1 none); special kinds ride on it (AMMO "base")
##   wagon        an ammunition wagon's crew: the row of WAGONS (tier) of the
##                wagon it comes with (-1 none; docs/DESIGN.md "The
##                ammunition wagon")
##   str_pct      campaign: % of its price per man that counts as fighting
##   upkeep_pct   campaign: % of the normal upkeep (price x UPKEEP_PCT) it costs a turn (generals 0)
##                strength (auto-resolve, the AI); a wagon's crew little
## Beasts (docs/DESIGN.md "Camels and elephants"; generic: any row may use them):
##   mount        what its men ride: 0 on foot, 1 horse, 2 camel, 3 elephant
##                (the auras pick their victims by it)
##   files0       formation files at full size (0: Scenarios' table by base type)
##   acc          charge momentum gained per tick at speed (acceleration)
##   body_r       a big body's radius: missiles landing within it strike it,
##                blows reach its edge, it is never knocked down and its
##                footprint is padded by it (0: a man or a horse)
##   crew_shoot   missile shooters per soldier (an elephant's crew on its
##                back); more than one also shoot while the body fights
##   woods_pct    % of the woods' slowing it suffers (100 as its class)
##   trample_n    victims a charge impact carries on into after the first
##   trample_r    ... within this of the rider
##   trample_pct  ... each at this % of the impact
##   crush        % of a charge that still goes into a braced front (the
##                rider takes the points all the same)
##   scare_r      horse scare: enemy horse units (mount 1) this near take
##   scare_pct    ... this % of their charge power and turn rate,
##   scare_mor    ... and lose this much morale a second; a horse charging
##                a unit with a scare hits at scare_pct and loses heart
##   fear_r       fear aura: enemy units this near (but those with a fear
##   fear_horse   aura of their own) lose this much morale a second when
##   fear_foot    mounted on horses, this much otherwise
##   burn_pct     % of the morale burning drains (fire is the elephant's bane)
##   amok         1: on breaking it runs amok (erratic, tramples anyone)
##                instead of fleeing to its edge, and never rallies on its own
##   amok_r       ... it calms (the rider takes control again) once no unit of
##   amok_calm    either side has been within amok_r for amok_calm ticks
##   kill_delay   ticks from the Kill order to the driver killing his beast
##   gate_walls   it batters closed gates of cities with walls up to this
##                level like foot hack them (-1 never) ...
##   gate_pct     ... at this % of a foot soldier's rate (its own damage)
## Heroes and agents (docs/DESIGN.md "Heroes and agents"; one-man units the
## scenario's "chars" add, never counted toward holding the field):
##   char         1: a character (hero or agent) row
##   char_kind    CK_* (1 foot hero .. 4 siege hero, 5 assassin, 6 diplomat)
##   char_pct     campaign auto-resolve: his army's strength +this % (heroes)
##   ch_r         aura radius (box to box, once a second; not his own unit);
##                the siege hero's works for the whole side instead
##   au_hit       foot hero: friendly foot units' melee to-hit +this %
##   au_mor       ... and +this morale a second (up to the recovery cap)
##   au_rng       missile hero: missile units' and engines' range +this % ...
##   au_spr       ... and their scatter -this %
##   au_mom       cavalry hero: mounted units' charge impact +this % ...
##   au_rally     ... and routing mounted units +this a second toward rallying
##   au_climb     siege hero (the side): ladder climbs this % faster ...
##   au_reload    ... engines reload this % faster ...
##   au_batter    ... the ram and siege towers take this % less battering
##   au_steady    diplomat: friendly units' morale loss from fear (auras,
##                routing friends, artillery fright) cut by this %
##   fall_r       a hero falls: units within this (box to box) ...
##   fall_loss    ... of his side lose this morale at once ...
##   fall_gain    ... and of the enemy gain this
##   duel         to-hit added to each of his blows (a champion against single men)
##   unarmed      1: never strikes (the diplomat)
##   hidden       1: hidden from the enemy until he acts or an enemy is near (the assassin)
## Command (docs/DESIGN.md "The general"; generic: the fear aura inverted):
##   cmd_r        command aura: friendly units this near (box to box, once a
##                second; not the unit itself) ...
##   cmd_mor      ... in formation gain this much morale a second (also in
##                melee and under fire; up to what rest would bring back)
##   cmd_rally    ... routing gain this much more a second toward rallying
##                (with an enemy near too)
##   cmd_loss     when this unit routs or its last man falls (once a
##                battle): every other friendly unit on the field loses this
##                much morale at once ...
##   cmd_loss_r   ... and those within cmd_r this much instead
##   cmd_pct      campaign auto-resolve: its army's strength +this % while
##                it has men (the best of the army's units)
## War dogs (docs/DESIGN.md "War dogs"; generic: any row may use them):
##   pack_n       a handler unit: dogs per man in the pack it carries (0 none);
##                the pack is a unit of row pack_type the sim keeps off the
##                field until the Release order (BattleSim ORDER_RELEASE)
##   pack_type    the pack's row (built from "pack_key"; -1 none)
##   pack_r       release range: a target unit at most this far (box to box)
##   return_r     a released pack: once no enemy unit has been within this
##   return_t     ... for this many ticks (and it has no live target), it runs
##                back to its handlers and rejoins the pack (absorbed)
##   nobreak      1: it never routs (its morale only counts for show)
##   scare_am     the scare (scare_*) strikes any enemy unit whose armour is
##                at most this (horses or not); -1: horses only (camels)
##   as_cav       1: spears' vs_cav bonus applies against it as against riders
##   chase        1: on an attack its anchor runs on into its target whatever
##                the target does (a skirmisher falling back, as a router),
##                not waiting for its men to come within reach (a pack)
## Light artillery (docs/DESIGN.md "Light artillery"; generic):
##   carried      1: a battery whose engines its crews carry (scorpions): its
##                pace (walk) and set-up time (deploy) already say how it
##                moves; the AI reads it (never the sim): it marches with the
##                assault, sets up in its own range of the attacked gate and
##                shoots the men on the wall, and it does not count as a
##                battery that batters the gate down (sim/siege_ai.gd)

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
	"fixed": 0, "m_ak": -1, "wagon": -1, "str_pct": 100, "upkeep_pct": 100,
	"mount": 0, "files0": 0, "acc": 4, "body_r": 0, "crew_shoot": 1, "woods_pct": 100,
	"trample_n": 1, "trample_r": 1843, "trample_pct": 60, "crush": 0,
	"scare_r": 0, "scare_pct": 100, "scare_mor": 0, "fear_r": 0, "fear_horse": 0, "fear_foot": 0,
	"burn_pct": 100, "amok": 0, "amok_r": 0, "amok_calm": 0, "kill_delay": 0, "gate_walls": -1, "gate_pct": 0,
	"cmd_r": 0, "cmd_mor": 0, "cmd_rally": 0, "cmd_loss": 0, "cmd_loss_r": 0, "cmd_pct": 0,
	"pack_n": 0, "pack_type": -1, "pack_r": 0, "return_r": 0, "return_t": 0, "nobreak": 0,
	"scare_am": -1, "as_cav": 0, "chase": 0, "carried": 0, "m_spen": 0,
	"char": 0, "char_kind": 0, "char_pct": 0, "ch_r": 0, "au_hit": 0, "au_mor": 0, "au_rng": 0,
	"au_spr": 0, "au_mom": 0, "au_rally": 0, "au_climb": 0, "au_reload": 0, "au_batter": 0,
	"au_steady": 0, "fall_r": 0, "fall_loss": 0, "fall_gain": 0, "duel": 0, "unarmed": 0, "hidden": 0,
}
## Character kinds (the "char_kind" field; docs/DESIGN.md "Heroes and agents").
const CK_FOOT := 1      # Champion: foot units' to-hit and steadiness
const CK_MISSILE := 2   # Master of Archers: missile units' and engines' range and accuracy
const CK_CAV := 3       # Master of Horse: mounted units' charge and rally
const CK_SIEGE := 4     # Master Engineer: the side's ladders, engines, ram and tower
const CK_ASSASSIN := 5
const CK_DIPLOMAT := 6
## Mounts (the "mount" field).
const MOUNT_FOOT := 0
const MOUNT_HORSE := 1
const MOUNT_CAMEL := 2
const MOUNT_ELEPHANT := 3
const MOUNT_DOG := 4  # a dog: a man's small body (missiles, footprint), its own sprite

## The nine base types (tier 1 of their line). The sandbox battles use
## these; derived tier types are appended by _build_types() (see TIERS).
const BASE: Array[Dictionary] = [
	{
		"key": "heavy",
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
		"key": "light",
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
		"key": "spear",
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
		"key": "pike",
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
		"key": "archer",
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
		"m_ak": 0,          # arrows
	},
	{
		"key": "javelin",
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
		"m_spen": 15,        # pilum-style: 15 % of the target's missile shield is driven through (2026-10-09)
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
		"m_ak": 1,          # javelins
	},
	{
		"key": "cav",
		"name": "Shock Cavalry",
		"short": "Cav",
		"icon": 6,
		"role": "Shock cavalry",
		"desc": "Heavy horsemen. A charge at full speed rolls on rider by rider until the whole front rank has struck, knocking soldiers down and killing them; devastating into a flank or rear, into missile troops and artillery. Into the front of steady, shielded infantry a charge hurts but does not win: the shields take much of it, the ranks behind hold the men up and they strike back at the horses. Once stuck in melee the charge is spent: pull out (turning away costs a few riders) and charge again after a good run-up. Horses are big targets for archers.",
		"good_vs": "Missile troops, artillery, light infantry, skirmishers, the flanks and rear of engaged units, routers.",
		"weak_vs": "Braced spears and pike fronts (the charge is turned back), the front of heavy infantry (a costly grind), charging uphill, archers shooting at them in the open, long melee with heavy infantry.",
		"cls": CLS_CAV,
		"sprite": 5,
		"mount": MOUNT_HORSE,
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
		"key": "bolt",
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
		"m_fear": 22,        # 15 until 2026-10-09 (a struck unit is also pinned 0.8 s: BattleSim.PIN_TICKS)
		"arc": 71,           # +-25 degrees
		"traverse": 3,       # ~1 degree per tick
		"deploy": 60,        # 6 s to set up, 3 s to pack up
		"e_hp": 160,
		"cost": 25,
		"climb": 40,         # dragging engines uphill is slow
		"m_hgain": 60,
		"m_apex": 2,        # flat: any crest between engine and target stops it
		"m_ak": 2,          # bolts
	},
	{
		"key": "stone",
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
		"m_ak": 3,          # stones
	},
]


## ------------------------------------------------------------ unit tiers ---
## Every core line (the seven non-artillery base types) has three tiers,
## unlocked in the campaign by the level of the military building that
## trains it. Tier 1 is the base type itself; tiers 2 and 3 are derived rows:
## the base row plus the tier's stat changes (TIER_DELTA), the row's own
## extra changes ("add"), its own name, and a recruitment price of the base
## unit's price times the line's tier percentage (TIER_PRICE, plus the
## row's "price_add"). Faction-flavoured elites are derived
## the same way (a little character in "add"). Artillery has one tier.
## Derived rows carry "base" (base type index), "tier" and "line"; base rows
## get tier 1 and base = themselves. Rows are appended after the nine base
## types, so base type indices (and every sandbox battle) are unchanged.

## Default unit size per base type (soldiers; artillery: crews). Mirrors
## sim/scenarios.gd SIZE (which cannot be preloaded here).
const BASE_SIZE := [100, 100, 100, 120, 80, 60, 60, 16, 18]
## Line name per base type (campaign rosters and buildings use these).
const LINES := ["heavy", "light", "spear", "pike", "archer", "javelin", "cav", "bolt", "stone"]

## Stat changes per tier (added to the base row; hp/morale capped below).
const TIER_DELTA := {
	2: {"attack": 5, "defence": 5, "armour": 3, "hp": 6, "morale": 70, "damage": 2},
	3: {"attack": 10, "defence": 10, "armour": 6, "hp": 12, "morale": 140, "damage": 4},
}
## Price of tiers 2 and 3 per line, % of the base unit's price, set so a
## higher tier is roughly even with tier 1 at equal price (tests/matchups.gd
## --only=tiers): the tier bonuses are worth most to the low-attack spears
## and pikes and least to missile troops, whose numbers are their fire.
const TIER_PRICE := {"heavy": [135, 190], "light": [140, 180], "spear": [153, 262],
	"pike": [161, 275], "archer": [122, 128], "javelin": [120, 160], "cav": [147, 210],
	"cav_missile": [125], "sling": [120]}
## Attack and defence gains per line, % of TIER_DELTA: a formed pike wall
## multiplies small gains over four ranks of points.
const TIER_SKILL := {"pike": 50}

## Derived rows: key, base line, tier, name, short name, role, blurb (put in
## front of the base description), optional extra stat changes and price.
const TIERS: Array[Dictionary] = [
	{"key": "heavy2", "base": HEAVY, "tier": 2, "name": "Veteran Swordsmen", "short": "Vet Heavy",
		"blurb": "Trained, better-armoured swordsmen."},
	{"key": "heavy3", "base": HEAVY, "tier": 3, "name": "Guard Swordsmen", "short": "Guard Heavy",
		"blurb": "Picked, heavily armoured swordsmen."},
	{"key": "light2", "base": LIGHT, "tier": 2, "name": "Veteran Light Infantry", "short": "Vet Light",
		"blurb": "Seasoned light fighters."},
	{"key": "light3", "base": LIGHT, "tier": 3, "name": "Elite Light Infantry", "short": "Elite Light",
		"blurb": "The best of the light troops."},
	{"key": "spear2", "base": SPEAR, "tier": 2, "name": "Veteran Spearmen", "short": "Vet Spear",
		"blurb": "Drilled spearmen."},
	{"key": "spear3", "base": SPEAR, "tier": 3, "name": "Guard Spearmen", "short": "Guard Spear",
		"blurb": "Elite armoured spearmen."},
	{"key": "pike2", "base": PIKE, "tier": 2, "name": "Veteran Pikemen", "short": "Vet Pike",
		"blurb": "Drilled pikemen."},
	{"key": "pike3", "base": PIKE, "tier": 3, "name": "Guard Pikemen", "short": "Guard Pike",
		"blurb": "Elite pikemen."},
	{"key": "archer2", "base": ARCHER, "tier": 2, "name": "Veteran Archers", "short": "Vet Archer",
		"blurb": "Practised bowmen.", "add": {"m_damage": 3}},
	{"key": "archer3", "base": ARCHER, "tier": 3, "name": "Elite Archers", "short": "Elite Archer",
		"blurb": "Master bowmen.", "add": {"m_damage": 6}},
	{"key": "javelin2", "base": JAVELIN, "tier": 2, "name": "Veteran Javelinmen", "short": "Vet Javelin",
		"blurb": "Practised skirmishers.", "add": {"m_damage": 3}},
	{"key": "javelin3", "base": JAVELIN, "tier": 3, "name": "Elite Javelinmen", "short": "Elite Javelin",
		"blurb": "Expert skirmishers.", "add": {"m_damage": 6}},
	{"key": "cav2", "base": CAVALRY, "tier": 2, "name": "Veteran Cavalry", "short": "Vet Cav",
		"blurb": "Experienced horsemen on better horses.", "add": {"charge": 5}},
	{"key": "cav3", "base": CAVALRY, "tier": 3, "name": "Guard Cavalry", "short": "Guard Cav",
		"blurb": "Armoured noble horsemen.", "add": {"charge": 10}},
	# Faction elites.
	{"key": "principes", "base": HEAVY, "tier": 2, "name": "Principes", "short": "Principes",
		"blurb": "Roman citizens in their prime, the second line of the legion."},
	{"key": "extraordinarii", "base": HEAVY, "tier": 3, "name": "Extraordinarii", "short": "Extraord.",
		"blurb": "Picked men of the Italian allies, kept at the consul's hand.", "add": {"morale": 20}},
	{"key": "triarii", "base": SPEAR, "tier": 3, "name": "Triarii", "short": "Triarii",
		"blurb": "The legion's oldest veterans, kneeling behind their shields in the third line: 'it has come to the triarii'.",
		"add": {"morale": 60, "defence": 2}},
	{"key": "phalangites", "base": PIKE, "tier": 2, "name": "Phalangites", "short": "Phalangite",
		"blurb": "Macedonian levy pikemen, drilled in the sarissa phalanx."},
	{"key": "silver_shields", "base": PIKE, "tier": 3, "name": "Silver Shields", "short": "Silver Sh.",
		"blurb": "The argyraspides: veteran royal pikemen with silvered shields.", "add": {"armour": 2, "morale": 40}},
	{"key": "companions", "base": CAVALRY, "tier": 3, "name": "Companion Cavalry", "short": "Companions",
		"blurb": "The king's own heavy horse, the hammer of the Macedonian army.", "add": {"charge": 6}},
	{"key": "chaonians", "base": PIKE, "tier": 3, "name": "Chaonian Guard", "short": "Chaonians",
		"blurb": "Pyrrhus's royal pikemen from Chaonia.", "add": {"attack": 2}},
	{"key": "agema", "base": CAVALRY, "tier": 3, "name": "Agema", "short": "Agema",
		"blurb": "The royal guard cavalry of Epirus.", "add": {"defence": 2}},
	{"key": "sacred_band", "base": SPEAR, "tier": 3, "name": "Sacred Band", "short": "Sacred Band",
		"blurb": "Carthage's citizen elite: wealthy, heavily armoured spearmen sworn to stand.",
		"add": {"armour": 2, "morale": 60}, "price_add": 15},
	{"key": "hoplites", "base": SPEAR, "tier": 2, "name": "Hoplites", "short": "Hoplites",
		"blurb": "Greek citizen spearmen with the big round aspis.", "add": {"mshield": 5}},
	{"key": "picked_hoplites", "base": SPEAR, "tier": 3, "name": "Picked Hoplites", "short": "Picked Hopl.",
		"blurb": "Epilektoi: the city's chosen, full-time hoplites.", "add": {"mshield": 5}},
	{"key": "cretans", "base": ARCHER, "tier": 3, "name": "Cretan Archers", "short": "Cretans",
		"blurb": "The most sought-after mercenary bowmen of the Greek world.", "add": {"m_damage": 8}},
	{"key": "scutarii", "base": HEAVY, "tier": 2, "name": "Scutarii", "short": "Scutarii",
		"blurb": "Iberian swordsmen with the long scutum and the falcata."},
	{"key": "caetrati", "base": LIGHT, "tier": 2, "name": "Caetrati", "short": "Caetrati",
		"blurb": "Iberian light swordsmen with the small round caetra.", "add": {"attack": 2}},
	{"key": "warband", "base": LIGHT, "tier": 2, "name": "Gallic Warband", "short": "Warband",
		"blurb": "Gallic warriors who come on in a furious rush.", "add": {"damage": 4, "defence": -2}},
	{"key": "gallic_nobles", "base": HEAVY, "tier": 3, "name": "Gallic Nobles", "short": "Nobles",
		"blurb": "Mailed Gallic nobles and their sworn retainers."},
	{"key": "noble_cav", "base": CAVALRY, "tier": 3, "name": "Noble Cavalry", "short": "Noble Cav",
		"blurb": "Gallic nobles on horseback in mail shirts."},
]

## Siege types (docs/DESIGN.md "Siege equipment and wall towers"): never
## recruited (line "siege", in no roster or picker), appended after the
## tier rows so every other index is unchanged. The towers' engines are
## placed by the sim on a walls-2/3 city's towers (ladders and the ram are
## not units: BattleSim's siege equipment objects). base = the row itself;
## size = its crew.
const SPECIAL: Array[Dictionary] = [
	{
		"key": "tower_bolt",
		"name": "Tower Bolt Thrower",
		"short": "Tower",
		"icon": 7,
		"role": "Wall tower artillery (walls 2-3)",
		"desc": "A bolt thrower mounted on a tower of the city wall, with a crew of four. It shoots flat bolts down at anyone approaching the wall: rams, ladder parties, men at the gate, batteries. It cannot move and turns all the way round. A fixed load of bolts (half as many again with a workshop in the city). Gone when its crew is shot down or its tower is battered by enemy artillery (a few stones, many bolts).",
		"good_vs": "Rams and men at the gate, ladder parties, batteries in range.",
		"weak_vs": "Enemy stone throwers, archers picking off its crew.",
		"cls": CLS_ART,
		"sprite": 6,
		"fixed": 1,
		"attack": 14, "defence": 16, "armour": 4, "shield": 0, "mshield": 0, "damage": 22,
		"reach": 1024, "mass": 70, "walk": 82, "run": 200, "hp": 80, "cooldown": 12, "morale": 1000,
		"file_sp": 7 * 1024, "rank_sp": 1229, "turn": 0,
		"crew": 4, "crew_min": 2, "m_kind": 1, "m_range": 180 * 1024, "m_min": 5 * 1024,
		"m_damage": 120, "m_ap": 80, "m_ammo": 20, "m_reload": 60, "m_spread": 10, "m_spread0": 300,
		"m_speed": 5632, "m_arc": 0, "m_pierce": 5, "m_plough": 25 * 1024, "m_fear": 15,
		"arc": 512, "traverse": 6, "deploy": 1, "e_hp": 900, "cost": 0, "size": 4,
		"m_hgain": 60, "m_apex": 2, "m_ak": 2,
	},
	{
		"key": "tower_stone",
		"name": "Tower Stone Thrower",
		"short": "Tower St.",
		"icon": 8,
		"role": "Wall tower artillery (walls 3)",
		"desc": "An onager mounted on one of the two biggest towers of a walls-3 city, with a crew of six. It lobs stones far out over the approach: at batteries, at the ram, at the army forming up. It cannot move and turns all the way round. A fixed load of stones (half as many again with a workshop in the city). Gone when its crew is shot down or its tower is battered by enemy artillery.",
		"good_vs": "Batteries and big formations standing in range, the ram.",
		"weak_vs": "Small or moving targets, anything close under the wall.",
		"cls": CLS_ART,
		"sprite": 6,
		"fixed": 1,
		"attack": 14, "defence": 16, "armour": 4, "shield": 0, "mshield": 0, "damage": 22,
		"reach": 1024, "mass": 70, "walk": 72, "run": 200, "hp": 80, "cooldown": 12, "morale": 1000,
		"file_sp": 10 * 1024, "rank_sp": 1229, "turn": 0,
		"crew": 6, "crew_min": 3, "m_kind": 2, "m_range": 280 * 1024, "m_min": 30 * 1024,
		"m_damage": 130, "m_ap": 50, "m_ammo": 12, "m_reload": 150, "m_spread": 48, "m_spread0": 1536,
		"m_speed": 2867, "m_arc": 1, "m_lead": 90, "m_long": 50, "m_pierce": 6, "m_plough": 9 * 1024,
		"m_blast": 900, "m_fear": 60, "arc": 512, "traverse": 4, "deploy": 1, "e_hp": 1200, "cost": 0,
		"size": 6, "m_hgain": 150, "m_ak": 3,
	}
]

## Ammunition wagons (docs/DESIGN.md "The ammunition wagon"): recruited
## units (line "siege", the Workshop; appended after SPECIAL so every other
## index is unchanged) whose men are the crew of a wagon (WAGONS row
## "wagon"): unarmed but for knives, they pull, drive and guard it. The
## wagon itself is a piece of equipment in the battle (BattleSim EQ_WAGON).
const WAGON_CREW := {
	"cls": CLS_INF, "sprite": 6, "icon": 9, "role": "Ammunition wagon",
	"good_vs": "Nothing in a fight: it keeps the archers, javelinmen and engines shooting.",
	"weak_vs": "Anything that reaches it, above all from the flank or rear; fire missiles.",
	"attack": 8, "defence": 10, "armour": 2, "shield": 0, "mshield": 0, "damage": 14, "reach": 1024,
	"mass": 70, "walk": 133, "run": 380, "hp": 70, "cooldown": 12, "morale": 380,
	"file_sp": 1229, "rank_sp": 1331, "climb": 18,
	"str_pct": 20,  # (its price is mostly the wagon: little fighting strength)
}
const WAGON_ROWS: Array[Dictionary] = [
	{"key": "wagon", "name": "Hand Cart", "short": "Cart", "tier": 1, "wagon": 0, "size": 8, "cost": 25,
		"desc": "A hand cart of arrows, javelins and shot pulled by its eight men at walking pace or slower. Missile units and batteries standing near it refill from its stock (Refill). Any foot unit can take it over (tap it) and pull it, fighting badly meanwhile; it burns."},
	{"key": "wagon2", "name": "Ammunition Wagon", "short": "Wagon", "tier": 2, "wagon": 1, "size": 8, "cost": 40,
		"desc": "A one-horse wagon with half as much again: it keeps up with marching foot while the horse lives (a horse shot down leaves it at the crew's pace). Missile units and batteries standing near it refill from its stock (Refill). Any foot unit can take it over; it burns."},
	{"key": "wagon3", "name": "Supply Train", "short": "Train", "tier": 3, "wagon": 2, "size": 10, "cost": 45,
		"desc": "A two-horse wagon with more than twice the hand cart's stock that moves at a trot (one horse down: a marching pace). Missile units and batteries standing near it refill from its stock (Refill). Any foot unit can take it over; it burns."},
]
## Wagon tiers (the hand cart, one horse, two horses), all ints:
##   horses     horses in the traces (each a hit box: shot down, the wagon slows)
##   pace       speed (sim units per tick) with 0, 1, 2 horses alive
##   hp         the wagon's hit points (bolts, stones, fire)
##   horse_hp   each horse's hit points
##   stock_pct  stock carried, % of each standard kind's AMMO "wagon" amount
##              (a special kind it carries: that x the kind's share)
##   bonus_pct  auto-resolve: the army's missile and artillery strength +this %
const WAGONS: Array[Dictionary] = [
	{"horses": 0, "pace": [92, 92, 92], "hp": 600, "horse_hp": 0, "stock_pct": 100, "bonus_pct": 6},
	{"horses": 1, "pace": [92, 133, 133], "hp": 800, "horse_hp": 240, "stock_pct": 150, "bonus_pct": 9},
	{"horses": 2, "pace": [92, 133, 205], "hp": 1000, "horse_hp": 240, "stock_pct": 220, "bonus_pct": 12},
]


## Camels and elephants (docs/DESIGN.md "Camels and elephants"): recruited
## rows of their own lines (one tier), appended after the wagons so every
## other index is unchanged. Numbers chosen once from the design (shock
## cavalry as the yardstick: mass 400, charge 70, run 8.2 m/s, 90 degrees in
## 1.6 s), not tuned; each with its reason.
const BEASTS: Array[Dictionary] = [
	{
		"key": "camel", "line": "camel", "name": "Camel Riders", "short": "Camels", "icon": 10, "sprite": 9,
		"size": 60, "files0": 15,
		"role": "Anti-cavalry riders",
		"desc": "Riders on camels. Slower than horsemen and weaker in the charge, but they sit high and fight foot well, and horses will not face them: enemy horsemen within 30 m lose much of their charge and turn sluggishly, losing heart while they stay, and a horse charging camels hits them weakly and shies. Slow in woods. Spears and pikes stop them like any riders.",
		"good_vs": "Horse cavalry (the scare), skirmishers and archers they catch, the flanks of engaged foot.",
		"weak_vs": "Braced spears and pikes, heavy infantry from the front, archers shooting at them in the open.",
		"cls": CLS_CAV, "mount": MOUNT_CAMEL,
		"attack": 32,       # a little below shock cavalry: a slashing sword, no lance
		"defence": 34,      # high seat: guards better against foot than a horseman (28)
		"armour": 8, "shield": 20, "mshield": 15, "damage": 30, "reach": 1638,
		"mass": 450,        # camel and rider outweigh a horse a little
		"walk": 185,        # 1.8 m/s
		"run": 666,         # 6.5 m/s (horses 8.2)
		"hp": 150, "cooldown": 10,
		"morale": 720,      # steady beasts, a little below shock cavalry's 760
		"file_sp": 2048, "rank_sp": 3277,  # longer than a horse: 3.2 m ranks
		"charge": 45,       # the design's ~45 against the horse's 70
		"turn": 12,         # ~4.2 degrees a tick: 90 degrees in ~2.1 s
		"acc": 3,           # full momentum after ~3.3 s at the run (horses 2.5 s)
		"m_vuln": 120, "m_down": 7,  # big targets, a little harder to bring down than a horse
		"cost": 9,          # a horseman's 10 less the weaker charge
		"climb": 22, "woods_pct": 150,  # sure on slopes, lost among trees
		"scare_r": 30 * 1024,  # the design's ~30 m
		"scare_pct": 70,    # horses keep 70 % of their charge and turn rate
		"scare_mor": 2,     # ... and lose 2 morale a second near them
	},
	{
		"key": "camel_archer", "line": "camel_archer", "name": "Camel Archers", "short": "Camel Arch.",
		"icon": 12, "sprite": 9, "size": 60, "files0": 15,
		"role": "Mounted archers on camels",
		"desc": "Archers on camels: they shoot from the saddle at a fair range, ride away from what comes for them, and scare horses like any camels (enemy horsemen within 30 m lose much of their charge and turn rate and lose heart). Weak in melee; slow in woods.",
		"good_vs": "Slow foot they can shoot and outride, horse cavalry (the scare), skirmishers.",
		"weak_vs": "Shock cavalry or camels that catch them, archers on foot (who outrange them), anything in melee.",
		"cls": CLS_MISSILE, "mount": MOUNT_CAMEL,
		"attack": 20, "defence": 24, "armour": 4, "shield": 0, "mshield": 10, "damage": 26, "reach": 1229,
		"mass": 450, "walk": 185, "run": 640,  # 6.2 m/s: lighter riders, a little slower than lancers on camels with the bows and quivers
		"hp": 140, "cooldown": 11, "morale": 620,
		"file_sp": 2048, "rank_sp": 3277, "turn": 12, "acc": 3,
		"m_range": 110 * 1024,  # a saddle bow: shorter than foot archers' 140 m
		"m_damage": 26, "m_ap": 20, "m_ammo": 30, "m_reload": 45,  # a little weaker and slower than foot archers
		"m_spread": 50, "m_spread0": 1024, "m_speed": 4608, "m_arc": 1,
		"skirm": 1,         # mounted archers keep their distance by default
		"m_vuln": 120, "m_down": 7, "cost": 8, "climb": 22, "m_hgain": 150, "m_ak": 0,
		"woods_pct": 150, "scare_r": 30 * 1024, "scare_pct": 70, "scare_mor": 2,
	},
	{
		"key": "elephant", "line": "elephant", "name": "War Elephants", "short": "Elephants", "icon": 11, "sprite": 10,
		"size": 12, "files0": 6,
		"role": "Shock beasts",
		"desc": "Twelve war elephants, each a driver and two javelin men on its back. Slow to get going and to turn, but a charge at full tilt bowls over whole files and breaks formations, braced spears included (the points still hurt them); horses within 25 m lose heart fast and men somewhat. Arrows and javelins only chip them; fire is their bane. They batter down the gates of towns with walls up to level 1. When they break they run amok, trampling anyone in their way, their own side included, until they find themselves alone and calm down; their drivers can be told to kill them (Kill elephant).",
		"good_vs": "Infantry lines (the charge), horse cavalry (the fear), the gates of small towns.",
		"weak_vs": "Fire missiles, skirmishers and archers who chip them from a distance, being surrounded, narrow streets; when they break they are a danger to their own side.",
		"cls": CLS_CAV, "mount": MOUNT_ELEPHANT,
		"attack": 34, "defence": 20,   # strikes well, easy to hit (a big body)
		"armour": 10,       # thick hide: blows and arrows lose a little
		"shield": 0, "mshield": 0,
		"damage": 70,       # tusks, trunk and feet
		"reach": 3072,      # 3 m: its body (1.5 m) and tusks
		"mass": 2200,       # the design's 2,000+
		"walk": 154,        # 1.5 m/s
		"run": 615,         # 6 m/s
		"hp": 2500,         # a body: some 80 sword blows through its hide; missiles chip
		"cooldown": 15, "morale": 640,
		"file_sp": 6144, "rank_sp": 8192,  # 6 m between beasts, 8 m ranks
		"charge": 85,       # above the horse's 70: its mass does the rest
		"turn": 6,          # ~2.1 degrees a tick: 90 degrees in ~4.3 s
		"acc": 2,           # full momentum after 5 s at the run (horses 2.5 s)
		"m_vuln": 100, "m_down": 0,
		"body_r": 1536,     # 1.5 m
		"crew_shoot": 2,    # two javelin men on its back (and the driver)
		"m_range": 50 * 1024, "m_damage": 36, "m_ap": 50,  # javelins thrown down from height
		"m_ammo": 16, "m_reload": 30, "m_spread": 40, "m_spread0": 717, "m_speed": 2253,
		"m_arc": 1,         # over friends, from 3 m up
		"m_hgain": 100, "m_ak": 1,
		"trample_n": 4,     # a wide knock-down: four more men after the first ...
		"trample_r": 4096,  # ... within 4 m of its middle (its body and 2.5 m) ...
		"trample_pct": 80,  # ... each at 80 % of the impact
		"crush": 50,        # half the charge still goes into braced points; shields and ranks do not stop it
		"fear_r": 25 * 1024,  # the design's ~25 m
		"fear_horse": 6,    # horses: 6 morale a second (a cavalry unit of 760 wavers in ~1 min)
		"fear_foot": 2,     # men: 2 a second
		"burn_pct": 200,    # burning drains twice the heart (20 a second while it burns)
		"amok": 1,
		"amok_r": 50 * 1024,  # alone: nobody within 50 m (the rally's safe range)
		"amok_calm": 200,   # ... for 20 s, then the driver has it in hand again
		"kill_delay": 50,   # 5 s for the driver's chisel and mallet
		"gate_walls": 1,    # gates of walls 0-1 only (iron-bound gates above)
		"gate_pct": 600,    # a beast batters like six men
		"woods_pct": 200,   # crawls through trees
		"climb": 20,
		"cost": 80,         # 960 a unit: about one and a half shock cavalry units
	},
]


## Light missile troops (docs/DESIGN.md "Missile cavalry and slingers"):
## base rows of their own lines, appended after the beasts so every other
## index is unchanged, with faction variants in LIGHT_MISSILE_TIERS (the
## tier mechanism of TIERS: TIER_DELTA, TIER_PRICE, the row's "add" and
## "price_add", on the row named by "of"). Numbers chosen once from the
## existing rows (shock cavalry, camel archers, javelinmen, archers as the
## yardsticks), not tuned; each with its reason.
const LIGHT_MISSILE: Array[Dictionary] = [
	{
		"key": "cav_jav", "line": "cav_missile", "name": "Light Horse", "short": "Lt Horse", "icon": 13, "sprite": 5,
		"size": 60, "files0": 15,
		"role": "Missile cavalry",
		"desc": "Javelin riders on small, quick horses. They ride in, throw from the saddle and ride off again: by default they keep their distance from anything that comes for them, and nothing on foot can catch them. Few javelins each, so they need targets worth them. Weak in melee and no charge to speak of; horses are big targets for archers.",
		"good_vs": "Slow foot they can circle and pelt, the flanks and rear of engaged units, artillery crews, skirmishers caught in the open.",
		"weak_vs": "Shock cavalry and camels that catch them, archers and slingers (who outrange them), any melee.",
		"cls": CLS_MISSILE, "mount": MOUNT_HORSE,
		"attack": 24,       # shock cavalry 36: a javelin kept in hand, no lance
		"defence": 22,      # shock cavalry 28, camel archers 24: unarmoured, lives by not being there
		"armour": 4,        # shock cavalry 10: a helmet at most
		"shield": 20,       # the small round cavalry shield (as shock cavalry)
		"mshield": 25,      # shock cavalry 15: held up against missiles while skirmishing
		"damage": 26,       # shock cavalry 32: the javelin as a spear
		"reach": 1638,
		"mass": 330,        # shock cavalry 400: small horses, no armour
		"walk": 225,        # 2.2 m/s (shock cavalry 2.1)
		"run": 880,         # 8.6 m/s: a touch faster than shock cavalry's 8.2
		"hp": 130,          # shock cavalry 150: a smaller horse
		"cooldown": 10,
		"morale": 620,      # camel archers 620, shock cavalry 760: skirmishers, not a battle line
		"file_sp": 2048, "rank_sp": 3072,  # cavalry spacing
		"turn": 20,         # ~7 degrees a tick: 90 degrees in 1.3 s (shock cavalry 1.6 s)
		"charge": 30,       # a small charge (mounted with charge > 0: momentum as cavalry); shock cavalry 70, camels 45: no lance, light horses
		"m_vuln": 120, "m_down": 9,  # horses, as shock cavalry
		"m_range": 40 * 1024,  # the javelinmen's 40 m
		"m_damage": 38,     # javelinmen 42: thrown from a moving horse
		"m_ap": 50,         # javelinmen 60, the elephants' crew 50: less weight behind it
		"m_spen": 10,       # javelinmen 15: through a tenth of the shield
		"m_ammo": 5,        # javelinmen 6: a rider's sheaf of four or five
		"m_reload": 30,     # javelinmen 28
		"m_spread": 45,     # javelinmen 40: from the saddle
		"m_spread0": 717, "m_speed": 2253, "m_arc": 0, "m_apex": 10, "m_hgain": 100,  # thrown flat, as javelinmen
		"skirm": 1,         # keep their distance by default (as camel archers)
		"m_ak": 1,          # javelins
		"cost": 8,          # 480 a unit: the camel archers' price, shock cavalry 600
		"climb": 24,        # horses labour uphill (shock cavalry 24)
		"woods_pct": 180,   # the missile class's woods slowing x1.8 = about the cavalry's
	},
	{
		"key": "slinger", "line": "sling", "name": "Slingers", "short": "Slingers", "icon": 14, "sprite": 3,
		"size": 80, "files0": 20,
		"role": "Missile infantry",
		"desc": "Light troops with slings who outrange the bow and shoot faster. A sling stone hurts unarmoured men more than an arrow but does little against armour and big shields. They shoot over friendly units and hills, and by default fall back from melee troops that come for them. Weak in melee.",
		"good_vs": "Light infantry, skirmishers, archers, javelin riders and other unarmoured troops, crews.",
		"weak_vs": "Armoured and big-shielded infantry, cavalry that reaches them, any melee unit that closes.",
		"cls": CLS_MISSILE,
		"attack": 18, "defence": 16,  # archers' 18 / 16
		"armour": 2,        # archers 3: no armour at all
		"shield": 0, "mshield": 0,
		"damage": 22,       # archers 24: a knife
		"reach": 1024, "mass": 65,
		"walk": 160,        # archers 1.5 m/s, javelinmen 1.7
		"run": 430,         # 4.2 m/s, the javelinmen's: lighter than archers (4.0)
		"hp": 75, "cooldown": 11,
		"morale": 560,      # between archers (640) and javelinmen (500)
		"file_sp": 1638, "rank_sp": 1843,  # room to whirl the sling (archers 1.3 x 1.6 m)
		"m_range": 150 * 1024,  # archers 140 m: the sling outranges the bow
		"m_damage": 28,     # archers 30 ...
		"m_ap": 0,          # ... at 25 ap: a blunt stone, armour takes its full share
		"m_ammo": 40,       # archers 40: a bag of stones
		"m_reload": 30,     # archers 40: a faster shot
		"m_spread": 50,     # archers 45: a little less accurate
		"m_spread0": 1024,
		"m_speed": 4096,    # 40 m/s (arrows 45)
		"m_arc": 1,         # lobbed over friends and hills, as arrows
		"skirm": 1,         # light troops: fall back by default (as javelinmen)
		"m_hgain": 150,     # as arrows
		"m_ak": 9,          # sling stones
		"cost": 4,          # 320 a unit: archers 400 less the weak shot against armour
		"climb": 13,        # light foot (javelinmen 13)
	},
]
## Faction variants of the LIGHT_MISSILE rows ("of": the row's key): built
## like TIERS (TIER_DELTA, TIER_PRICE of the line, "add", "price_add").
const LIGHT_MISSILE_TIERS: Array[Dictionary] = [
	{"key": "numidians", "of": "cav_jav", "tier": 2, "name": "Numidian Horse", "short": "Numidians",
		"blurb": "Numidian javelin riders without saddle or bridle, the best light horse of the age.",
		"add": {"m_damage": 3, "run": 20, "turn": 2, "m_ammo": 1}, "price_add": 10},
	{"key": "tarentines", "of": "cav_jav", "tier": 2, "name": "Tarentine Horse", "short": "Tarentines",
		"blurb": "Javelin riders of the Tarentine kind, with a shield to stand off fire.",
		"add": {"m_damage": 3, "mshield": 10}},
	{"key": "gallic_horse", "of": "cav_jav", "tier": 2, "name": "Gallic Light Horse", "short": "Gallic Horse",
		"blurb": "Young Gallic riders who throw their javelins and close in readily.",
		"add": {"m_damage": 3, "attack": 3, "damage": 2}},
	{"key": "iberian_horse", "of": "cav_jav", "tier": 2, "name": "Iberian Light Horse", "short": "Iberian Horse",
		"blurb": "Iberian riders who skirmish with javelins and fight on foot or horse.",
		"add": {"m_damage": 3, "defence": 2, "armour": 1}},
	{"key": "balearic", "of": "slinger", "tier": 2, "name": "Balearic Slingers", "short": "Balearics",
		"blurb": "Islanders raised to the sling from boyhood, the most famous slingers of the age.",
		"add": {"m_damage": 3, "m_spread": -5}, "price_add": 10},
	{"key": "rhodians", "of": "slinger", "tier": 2, "name": "Rhodian Slingers", "short": "Rhodians",
		"blurb": "Rhodian slingers, famed for their range.",
		"add": {"m_damage": 2, "m_range": 10 * 1024}, "price_add": 10},
	{"key": "iberian_slingers", "of": "slinger", "tier": 2, "name": "Iberian Slingers", "short": "Ib. Slingers",
		"blurb": "Native Iberian slingers.", "add": {"m_damage": 2, "attack": 2}},
]


## The general and his bodyguard (docs/DESIGN.md "The general"): one base
## row of its own line ("general"), appended after the light missile rows so
## every other index is unchanged, with faction variants in GENERAL_TIERS
## (built like LIGHT_MISSILE_TIERS, at tier 1: no TIER_DELTA, the base
## price). A small elite cavalry unit carrying the command aura (cmd_*).
## Numbers chosen once from the existing rows (Guard Cavalry, cav3, the
## yardstick: att 46, def 38, armour 16, hp 162, morale 900, charge 80;
## 60 men, 1,260), not tuned; each with its reason.
const GENERAL: Array[Dictionary] = [
	{
		"key": "general", "line": "general", "name": "General's Bodyguard", "short": "General", "icon": 15, "sprite": 5,
		"size": 30, "files0": 10,  # 24-32 men: half a cavalry unit, three ranks
		"role": "The general and his guard",
		"desc": "The army's commander and his picked riders. Friendly units near him stand longer under fire and in melee, and routers near him rally sooner; if he flees or falls, the whole army is shaken, the units near him most. Keep him behind the line and commit him only to finish a wavering enemy or to steady a breaking unit.",
		"good_vs": "Wavering or engaged enemy units hit in the flank, routers; steadying his own line.",
		"weak_vs": "Braced spears and pikes, missile fire, a long melee: losing him costs the army more than his men.",
		"cls": CLS_CAV, "mount": MOUNT_HORSE,
		"attack": 44,       # Guard Cavalry 46: picked riders, not a shock unit
		"defence": 40,      # Guard Cavalry 38: the best armour, guarding one man
		"armour": 16,       # Guard Cavalry's 16
		"shield": 25, "mshield": 20,  # shock cavalry 20 / 15: bigger shields held over the general
		"damage": 36,       # Guard Cavalry's 36
		"reach": 1638,
		"mass": 420,        # shock cavalry 400: armoured riders on the best horses
		"walk": 215, "run": 840,  # shock cavalry's pace (8.2 m/s): he must keep up with the wings
		"hp": 160,          # Guard Cavalry 162
		"cooldown": 10,
		"morale": 950,      # Guard Cavalry 900: the commander's own guard almost never breaks
		"file_sp": 2048, "rank_sp": 3072,
		"charge": 75,       # shock cavalry 70, Guard Cavalry 80: fewer riders on the same horses
		"turn": 16, "m_vuln": 120, "m_down": 9, "climb": 24,  # shock cavalry's
		"cost": 40,         # 1,200 a unit: Guard Cavalry's 1,260 for half the men; the aura pays for the other half
		"str_pct": 50,      # campaign strength: its riders count half its price (the rest is cmd_pct)
		"upkeep_pct": 0,    # a general costs no upkeep (decided 2026-10-09; Rome 2 generals have none)
		"cmd_r": 40 * 1024,  # 40 m: between the elephants' fear (25 m) and the rally's safe range (50 m)
		"cmd_mor": 5,       # +5 a second: cancels one routing friend near (-5) or two elephants' fear on foot (-2 each)
		"cmd_rally": 40,    # +40 a second: doubles a router's safe recovery (40), and works with an enemy near
		"cmd_loss": 120,    # -120 at once: about ten men of a 100-man unit falling together
		"cmd_loss_r": 250,  # -250 near him: a steady heavy line (900) holds, a shaken one (under 350) breaks
		"cmd_pct": 8,       # auto-resolve: the army +8 % (the design's "small percentage")
	},
]
## Faction variants of the general ("of": the base row's key), tier 1.
const GENERAL_TIERS: Array[Dictionary] = [
	{"key": "legate", "of": "general", "tier": 1, "name": "Legate's Guard", "short": "Legate",
		"blurb": "A Roman legate and the picked horsemen of his staff.", "add": {"defence": 2}},
	{"key": "sufet", "of": "general", "tier": 1, "name": "Sufet's Guard", "short": "Sufet",
		"blurb": "A Carthaginian general of the great families and his Punic noble horse.", "add": {"charge": 5}},
	{"key": "hetairoi_guard", "of": "general", "tier": 1, "name": "Royal Hetairoi", "short": "Hetairoi",
		"blurb": "The king and his royal squadron of Companions, who lead from the front.", "add": {"charge": 6, "attack": 2}},
	{"key": "strategos", "of": "general", "tier": 1, "name": "Strategos' Guard", "short": "Strategos",
		"blurb": "An elected Greek general and his mounted guard of citizens.", "add": {"mshield": 5}},
	{"key": "chieftain", "of": "general", "tier": 1, "name": "Chieftain's Guard", "short": "Chieftain",
		"blurb": "A chieftain and his sworn retinue, who will die before he does.", "add": {"damage": 4, "defence": -2}},
	# Never recruited: a second general's guard in one campaign army (CRules
	# _one_general) serves on as these plain riders, without the aura.
	{"key": "bodyguard", "of": "general", "tier": 1, "name": "Bodyguard Cavalry", "short": "Bodyguard",
		"blurb": "A second general's riders, serving under the army's commander: no command of their own.", "plain": 1},
]
## The command fields a "plain" GENERAL_TIERS row clears.
const CMD_FIELDS: Array[String] = ["cmd_r", "cmd_mor", "cmd_rally", "cmd_loss", "cmd_loss_r", "cmd_pct"]




## War dogs (docs/DESIGN.md "War dogs"): the handlers, a light foot row of
## its own line ("dogs", recruited) that carries a pack (pack_n dogs a man,
## of row pack_key), and the pack's row (line "dog_pack", never recruited:
## the sim makes the pack from the handlers). Appended after the general's
## rows so every other index is unchanged. Numbers chosen once from the
## existing rows (light infantry, javelinmen, archers, slingers as the
## yardsticks), not tuned; each with its reason.
const DOGS: Array[Dictionary] = [
	{
		"key": "dog_handlers", "line": "dogs", "name": "War Dogs", "short": "Dogs", "icon": 16, "sprite": 0,
		"size": 16, "files0": 8,
		"role": "Handlers and a pack of war dogs",
		"desc": "Sixteen handlers with a pack of two dogs each. Release the pack at an enemy unit within 80 m: the dogs run it down at 9 m/s, fight until nothing is left within 30 m for 5 s, then run back to their handlers (who can release them again). The pack never breaks and frightens unarmoured troops near it. Deadly to skirmishers, archers, slingers, crews and routers; useless against armoured foot and spears, and elephants ignore them. The handlers themselves are poor fighters.",
		"good_vs": "Skirmishers, archers and slingers, artillery crews, wagons, routers (the pursuit).",
		"weak_vs": "Armoured foot and spears (the pack), elephants, any melee unit that reaches the handlers.",
		"attack": 20,       # archers 18, light infantry 36: a knife and a whip
		"defence": 18,      # archers 16
		"armour": 2,        # slingers' 2: no armour
		"shield": 10, "mshield": 20,  # a small buckler
		"damage": 22,       # slingers' knife
		"reach": 1229, "mass": 70,
		"walk": 164, "run": 451,  # light infantry's pace: they must keep up with the dogs' return
		"hp": 75,           # archers'
		"cooldown": 10,
		"morale": 520,      # javelinmen 500: they hang back while the dogs fight
		"file_sp": 1434, "rank_sp": 1638,  # loose order, room for the leashes
		"cost": 24,         # 384 a unit: slingers' 320 for the 32 dogs' bite on light troops and the pursuit, plus 16 weak men (light infantry 400)
		"climb": 13,        # light foot
		"pack_n": 2,        # two dogs a man: 32 dogs for 16 handlers
		"pack_key": "war_dogs",
		"pack_r": 80 * 1024,  # 80 m: twice the javelin's throw, about half the bow's range
	},
	{
		"key": "war_dogs", "line": "dog_pack", "name": "War Dog Pack", "short": "Pack", "icon": 17, "sprite": 11,
		"size": 32, "files0": 8,
		"role": "A released pack of war dogs",
		"desc": "Mastiffs let off the leash. Fast and fierce against unarmoured men and anyone running away; they never break, but a formed line of armour, shields or spears kills them. They run back to their handlers once no enemy is near.",
		"good_vs": "Skirmishers, archers, crews, routers.",
		"weak_vs": "Armoured foot, spears, elephants.",
		"mount": MOUNT_DOG,
		"attack": 40,       # light infantry 36: the lunge of a big dog at a man's throat
		"defence": 22,      # light infantry 26: quick, but no shield and no parry
		"armour": 0, "shield": 0, "mshield": 0,
		"damage": 34,       # 31 on an archer's armour 3, 20 on heavy swords' 14 (damage less armour, no piercing)
		"reach": 922,       # 0.9 m: a bite
		"mass": 35,
		"walk": 205,        # 2 m/s at heel
		"run": 922,         # 9 m/s: faster than any rider (light horse 8.6): they catch routers and skirmishers
		"hp": 45,           # half a light infantryman's 85: one spear thrust (30 + 20 vs riders), two sword cuts or knife stabs
		"cooldown": 8,      # quick bites (light infantry 9)
		"morale": 600,      # (never breaks: nobreak)
		"file_sp": 1434, "rank_sp": 1434,  # a loose pack
		"cost": 4,          # (never recruited: the handlers' price carries the pack)
		"str_pct": 0,
		"climb": 8,         # dogs take slopes easily (light foot 13)
		"nobreak": 1,
		"return_r": 30 * 1024,  # 30 m: the elephants' calm rule shortened (amok_r 50 m): nothing within a short dash
		"return_t": 50,     # ... for 5 s
		"scare_r": 15 * 1024,  # 15 m: half the camels' horse scare
		"scare_pct": 100,   # no hold on charges or turning (that is the camels')
		"scare_mor": 4,     # 4 morale a second (camels' scare on horses 2, elephants' fear on horses 6): light troops dread dogs
		"scare_am": 4,      # light troops only: armour 4 and below (light infantry, missile troops, light horse)
		"as_cav": 1,        # spears hold them off as they hold riders (vs_cav)
		"chase": 1,         # a pack runs its quarry down, skirmishers falling back included
	},
]


## Light artillery and the belly-bow (docs/DESIGN.md "Light artillery";
## STATUS 4f.3): two base rows of their own lines, appended after the war
## dogs so every other index is unchanged. Scorpions are a battery (CLS_ART,
## engines as equipment like any battery) whose small engines the crews
## carry ("carried"); the gastraphetes a missile foot row. Numbers chosen
## once from the existing rows (Bolt Throwers, Archers, heavy bolts as the
## yardsticks), not tuned; each with its reason.
const LIGHT_ART: Array[Dictionary] = [
	{
		"key": "scorpions", "line": "light_art", "name": "Scorpions", "short": "Scorpions", "icon": 18, "sprite": 6,
		"size": 12, "files0": 6,
		"role": "Light artillery (carried scorpions)",
		"desc": "Six small bolt engines, two men to each, light enough for the crews to carry: they march at a man's walking pace and set up or pack up in a moment, so they keep up with an assault and shoot the men on the wall above the ladders and the ram. A small bolt flies flat and true but goes through at most two men; shorter range and a lighter blow than the big bolt throwers, a faster shot, fewer bolts. Crews are poor fighters and the little engines break easily.",
		"good_vs": "Men on a wall over the gate or the ladders, archers and skirmishers in range, enemy crews.",
		"weak_vs": "Cavalry and any melee troops that reach them, big shields and armour, deep blocks (a bolt stops after two men), targets behind friends or a crest.",
		"cls": CLS_ART,
		"attack": 14, "defence": 14, "armour": 3, "shield": 0, "mshield": 0,  # Bolt Throwers' crews
		"damage": 22, "reach": 1024, "mass": 70,
		"walk": 150,         # 1.5 m/s: archers' 154 less a little for the load (Bolt Throwers drag at 0.8)
		"run": 400,          # Bolt Throwers' crews running away
		"hp": 75, "cooldown": 12,
		"morale": 450,       # Bolt Throwers' crews
		"file_sp": 4 * 1024, # engines 4 m apart (Bolt Throwers 7 m): small machines
		"rank_sp": 1229,
		"turn": 4,           # twice the heavy battery's turn: light frames
		"crew": 2,
		"crew_min": 1,       # one man can still shoot one (slower)
		"m_kind": 1,
		"m_range": 160 * 1024,  # 70 % of Bolt Throwers' 230 m, still beyond the bow (140 m)
		"m_min": 10 * 1024,  # Bolt Throwers 15 m: a short engine depresses further
		"m_damage": 90,      # 75 % of Bolt Throwers' 120 (72 until 2026-10-09: it never killed a pikeman outright)
		"m_ap": 70,          # Bolt Throwers 80, arrows 25
		"m_ammo": 8,         # Bolt Throwers 11: what two men carry with the engine
		"m_reserve": 8,      # one more load in the baggage (Refill)
		"m_refill": 40,      # 4 s a bolt (Bolt Throwers 6.5 s): light bolts
		"m_reload": 50,      # 5 s a bolt at full crew (Bolt Throwers 7.5 s)
		"m_spread": 12,      # Bolt Throwers 10: a lighter frame
		"m_spread0": 300,
		"m_speed": 5120,     # 50 m/s (Bolt Throwers 55)
		"m_arc": 0,
		"m_pierce": 2,       # at most two men (Bolt Throwers 5); heavy bolts' 140 % still 2
		"m_plough": 15 * 1024,  # Bolt Throwers 25 m
		"m_fear": 15,        # Bolt Throwers 22 (8 until 2026-10-09)
		"arc": 85,           # +-30 degrees (Bolt Throwers +-25): each engine is turned by hand
		"traverse": 6,       # twice Bolt Throwers' 3
		"deploy": 15,        # 1.5 s to set up, under a second to pack (Bolt Throwers 6 / 3 s)
		"e_hp": 60,          # Bolt Throwers 160: a small frame breaks under a few blows
		"cost": 33,          # 396 a unit: Archers and Bolt Throwers both cost 400; between them in reach and blow, so the same price
		"climb": 16,         # foot with a load (archers 14; Bolt Throwers dragged 40)
		"m_hgain": 60, "m_apex": 2,  # flat, as Bolt Throwers
		"m_ak": 2,           # bolts: heavy bolts ride on them where the faction has them
		"carried": 1,
	},
	{
		"key": "gastraphetes", "line": "belly_bow", "name": "Gastraphetes", "short": "Belly-bows", "icon": 19, "sprite": 3,
		"size": 80, "files0": 20,
		"role": "Missile infantry (belly-bows)",
		"desc": "Greek belly-bowmen: a composite bow on a stock, spanned by leaning on it with the belly, shot like a small bolt engine. Each shot outranges the bow and goes through armour, but loading takes a long time and the shot flies flat, so they need a clear line past friends and over the ground (no shooting over a crest). They stand their ground rather than skirmish. Weak in melee.",
		"good_vs": "Armoured men in the open, crews and men on walls in a clear line, archers (which they outrange).",
		"weak_vs": "Anything that closes fast (cavalry, light infantry), targets behind friends or a crest, swarms (few shots).",
		"cls": CLS_MISSILE,
		"attack": 18, "defence": 16,  # archers'
		"armour": 4,         # archers 3: citizen bowmen with a little more kit
		"shield": 0, "mshield": 0,
		"damage": 24, "reach": 1024, "mass": 70,
		"walk": 154, "run": 400,  # archers' walk; a heavier weapon to run with (archers 410)
		"hp": 75, "cooldown": 11,
		"morale": 640,       # archers'
		"file_sp": 1331, "rank_sp": 1638,  # archers'
		"m_range": 160 * 1024,  # archers 140 m: the stock bow throws further
		"m_damage": 48,      # between an arrow (30) and a scorpion bolt (72)
		"m_ap": 50,          # between arrows (25) and a scorpion bolt (70)
		"m_ammo": 20,        # archers 40: heavier missiles, half as many
		"m_reload": 100,     # 10 s a shot: 2.5 x the bow's 4 s (spanned against the belly)
		"m_spread": 30,      # archers 45: aimed along a stock
		"m_spread0": 800,
		"m_speed": 5120,     # 50 m/s (arrows 45)
		"m_arc": 0,          # flat, as bolts: needs a clear line past friends
		"m_apex": 3,         # a crest between them and the target stops it (javelins 10, bolts 2)
		"m_hgain": 100,
		"skirm": 0,
		"m_ak": 0,           # arrows (bolt-arrows): fire arrows ride on them, a wagon refills them
		"cost": 5,           # 400 a unit, archers': two thirds of the bow's damage a second (4.8 vs 7.5), paid back in range and armour piercing
		"climb": 14,         # archers'
	},
]


## Heroes and agents (docs/DESIGN.md "Heroes and agents"; STATUS 8a): one-man
## rows of their own lines, appended after the light artillery so every
## other index is unchanged. The campaign recruits them (campaign/cchars.gd,
## price_of) and the scenario's "chars" puts them in a battle. Numbers
## chosen once (Guard Cavalry and Agema, 46 / 40 / 16, the yardstick for a
## hero), not tuned; each with its reason.
const CHARS: Array[Dictionary] = [
	{
		"key": "hero_foot", "line": "hero_foot", "name": "Champion", "short": "Champion", "icon": 20, "sprite": 0,
		"size": 1, "files0": 1, "char": 1, "char_kind": CK_FOOT,
		"role": "Hero: champion on foot",
		"desc": "A famous fighter on foot. Friendly foot within 40 m strike truer (+15 % to-hit) and stand longer (+3 morale a second). He never breaks and is cut down only by a crowd or a lucky shot; if he falls, his side near him (60 m) is shaken and the enemy heartened. Keep him in the second line.",
		"good_vs": "Single men: he duels any of them; steadying a foot line.",
		"weak_vs": "Being surrounded, missiles, a charge.",
		"cls": CLS_INF, "mount": MOUNT_FOOT,
		"attack": 46, "defence": 40,  # Agema's 46 / 40: the best guard rider's skill
		"armour": 16, "shield": 40, "mshield": 70,  # a guard's armour, a heavy infantryman's shield
		"damage": 44, "reach": 1331, "mass": 100,
		"walk": 164, "run": 451,  # light infantry's pace: he keeps up with any foot
		"hp": 600,          # six heavy infantrymen: only a crowd or a lucky shot cuts him down
		"cooldown": 9, "morale": 1000, "nobreak": 1,
		"cost": 1500, "str_pct": 0, "upkeep_pct": 0, "char_pct": 6,
		"ch_r": 40 * 1024,  # the general's command radius
		"au_hit": 15, "au_mor": 3,
		"fall_r": 60 * 1024, "fall_loss": 120, "fall_gain": 60,  # the general's cmd_loss near him; half of it heartens the enemy
		"duel": 35,         # DOWN_BONUS: the edge a man has on one who is down
		"climb": 13,
	},
	{
		"key": "hero_missile", "line": "hero_missile", "name": "Master of Archers", "short": "Archer Lord", "icon": 20, "sprite": 5,
		"size": 1, "files0": 1, "char": 1, "char_kind": CK_MISSILE,
		"role": "Hero: master of archers (mounted)",
		"desc": "A mounted master bowman. Friendly missile units and engines within 40 m shoot 10 % further and 20 % straighter. He shoots well himself and never breaks; if he falls, his side near him is shaken. Keep him behind the archers.",
		"good_vs": "Anything in bow range; making the archers and engines near him count.",
		"weak_vs": "Cavalry that reaches him, being surrounded.",
		"cls": CLS_MISSILE, "mount": MOUNT_HORSE,
		"attack": 46, "defence": 40, "armour": 16, "shield": 20, "mshield": 40,
		"damage": 36, "reach": 1638, "mass": 420,
		"walk": 215, "run": 840,  # shock cavalry's pace
		"hp": 600, "cooldown": 10, "morale": 1000, "nobreak": 1,
		"file_sp": 2048, "rank_sp": 3072, "turn": 16, "m_vuln": 100, "m_down": 1, "climb": 24,
		"m_range": 160 * 1024,  # archers 140 m: the best bow, from the saddle
		"m_damage": 40, "m_ap": 40,  # archers 30 at 25: a heavy war arrow
		"m_ammo": 60, "m_reload": 30,  # archers 40 shots, 4 s
		"m_spread": 25, "m_spread0": 512,  # archers 45 / 1 m: a master's aim
		"m_speed": 4608, "m_arc": 1, "m_hgain": 150, "m_ak": 0,
		"cost": 1500, "str_pct": 0, "upkeep_pct": 0, "char_pct": 6,
		"ch_r": 40 * 1024, "au_rng": 10, "au_spr": 20,
		"fall_r": 60 * 1024, "fall_loss": 120, "fall_gain": 60,
	},
	{
		"key": "hero_cav", "line": "hero_cav", "name": "Master of Horse", "short": "Horse Lord", "icon": 20, "sprite": 5,
		"size": 1, "files0": 1, "char": 1, "char_kind": CK_CAV,
		"role": "Hero: master of horse",
		"desc": "A great horseman. Friendly mounted units within 40 m charge 20 % harder and their routers rally faster (+40 a second). He charges with them and never breaks; if he falls, his side near him is shaken. Keep him with the cavalry reserve.",
		"good_vs": "Charging with the cavalry, rallying broken horse.",
		"weak_vs": "Braced spears, being surrounded, missiles.",
		"cls": CLS_CAV, "mount": MOUNT_HORSE,
		"attack": 46, "defence": 40, "armour": 16, "shield": 25, "mshield": 20,
		"damage": 36, "reach": 1638, "mass": 420,
		"walk": 215, "run": 840, "charge": 80,  # Guard Cavalry's charge
		"hp": 600, "cooldown": 10, "morale": 1000, "nobreak": 1,
		"file_sp": 2048, "rank_sp": 3072, "turn": 16, "m_vuln": 100, "m_down": 1, "climb": 24,
		"cost": 1500, "str_pct": 0, "upkeep_pct": 0, "char_pct": 6,
		"ch_r": 40 * 1024, "au_mom": 20, "au_rally": 40,  # the general's rally again, for riders
		"fall_r": 60 * 1024, "fall_loss": 120, "fall_gain": 60,
	},
	{
		"key": "hero_siege", "line": "hero_siege", "name": "Master Engineer", "short": "Engineer", "icon": 20, "sprite": 5,
		"size": 1, "files0": 1, "char": 1, "char_kind": CK_SIEGE,
		"role": "Hero: master engineer (mounted)",
		"desc": "A master of siegecraft riding between the works. For his whole side (siege works are spread out, so not bound to a radius): ladders are climbed 25 % faster, engines reload 20 % faster, the ram and siege towers take 25 % less battering. He never breaks; if he falls, his side near him is shaken. Keep him near the batteries.",
		"good_vs": "Sieges: assaults by ladder, ram or tower, batteries.",
		"weak_vs": "Being caught alone, missiles (wall engines look for him).",
		"cls": CLS_CAV, "mount": MOUNT_HORSE,
		"attack": 46, "defence": 40, "armour": 16, "shield": 25, "mshield": 20,
		"damage": 32, "reach": 1638, "mass": 420,
		"walk": 215, "run": 840, "charge": 40,  # light horse's: he is no shock rider
		"hp": 600, "cooldown": 10, "morale": 1000, "nobreak": 1,
		"file_sp": 2048, "rank_sp": 3072, "turn": 16, "m_vuln": 100, "m_down": 1, "climb": 24,
		"cost": 1500, "str_pct": 0, "upkeep_pct": 0, "char_pct": 6,
		"au_climb": 25, "au_reload": 20, "au_batter": 25,
		"fall_r": 60 * 1024, "fall_loss": 120, "fall_gain": 60,
	},
	{
		"key": "assassin", "line": "assassin", "name": "Assassin", "short": "Assassin", "icon": 21, "sprite": 0,
		"size": 1, "files0": 1, "char": 1, "char_kind": CK_ASSASSIN,
		"role": "Agent: assassin (hidden)",
		"desc": "A single man the enemy does not see until he acts or comes within 10 m of them in the open. Sabotage: he walks to an enemy battery and wrecks an engine every 5 s beside it, or slips over the wall by a gate and unbars it from inside in 15 s. Attempt: he walks up to an enemy hero or general and strikes once (40 % kills, 30 % wounds, 30 % fails). Once he has acted he fights as a weak light man; three enemy men around him take him.",
		"good_vs": "Batteries left unguarded, a shut gate, an enemy general or hero.",
		"weak_vs": "Any fight once he is seen.",
		"cls": CLS_INF, "mount": MOUNT_FOOT,
		"attack": 30, "defence": 20, "armour": 3, "shield": 0, "mshield": 0,  # a weak light man (light infantry 36 / 26 / 4)
		"damage": 30, "reach": 1024, "mass": 70,
		"walk": 164, "run": 451,  # light infantry's pace
		"hp": 80, "cooldown": 9, "morale": 1000, "nobreak": 1,
		"cost": 800, "str_pct": 0, "upkeep_pct": 0, "char_pct": 0,
		"hidden": 1, "climb": 13,
	},
	{
		"key": "diplomat", "line": "diplomat", "name": "Diplomat", "short": "Diplomat", "icon": 22, "sprite": 0,
		"size": 1, "files0": 1, "char": 1, "char_kind": CK_DIPLOMAT,
		"role": "Agent: diplomat (unarmed)",
		"desc": "An envoy under a white flag. Friendly units within 30 m lose only half the heart they would from fear (beasts, routing friends, artillery). Parley: he walks to within 20 m of a routing enemy unit, or one below a quarter of its morale; for 5 s it stops fighting (the men near it hold), then it surrenders (60 % routing, 35 % wavering) and its men are taken prisoner. A garrison on a wall surrenders only once its plaza is held. He never fights; only missiles can kill him during a parley.",
		"good_vs": "Broken or wavering enemy units: prisoners instead of a pursuit.",
		"weak_vs": "Anything that reaches him: he never strikes back.",
		"cls": CLS_INF, "mount": MOUNT_FOOT,
		"attack": 0, "defence": 15, "armour": 2, "shield": 0, "mshield": 0,
		"damage": 4, "reach": 1024, "mass": 70,
		"walk": 140, "run": 400,
		"hp": 100, "cooldown": 10, "morale": 1000, "nobreak": 1, "unarmed": 1,
		"cost": 800, "str_pct": 0, "upkeep_pct": 0, "char_pct": 0,
		"ch_r": 30 * 1024, "au_steady": 50, "climb": 13,
	},
]


## Field of wagon tier w (0 if out of range); "pace" with h horses alive.
static func wagon_stat(w: int, field: String) -> int:
	if w < 0 or w >= WAGONS.size():
		return 0
	return int(WAGONS[w].get(field, 0))


static func wagon_pace(w: int, horses: int) -> int:
	if w < 0 or w >= WAGONS.size():
		return 0
	var p: Array = WAGONS[w]["pace"]
	return int(p[clampi(horses, 0, p.size() - 1)])


## Every type: the base rows, the derived tier rows, then SPECIAL.
static var TYPES: Array[Dictionary] = _build_types()
static var _by_key := {}
## Indices of the siege types (after the tier rows).
static var TOWER_BOLT: int = BASE.size() + TIERS.size()
static var TOWER_STONE: int = BASE.size() + TIERS.size() + 1


static func _build_types() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in BASE.size():
		var row: Dictionary = BASE[b].duplicate()
		row["base"] = b
		row["tier"] = 1
		row["line"] = LINES[b]
		row["size"] = BASE_SIZE[b]
		row["price"] = int(row["cost"]) * BASE_SIZE[b]
		out.append(row)
	for t in TIERS:
		var b: int = t["base"]
		out.append(_derived(BASE[b], b, LINES[b], BASE_SIZE[b], t))
	for sp in SPECIAL:
		var row: Dictionary = sp.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["line"] = "siege"
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	for wr in WAGON_ROWS:
		var row: Dictionary = WAGON_CREW.duplicate()
		for k in wr:
			row[k] = wr[k]
		row["base"] = out.size()
		row["line"] = "siege"
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	for br in BEASTS:
		var row: Dictionary = br.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	var first := out.size()
	for lr in LIGHT_MISSILE:
		var row: Dictionary = lr.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	for t in LIGHT_MISSILE_TIERS:
		var b := first
		while str(out[b]["key"]) != str(t["of"]):
			b += 1
		var br: Dictionary = out[b]
		out.append(_derived(br, b, str(br["line"]), int(br["size"]), t))
	first = out.size()
	for gr in GENERAL:
		var row: Dictionary = gr.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	for t in GENERAL_TIERS:
		var b := first
		while str(out[b]["key"]) != str(t["of"]):
			b += 1
		var br: Dictionary = out[b]
		var row := _derived(br, b, str(br["line"]), int(br["size"]), t)
		if int(t.get("plain", 0)) != 0:
			for k in CMD_FIELDS:
				row[k] = 0
			row["icon"] = 6
			row["role"] = "Heavy cavalry"
			row["desc"] = str(t["blurb"])
		out.append(row)
	first = out.size()
	for dr in DOGS:
		var row: Dictionary = dr.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	for lr in LIGHT_ART:
		var row: Dictionary = lr.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	for cr in CHARS:
		var row: Dictionary = cr.duplicate()
		row["base"] = out.size()
		row["tier"] = 1
		row["price"] = int(row["cost"]) * int(row["size"])
		out.append(row)
	# A handler row's pack: its row index.
	for t in range(first, out.size()):
		if out[t].has("pack_key"):
			for t2 in range(first, out.size()):
				if str(out[t2]["key"]) == str(out[t]["pack_key"]):
					out[t]["pack_type"] = t2
	return out


## Derived tier row t (TIERS, LIGHT_MISSILE_TIERS, GENERAL_TIERS) of base row `row0` (type
## index b, line, unit size): the base row plus the tier's TIER_DELTA (attack
## and defence by the line's TIER_SKILL), the row's "add", its own names, and
## the base price times the line's TIER_PRICE (+ "price_add") %.
static func _derived(row0: Dictionary, b: int, line: String, size: int, t: Dictionary) -> Dictionary:
	var tier: int = t["tier"]
	var row: Dictionary = row0.duplicate()
	var delta: Dictionary = TIER_DELTA.get(tier, {})  # (tier 1 variants: none)
	for k in delta:
		var dv := int(delta[k])
		if k == "attack" or k == "defence":
			dv = dv * int(TIER_SKILL.get(line, 100)) / 100
		row[k] = int(row.get(k, DEFAULTS.get(k, 0))) + dv
	var add: Dictionary = t.get("add", {})
	for k in add:
		row[k] = int(row.get(k, DEFAULTS.get(k, 0))) + int(add[k])
	row["morale"] = mini(int(row["morale"]), 1000)
	for k in ["key", "name", "short"]:
		row[k] = t[k]
	row["desc"] = str(t["blurb"]) + " " + str(row0["desc"])
	row["base"] = b
	row["tier"] = tier
	row["line"] = line
	row["size"] = size
	var pct: int = (TIER_PRICE[line][tier - 2] if tier >= 2 else 100) + int(t.get("price_add", 0))
	var price: int = int(row0["cost"]) * size * pct / 100
	row["price"] = price
	row["cost"] = maxi((price + size / 2) / size, 1)
	return row


## Index of the type with this key, -1 if none.
static func index_of(key: String) -> int:
	if _by_key.is_empty():
		for t in TYPES.size():
			_by_key[str(TYPES[t]["key"])] = t
	return int(_by_key.get(key, -1))


static func key_of(ty: int) -> String:
	return str(TYPES[ty]["key"])


## Base type (tier 1 of the line) of any type.
static func base_of(ty: int) -> int:
	return int(TYPES[ty]["base"])


static func tier_of(ty: int) -> int:
	return int(TYPES[ty]["tier"])


static func line_of(ty: int) -> String:
	return str(TYPES[ty]["line"])


## Full-strength unit size (soldiers; artillery: crews).
static func size_of(ty: int) -> int:
	return int(TYPES[ty]["size"])


## Campaign recruitment price of a full unit.
static func price_of(ty: int) -> int:
	return int(TYPES[ty]["price"])


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


## ------------------------------------------------------ ammunition kinds ---
## docs/DESIGN.md "Ammunition kinds". A missile weapon shoots its standard
## kind (the type's m_ak); a unit may also carry one special kind that rides
## on the same weapon (its "base"), a fixed share of its load, and the player
## (or the AI) chooses which it shoots (BattleSim ORDER_AMMO). The sim copies
## every field into packed arrays (t_k_*) and applies each generically: no
## code branches on a kind. Which special kind a campaign unit carries comes
## from campaign/cdata.gd AMMO_AVAIL (faction and building). All ints:
##   base    -1: a standard kind; else the standard kind it replaces
##   share   % of the load carried as this kind (special kinds)
##   dmg     damage against men and engines, % of the weapon's
##   obj     damage against gates, towers, rams, ladders and wagons, % of the weapon's
##   ap      armour piercing: points added to the weapon's m_ap
##   pierce  victims per shot (bolts, stones), % of the weapon's m_pierce
##   range   % of the weapon's range
##   rate    time to reload, % of the weapon's
##   fear    morale lost by a unit for each man of it hit (artillery: added fright)
##   blast   extra blast radius where it lands (sim units; stones)
##   fire    % chance it sets a wooden thing it lands on alight (gate, tower,
##           engine, ladders, ram, wagon); a man it hits sets his unit burning
##   wagon   standard kinds: what a hand cart carries of it (WAGONS stock_pct)
## Display only: key, name, short (the HUD toggle's word), desc.
## Special kinds are never strictly better than the standard one: each pays
## in range, rate or damage for what it adds (one-line reasons below).
const AMMO: Array[Dictionary] = [
	{"key": "arrows", "name": "Arrows", "short": "arrows", "base": -1, "share": 100, "dmg": 100, "obj": 100,
		"ap": 0, "pierce": 100, "range": 100, "rate": 100, "fear": 0, "blast": 0, "fire": 0, "wagon": 1600,
		"desc": "The bow's standard arrows."},
	{"key": "javelins", "name": "Javelins", "short": "javelins", "base": -1, "share": 100, "dmg": 100, "obj": 100,
		"ap": 0, "pierce": 100, "range": 100, "rate": 100, "fear": 0, "blast": 0, "fire": 0, "wagon": 240,
		"desc": "Standard throwing javelins."},
	{"key": "bolts", "name": "Bolts", "short": "bolts", "base": -1, "share": 100, "dmg": 100, "obj": 100,
		"ap": 0, "pierce": 100, "range": 100, "rate": 100, "fear": 0, "blast": 0, "fire": 0, "wagon": 22,
		"desc": "The bolt thrower's standard bolts."},
	{"key": "stones", "name": "Stones", "short": "stones", "base": -1, "share": 100, "dmg": 100, "obj": 100,
		"ap": 0, "pierce": 100, "range": 100, "rate": 100, "fear": 0, "blast": 0, "fire": 0, "wagon": 16,
		"desc": "Plain dressed stones."},
	# Fire arrows: 70 % damage, 85 % range, 125 % reload (lit before each
	# shot) pay for a morale shock of 3 a man hit and fire (35 %).
	{"key": "fire_arrows", "name": "Fire arrows", "short": "fire", "base": 0, "share": 33, "dmg": 70, "obj": 100,
		"ap": 0, "pierce": 100, "range": 85, "rate": 125, "fear": 3, "blast": 0, "fire": 35,
		"desc": "Pitch-soaked arrows, a third of the quiver: weaker and shorter than arrows, but they set gates, towers, engines, rams and wagons alight and a unit they burn loses heart."},
	# Heavy bolts: +35 % damage, +10 armour piercing, 140 % victims and 150 %
	# against towers and gates, paid for with 75 % range and 140 % reload.
	{"key": "heavy_bolts", "name": "Heavy bolts", "short": "heavy", "base": 2, "share": 33, "dmg": 135, "obj": 150,
		"ap": 10, "pierce": 140, "range": 75, "rate": 140, "fear": 0, "blast": 0, "fire": 0,
		"desc": "Heavier bolts, a third of the load: they hit harder and go through more men and armour, at a shorter range and a slower rate."},
	# Fire javelins: as fire arrows for the thrown kind (75 % damage, 85 %
	# range, 120 % reload; fear 3, fire 35).
	{"key": "fire_javelins", "name": "Fire javelins", "short": "fire", "base": 1, "share": 33, "dmg": 75, "obj": 100,
		"ap": 0, "pierce": 100, "range": 85, "rate": 120, "fear": 3, "blast": 0, "fire": 35,
		"desc": "Burning javelins, a third of the load: weaker and shorter, but they set wooden things alight and a unit they burn loses heart."},
	# Fire pots: 200 % against gates and towers and fire (70 %), but only 55 %
	# against men, 90 % range, 110 % reload; +30 fright.
	{"key": "fire_pots", "name": "Fire pots", "short": "pots", "base": 3, "share": 33, "dmg": 55, "obj": 200,
		"ap": 0, "pierce": 100, "range": 90, "rate": 110, "fear": 30, "blast": 0, "fire": 70,
		"desc": "Clay pots of burning pitch, a third of the load: hard on gates, towers and wooden things, which they set alight; less against men."},
	# Explosive: a burst 4 m round where it lands (the stone's 0.9 m + 3.12 m;
	# aoe: every man in it struck, full damage at the centre to a third at
	# the edge, the survivors thrown 1-2 m and down ~2.5 s; no plough) against
	# men and engines (+40 fright), but 50 % against walls, 85 % range, 125 %
	# reload and a fifth of the load.
	{"key": "explosive", "name": "Explosive stones", "short": "blast", "base": 3, "share": 20, "dmg": 100, "obj": 50,
		"ap": 0, "pierce": 130, "range": 85, "rate": 125, "fear": 40, "blast": 3196, "fire": 0, "aoe": 1,
		"desc": "Rare charges that burst where they land, a fifth of the load: a wide blast against men and engines, weak against walls, shorter and slower."},
	# Sling stones (index 9): the slingers' standard kind; a hand cart
	# carries as many as arrows (small missiles by the bag).
	{"key": "sling", "name": "Sling stones", "short": "sling", "base": -1, "share": 100, "dmg": 100, "obj": 100,
		"ap": 0, "pierce": 100, "range": 100, "rate": 100, "fear": 0, "blast": 0, "fire": 0, "wagon": 1600,
		"desc": "Smooth river stones for the sling."},
	# Lead bullets: 130 % damage and +20 armour piercing (cast lead, heavier
	# for its size), paid for with 85 % range (a special kind is never
	# strictly better) and a third of the bag.
	{"key": "lead_bullets", "name": "Lead bullets", "short": "lead", "base": 9, "share": 33, "dmg": 130, "obj": 100,
		"ap": 20, "pierce": 100, "range": 85, "rate": 100, "fear": 0, "blast": 0, "fire": 0,
		"desc": "Cast lead sling bullets, a third of the bag: they hit harder and bite through some armour, at a shorter range."},
]
## Fields of AMMO the sim reads, in t_k_* order (BattleSim._load_types).
const AMMO_FIELDS: Array[String] = ["base", "share", "dmg", "obj", "ap", "pierce", "range", "rate", "fear",
	"blast", "fire", "aoe"]
static var _ak_by_key := {}


## Index of the ammunition kind with this key, -1 if none ("" too).
static func ammo_index(key: String) -> int:
	if _ak_by_key.is_empty():
		for k in AMMO.size():
			_ak_by_key[str(AMMO[k]["key"])] = k
	return int(_ak_by_key.get(key, -1))


## Field of ammunition kind k (0 if out of range).
static func ammo_stat(k: int, field: String) -> int:
	if k < 0 or k >= AMMO.size():
		return 0
	return int(AMMO[k].get(field, 0))


static func ammo_text(k: int, field: String) -> String:
	if k < 0 or k >= AMMO.size():
		return ""
	return str(AMMO[k].get(field, ""))


## Special kinds that ride on unit type ty's weapon, in table order.
static func ammo_specials(ty: int) -> Array[int]:
	var out: Array[int] = []
	var std := stat(ty, "m_ak")
	if std < 0:
		return out
	for k in AMMO.size():
		if int(AMMO[k]["base"]) == std:
			out.append(k)
	return out
