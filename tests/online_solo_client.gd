extends SceneTree
## One-human online campaign (run by tests/online_solo_e2e.py): creates it on the server like the Host card does
## (CState.new_campaign with one human), submits empty plans and checks every turn resolves and the next opens.
## --tutorial: the Host screen's Tutorial toggle (West, one human): the state is Tutorial.make_state, settings.tutorial 1.
## godot --headless --script res://tests/online_solo_client.gd -- --server=URL --dir=DIR --pack=rome|west --turns=3 [--tutorial]

const NetScript := preload("res://game/net/net.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Tutorial := preload("res://game/campaign/tutorial.gd")

var dir := ""
var pack := "rome"
var turns := 3
var tutorial := false
var errors: Array = []


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--dir="):
			dir = v
		elif a.begins_with("--pack="):
			pack = v
		elif a.begins_with("--turns="):
			turns = int(v)
		elif a == "--tutorial":
			tutorial = true
	CData.use_pack(pack)
	var f := CData.faction_index("rome" if pack == "rome" else "england")
	var net := NetScript.new()
	net.accounts_path = dir.path_join("acc_solo_%s.json" % (pack + ("_tutorial" if tutorial else "")))
	root.add_child(net)
	await process_frame
	var st: Dictionary
	if tutorial:
		st = Tutorial.make_state("Solo tutorial", Tutorial.SEED, 0, 1, {"turn_timeout_h": 0})
	else:
		st = CState.new_campaign("Solo " + pack, 11, [f], {"turn_timeout_h": 0}, [], pack)
	var tag := pack + ("_tutorial" if tutorial else "")
	var r: Dictionary = await net.create_campaign(st, f, {"name": "Solo " + pack})
	var out := {"pack": pack, "turns": [], "join_code": "", "ok": false}
	out["tutorial_requested"] = tutorial
	if not r["ok"]:
		errors.append("create: %s" % r)
	else:
		var cid := str(r["data"]["id"])
		out["join_code"] = str(r["data"].get("join_code", ""))
		var oc = net.open_campaign(cid)
		oc.cache_dir = dir.path_join("cache_" + tag) + "/"
		oc.resolve_grace = 0.0
		await oc.open()
		out["state_pack"] = str(oc.st.get("pack", "rome"))
		out["data_pack"] = CData.pack
		out["tutorial_setting"] = int(oc.st["settings"].get("tutorial", 0))
		out["humans"] = (oc.st["humans"] as Array).size()
		for i in turns:
			await oc.sync()
			var t := int(oc.st["turn"])
			if str(oc.st["phase"]) != "plan":
				errors.append("turn %d phase %s" % [t, oc.st["phase"]])
				break
			var sr: Dictionary = await oc.submit([])
			var ok := false
			for k in 200:
				await oc.sync()
				if int(oc.st["turn"]) > t:
					ok = true
					break
				await create_timer(0.1).timeout
			out["turns"].append({"turn": t, "submit_ok": sr["ok"], "all_in": sr.get("data", {}).get("all_in", null), "next_turn": int(oc.st["turn"]), "phase": str(oc.st["phase"]), "resolved": ok})
			if not ok:
				errors.append("turn %d did not resolve (%s)" % [t, sr])
				break
		out["hash"] = oc.state_hash
		out["local_hash"] = CState.hash_text(oc.st)
		out["ok"] = errors.is_empty()
	out["errors"] = errors
	var fa := FileAccess.open(dir.path_join("solo_%s.json" % tag), FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	print("SOLO ", JSON.stringify(out))
	quit(0 if errors.is_empty() else 1)
