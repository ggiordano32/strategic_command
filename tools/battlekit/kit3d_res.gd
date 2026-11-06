extends SceneTree
## Packs the kit's 3D meshes (tools/battlekit/export3d.py: <frames>/<piece>.json + .png) into the 3D battle view's resources
## (docs/design/art_pipeline.md "The 3D battle view, step two: houses as geometry"):
##   godot --headless --path . --script res://tools/battlekit/kit3d_res.gd [-- --frames=DIR]
## writes assets/battlekit_ob/kit3d_albedo.png (every piece's baked texture shelf-packed into one atlas, 4 px gutters bled
## out from each texture's edge) and assets/battlekit_ob/kit3d.res (one ArrayMesh, a surface per piece named by the piece:
## vertex, normal, the atlas UV, the mask class in UV2.x (a
## vertex colour would be read as sRGB), indices; the mesh's metadata "pieces" maps a piece to
## [surface, footprint centre x, y (m, the piece frame, y its outer side), height m, triangles]). Then
## `godot --headless --path . --import` for the atlas's .import (lossy WebP with mipmaps, kept in its .import file).

const OUT := "res://assets/battlekit_ob/"
const W := 2048
const MAX_H := 2048
const GUTTER := 4


## Shelf-packs the items' textures scaled by `fit` (their px, py); returns the atlas height.
func _pack(items: Array, fit: float) -> int:
	var order := items.duplicate()
	order.sort_custom(func(a, b): return (a["img"] as Image).get_height() > (b["img"] as Image).get_height())
	var x := 0
	var y := 0
	var rowh := 0
	for it in order:
		var im: Image = it["img"]
		var w := maxi(int(round(im.get_width() * fit)), 8) + GUTTER * 2
		var h := maxi(int(round(im.get_height() * fit)), 8) + GUTTER * 2
		if x + w > W:
			x = 0
			y += rowh
			rowh = 0
		it["px"] = x + GUTTER
		it["py"] = y + GUTTER
		x += w
		rowh = maxi(rowh, h)
	var hh := 64
	while hh < y + rowh:
		hh += 64
	return hh


func _initialize() -> void:
	var frames := ProjectSettings.globalize_path("res://tools/battlekit/_frames3d")
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--frames="):
			frames = str(a).get_slice("=", 1)
	var names: Array[String] = []
	for f in DirAccess.get_files_at(frames):
		if f.ends_with(".json"):
			names.append(f.get_basename())
	names.sort()
	var items: Array = []
	for n in names:
		var d = JSON.parse_string(FileAccess.get_file_as_string(frames + "/" + n + ".json"))
		var img := Image.load_from_file(frames + "/" + n + ".png")
		if not (d is Dictionary) or img == null:
			push_error("kit3d: cannot read " + n)
			continue
		img.convert(Image.FORMAT_RGBA8)
		items.append({"name": n, "d": d, "img": img})
	# Shelf packing, tallest first, into W x MAX_H: the textures scaled down together until they fit.
	var H := 0
	var fit := 1.0
	while true:
		H = _pack(items, fit)
		if H <= MAX_H:
			break
		fit *= 0.96
	if fit < 1.0:
		for it in items:
			var im: Image = it["img"]
			im.resize(maxi(int(round(im.get_width() * fit)), 8), maxi(int(round(im.get_height() * fit)), 8), Image.INTERPOLATE_LANCZOS)
	var atlas := Image.create(W, H, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.5, 0.5, 0.5, 1.0))
	for it in items:
		var im: Image = it["img"]
		var px: int = it["px"]
		var py: int = it["py"]
		# the gutter: the texture's edge rows and columns smeared outwards (mipmaps and filtering read clean colour)
		for g in range(GUTTER, 0, -1):
			atlas.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(px - g, py))
			atlas.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(px + g, py))
		for g in range(GUTTER, 0, -1):
			atlas.blit_rect(atlas, Rect2i(px - GUTTER, py, im.get_width() + GUTTER * 2, 1), Vector2i(px - GUTTER, py - g))
			atlas.blit_rect(atlas, Rect2i(px - GUTTER, py + im.get_height() - 1, im.get_width() + GUTTER * 2, 1),
				Vector2i(px - GUTTER, py + im.get_height() - 1 + g))
		atlas.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(px, py))
	var mesh := ArrayMesh.new()
	var meta := {}
	var tris := 0
	for it in items:
		var d: Dictionary = it["d"]
		var im: Image = it["img"]
		var v: Array = d["v"]
		var nn: Array = d["n"]
		var uv: Array = d["uv"]
		var c: Array = d["c"]
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
		var sx := float(im.get_width()) / W
		var sy := float(im.get_height()) / H
		var ox := float(it["px"]) / W
		var oy := float(it["py"]) / H
		for q in nv:
			verts[q] = Vector3(float(v[q * 3]), float(v[q * 3 + 1]), float(v[q * 3 + 2]))
			norms[q] = Vector3(float(nn[q * 3]), float(nn[q * 3 + 1]), float(nn[q * 3 + 2])).normalized()
			uvs[q] = Vector2(ox + clampf(float(uv[q * 2]), 0.0, 1.0) * sx, oy + clampf(float(uv[q * 2 + 1]), 0.0, 1.0) * sy)
			cls[q] = Vector2(float(c[q]), 0.0)
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
		mesh.surface_set_name(s, str(it["name"]))
		var fc: Array = d["fc"]
		meta[str(it["name"])] = [s, float(fc[0]), float(fc[1]), float(d["height_m"]), int(d["tris"])]
		tris += int(d["tris"])
	mesh.set_meta("pieces", meta)
	mesh.set_meta("atlas", [W, H])
	var err := ResourceSaver.save(mesh, OUT + "kit3d.res", ResourceSaver.FLAG_COMPRESS)
	var err2 := atlas.save_png(ProjectSettings.globalize_path(OUT + "kit3d_albedo.png"))
	print("kit3d: %d pieces, %d triangles, atlas %d x %d, textures at %.2f (save %d / %d)" % [items.size(), tris, W, H, fit, err, err2])
	quit(0 if err == OK and err2 == OK else 1)
