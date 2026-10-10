extends RefCounted
## What a unit type is good at, in glyphs. View-side only: everything here is
## derived from the unit type rows (sim/unit_types.gd), so a new row gets its
## traits, class counters and pips for free; nothing is written back to the
## sim. Used by the unit cards (recruit lists, army cards, pre-battle card),
## the unit book and the battle matchup mark.
##
## TRAITS (traits(ty), at most 3, in this priority; the text is the tap hint):
##   siege       CLS_ART (engines of any kind)
##   shock       charge >= 60 (cavalry, generals, elephants)
##   anti_cav    brace > 0 or vs_cav > 0 (spears, pikes), or a horse scare
##               (scare_r > 0 with no armour limit: camels)
##   fearsome    fear_r > 0 (elephants) or an armour-limited scare (dogs)
##   ap          m_ap >= 50 (javelins, bolts, elephants' crews)
##   long_range  m_range >= 140 m, or any engine
##   skirmish    skirm == 1
##   fire        (only when a faction is given) it can carry a fire kind that
##               the faction fields (CData.AMMO_AVAIL)
##   beast       mount is a camel, elephant or dog (2, 3, 4)
##   fast        run >= 420, or mounted and not shock
## CLASSES (the six enemy classes, CLASS_NAMES order: foot, spear, horse,
## missile, beast, engine). own_class(ty) is what a unit counts as when it is
## the target: engine (CLS_ART), beast (mount 2-4), horse (mount 1), missile
## (CLS_MISSILE), spear (brace > 0: spears and pikes), else foot.
## classes_good / classes_bad come from the unit's shape, read off the stats of
## its base type (tiers of one line share their counters; a handler unit takes
## its dogs'):
##   engine battery   good: foot, spear, engine;  bad: horse, beast, missile
##   mounted shock    good: foot, missile, engine; bad: spear, beast
##     (a horse scare adds good: horse and drops nothing)
##   elephant         good: foot, horse;           bad: missile
##   camel (melee)    good: horse, missile;        bad: spear, foot
##   pack (dogs)      good: missile, engine;       bad: spear, foot, beast
##   missile on foot  good: foot; + spear if m_ap >= 25 and range >= 140 m;
##                    + missile if skirmishing or m_ap < 25; + beast if
##                    m_ap >= 25 and (range >= 140 m or m_ap >= 50); + engine
##                    (crews) if skirmishing; bad: horse (it reaches them),
##                    + spear if skirmishing or m_ap < 25
##   missile mounted  good: foot, engine (+ horse if it scares); bad: horse
##     (the scare removes it), spear, + beast when it has no scare
##   pike             good: foot, spear, horse;    bad: missile, engine
##   spear            good: horse, beast;          bad: missile
##   heavy foot (armour >= 14 at base): good: foot, missile; bad: spear
##   light foot       good: missile, engine;       bad: horse, spear
##   support (wagon)  good: none;                  bad: foot, horse
## PIPS (pips(ty): attack, defence, armour, missile, speed, 0-4): the stat
## over the best of its class (CLS_*) for attack / defence / armour (engines:
## shot energy for attack), the missile rating (damage x (100 + ap) / reload,
## blast and pierce ignored) over the best of all missile rows (engines are
## scaled among engines: their energy is another scale), run over the best run
## of every row. A non-zero stat is at least 1 pip.

const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")

const CLASS_NAMES: Array[String] = ["foot", "spear", "horse", "missile", "beast", "engine"]
const CLASS_LABEL: Array[String] = ["Foot", "Spears", "Horse", "Missile", "Beasts", "Engines"]
const CLASS_ICONS: Array[String] = ["cl_foot", "cl_spear", "cl_horse", "cl_missile", "cl_beast", "cl_engine"]
const FOOT := 0
const SPEAR := 1
const HORSE := 2
const MISSILE := 3
const BEAST := 4
const ENGINE := 5

## Recruit list groups, in order: the six classes by own class, then support.
const GROUP_LABEL: Array[String] = ["Foot", "Spears", "Missile", "Horse", "Beasts", "Engines", "Support"]
const GROUP_ICONS: Array[String] = ["cl_foot", "cl_spear", "cl_missile", "cl_horse", "cl_beast", "cl_engine", "men"]

