extends RefCounted
## The sea battle's coast in 3D (stage D2 part 1; docs/design/sea.md "The sea battle in 3D, stage D2"): the land as a modelled terrain
## piece instead of D1's flat quad. View only: it reads the baked fields of SeaLook (the signed distance to the coast, the steepness,
## the woods' noise) and never the sim.
##  - the relief mesh: a grid of 10 m (20 m on Low) over the field and the board's margin (the outer lines the margin's edge, where the
##    baked fields go on as their edge texel), cells that touch no land left out, the beach rising from the drawn shore, a cliff where
##    the coast is steep, a gentle swell of hills inland from the woods' noise, a skirt down to the slab's foot where land meets the
##    board's cut edge; painted by game/sea_coast3d.gdshader (the 2D screen's land fragment), alpha-cut at the drawn shore;
##  - the trees as cards (game/sea_trees3d.gdshader) from SeaLook.trees: the oblique sheet's palms (the tropics), pines, broadleaf and
##    scrub, one MultiMesh, 600 (200 on Low);
##  - the rocks, the ruined tower and the harbour forts (Havana's Morro and Fuerza ...) as the kit's meshes (game/kit3d.gd), one
##    MultiMesh a piece, standing on the relief.
## The vertex budget is VERT_MAX (40,000).

const Kit3D := preload("res://game/kit3d.gd")
const KitOb := preload("res://game/kit_ob.gd")
const Atlas := preload("res://game/battlekit_atlas.gd")
const Atlas2 := preload("res://game/battlekit_atlas2.gd")
const Kit := preload("res://game/battlekit.gd")
const Table3D := preload("res://game/table3d.gd")
const COAST_SHADER := preload("res://game/sea_coast3d.gdshader")
const TREE_SHADER := preload("res://game/sea_trees3d.gdshader")
const KIT_SHADER := preload("res://game/kit_mesh3d.gdshader")

const VERT_MAX := 40000
const TREE_K := 1.8              # a miniature's tree: oversize against the ships (1.5 x), as the flags are
const SHORE_Y := 0.12            # the land's height at the drawn shore (metres over the water)
const CARD_PIECES := ["tree_palm_a", "tree_palm_b", "tree_broad_a", "tree_broad_b", "tree_pine_a", "tree_pine_b", "bush_a", "bush_b"]

var verts := 0                   # (stats for the tests and the cost table)
var tris := 0
var trees := 0
var kit_instances := 0
var kit_tris := 0
var mesh: ArrayMesh
var tree_mi: MultiMeshInstance3D
var kit_mis: Array = []          # MultiMeshInstance3D per piece
var kit_mat: ShaderMaterial


## The land's height (metres over the water) at sea point p.
static func height(look, p: Vector2) -> float:
	var im: float = maxf(-float(look.sdf_at(p)) - 6.0, 0.0)
	var st: float = smoothstep(0.35, 0.7, float(look._csample(look.cst, p)))
	var beach := 4.0 * (1.0 - exp(-im / 70.0))
	var cliff := 14.0 * smoothstep(0.0, 45.0, im)
	var hills: float = (float(look._csample(look.cwn, p)) - 0.5) * 9.0 * smoothstep(25.0, 140.0, im)
	return SHORE_Y + lerpf(beach, cliff, st) + hills * (0.5 + 0.5 * st)


static func _lines(len_m: float, margin: float, step: float) -> PackedFloat32Array:
	var a := PackedFloat32Array([-margin])
	var n := int(ceil(len_m / step))
	for i in n + 1:
		a.append(minf(float(i) * step, len_m))
	if a[a.size() - 1] < len_m:
		a.append(len_m)
	a.append(len_m + margin)
	return a


