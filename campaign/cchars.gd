extends RefCounted
## Heroes and agents on the campaign map (docs/CAMPAIGN.md "Heroes and
## agents", STATUS item 8a). A character is a one-man piece that rides with
## an army without taking one of its 12 unit slots and costs no upkeep: a
## hero (Champion, Master of Archers, Master of Horse, Master Engineer: one
## per army), an assassin and a diplomat (one each per army). Same discipline
## as the rest of campaign/: integers, the state's RNG, index order.
##
## State (lazy: absent until the first character is raised, so a campaign
## without any keeps its hash):
##   chars [{id, kind (unit key), f, name, army (id, or -1: in a city of ours),
##     r (region: where he stands; kept for the attached ones by track()),
##     wounded (the turn he is fit again, 0 fit)}] sorted by id,
##   next_char, region["cq"] [[kind, army id or -1]] (raised this turn, appear at
##   the end of it), factions[f]["ransom"] (men taken prisoner, paid at the end
##   of the turn: PRISONER_RANSOM gold a man).
## Orders (crules.apply_order): recruit_char {kind, r, army?}, attach {id,
## army}, detach {id}. Characters move with their army.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const UT := preload("res://sim/unit_types.gd")

const KINDS: Array[String] = ["hero_foot", "hero_missile", "hero_cav", "hero_siege", "assassin", "diplomat"]
const SLOT_HERO := 0
const SLOT_ASSASSIN := 1
const SLOT_DIPLOMAT := 2
const SLOT_NAMES: Array[String] = ["Hero", "Assassin", "Diplomat"]


## crules.gd preloads this file, so it is loaded at run time here (a cached
## script; no preload cycle).
static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


# --------------------------------------------------------------- rows ---

## Slot (SLOT_*) of a character kind key (-1 unknown).
static func slot_of(kind: String) -> int:
	var k := KINDS.find(kind)
	if k < 0:
		return -1
	return SLOT_HERO if k < 4 else (SLOT_ASSASSIN if k == 4 else SLOT_DIPLOMAT)


static func is_char_key(kind: String) -> bool:
	return KINDS.has(kind)


## The unit row exists (the sim's rows are added by the sim agent).
static func available(kind: String) -> bool:
	return is_char_key(kind) and UT.index_of(kind) >= 0


## A row field, 0 when the row (or the field) does not exist.
static func stat(kind: String, key: String) -> int:
	var ty := UT.index_of(kind)
	if ty < 0 or not (UT.TYPES[ty] as Dictionary).has(key):
		return 0
	return int(UT.TYPES[ty][key])


static func price_of(kind: String) -> int:
	var ty := UT.index_of(kind)
	return UT.price_of(ty) if ty >= 0 else 0


static func display(kind: String) -> String:
	var ty := UT.index_of(kind)
	return UT.text(ty, "name") if ty >= 0 else kind


## Building [chain, level] a kind is raised at.
static func needs(kind: String) -> Array:
	return CData.CHAR_NEEDS[kind]


# ------------------------------------------------------------- lookups ---

static func all(st: Dictionary) -> Array:
	return st.get("chars", [])


static func by_id(st: Dictionary, id: int) -> Dictionary:
	for c in all(st):
		if int(c["id"]) == id:
			return c
	return {}


## Characters riding with army id, in id order.
static func of_army(st: Dictionary, id: int) -> Array:
	var out: Array = []
	for c in all(st):
		if int(c["army"]) == id:
			out.append(c)
	return out


