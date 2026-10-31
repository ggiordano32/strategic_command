extends SceneTree
## Tutorial popup-lesson shots (windowed): lesson 2 with the recruit list open before and after the two recruits, lesson 3
## with the build list open, lesson 6 with the pending battles dialog; saved as <dir>/<WxH>_<name>.png.
##   godot --path . --disable-vsync --resolution 1280x720 -s tests/tutorial_shots.gd -- --shots=DIR
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CData := preload("res://campaign/cdata.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Tips := preload("res://game/campaign/tips.gd")
const Tutorial := preload("res://game/campaign/tutorial.gd")
var cs
var shots := ""
var tag := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	Saves.subdir = "tutorial_shots/"
	Tips.in_tests = true
	_run.call_deferred()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _shot(nm: String) -> void:
	await _frames(8)
	var vp := Vector2(root.get_texture().get_size())
	var w := "w1280x720" if vp.x > 1000 else "w844x390"
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [shots, w, nm])


func _run() -> void:
	PackView.use_pack("west")
	var st := Tutorial.make_state("Shots", Tutorial.SEED, 0)
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "tutorial_shots")
	root.add_child(cs)
	await _frames(20)
	cs.close_dialog()
	await _frames(4)
	var tu = cs.tutorial
	var pr := CData.region_index("port_royal")
	await _turn()   # lesson 1 skipped
	# lesson 2
	var a: Dictionary = {}
	for x in CState.armies_of(cs.ps, cs.f):
		a = x
	cs.select_army(int(a["id"]))
	await _frames(3)
	cs.panels.show_army_recruit(int(a["id"]))
	await _shot("l2_open")
	(cs.dialog.find_child("recruit_musketeers", true, false) as Button).pressed.emit()
	await _frames(4)
	(cs.dialog.find_child("recruit_musketeers", true, false) as Button).pressed.emit()
	await _shot("l2_done")
	cs.close_dialog()
	await _shot("l2_closed")
	await _turn(false)
	# lesson 3
	cs.select_region(pr)
	await _frames(3)
	cs.panels.show_build(pr)
	await _shot("l3_open")
	cs.close_dialog()
	await _turn()
	await _turn()
	# lesson 8's Diplomacy (the lesson number is set by hand for the shot, then put back)
	var vd: Dictionary = cs.data["session"]["tutorial"]
	var keep_n: int = int(vd["n"])
	vd["n"] = 8
	tu._shown_n = -1
	tu.refresh()
	cs.panels.show_diplomacy()
	await _shot("l8_open")
	cs.dialog.find_child("dip_press_dutch", true, false).pressed.emit()
	await _frames(12)
	await _shot("l8_expanded")
	cs.close_dialog()
	vd["n"] = keep_n
	tu._shown_n = -1
	tu.refresh()
	await _turn()
	# lesson 6: assault, end turn, the battle is pending
	tu.skip()
	await _frames(3)
	cs.end_turn(true)
	for k in 200:
		await process_frame
		if not CTurn.pending_for(cs.st).is_empty():
			break
	await _frames(10)
	cs.close_dialog()
	cs.panels.show_battles()
	await _shot("l6_battles")
	quit(0)


## Skip the lesson (when `skip`) and end the turn.
func _turn(skip := true) -> void:
	if skip:
		cs.tutorial.skip()
	await _frames(3)
	var t0 := int(cs.st["turn"])
	cs.end_turn(true)
	for k in 200:
		await process_frame
		if int(cs.st["turn"]) > t0 and cs.dialog_kind != "resolving":
			break
	await _frames(4)
	for k in 4:
		if cs.dialog_open():
			cs.close_dialog()
		await _frames(2)
