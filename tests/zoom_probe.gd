extends SceneTree
## Overworld zoom probe (windowed): opens a campaign in a map style and view,
## zooms to the minimum, the maximum, then a middle zoom at the map's top-left
## corner, saves a screenshot of each and checks that the map-table frame
## (table_frame.gd) spans the viewport. The paper patch at the top left at
## minimum zoom (owner, 2026-10-27) was that frame left at a stale size.
##   DISPLAY=:0 godot --path . --disable-vsync --resolution 2000x923 -s tests/zoom_probe.gd -- \
##     --pack=west|rome --style=table|relief|auto --view=terrain|political [--grow] [--nofog] [--shots=DIR] [--tag=NAME]
##   --grow: the viewport grows by 1 / 0.85 (about 18 %) after the screen is built
##   (--disable-vsync: an idle display can throttle the window to 1 frame a second)
## Prints RESULT: PASS / FAIL and exits 0 / 1 (it may then abort at exit, a known quirk).
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
var cs
var frame := 0
var pack := "west"
var style := "table"
var view := "terrain"
var shots := ""
var tag := ""
var fails: Array = []
var grow := false
var nofog := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--view="):
			view = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
		elif a == "--nofog":
			nofog = true   # the whole map in sight (the fog darkens the unseen sea; for the look shots)
		elif a == "--grow":
			grow = true
		elif a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
	FogView.all_seeing = nofog
	MapView.load_view_pref()
	MapView.set_style(style, false)
	MapView.set_terrain_view(view != "political", false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("brethren" if pack == "west" else "rome")]
	if int(humans[0]) < 0:
		humans = [0]
	var st: Dictionary = CState.new_campaign("Z", 3, humans, {}, [], pack)
	st["humans"] = humans
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "zoom_probe")
	root.add_child(cs)

func _check(name: String) -> void:
	var vp: Vector2 = cs._vp()
	var tf: Control = cs.table_frame
	print("%s zoom=%.3f vp=%s frame visible=%s rect=%s" % [name, cs.zoom, vp, tf.is_visible_in_tree(), tf.get_global_rect()])
	if tf.is_visible_in_tree() and not tf.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, vp)):
		fails.append("%s: the table frame is %s, not the viewport %s" % [name, tf.get_global_rect(), vp])

func _shot(name: String) -> void:
	if shots == "":
		return
	var img := root.get_texture().get_image()
	img.save_png(shots.path_join("%s%s_%s_%s_%s.png" % [tag, pack, style, view, name]))

func _process(_d: float) -> bool:
	frame += 1
	if frame == 20 and grow:
		# the owner's case: the viewport grows after the screen is built (a web
		# canvas or window resized, the UI scale applied): the frame must follow
		root.content_scale_size = Vector2i(Vector2(root.content_scale_size) / 0.85)
	if frame == 40:
		cs.close_dialog()
		cs.cover.visible = false
		cs._zoom_at(cs._vp() * 0.5, 0.001)
	elif frame == 70:
		_check("min")
		_shot("min")
		cs._zoom_at(cs._vp() * 0.5, 1000.0)
	elif frame == 100:
		_check("max")
		_shot("max")
		# a middle zoom with the map's top-left corner and the table beyond it in view
		cs.zoom = 0.6
		cs.offset = Vector2(1e5, 1e5)
		cs._clamp_view()
	elif frame == 130:
		_check("edge")
		_shot("edge")
		# a middle zoom on the Gulf coast (West: Veracruz; Rome: Massalia): the shelf and the coast bands in view
		var key := "veracruz" if pack == "west" else "massalia"
		var rg := CData.region_index(key)
		cs.zoom = 1.0
		cs.offset = cs._vp() * 0.5 - Geo.site(maxi(rg, 0)) * cs.zoom + Vector2(-250, 0)
		cs._clamp_view()
	elif frame == 170:
		_check("mid")
		_shot("mid")
		for f in fails:
			print("FAIL ", f)
		print("RESULT: ", "PASS" if fails.is_empty() else "FAIL")
		quit(0 if fails.is_empty() else 1)
	return false