## Characters of faction f standing in city r (not attached).
static func in_city(st: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	for c in all(st):
		if int(c["army"]) < 0 and int(c["f"]) == f and int(c["r"]) == r:
			out.append(c)
	return out


static func fit(st: Dictionary, c: Dictionary) -> bool:
	return int(c["wounded"]) <= int(st["turn"])


## Turns until he is fit again (0 fit).
static func wounded_left(st: Dictionary, c: Dictionary) -> int:
	return maxi(int(c["wounded"]) - int(st["turn"]), 0)


## The character of army id in `slot` ({} none).
static func in_slot(st: Dictionary, id: int, slot: int) -> Dictionary:
	for c in of_army(st, id):
		if slot_of(str(c["kind"])) == slot:
			return c
	return {}


## Slot of army id holds a character, or one is queued for it this turn.
static func slot_taken(st: Dictionary, id: int, slot: int) -> bool:
	if not in_slot(st, id, slot).is_empty():
		return true
	for rs in st["regions"]:
		for q in rs.get("cq", []):
			if int(q[1]) == id and slot_of(str(q[0])) == slot:
				return true
	return false


## Region of the city army a stands at (on its cell or next to it; the
## lowest index), -1 in the open. Older formats: its region.
static func city_of(st: Dictionary, a: Dictionary) -> int:
	if not CState.grid_on(st):
		return int(a["r"])
	var c := CState.cell(a)
	for r in CData.region_count():
		if CGrid.cheb(c, CGrid.site(r)) <= 1:
			return r
	return -1


## Two armies carry a character of the same slot (they cannot merge).
static func merge_conflict(st: Dictionary, ida: int, idb: int) -> bool:
	for c in of_army(st, ida):
		if not in_slot(st, idb, slot_of(str(c["kind"]))).is_empty():
			return true
	return false


## Fit characters of army a's strength bonus in %: the best hero's char_pct.
static func pct(st: Dictionary, a: Dictionary) -> int:
	var best := 0
	for c in of_army(st, int(a["id"])):
		if fit(st, c):
			best = maxi(best, stat(str(c["kind"]), "char_pct"))
	return best


# ------------------------------------------------------------ recruiting ---

## "" if faction f may raise character `kind` at region r now (army: an army
## of ours on or next to the settlement whose slot is free, -1 none: he stands
## in the city).
static func recruit_check(st: Dictionary, f: int, r: int, kind: String, army: int = -1) -> String:
	if r < 0 or r >= CData.region_count() or not is_char_key(kind):
		return "bad order"
	if not available(kind):
		return "unknown unit"
	var rs: Dictionary = st["regions"][r]
	if int(rs["owner"]) != f:
		return "not your region"
	if not CState.siege_at(st, r).is_empty():
		return "besieged"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending here"
	var nd := needs(kind)
	if CState.building(st, r, int(nd[0])) < int(nd[1]):
		return "needs %s %d" % [CData.CHAINS[int(nd[0])]["name"], int(nd[1])]
	if not (rs.get("cq", []) as Array).is_empty():
		return "a character is already raised here this turn"
	if price_of(kind) > int(st["factions"][f]["treasury"]):
		return "not enough money"
	if army >= 0:
		var a := CState.army(st, army)
		if a.is_empty() or int(a["f"]) != f:
			return "no such army"
		if CState.grid_on(st):
			if CGrid.cheb(CState.cell(a), CGrid.site(r)) > 1:
				return "not at the settlement"
		elif int(a["r"]) != r:
			return "not at the settlement"
		if int(a["busy"]) != 0:
			return "in a battle"
		if slot_taken(st, army, slot_of(kind)):
			return "the army already has a %s" % SLOT_NAMES[slot_of(kind)].to_lower()
	return ""


static func recruit(st: Dictionary, f: int, o: Dictionary) -> String:
	var r := int(o.get("r", -1))
	var kind := str(o.get("kind", ""))
	var army := int(o.get("army", -1))
	var why := recruit_check(st, f, r, kind, army)
	if why != "":
		return why
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - price_of(kind)
	var rs: Dictionary = st["regions"][r]
	rs["cq"] = [[kind, army]]
	return ""


## End of turn: the characters raised this turn appear (named from the
## faction's culture with the state's RNG), attached to the army given if
## it still stands at the settlement with the slot free, else in the city.
static func appear(st: Dictionary) -> void:
	for r in CData.region_count():
		var rs: Dictionary = st["regions"][r]
		if not rs.has("cq"):
			continue
		var f := int(rs["owner"])
		for q in rs["cq"]:
			if f < 0:
				continue
			var kind := str(q[0])
			var army := int(q[1])
			var a := CState.army(st, army) if army >= 0 else {}
			var ok := not a.is_empty() and int(a["f"]) == f and int(a["busy"]) == 0 \
					and not (CGrid.cheb(CState.cell(a), CGrid.site(r)) > 1 if CState.grid_on(st) else int(a["r"]) != r) \
					and in_slot(st, army, slot_of(kind)).is_empty()
			var c := make_char(st, f, kind, r, army if ok else -1)
			_rules().event(st, {"k": "char_recruited", "f": f, "r": r, "kind": kind, "name": str(c["name"])})
		rs.erase("cq")


## A new character of faction f (id, name from the RNG), appended to the state.
static func make_char(st: Dictionary, f: int, kind: String, r: int, army: int) -> Dictionary:
	var names := CData.name_list(f)
	var nm := names[CState.rand(st, names.size())]
	var id := int(st.get("next_char", 1))
	st["next_char"] = id + 1
	var c := {"id": id, "kind": kind, "f": f, "name": nm, "army": army, "r": r, "wounded": 0}
	if not st.has("chars"):
		st["chars"] = []
	(st["chars"] as Array).append(c)
	return c


# ----------------------------------------------------- attach and detach ---

static func attach_check(st: Dictionary, f: int, id: int, army: int) -> String:
	var c := by_id(st, id)
	if c.is_empty() or int(c["f"]) != f:
		return "no such character"
	if int(c["army"]) >= 0:
		return "already with an army"
	var a := CState.army(st, army)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	var r := int(c["r"])
	if int(st["regions"][r]["owner"]) != f:
		return "not in a city of yours"
	if CState.grid_on(st):
		if CGrid.cheb(CState.cell(a), CGrid.site(r)) > 1:
			return "the army is not at the city"
	elif int(a["r"]) != r:
		return "the army is not at the city"
	if int(a["busy"]) != 0:
		return "in a battle"
	if slot_taken(st, army, slot_of(str(c["kind"]))):
		return "the army already has a %s" % SLOT_NAMES[slot_of(str(c["kind"]))].to_lower()
	return ""


static func attach(st: Dictionary, f: int, o: Dictionary) -> String:
	var why := attach_check(st, f, int(o.get("id", -1)), int(o.get("army", -1)))
	if why != "":
		return why
	var c := by_id(st, int(o["id"]))
	c["army"] = int(o["army"])
	return ""


static func detach_check(st: Dictionary, f: int, id: int) -> String:
	var c := by_id(st, id)
	if c.is_empty() or int(c["f"]) != f:
		return "no such character"
	if int(c["army"]) < 0:
		return "not with an army"
	var a := CState.army(st, int(c["army"]))
	if a.is_empty():
		return "no such army"
	if int(a["busy"]) != 0:
		return "in a battle"
	var r := city_of(st, a)
	if r < 0 or int(st["regions"][r]["owner"]) != f:
		return "the army is not at a city of yours"
	return ""


static func detach(st: Dictionary, f: int, o: Dictionary) -> String:
	var why := detach_check(st, f, int(o.get("id", -1)))
	if why != "":
		return why
	var c := by_id(st, int(o["id"]))
	c["r"] = city_of(st, CState.army(st, int(c["army"])))
	c["army"] = -1
	return ""


# ------------------------------------------------------- upkeep of state ---

## Attached characters stand where their army stands (called before armies
## can be lost: sweep() sends a lost army's characters home from there).
static func track(st: Dictionary) -> void:
	for c in all(st):
		if int(c["army"]) >= 0:
			var a := CState.army(st, int(c["army"]))
			if not a.is_empty():
				c["r"] = int(a["r"])


## Armies merged: the characters of army `from` go with it into `to`
## (merge_conflict is refused beforehand).
static func transfer(st: Dictionary, from: int, to: int) -> void:
	for c in all(st):
		if int(c["army"]) == from:
			c["army"] = to


## Army id is gone without a fight (disbanded): his characters stay in the
## city it stood at, if it was one of ours.
static func release(st: Dictionary, a: Dictionary) -> void:
	var r := city_of(st, a)
	for c in all(st):
		if int(c["army"]) == int(a["id"]) and r >= 0 and int(st["regions"][r]["owner"]) == int(c["f"]):
			c["army"] = -1
			c["r"] = r


## After armies may have gone and cities changed hands: a character whose
## army is gone reaches the nearest city of ours, wounded CHAR_LOST_TURNS
## (none left: lost); one left in a city that is no longer friendly is
## captured (removed, a chronicle row); a faction that died loses its own.
static func sweep(st: Dictionary) -> void:
	if not st.has("chars"):
		return
	var keep: Array = []
	for c in st["chars"]:
		var f := int(c["f"])
		if not CState.alive(st, f):
			continue
		if int(c["army"]) >= 0:
			if not CState.army(st, int(c["army"])).is_empty():
				keep.append(c)
				continue
			c["army"] = -1
			var at := int(c["r"])
			var dest: int = at if CState.owner(st, at) == f else _rules()._nearest_friendly(st, f, at)
			if dest < 0:
				_rules().event(st, {"k": "char_captured", "f": f, "r": at, "name": str(c["name"]), "kind": str(c["kind"]), "by": -1})
				continue
			c["r"] = dest
			c["wounded"] = maxi(int(c["wounded"]), int(st["turn"]) + CData.CHAR_LOST_TURNS)
			keep.append(c)
			continue
		var r := int(c["r"])
		var o := CState.owner(st, r)
		if o == f or CState.friendly(st, f, o):
			keep.append(c)
			continue
		_rules().event(st, {"k": "char_captured", "f": f, "r": r, "name": str(c["name"]), "kind": str(c["kind"]), "by": o})
	st["chars"] = keep
	track(st)


## End of turn: prisoners' ransoms are paid (a chronicle row).
static func pay_ransom(st: Dictionary) -> void:
	for f in CState.nf():
		var fs: Dictionary = st["factions"][f]
		if not fs.has("ransom"):
			continue
		var men := int(fs["ransom"])
		fs.erase("ransom")
		if men <= 0 or int(fs["alive"]) == 0:
			continue
		var gold := men * CData.PRISONER_RANSOM
		fs["treasury"] = int(fs["treasury"]) + gold
		_rules().event(st, {"k": "ransom", "f": f, "men": men, "gold": gold})


# ------------------------------------------------------------- battles ---

## Fit characters of the armies of one side of a battle, in army then id
## order: [{id, key, name}].
static func side_list(st: Dictionary, armies: Array) -> Array:
	var out: Array = []
	for a in armies:
		for c in of_army(st, int(a["id"])):
			if fit(st, c) and available(str(c["kind"])):
				out.append(c)
	return out


## The battle's result for character id: he fell (alive 0), wounded
## CHAR_WOUND_TURNS; a chronicle row.
static func wound(st: Dictionary, id: int) -> void:
	var c := by_id(st, id)
	if c.is_empty():
		return
	c["wounded"] = int(st["turn"]) + CData.CHAR_WOUND_TURNS
	_rules().event(st, {"k": "char_wounded", "f": int(c["f"]), "name": str(c["name"]), "kind": str(c["kind"]),
		"turns": CData.CHAR_WOUND_TURNS})


## Prisoners taken by faction f in a battle: ransom at the end of the turn.
static func add_ransom(st: Dictionary, f: int, men: int) -> void:
	if men <= 0 or f < 0:
		return
	var fs: Dictionary = st["factions"][f]
	fs["ransom"] = int(fs.get("ransom", 0)) + men


## Card text: "Master of Horse Marcus Valerius".
static func title(c: Dictionary) -> String:
	return "%s %s" % [display(str(c["kind"])), str(c["name"])]
