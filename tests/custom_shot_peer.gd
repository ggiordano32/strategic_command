extends SceneTree
## Helper for tests/custom_shots.py: holds Player 1's seat of a custom
## battle room open (connected, ready) for a while, so a windowed client
## joining as Player 2 sees a full lobby.
##   godot --headless --script res://tests/custom_shot_peer.gd -- --server=URL --code=C --token=T [--secs=60]

const CoopSession := preload("res://game/net/coop_session.gd")
const CS := preload("res://game/custom/custom_setup.gd")


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var server := ""
	var code := ""
	var token := ""
	var secs := 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			server = a.get_slice("=", 1)
		elif a.begins_with("--code="):
			code = a.get_slice("=", 1)
		elif a.begins_with("--token="):
			token = a.get_slice("=", 1)
		elif a.begins_with("--secs="):
			secs = float(a.get_slice("=", 1))
	var s := CoopSession.new()
	root.add_child(s)
	s.setup_custom(server, code, token, 0, func(st: Dictionary) -> Dictionary: return CS.build(st))
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		await create_timer(0.2).timeout
		if s.phase == "lobby" and not s.want_ready and s.build_error == "":
			s.lobby_ready(true)
	s.leave()
	await create_timer(0.5).timeout
	quit(0)
