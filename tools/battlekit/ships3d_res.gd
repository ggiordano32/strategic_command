extends SceneTree
## Packs the sea battle's ship models (tools/battlekit/export_ships.py: <frames>/<row>.json and ships3d_albedo.png) into
## assets/battlekit_ob/ships3d.res (one ArrayMesh, a surface per row named by the row's key: vertex, normal, the atlas UV, the mask class
## in UV2.x and the baked occlusion in UV2.y, indices; the metadata "models" maps a row to [surface, triangles, length m, beam m, freeboard m])
## and ships3d_albedo.png (the painted swatch atlas, copied as it is: the UVs already address it):
##   godot --headless --path . --script res://tools/battlekit/ships3d_res.gd [-- --frames=DIR]
## then `godot --headless --import` for the atlas's .import.

const OUT := "res://assets/battlekit_ob/"


func _initialize() -> void:
	var frames := ProjectSettings.globalize_path("res://tools/battlekit/_frames_ships")
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--frames="):
			frames = str(a).get_slice("=", 1)
	var names: Array[String] = []
	for f in DirAccess.get_files_at(frames):
		if f.ends_with(".json"):
			names.append(f.get_basename())
	names.sort()
	var mesh := ArrayMesh.new()
	var meta := {}
	var tris := 0
	for n in names:
		var d = JSON.parse_string(FileAccess.get_file_as_string(frames + "/" + n + ".json"))
		if not (d is Dictionary):
			push_error("ships3d: cannot read " + n)
			continue
		var v: Array = d["v"]
		var nn: Array = d["n"]
		var uv: Array = d["uv"]
		var c: Array = d["c"]
		var ao: Array = d["ao"]
		var ix: Array = d["i"]
		var nv := v.size() / 3
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cls := PackedVector2Array()
		verts.resize(nv)
		norms.resize(nv)
		uvs.resize(nv)
		cls.resize(nv)
		for q in nv:
			verts[q] = Vector3(float(v[q * 3]), float(v[q * 3 + 1]), float(v[q * 3 + 2]))
			norms[q] = Vector3(float(nn[q * 3]), float(nn[q * 3 + 1]), float(nn[q * 3 + 2])).normalized()
			uvs[q] = Vector2(float(uv[q * 2]), float(uv[q * 2 + 1]))
			cls[q] = Vector2(float(c[q]), float(ao[q]))
		var idx := PackedInt32Array()
		idx.resize(ix.size())
		for q in ix.size():
			idx[q] = int(ix[q])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = cls
		arr[Mesh.ARRAY_INDEX] = idx
		var s := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_name(s, n)
		meta[n] = [s, int(d["tris"]), float(d["len"]), float(d["beam"]), float(d["fb"])]
		tris += int(d["tris"])
	mesh.set_meta("models", meta)
	var err := ResourceSaver.save(mesh, OUT + "ships3d.res", ResourceSaver.FLAG_COMPRESS)
	var img := Image.load_from_file(frames + "/ships3d_albedo.png")
	var err2 := ERR_FILE_NOT_FOUND
	if img != null:
		err2 = img.save_png(ProjectSettings.globalize_path(OUT + "ships3d_albedo.png"))
	print("ships3d: %d models, %d triangles (save %d / %d)" % [meta.size(), tris, err, err2])
	quit(0 if err == OK and err2 == OK else 1)
