extends RefCounted
## Per-faction unit names read from a pack's own table (west.gd UNIT_NAMES) without
## making the pack active: for screens that name units of a setting that is not the
## active one (the custom battle setup). View only; same data as CData.unit_name.

const UT := preload("res://sim/unit_types.gd")

static var _tables := {}
static var _fnames := {}


static func _consts(pack: String) -> Dictionary:
	if not _tables.has(pack):
		var path := "res://campaign/data/%s.gd" % pack
		var c := {}
		if ResourceLoader.exists(path):
			c = (load(path) as GDScript).get_script_constant_map()
		_tables[pack] = c.get("UNIT_NAMES", {})
		var fn := {}
		for f in c.get("FACTIONS", []):
			fn[str(f["key"])] = str(f["name"])
		_fnames[pack] = fn
	return _tables


## Faction keys of `pack` that have their own unit names (table order).
static func factions(pack: String) -> Array:
	_consts(pack)
	return (_tables[pack] as Dictionary).keys()


static func faction_name(pack: String, fkey: String) -> String:
	_consts(pack)
	return str((_fnames[pack] as Dictionary).get(fkey, fkey))


## The name (or short name) of unit row `ukey` for faction `fkey` of `pack`; the row's own name
## when there is no faction or no entry.
static func name_of(pack: String, fkey: String, ukey: String, short := false) -> String:
	_consts(pack)
	var e = (_tables[pack] as Dictionary).get(fkey, {}).get(ukey)
	if e != null:
		return str(e[1] if short else e[0])
	var ty := UT.index_of(ukey)
	if ty < 0:
		return ukey
	var row: Dictionary = UT.TYPES[ty]
	return str(row.get("short", row["name"])) if short else str(row["name"])


## The distinct per-faction names of row `ukey` that differ from the row's own name, as
## [[faction name, unit name], ...] in table order.
static func variants(pack: String, ukey: String) -> Array:
	_consts(pack)
	var out: Array = []
	var own := name_of(pack, "", ukey)
	for fk in (_tables[pack] as Dictionary):
		var n := name_of(pack, str(fk), ukey)
		if n != own:
			out.append([faction_name(pack, str(fk)), n])
	return out
