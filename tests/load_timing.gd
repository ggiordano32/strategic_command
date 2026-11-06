extends SceneTree
## The battle's setup phase by phase (docs/design/ui.md "The battle's loading bar"): builds one scenario twice in one process,
## staged as the menu starts it, and prints each build's tap-to-frame time and its steps (Battle.load_timings). The first is a
## cold start (this process's static caches empty: the soldiers' atlas, the tree atlas, the oblique sheets, the kit sheets, the
## 3D meshes), the second what every battle after the first finds (or the first after the menu's warm-up, game/battle_warm.gd),
## the two built minutes apart so a busy machine hits both alike.
##   godot --path . --resolution 1280x720 --script res://tests/load_timing.gd -- --scn=west_town --battle-view=3d --quality=high [--warm]
## --warm runs BattleWarm's steps first (the menu's idle), so the first build is the warm one too.

const Battle := preload("res://game/battle.gd")
const BattleWarm := preload("res://game/battle_warm.gd")


func _init() -> void:
	await process_frame
	var scn := "battle_2000"
	var warm := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scn="):
			scn = a.get_slice("=", 1)
		elif a == "--warm":
			warm = true
	if warm:
		BattleWarm._run_all()
	for i in 2:
		var b := Battle.new()
		b.scenario_id = scn
		b.seed_value = 42
		b.staged = true
		b.tap_msec = Time.get_ticks_msec()
		root.add_child(b)
		await b.load_done
		var parts := PackedStringArray()
		for t in b.load_timings:
			parts.append("%s %.0f" % [t[0], t[1]])
		print("LOAD %s build %d: %.0f ms (%s)" % [scn, i + 1, b.load_total_ms, ", ".join(parts)])
		b.queue_free()
		for k in 5:
			await process_frame
	quit(0)
