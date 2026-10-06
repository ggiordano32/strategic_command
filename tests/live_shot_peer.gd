extends SceneTree
## The other player for the live co-op screenshots and UI checks (run by
## tests/live_shots.py): a headless CoopSession in a room, scripted.
##   godot --headless --script res://tests/live_shot_peer.gd -- --server=URL --dir=DIR
##     --role=setup | A | B  --bid=N [--create] [--start] [--pause-at=F]
##     [--drop-at=F] [--withdraw-at=F] [--hold=SEC]
## setup: A (Rome) creates a campaign with three live battles
## (net_selftest.gd live_test_state), B (Carthage) joins; writes
## <dir>/cid.txt. A / B: open (--create) or join the room of battle N;
## --start: start at once (alone if need be); --pause-at: ask for a pause at
## that frame; --drop-at: close the connection at that frame (no leave);
## stays --hold seconds, then leaves.

const NetScript := preload("res://game/net/net.gd")
const SelfTest := preload("res://game/net/net_selftest.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var o := {"role": "A", "bid": 1, "hold": 30.0, "pause-at": -1, "drop-at": -1, "withdraw-at": -1}
	var create := false
	var start := false
	var start_ally := false
	var dir := ""
	for a in OS.get_cmdline_user_args():
		var k := a.trim_prefix("--").get_slice("=", 0)
		var v := a.get_slice("=", 1)
		match k:
			"dir":
				dir = v
			"role":
				o["role"] = v
			"bid", "pause-at", "drop-at", "withdraw-at":
				o[k] = int(v)
			"hold":
				o["hold"] = float(v)
			"create":
				create = true
			"start":
				start = true
			"start-when-ally":
				start_ally = true
	var rome := CData.faction_index("rome")
	var carth := CData.faction_index("carthage")
	if o["role"] == "setup":
		var na := _net(dir, "A")
		var nb := _net(dir, "B")
		await process_frame
		await na.check_server()
		var st := SelfTest.live_test_state("Live battles", 21, rome, carth, [7, 11, 13, 15, 18], 6)
		var r: Dictionary = await na.create_campaign(st, rome, {})
		await nb.join(str(r["data"]["join_code"]), carth)
		var f := FileAccess.open(dir.path_join("cid.txt"), FileAccess.WRITE)
		f.store_string(str(r["data"]["id"]))
		f.close()
		print("campaign ", r["data"]["id"])
		quit(0)
		return
	var me := rome if o["role"] == "A" else carth
	var net := _net(dir, o["role"])
	await process_frame
	await net.check_server()
	var cid := FileAccess.get_file_as_string(dir.path_join("cid.txt")).strip_edges()
	var oc = net.open_campaign(cid)
	await oc.open()
	var bid: int = o["bid"]
	var b := CState.battle(oc.st, bid)
	var hs: Array = CRules.battle_humans(oc.st, b)
	var built := CBattle.build(oc.st, b, int(hs.min()))
	var s := CoopSession.new()
	root.add_child(s)
	s.auto_start = false
	s.setup(net.api.base_url, cid, oc.token, me, built, hs, oc.version, create)
	var t0 := Time.get_ticks_msec()
	var asked := false
	while Time.get_ticks_msec() - t0 < int(o["hold"] * 1000.0):
		await process_frame
		if start and s.phase == "lobby" and s.room.is_open():
			s.start_battle()
			start = false
		if start_ally and s.phase == "lobby" and s.connected(carth if me == rome else rome):
			await create_timer(1.0).timeout
			s.start_battle()
			start_ally = false
		if s.ls == null:
			continue
		if o["pause-at"] >= 0 and not asked and s.ls.frame >= o["pause-at"]:
			asked = true
			s.request_pause()
		if o["withdraw-at"] >= 0 and s.ls.frame >= o["withdraw-at"] and s.can_issue():
			o["withdraw-at"] = -1
			s.issue({"type": 8, "side": 0})  # ORDER_WITHDRAW_ALL: my units only
		if o["drop-at"] >= 0 and s.ls.frame >= o["drop-at"]:
			print("dropping at frame ", s.ls.frame)
			s.room.close()
			s.queue_free()
			await create_timer(o["hold"]).timeout
			break
	if is_instance_valid(s):
		s.leave()
	await create_timer(0.5).timeout
	quit(0)


func _net(dir: String, role: String) -> NetScript:
	var n := NetScript.new()
	n.accounts_path = dir.path_join("acc_%s.json" % role)
	n.cache_dir = dir.path_join("cache_%s" % role) + "/"
	root.add_child(n)
	return n
