extends RefCounted
## The online campaigns this device holds a seat in, and their seat tokens:
## user://online/accounts.json (IndexedDB in the browser). A seat token is
## the only credential: whoever has it plays that seat. Moving to another
## device goes through a short-lived device code (server side), which gives
## the new device its own token for the same seat.
##
## {"device": random id, "invite": invite key last used,
##  "discord_user": the player's Discord id (optional),
##  "server": the game server chosen on this device (absent: the default),
##  "campaigns": {id: {id, f, token, name, added_at, server}}}
## A seat token is only ever sent to the server the campaign was made on
## (`server`; entries without one belong to the official server).

var path := "user://online/accounts.json"
var data := {"device": "", "invite": "", "discord_user": "", "campaigns": {}}


func _init(p_path: String = "") -> void:
	if p_path != "":
		path = p_path
	load_file()


func load_file() -> void:
	if FileAccess.file_exists(path):
		var v = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			for k in v:
				data[k] = v[k]
	if not (data.get("campaigns") is Dictionary):
		data["campaigns"] = {}
	if str(data.get("device", "")) == "":
		data["device"] = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xFFFFFFFF]
		save()


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "", true))
	f.close()
	return true


func device() -> String:
	return str(data["device"])


func add(id: String, f: int, token: String, name: String, pack: String = "rome", server: String = "") -> void:
	data["campaigns"][id] = {"id": id, "f": f, "token": token, "name": name,
		"added_at": int(Time.get_unix_time_from_system())}
	if server != "":
		data["campaigns"][id]["server"] = server
	if pack != "rome":
		data["campaigns"][id]["pack"] = pack
	save()


func remove(id: String) -> void:
	(data["campaigns"] as Dictionary).erase(id)
	save()


func get_entry(id: String) -> Dictionary:
	var c: Dictionary = data["campaigns"]
	return c.get(id, {})


## Newest first.
func list() -> Array:
	var out: Array = (data["campaigns"] as Dictionary).values()
	out.sort_custom(func(a, b): return int(a.get("added_at", 0)) > int(b.get("added_at", 0)))
	return out


## Newest first, only the campaigns that live on `server`.
func list_for(server: String, official: String) -> Array:
	var out: Array = []
	for e in list():
		if str(e.get("server", official)) == server:
			out.append(e)
	return out


func set_value(k: String, v) -> void:
	data[k] = v
	save()
