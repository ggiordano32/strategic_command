extends SceneTree
## Builds online campaigns in the states worth a screenshot, against a test
## server, for player A (Rome; seat store <dir>/acc_A.json) with B
## (Carthage; <dir>/acc_B.json) as the ally:
##   "Tiber"    both joined, A has submitted turn 1: Waiting for Carthage
##   "Ostia"    both joined, nobody submitted: Your turn
##   "Carthago" created by A, nobody joined yet (its join code -> <dir>/open_code.txt)
##   "Zama"     played until battles are pending; B claims one of its battles
## Writes <dir>/shots.json {name: id}.
##   godot --headless --script res://tests/online_shot_setup.gd -- --server=URL --dir=DIR

const NetScript := preload("res://game/net/net.gd")
const Policy := preload("res://tests/online_policy.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")

var dir := ""
var a: NetScript
var b: NetScript
var out := {}


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.get_slice("=", 1)
	a = _net("acc_A")
	b = _net("acc_B")
	await process_frame
	var rome := CData.faction_index("rome")
	var carth := CData.faction_index("carthage")
	# Tiber: A has submitted.
	var t := await _pair("Tiber", 3)
	var oa = a.open_campaign(t)
	await oa.open()
	oa.set_seen(0)
	await oa.flush_session()
	await oa.submit(Policy.plan(oa.st, rome, 110, true))
	a.close_campaign()
	# Ostia: fresh.
	var o := await _pair("Ostia", 4)
	oa = a.open_campaign(o)
	await oa.open()
	oa.set_seen(0)
	await oa.flush_session()
	a.close_campaign()
	# Carthago: open seat.
	var st := CState.new_campaign("Carthago", 5, [rome, carth], {"turn_timeout_h": 24})
	var r: Dictionary = await a.create_campaign(st, rome, {})
	out["Carthago"] = str(r["data"]["id"])
	var f := FileAccess.open(dir.path_join("open_code.txt"), FileAccess.WRITE)
	f.store_string(str(r["data"]["join_code"]))
	f.close()
	# Zama: until battles.
	var z := await _pair("Zama", 11)
	oa = a.open_campaign(z)
	var ob = b.open_campaign(z)
	oa.resolve_grace = 0.5
	ob.resolve_grace = 0.5
	await oa.open()
	await ob.open()
	for i in 12:
		await oa.sync()
		await ob.sync()
		# Stop at a battles phase with a battle of each player's.
		if str(oa.st["phase"]) == "battles" and not CTurn.pending_for(oa.st, rome).is_empty() \
				and not CTurn.pending_for(oa.st, carth).is_empty():
			break
		if str(oa.st["phase"]) == "battles":
			# Resolve them all (formula) and go on.
			while str(ob.st["phase"]) == "battles":
				var bt: Dictionary = CTurn.pending_for(ob.st)[0]
				var hs2: Array = []
				for x in CTurn.pending_for(ob.st, carth):
					hs2.append(int(x["id"]))
				var side = ob if hs2.has(int(bt["id"])) else oa
				if side == ob and CTurn.pending_for(ob.st, rome).has(bt):
					await ob.choose(int(bt["id"]), "command")
				await side.claim(int(bt["id"]), "auto")
				await side.upload_battle(int(bt["id"]), CBattle.formula(side.st, bt))
				await ob.sync()
				await oa.sync()
			continue
		await oa.submit(Policy.plan(oa.st, rome, 100, true))
		await ob.submit(Policy.plan(ob.st, carth, 100, true))
		for k in 50:
			await create_timer(0.2).timeout
			await oa.sync()
			if int(oa.st["turn"]) > i or str(oa.st["phase"]) == "battles":
				break
	# B claims one of its battles; A has seen this turn (no summary first).
	for bt in CTurn.pending_for(ob.st, carth):
		var hs3: Array = CTurn.pending_for(ob.st, rome)
		if not hs3.has(bt):
			await ob.claim(int(bt["id"]), "fight")
			break
	oa.set_seen(int(oa.st["turn"]))
	await oa.flush_session()
	out["Zama"] = z
	print("Zama: turn %d, phase %s, battles %d" % [int(oa.st["turn"]), oa.st["phase"], (oa.st["battles"] as Array).size()])
	a.close_campaign()
	b.close_campaign()
	out["Tiber"] = t
	out["Ostia"] = o
	var g := FileAccess.open(dir.path_join("shots.json"), FileAccess.WRITE)
	g.store_string(JSON.stringify(out))
	g.close()
	print(out)
	quit(0)


func _net(acc: String) -> NetScript:
	var n := NetScript.new()
	n.accounts_path = dir.path_join(acc + ".json")
	n.cache_dir = dir.path_join("cache_" + acc) + "/"
	root.add_child(n)
	return n


func _pair(name: String, sd: int) -> String:
	var rome := CData.faction_index("rome")
	var carth := CData.faction_index("carthage")
	var st := CState.new_campaign(name, sd, [rome, carth], {"turn_timeout_h": 24})
	var r: Dictionary = await a.create_campaign(st, rome, {})
	var cid := str(r["data"]["id"])
	await b.join(str(r["data"]["join_code"]), carth)
	return cid
