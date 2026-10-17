extends RefCounted
## Campaign save slots in user://campaigns/ (IndexedDB in the browser).
## One file per campaign, rewritten on every autosave (each submitted turn,
## each resolved battle, each order change): {"meta", "state", "session"}.
## "state" is the campaign state (campaign/cstate.gd); "session" is the
## hot-seat bookkeeping that is not part of the shared state: submissions
## already made this turn, the orders being planned, and when each player
## last saw the map (for the turn summary). Export / import turn the whole
## file into one line of text (gzip + base64) to pass between devices.

const CState := preload("res://campaign/cstate.gd")
const CData := preload("res://campaign/cdata.gd")

const DIR := "user://campaigns/"
const EXPORT_PREFIX := "SCC1:"
const TESTS_SUBDIR := "tests/"

## Sub-folder of DIR that saves go to ("" = the player's own list, which the
## Continue screen reads; Saves.list() never looks into sub-folders). Set to
## "tests/" automatically for runs of tests/*.gd and tools/*.gd and for the
## testing aids (--details, --popup=, --host-start=, --scenario=, --campaign=,
## --story=); a caller may also set it. Reads fall back to the top folder, so
## a test aid can open a real save without touching it.
static var subdir := ""
static var _auto_done := false


static func _test_run() -> bool:
	var args := OS.get_cmdline_args()
	for i in args.size():
		var a := str(args[i])
		if (a == "-s" or a == "--script") and i + 1 < args.size():
			var sp := str(args[i + 1]).replace("\\", "/")
			if sp.contains("tests/") or sp.contains("tools/"):
				return true
	for a in OS.get_cmdline_user_args():
		var u := str(a)
		if u == "--details" or u.begins_with("--popup=") or u.begins_with("--host-start=") \
				or u.begins_with("--scenario=") or u.begins_with("--campaign=") or u.begins_with("--story="):
			return true
	return false


## Folder saves are written to.
static func dir() -> String:
	if not _auto_done:
		_auto_done = true
		if subdir == "" and _test_run():
			subdir = TESTS_SUBDIR
	return DIR + subdir


## Existing file for a slot: the current folder's, else the top folder's.
static func _path(slot: String) -> String:
	var p := dir() + slot + ".json"
	if subdir != "" and not FileAccess.file_exists(p):
		var top := DIR + slot + ".json"
		if FileAccess.file_exists(top):
			return top
	return p


static func slot_for(name: String, p_seed: int) -> String:
	var clean := ""
	for ch in name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
	if clean == "":
		clean = "campaign"
	return "%s_%d" % [clean.substr(0, 24), p_seed]


static func save(slot: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir())
	var st: Dictionary = data["state"]
	var keep := CData.pack
	CData.use_state(st)  # names and dates are the state's pack's (formatted now, stored in the meta)
	var factions: Array = []
	for h in st["humans"]:
		factions.append(CData.faction_name(int(h)))
	data["meta"] = {"slot": slot, "name": str(st["name"]), "turn": int(st["turn"]),
		"date": CData.date_text(int(st["turn"])), "factions": factions,
		"pack": str(st.get("pack", "rome")),
		"saved_at": int(Time.get_unix_time_from_system()), "phase": str(st["phase"])}
	CData.use_pack(keep)
	var f := FileAccess.open(dir() + slot + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "", true))
	f.close()
	return true


static func load_slot(slot: String) -> Dictionary:
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	return parse(text)


static func parse(text: String) -> Dictionary:
	var v = JSON.parse_string(text)
	if not (v is Dictionary) or not (v as Dictionary).has("state"):
		return {}
	var data: Dictionary = CState.normalise(v)
	var st: Dictionary = data["state"]
	if str(st.get("format", "")) != CState.FORMAT or int(st.get("version", 0)) > CState.VERSION \
			or int(st.get("version", 0)) < CState.MIN_VERSION:
		return {}
	CState.migrate(st)  # older local saves get the new fields
	if not data.has("session"):
		data["session"] = {}
	return data


## Saved campaigns, newest first: [{slot, name, turn, date, factions, saved_at}].
static func list() -> Array:
	var out: Array = []
	var d := DirAccess.open(dir())
	if d == null:
		return out
	for fn in d.get_files():
		if not fn.ends_with(".json"):
			continue
		var data := load_slot(fn.trim_suffix(".json"))
		if data.is_empty() or not data.has("meta"):
			continue
		var m: Dictionary = data["meta"]
		m["slot"] = fn.trim_suffix(".json")
		out.append(m)
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


static func delete(slot: String) -> void:
	DirAccess.remove_absolute(dir() + slot + ".json")


static func export_text(data: Dictionary) -> String:
	var raw := JSON.stringify(data, "", true).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_GZIP)
	return EXPORT_PREFIX + str(raw.size()) + ":" + Marshalls.raw_to_base64(packed)


## Exported text -> save data ({} if it cannot be read).
static func import_text(text: String) -> Dictionary:
	var t := text.strip_edges().replace("\n", "").replace(" ", "")
	if not t.begins_with(EXPORT_PREFIX):
		return parse(text)  # plain JSON also works
	t = t.substr(EXPORT_PREFIX.length())
	var colon := t.find(":")
	if colon < 0:
		return {}
	var n := int(t.substr(0, colon))
	var packed := Marshalls.base64_to_raw(t.substr(colon + 1))
	if packed.is_empty():
		return {}
	var raw := packed.decompress(n, FileAccess.COMPRESSION_GZIP)
	if raw.size() != n:
		return {}
	return parse(raw.get_string_from_utf8())
