extends SceneTree
## Bakes the overworld's chart-sea distance fields (map_view.gd chart_build_d / chart_build_z) to
## assets/chart/<pack>_chart_d.png, <pack>_chart_z.png (L8, the encoding the water and fog shaders read) and the
## sidecar <pack>_chart.json (key = MapView.chart_key(), a hash of LANDS, CHART, the coast field and the grid; the
## sizes). The map loads these when the key and sizes match and builds at runtime otherwise.
##   godot --headless --script res://tools/bake_chart.gd -- --pack=west|rome [--check]
##   then: godot --headless --import   (writes the .import files; commit them with the PNGs)
## --check: rebuild and compare with the files on disk (max channel delta, differing pixels; exit 1 if any).
## Re-bake after any change to a pack's LANDS / CHART / relief data (a stale key just falls back to the runtime build).
## scale constants (the shaders): d is map px / 3 (L8); z is (signed distance + 150) / 300 * 255.

const PackView := preload("res://game/campaign/pack_view.gd")
const MapView := preload("res://game/campaign/map_view.gd")


func _initialize() -> void:
	var pack := "west"
	var check := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a == "--check":
			check = true
	PackView.use_pack(pack)
	var dir := "res://assets/chart"
	var built := {"d": MapView.chart_build_d(), "z": MapView.chart_build_z()}
	var side := {"key": MapView.chart_key(), "d": [built.d.w, built.d.h], "z": [built.z.w, built.z.h]}
	var base := "%s/%s_chart" % [dir, pack]
	if check:
		var bad := 0
		var f := FileAccess.open(base + ".json", FileAccess.READ)
		var disk = JSON.parse_string(f.get_as_text()) if f != null else null   # (numbers parse as floats: compare as text)
		if not (disk is Dictionary) or str(disk.get("key", "")) != side.key or str(disk.get("d", [])).replace(".0", "") != str(side.d) \
				or str(disk.get("z", [])).replace(".0", "") != str(side.z):
			print("CHECK %s: sidecar missing or different" % pack)
			bad += 1
		for k in ["d", "z"]:
			var img := Image.load_from_file("%s_%s.png" % [base, k])
			var b: Dictionary = built[k]
			if img == null or img.get_width() != b.w or img.get_height() != b.h:
				print("CHECK %s %s: missing or wrong size" % [pack, k])
				bad += 1
				continue
			img.convert(Image.FORMAT_L8)
			var data := img.get_data()
			var diff := 0
			var mx := 0
			for i in data.size():
				var dl := absi(int(data[i]) - int(b.bytes[i]))
				if dl > 0:
					diff += 1
					mx = maxi(mx, dl)
			print("CHECK %s %s: %dx%d, %d differing pixels, max delta %d" % [pack, k, b.w, b.h, diff, mx])
			if diff > 0:
				bad += 1
		print("RESULT: %s" % ("PASS" if bad == 0 else "FAIL"))
		quit(0 if bad == 0 else 1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for k in ["d", "z"]:
		var b: Dictionary = built[k]
		var err := Image.create_from_data(b.w, b.h, false, Image.FORMAT_L8, b.bytes).save_png("%s_%s.png" % [base, k])
		if err != OK:
			push_error("bake_chart: cannot write %s (%d)" % [k, err])
			quit(1)
			return
	var out := FileAccess.open(base + ".json", FileAccess.WRITE)
	out.store_string(JSON.stringify(side, "\t") + "\n")
	out.close()
	print("baked %s: d %dx%d, z %dx%d, key %s" % [pack, built.d.w, built.d.h, built.z.w, built.z.h, side.key])
	quit(0)