## The relief mesh of the land; null when the field has no land.
func build_mesh(look, field: Vector2, margin: float) -> ArrayMesh:
	var step := 20.0 if look.low else 10.0
	var xs := _lines(field.x, margin, step)
	var zs := _lines(field.y, margin, step)
	var nx := xs.size()
	var nz := zs.size()
	var h := PackedFloat32Array()
	var sd := PackedFloat32Array()
	h.resize(nx * nz)
	sd.resize(nx * nz)
	for j in nz:
		for i in nx:
			var p := Vector2(xs[i], zs[j])
			var s: float = look.sdf_at(p)
			sd[j * nx + i] = s
			h[j * nx + i] = height(look, p) if s < 4.0 else SHORE_Y
	var vid := PackedInt32Array()
	vid.resize(nx * nz)
	vid.fill(-1)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var foot := -Table3D.SLAB_BELOW
	for j in nz - 1:
		for i in nx - 1:
			var k00 := j * nx + i
			var k10 := k00 + 1
			var k01 := k00 + nx
			var k11 := k01 + 1
			if minf(minf(sd[k00], sd[k10]), minf(sd[k01], sd[k11])) > 2.0:
				continue
			for k in [k00, k10, k01, k11]:
				if vid[k] < 0:
					vid[k] = pos.size()
					var ii: int = k % nx
					var jj: int = k / nx
					pos.append(Vector3(xs[ii], h[k], zs[jj]))
					var il := maxi(ii - 1, 0)
					var ir := mini(ii + 1, nx - 1)
					var ju := maxi(jj - 1, 0)
					var jd := mini(jj + 1, nz - 1)
					var dhx := (h[jj * nx + ir] - h[jj * nx + il]) / maxf(xs[ir] - xs[il], 0.01)
					var dhz := (h[jd * nx + ii] - h[ju * nx + ii]) / maxf(zs[jd] - zs[ju], 0.01)
					nrm.append(Vector3(-dhx, 1.0, -dhz).normalized())
					col.append(Color(0, 0, 0, 1))
			idx.append_array(PackedInt32Array([vid[k00], vid[k01], vid[k10], vid[k10], vid[k01], vid[k11]]))
	if idx.is_empty():
		return null
	# The board's cut edge: a skirt down to the slab's foot along the perimeter cells that hold land.
	var edges: Array = []
	for i in nx - 1:
		edges.append([i, 0, i + 1, 0, Vector3(0, 0, -1)])
		edges.append([i, nz - 1, i + 1, nz - 1, Vector3(0, 0, 1)])
	for j in nz - 1:
		edges.append([0, j, 0, j + 1, Vector3(-1, 0, 0)])
		edges.append([nx - 1, j, nx - 1, j + 1, Vector3(1, 0, 0)])
	for e in edges:
		var ka: int = int(e[1]) * nx + int(e[0])
		var kb: int = int(e[3]) * nx + int(e[2])
		if vid[ka] < 0 or vid[kb] < 0 or sd[ka] > -5.0 or sd[kb] > -5.0:
			continue
		var base := pos.size()
		var a: Vector3 = pos[vid[ka]]
		var b: Vector3 = pos[vid[kb]]
		for q in [a, b, Vector3(a.x, foot, a.z), Vector3(b.x, foot, b.z)]:
			pos.append(q)
			nrm.append(e[4])
			col.append(Color(1, 0, 0, 1))
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-margin, foot, -margin), Vector3(field.x + 2.0 * margin, 40.0 - foot, field.y + 2.0 * margin))
	verts = pos.size()
	tris = idx.size() / 3
	return mesh


## Builds the mesh, the trees and the kit pieces under `parent`; `lamp_dir` the world lamp's direction (toward the light) for the
## kit's faces. Returns the land's MeshInstance3D (null: no land).
func build(parent: Node3D, look, field: Vector2, margin: float, land_mat: ShaderMaterial, lamp_dir: Vector3) -> MeshInstance3D:
	var m := build_mesh(look, field, margin)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "coast"
	mi.mesh = m
	mi.material_override = land_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_build_props(parent, look, lamp_dir)
	return mi


func _build_props(parent: Node3D, look, lamp_dir: Vector3) -> void:
	var cards: Array = []
	var kit_rows := {}
	for t in look.trees:
		var nm: String = Atlas.NAMES[int(t[2])]
		if nm in CARD_PIECES:
			cards.append(t)
		elif Kit3D.has(nm):
			var rows: PackedFloat32Array = kit_rows.get(nm, PackedFloat32Array())
			var p := Vector2(t[0], t[1])
			var hh := hash(Vector2i(int(p.x * 7.0), int(p.y * 7.0)))
			var yaw := float(hh % 628) / 100.0
			_row(rows, look, nm, p, Vector2(cos(yaw), sin(yaw)), float(t[3]) * (1.6 if nm.begins_with("rock") else 1.0), 0.6, 0.0)
			kit_rows[nm] = rows
	for f in look.forts:
		var nm: String = Atlas2.NAMES[int(f[2])]
		if not Kit3D.has(nm):
			continue
		var rows2: PackedFloat32Array = kit_rows.get(nm, PackedFloat32Array())
		var yaw2 := float(f[3])
		_row(rows2, look, nm, Vector2(f[0], f[1]), Vector2(cos(yaw2), sin(yaw2)), float(f[4]), 0.4, 4.0)
		kit_rows[nm] = rows2
	if not cards.is_empty() and KitOb.ok():
		_build_trees(parent, look, cards)
	if not kit_rows.is_empty():
		_build_kit(parent, kit_rows, lamp_dir)