const TRAIT_ORDER: Array[String] = ["siege", "shock", "anti_cav", "fearsome", "ap", "long_range", "skirmish", "fire", "beast", "fast"]
const TRAIT_TEXT := {
	"siege": "Siege engine: batters and shoots from set-up positions; crews are fragile.",
	"shock": "Shock: a charge knocks soldiers down; needs a run-up.",
	"anti_cav": "Anti-cavalry: braces against charges or scares horses.",
	"fearsome": "Fearsome: enemies near it lose morale.",
	"ap": "Armour piercing: its missiles bite through armour.",
	"long_range": "Long range: 140 m or more.",
	"skirmish": "Skirmisher: shoots and keeps its distance.",
	"fire": "Fire: can carry fire ammunition for this faction.",
	"beast": "Beast: camels, elephants and dogs have their own rules.",
	"fast": "Fast: runs and manoeuvres quickly.",
}
const TRAIT_ICONS := {
	"siege": "tr_siege", "shock": "tr_shock", "anti_cav": "tr_anti_cav", "fearsome": "tr_fearsome", "ap": "tr_ap",
	"long_range": "tr_long_range", "skirmish": "tr_skirmish", "fire": "tr_fire", "beast": "tr_beast", "fast": "tr_fast",
}
const CLASS_TEXT: Array[String] = ["foot soldiers", "spears and pikes", "horsemen", "missile troops", "camels, elephants and dogs", "artillery and engines"]
const PIP_NAMES: Array[String] = ["attack", "defence", "armour", "missile", "speed"]
const M := 1024


static func traits(ty: int, faction: int = -1) -> Array[String]:
	var have := {}
	var cl := UT.cls(ty)
	var mount := UT.stat(ty, "mount")
	var shock := UT.stat(ty, "charge") >= 60
	have["siege"] = cl == UT.CLS_ART
	have["shock"] = shock
	have["anti_cav"] = UT.stat(ty, "brace") > 0 or UT.stat(ty, "vs_cav") > 0 \
		or (UT.stat(ty, "scare_r") > 0 and UT.stat(ty, "scare_am") < 0)
	have["fearsome"] = UT.stat(ty, "fear_r") > 0 or (UT.stat(ty, "scare_r") > 0 and UT.stat(ty, "scare_am") >= 0)
	have["ap"] = UT.stat(ty, "m_ap") >= 50 and UT.stat(ty, "m_ammo") > 0
	have["long_range"] = UT.stat(ty, "m_range") >= 140 * M or (cl == UT.CLS_ART and UT.stat(ty, "m_ammo") > 0)
	have["skirmish"] = UT.stat(ty, "skirm") == 1
	have["fire"] = faction >= 0 and has_fire(ty, faction)
	have["beast"] = mount >= 2
	have["fast"] = UT.stat(ty, "run") >= 420 or (mount == 1 and not shock)
	var out: Array[String] = []
	for t in TRAIT_ORDER:
		if have[t] and out.size() < 3:
			out.append(t)
	return out


## True if unit type ty can carry a fire ammunition kind that faction (index)
## fields (CData.AMMO_AVAIL).
static func has_fire(ty: int, faction: int) -> bool:
	var fk: String = str(CData.FACTIONS[faction]["key"]) if faction >= 0 and faction < CData.FACTIONS.size() else ""
	for k in UT.ammo_specials(ty):
		if UT.ammo_stat(k, "fire") <= 0:
			continue
		for row in CData.AMMO_AVAIL:
			if str(row[0]) == str(UT.AMMO[k]["key"]) and (row[1] as Array).has(fk):
				return true
	return false


static func trait_text(t: String) -> String:
	return str(TRAIT_TEXT.get(t, t))


## What the unit counts as when it is the target.
static func own_class(ty: int) -> int:
	var cl := UT.cls(ty)
	var mount := UT.stat(ty, "mount")
	if cl == UT.CLS_ART:
		return ENGINE
	if mount >= 2:
		return BEAST
	if mount == 1:
		return HORSE
	if cl == UT.CLS_MISSILE:
		return MISSILE
	if cl == UT.CLS_PIKE or UT.stat(ty, "brace") > 0:
		return SPEAR
	return FOOT


## The recruit-list group (index into GROUP_LABEL): the unit's own class
## (missile cavalry with the horse), wagons as support, the dog handlers with
## the beasts.
static func group_of(ty: int) -> int:
	if UT.stat(ty, "wagon") >= 0:
		return 6
	if UT.stat(ty, "pack_n") > 0:
		return 4
	return [0, 1, 3, 2, 4, 5][own_class(ty)]


static func classes_good(ty: int) -> Array[int]:
	return _counters(ty)[0]


static func classes_bad(ty: int) -> Array[int]:
	return _counters(ty)[1]


## [good, bad] class index arrays (ascending), see the head comment.
static func _counters(ty: int) -> Array:
	var good := {}
	var bad := {}
	var pk := UT.stat(ty, "pack_type")
	if UT.stat(ty, "pack_n") > 0 and pk >= 0:
		return _counters(pk)
	if UT.stat(ty, "wagon") >= 0:
		bad = {FOOT: 1, HORSE: 1}
		return [_sorted(good), _sorted(bad)]
	var b := UT.base_of(ty)
	var cl := UT.cls(b)
	var mount := UT.stat(b, "mount")
	var ap := UT.stat(b, "m_ap")
	var rng := UT.stat(b, "m_range")
	var shooter := UT.stat(b, "m_ammo") > 0 and rng > 0
	var skirm := UT.stat(b, "skirm") == 1
	var scares := UT.stat(b, "scare_r") > 0 and UT.stat(b, "scare_am") < 0
	if cl == UT.CLS_ART:
		good = {FOOT: 1, SPEAR: 1, ENGINE: 1}
		bad = {HORSE: 1, BEAST: 1, MISSILE: 1}
	elif mount == 3:
		good = {FOOT: 1, HORSE: 1}
		bad = {MISSILE: 1}
	elif mount == 4:
		good = {MISSILE: 1, ENGINE: 1}
		bad = {SPEAR: 1, FOOT: 1, BEAST: 1}
	elif mount == 2 and not shooter:
		good = {HORSE: 1, MISSILE: 1}
		bad = {SPEAR: 1, FOOT: 1}
	elif mount >= 1 and shooter:
		good = {FOOT: 1, ENGINE: 1}
		bad = {SPEAR: 1}
		if scares:
			good[HORSE] = 1
		else:
			bad[HORSE] = 1
		if mount == 1:
			bad[BEAST] = 1
	elif mount == 1:
		good = {FOOT: 1, MISSILE: 1, ENGINE: 1}
		bad = {SPEAR: 1, BEAST: 1}
	elif shooter:
		good[FOOT] = 1
		bad[HORSE] = 1
		if ap >= 25 and rng >= 140 * M:
			good[SPEAR] = 1
		if ap >= 25 and (rng >= 140 * M or ap >= 50):
			good[BEAST] = 1
		if skirm or ap < 25:
			good[MISSILE] = 1
			bad[SPEAR] = 1
		if skirm:
			good[ENGINE] = 1
	elif cl == UT.CLS_PIKE:
		good = {FOOT: 1, SPEAR: 1, HORSE: 1}
		bad = {MISSILE: 1, ENGINE: 1}
	elif UT.stat(b, "brace") > 0:
		good = {HORSE: 1, BEAST: 1}
		bad = {MISSILE: 1}
	elif UT.stat(b, "armour") >= 14:
		good = {FOOT: 1, MISSILE: 1}
		bad = {SPEAR: 1}
	else:
		good = {MISSILE: 1, ENGINE: 1}
		bad = {HORSE: 1, SPEAR: 1}
	for k in good.keys():
		bad.erase(k)
	return [_sorted(good), _sorted(bad)]