## One kit instance row (16 floats; as View3D._mesh_row): the piece's footprint centre on `p`, its right `e` on the map, outer side
## (-z of the mesh) to the map's e rotated a quarter turn, scale `sc`, sunk `sink` metres.
func _row(rows: PackedFloat32Array, look, nm: String, p: Vector2, e: Vector2, sc: float, sink: float, cul: float) -> void:
	var c := Kit3D.centre(nm)
	var o := p - e * (c.x * sc) - Vector2(e.y, -e.x) * (c.y * sc)
	var g := height(look, p) - sink
	var bx := Vector3(e.x * sc, 0.0, e.y * sc)
	var by := Vector3(0.0, sc, 0.0)
	var bz := Vector3(-e.y * sc, 0.0, e.x * sc)
	rows.append_array(PackedFloat32Array([bx.x, by.x, bz.x, o.x, bx.y, by.y, bz.y, g, bx.z, by.z, bz.z, o.y,
		cul + (0.0 if look.tropic else 0.0), 0.0, 0.0, 0.0]))


func _build_kit(parent: Node3D, kit_rows: Dictionary, lamp_dir: Vector3) -> void:
	kit_mat = ShaderMaterial.new()
	kit_mat.shader = KIT_SHADER
	kit_mat.set_shader_parameter("kit_tex", Kit3D.tex)
	kit_mat.set_shader_parameter("stone_tint", PackedVector3Array(Kit.STONE_TINT))
	kit_mat.set_shader_parameter("pal_r", PackedVector3Array(Kit.PAL_R))
	kit_mat.set_shader_parameter("pal_g", PackedVector3Array(Kit.PAL_G))
	kit_mat.set_shader_parameter("pal_b", PackedVector3Array(Kit.PAL_B))
	kit_mat.set_shader_parameter("key_dir", lamp_dir)
	for nm in kit_rows:
		var buf: PackedFloat32Array = kit_rows[nm]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Kit3D.mesh(nm)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		mm.custom_aabb = AABB(Vector3(-400.0, -10.0, -400.0), Vector3(3400.0, 120.0, 2400.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "kit_" + nm
		mi.multimesh = mm
		mi.material_override = kit_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		kit_mis.append(mi)
		kit_instances += mm.instance_count
		kit_tris += mm.instance_count * Kit3D.tris(nm)


func _build_trees(parent: Node3D, look, cards: Array) -> void:
	var names: Array = []
	var rects := PackedVector4Array()
	var anch := PackedVector4Array()
	rects.resize(16)
	anch.resize(16)
	var tw := float(KitOb.alb.get_width())
	var th := float(KitOb.alb.get_height())
	var buf := PackedFloat32Array()
	var n := 0
	for t in cards:
		var nm: String = Atlas.NAMES[int(t[2])]
		var li := names.find(nm)
		if li < 0:
			var q := KitOb.index(nm, false)
			if q < 0 or names.size() >= 16:
				continue
			names.append(nm)
			li = names.size() - 1
			var sp: Array = KitOb.px(q)
			rects[li] = Vector4(sp[0] / tw, sp[1] / th, sp[2] / tw, sp[3] / th)
			anch[li] = Vector4(sp[2], sp[3], sp[4], sp[5])
		var p := Vector2(t[0], t[1])
		var sc := float(t[3])
		var shade := 3.0 if nm.begins_with("tree_palm") else float(hash(Vector2i(int(p.x), int(p.y))) % 3)
		buf.append_array(PackedFloat32Array([1, 0, 0, p.x, 0, 1, 0, height(look, p) - 0.1, 0, 0, 1, p.y,
			float(t[4]), float(li), sc * TREE_K * (1.5 if nm.begins_with("bush") else 1.0), shade]))
		n += 1
	if n == 0:
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var qm := ArrayMesh.new()
	qm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = qm
	mm.instance_count = n
	mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-100.0, -10.0, -100.0), Vector3(look.field.x + 200.0, 140.0, look.field.y + 200.0))
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SHADER
	mat.set_shader_parameter("albedo_tex", KitOb.low if look.low and KitOb.low != null else KitOb.alb)
	mat.set_shader_parameter("rects", rects)
	mat.set_shader_parameter("anch", anch)
	mat.set_shader_parameter("mpp", 1.0 / KitOb.ppm)
	tree_mi = MultiMeshInstance3D.new()
	tree_mi.name = "trees"
	tree_mi.multimesh = mm
	tree_mi.material_override = mat
	tree_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(tree_mi)
	trees = n