static func _sorted(d: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for c in 6:
		if d.has(c):
			out.append(c)
	return out


## Matchup of attacker a against defender d: 1 up (the attacker's strengths
## meet the defender's class), -1 down, 0 level. For the battle HUD.
static func matchup(a: int, d: int) -> int:
	var c := own_class(d)
	var up := classes_good(a).has(c)
	var down := classes_bad(a).has(c)
	if up == down:
		return 0
	return 1 if up else -1


# ------------------------------------------------------------------ pips ---

static var _max := {}


## The five pips, 0-4 each.
static func pips(ty: int) -> Dictionary:
	_prep()
	var cl := UT.cls(ty)
	var art := cl == UT.CLS_ART
	var out := {}
	out["attack"] = _pip(UT.stat(ty, "m_damage") if art else UT.stat(ty, "attack"), _max["a%d" % cl])
	out["defence"] = _pip(UT.stat(ty, "defence"), _max["d%d" % cl])
	out["armour"] = _pip(UT.stat(ty, "armour"), _max["r%d" % cl])
	out["missile"] = _pip(missile_rating(ty), _max["mA" if art else "mF"])
	out["speed"] = _pip(UT.stat(ty, "run"), _max["run"])
	return out


## Damage x (100 + armour piercing) per reload tick x 1000 (0: no missiles).
static func missile_rating(ty: int) -> int:
	if UT.stat(ty, "m_ammo") <= 0 or UT.stat(ty, "m_damage") <= 0:
		return 0
	return UT.stat(ty, "m_damage") * (100 + UT.stat(ty, "m_ap")) * 1000 / (100 * maxi(UT.stat(ty, "m_reload"), 1))


static func _pip(v: int, mx: int) -> int:
	if v <= 0 or mx <= 0:
		return 0
	return clampi((v * 4 + mx / 2) / mx, 1, 4)


static func _prep() -> void:
	if not _max.is_empty():
		return
	for c in 5:
		_max["a%d" % c] = 0
		_max["d%d" % c] = 0
		_max["r%d" % c] = 0
	_max["mF"] = 0
	_max["mA"] = 0
	_max["run"] = 0
	for ty in UT.count():
		var cl := UT.cls(ty)
		var art := cl == UT.CLS_ART
		_max["a%d" % cl] = maxi(_max["a%d" % cl], UT.stat(ty, "m_damage") if art else UT.stat(ty, "attack"))
		_max["d%d" % cl] = maxi(_max["d%d" % cl], UT.stat(ty, "defence"))
		_max["r%d" % cl] = maxi(_max["r%d" % cl], UT.stat(ty, "armour"))
		var k := "mA" if art else "mF"
		_max[k] = maxi(_max[k], missile_rating(ty))
		if UT.stat(ty, "fixed") == 0:
			_max["run"] = maxi(_max["run"], UT.stat(ty, "run"))


## "Attack 3, defence 2, ..." for a hint.
static func pips_text(ty: int) -> String:
	var p := pips(ty)
	var parts: Array[String] = []
	for n in PIP_NAMES:
		if int(p[n]) > 0:
			parts.append("%s %d" % [n, int(p[n])])
	return "Out of 4 against its class: " + ", ".join(parts) + "."


static func classes_text(ty: int, good: bool) -> String:
	var names: Array[String] = []
	for c in (classes_good(ty) if good else classes_bad(ty)):
		names.append(CLASS_TEXT[c])
	if names.is_empty():
		return "Nothing in particular."
	return ("Good against " if good else "Weak against ") + ", ".join(names) + "."


# ------------------------------------------------ heroes and agents (8a) ---

## UI icon of a character row (char_kind 1-4 a hero: "crown", 5 assassin:
## "dagger", 6 diplomat: "scroll"); "" for any other row.
static func char_icon(ty: int) -> String:
	match UT.stat(ty, "char_kind"):
		1, 2, 3, 4:
			return "crown"
		5:
			return "dagger"
		6:
			return "scroll"
	return ""


## "Hero: Master of Horse, aura: ..." for a character row, derived from its
## fields (au_* / fall_* / duel / hidden / unarmed); "" for other rows.
static func char_text(ty: int) -> String:
	var ck := UT.stat(ty, "char_kind")
	if ck <= 0:
		return ""
	var nm := str(UT.TYPES[ty]["name"])
	var parts: Array[String] = []
	var pairs := [["au_hit", "foot melee to-hit +%d %%"], ["au_mor", "morale +%d a second"], ["au_rng", "missile range +%d %%"],
		["au_spr", "scatter -%d %%"], ["au_mom", "charge impact +%d %%"], ["au_rally", "routers rally +%d a second"],
		["au_climb", "ladders %d %% faster"], ["au_reload", "engines reload %d %% faster"],
		["au_batter", "ram and towers take %d %% less battering"], ["au_steady", "fear costs %d %% less morale"]]
	for p in pairs:
		var v := UT.stat(ty, str(p[0]))
		if v != 0:
			parts.append(str(p[1]) % v)
	var kind := "Hero" if ck <= 4 else "Agent"
	var out := "%s: %s" % [kind, nm]
	if not parts.is_empty():
		var r := UT.stat(ty, "ch_r") / 1024
		out += ", aura%s: %s" % [(" (%d m)" % r) if r > 0 and ck != 4 else (" (the whole side)" if ck == 4 else ""), "; ".join(parts)]
	if ck == 5:
		out += ", hidden until he acts"
	if ck == 6:
		out += ", unarmed"
	if UT.stat(ty, "fall_r") > 0:
		out += ". If he falls, units near him lose heart"
	return out + "."
