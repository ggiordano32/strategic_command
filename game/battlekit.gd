extends Node2D
## The settlement's walls, towers and gates on the battle map, drawn from the battle kit
## (tools/battlekit, atlases in assets/battlekit, table in game/battlekit_atlas.gd). View only:
## nothing here touches the sim; it reads the layout (sim.map_info["city"], metres) and the gates'
## state each tick.
##
## High: one MultiMesh (one draw call), every wall segment / tower / gate a quad with its piece of the
## atlas; game/battlekit.gdshader lights it (NW key, the piece's normal turned by the instance angle)
## and tints it by the founding culture. A baked cast shadow + AO layer under it
## (game/battlekit_shadow.gd). Low / CPU path (Graphics Low): the same instances drawn with
## draw_texture_rect_region from the 4 px/m pre-lit atlas, tinted by modulate, no shadow layer, no
## shader at all.
##
## Pieces: walls laid along each edge of the wall polygon, tiled to its length (x scale <= ~25 %), the
## variant matching the sim's (thickness, parapet) so the walkway sits where the men stand; round /
## square (or timber) towers at the sim's tower list (the gate towers are in it); a gate piece
## (closed / open / broken) over the wall at each gate, widths from the sim.

const Atlas := preload("res://game/battlekit_atlas.gd")
const Shadow := preload("res://game/battlekit_shadow.gd")
const Quality := preload("res://game/quality.gd")
const BattleLook := preload("res://game/battle_look.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CData := preload("res://campaign/cdata.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const SHADER := preload("res://game/battlekit.gdshader")
## Block 2 (landmark and civic pieces, "lm_*" / "cv_*"; atlas2_*; tools/battlekit/spec_pieces.py). Used only by
## draw_piece for now; its texture is loaded on the first call.
const Atlas2 := preload("res://game/battlekit_atlas2.gd")
const FortTraces := preload("res://sim/fort_traces.gd")
const CityDraw := preload("res://game/city_draw.gd")
## The mitred wall strips (tools/battlekit/pack_strips.py): one texture per strip, repeated along the wall.
const Strips := preload("res://game/battlekit_strips.gd")
const SHADER_STRIP := preload("res://game/battlekit_strip.gdshader")
const MITRE_MAX := 2.5          # a mitre longer than this many wall thicknesses is bevelled instead
## Loaded when needed (the script checkers' scratch project has no assets/).
var TEX_ALB: Texture2D
var TEX_NRM: Texture2D
var TEX_LOW: Texture2D
var TEX_S_ALB: Texture2D
var TEX_S_NRM: Texture2D
var TEX_S_LOW: Texture2D

const WALL_LEN := 16.0          # a wall piece's length (stone); a palisade piece is PAL_LEN
const PAL_LEN := 12.0
const WALL_H := [5, 5, 7, 9]    # MapGen.WALL_H by wall level
const WALL_VARIANTS := [[8, 2, "wall_8_2"], [10, 2, "wall_10_2"], [12, 2, "wall_12_2"], [12, 4, "wall_12_4"],
	[14, 4, "wall_14_4"]]
const PAL_VARIANTS := [[8, "pal_8"], [10, "pal_10"], [12, "pal_12"]]
## Stone tint by culture: Latin, Greek, Punic, Celtic, Spanish colonial, native, spare, spare.
## (6 and 7: the West towns' painted houses, phase W: ochre walls under dark red tiles, pale blue walls
## under terracotta.)
const STONE_TINT: Array[Vector3] = [Vector3(1.0, 0.98, 0.95), Vector3(1.06, 1.0, 0.9), Vector3(1.12, 1.05, 0.92),
	Vector3(0.92, 0.95, 0.9), Vector3(1.1, 0.98, 0.84), Vector3(0.98, 0.86, 0.7), Vector3(1.08, 1.0, 0.88), Vector3(1.02, 1.0, 0.96)]
const PAL_R: Array[Vector3] = [Vector3(0.78, 0.34, 0.22), Vector3(0.86, 0.70, 0.54), Vector3(0.90, 0.88, 0.82),
	Vector3(0.70, 0.58, 0.36), Vector3(0.84, 0.48, 0.28), Vector3(0.62, 0.48, 0.36), Vector3(0.64, 0.28, 0.20), Vector3(0.82, 0.46, 0.30)]
const PAL_G: Array[Vector3] = [Vector3(0.90, 0.83, 0.68), Vector3(0.92, 0.9, 0.82), Vector3(0.95, 0.93, 0.86),
	Vector3(0.80, 0.72, 0.58), Vector3(0.95, 0.92, 0.82), Vector3(0.78, 0.60, 0.42), Vector3(0.96, 0.82, 0.52), Vector3(0.78, 0.87, 0.92)]
const PAL_B: Array[Vector3] = [Vector3(0.70, 0.18, 0.16), Vector3(0.25, 0.35, 0.65), Vector3(0.45, 0.30, 0.55),
	Vector3(0.25, 0.35, 0.65), Vector3(0.88, 0.68, 0.20), Vector3(0.20, 0.55, 0.55), Vector3(0.18, 0.52, 0.52), Vector3(0.74, 0.22, 0.18)]
## West town pieces by building kind (MapGen.B_*; phase W), their street front up.
const WEST_PIECE := {MapGen.B_TAVERN: "tavern", MapGen.B_SHOP: "shop", MapGen.B_STORE: "store",
	MapGen.B_WAREHOUSE: "warehouse", MapGen.B_CHANDLER: "chandler", MapGen.B_GOVERNOR: "governor",
	MapGen.B_SHACK: "shack", MapGen.B_LEANTO: "leanto", MapGen.B_MAGAZINE: "magazine"}
const PROP_PIECE := ["barrels", "crates", "cart", "well"]

static var _tex2_low: Texture2D
static var _name_idx2 := {}

var sim
var lay: Dictionary = {}
var k := 10.0                       # px per metre
var low := false
var shadows_on := true
var culture := 0
var cul_override := -1              # --kit-culture=N: every building in that culture (testing)
var build_ms := 0.0
var shadow_ms := 0.0

# Instances (parallel arrays).
var i_piece := PackedInt32Array()
var i_pos := PackedVector2Array()   # metres
var i_e := PackedVector2Array()     # unit vector of the piece's right (image x) on the screen
var i_sx := PackedFloat32Array()
var i_sy := PackedFloat32Array()
var i_hs := PackedFloat32Array()    # height scale (shadows)
var i_gate := PackedInt32Array()    # gate index, or -1
var i_cul := PackedInt32Array()     # culture of the instance (palette)
var shadow_cell := 0.5              # metres per cell of the baked shadow
var tropic := false                 # palms and the Caribbean palette (pack "west")
var i_flash := PackedFloat32Array()
var _gate_inst := PackedInt32Array()
var _gate_state := PackedInt32Array()
var _gate_hit := PackedInt32Array()
var _timber := false
var _mm: MultiMesh
var _mmi: MultiMeshInstance2D
var _mm_a: MultiMesh                # the instances before strip_at (_mm holds those from strip_at on)
var _mmi_a: MultiMeshInstance2D
var _strip_node: Node2D
var _low_node: Node2D
var _shadow: Node2D
var _name_idx := {}
var roofy := PackedByteArray()      # per atlas piece: 1 = a building (roof palette on Low)
## The wall strips (_wall_ring): triangles, three vertices each (metres), their UV (u tiles along the wall,
## v 0 outer edge .. 1 inner edge), the stretch's angle, and per triangle the stretch's origin / unit
## direction / tile step (the UV is affine in the position; the shadow bake reads it back that way).
var strip_name := ""                # "" = none (no walls)
var strip_at := 0                   # the walls stand over the instances before this index, under those after
var strip_hs := 1.0
var strip_vo := 0.0                 # metres from the wall's centre line (+ inward) of the texture's top / bottom edge
var strip_vi := 0.0
var s_vx := PackedVector2Array()
var s_uv := PackedVector2Array()
var s_rot := PackedFloat32Array()   # per triangle
var s_a := PackedVector2Array()     # per triangle
var s_d := PackedVector2Array()
var s_step := PackedFloat32Array()


func setup(p_sim, p_lay: Dictionary, p_k: float) -> void:
	sim = p_sim
	lay = p_lay
	k = p_k
	var t0 := Time.get_ticks_usec()
	_index_names()
	culture = clampi(int(lay.get("founder", lay.get("plan", 0))), 0, 7)
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--kit-culture="):
			culture = clampi(int(str(a).get_slice("=", 1)), 0, 7)
			cul_override = culture
	_timber = int(lay.get("palisade", 0)) != 0
	if int(lay.get("west", 0)) != 0:
		tropic = true
		_build_west()
	else:
		_build_houses()
	_build_instances()
	low = Quality.is_low()
	_make_nodes()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


# ------------------------------------------------- landmark / civic pieces ----

## True when `piece` is a block 2 piece (Atlas2.NAMES: "lm_morro", "cv_cathedral", ...).
static func has_piece(piece: String) -> bool:
	_index2()
	return _name_idx2.has(piece)


static func _index2() -> void:
	if _name_idx2.is_empty():
		for q in Atlas2.NAMES.size():
			_name_idx2[Atlas2.NAMES[q]] = q


## A block 2 piece's footprint in metres: {"x0","y0","x1","y1"} in the piece frame (origin = the piece origin,
## y down on the screen, so the piece's front is y0), "h" its height as built, "w" / "d" the extent. {} if unknown.
static func piece_foot(piece: String) -> Dictionary:
	_index2()
	if not _name_idx2.has(piece):
		return {}
	var f: Array = Atlas2.FOOT[_name_idx2[piece]]
	return {"x0": f[0], "y0": f[1], "x1": f[2], "y1": f[3], "h": f[4], "w": f[2] - f[0], "d": f[3] - f[1]}


## A landmark fort piece's trace (the outer line of its rampart, bastion salients as vertices) in metres in
## the piece frame of piece_foot (front, with its gate, toward -y); empty for a piece without one. Data only:
## the sim's generated table (sim/fort_traces.gd, from the minis' geometry: tools/battlekit/fort_trace.py).
static func piece_trace(piece: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pn := "fort" if piece == "cv_fort" else piece.trim_prefix("lm_")
	var t: Dictionary = FortTraces.T.get(pn, {})
	var v: Array = t.get("v", [])
	for q in v.size() / 2:
		out.append(Vector2(float(int(v[q * 2])), float(int(v[q * 2 + 1]))) * 0.1)
	return out


## Draws a block 2 piece on `canvas` (any CanvasItem, inside its _draw) at pos_m metres, turned by yaw radians
## (0: the piece's front towards screen up; clockwise positive), multiplied by `tint`, at px_per_m screen px per
## metre (the battle map's k). Uses the pre-lit 4 px/m atlas (Roman palette), so it needs no shader and
## works on the Low path too; the shaded MultiMesh path comes with the map builder. Leaves the canvas
## transform reset to identity. Used by nothing yet.
static func draw_piece(canvas: CanvasItem, piece: String, pos_m: Vector2, yaw: float, tint := Color.WHITE,
		px_per_m := 10.0) -> void:
	_index2()
	if not _name_idx2.has(piece):
		return
	if _tex2_low == null:
		_tex2_low = load("res://assets/battlekit/atlas2_low.png")
	var p: int = _name_idx2[piece]
	var an: Array = Atlas2.ANCHOR[p]
	var r: Array = Atlas2.RECT[p]
	var e := Vector2(cos(yaw), sin(yaw))
	var dn := Vector2(-e.y, e.x)
	var w := float(an[2]) * px_per_m
	var h := float(an[3]) * px_per_m
	var o: Vector2 = (pos_m + e * float(an[0]) + dn * float(an[1])) * px_per_m
	var lowk: float = Atlas2.LOW_PPM / Atlas2.PPM
	canvas.draw_set_transform_matrix(Transform2D(e, dn, o))
	canvas.draw_texture_rect_region(_tex2_low, Rect2(-w * 0.5, -h * 0.5, w, h),
		Rect2(float(r[0]) * lowk, float(r[1]) * lowk, float(r[2]) * lowk, float(r[3]) * lowk), tint)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


# ------------------------------------------------------------ instances ----

func _add(piece: String, pos: Vector2, e: Vector2, sx: float, sy: float, hs: float, gate := -1, cul := -1) -> int:
	i_piece.append(_name_idx[piece])
	i_pos.append(pos)
	i_e.append(e)
	i_sx.append(sx)
	i_sy.append(sy)
	i_hs.append(hs)
	i_gate.append(gate)
	i_cul.append(culture if cul < 0 else cul)
	i_flash.append(0.0)
	return i_piece.size() - 1


func _build_instances() -> void:
	if not lay.has("t"):
		return
	var t: float = lay["t"]
	var pp: int = int(lay["pp"])
	var walls := clampi(int(lay["walls"]), 0, 3)
	var hs := 1.0 if _timber else float(WALL_H[walls]) / 5.0
	if walls <= 0:
		return
	var west_fort := int(lay.get("west", 0)) != 0
	if west_fort:
		hs = float(int(lay.get("wall_h_m", 6))) / 5.0  # (slice 2c: the harbour fort's low walls)
	# Wall variant: the sim's (thickness, parapet), else the nearest.
	var wname := ""
	var wt := 10.0
	if _timber:
		var best := 1000.0
		for v in PAL_VARIANTS:
			if absf(float(v[0]) - t) < best:
				best = absf(float(v[0]) - t)
				wname = v[1]
				wt = float(v[0])
	else:
		var best2 := 1000.0
		for v in WALL_VARIANTS:
			var d := absf(float(v[0]) - t) * 10.0 + absf(float(v[1]) - pp)
			if d < best2:
				best2 = d
				wname = v[2]
				wt = float(v[0])
	# (A West town's outline is not a wall: only its fort's trace is, slice 2c.)
	var rings: Array = [] if west_fort else [lay["poly"]]
	var cit: Dictionary = lay.get("cit", {})
	if not cit.is_empty():
		rings.append(cit["poly"])
	strip_at = i_piece.size()
	strip_hs = hs
	strip_name = wname.replace("wall_", "ws_").replace("pal_", "ps_")
	for poly: PackedInt32Array in rings:
		_wall_ring(poly, t / wt)
	if s_vx.is_empty():
		strip_name = ""
		strip_at = 0
	# Gates over the wall, then the towers over everything.
	_gate_inst.resize(0)
	var gates: Array = lay["gates"]
	for g in gates.size():
		var gd: Dictionary = gates[g]
		var ang := float(int(gd["dir"])) * TAU / 1024.0
		var n := Vector2(cos(ang), sin(ang))
		var e := Vector2(-n.y, n.x)
		var hw := float(int(gd.get("hw", 4)))
		var st: int = sim.g_state[g] if g < sim.n_gates else BattleSim.GATE_CLOSED
		_gate_inst.append(_add(_gate_name(st), Vector2(gd["x"], gd["y"]), e, hw / 4.0, (t + 1.0) / 11.0, hs, g))
	_gate_state.resize(gates.size())
	_gate_hit.resize(gates.size())
	for g in gates.size():
		_gate_state[g] = sim.g_state[g] if g < sim.n_gates else BattleSim.GATE_CLOSED
		_gate_hit[g] = 0
	var q := 0
	for tw in lay["towers"]:
		q += 1
		_tower(tw, q, hs)
	var sea: Dictionary = lay.get("sea", {})
	if not sea.is_empty() and not (sea["gate"] as Array).is_empty():
		var g2: Array = sea["gate"]
		var ang2 := float(int(g2[2])) * TAU / 1024.0
		var n2 := Vector2(cos(ang2), sin(ang2))
		var e2 := Vector2(-n2.y, n2.x)
		for s in [-1.0, 1.0]:
			var tc: Vector2 = Vector2(g2[0], g2[1]) + e2 * (3.0 + t * 0.5) * s
			_tower([tc.x, tc.y, t * 0.5, 0, 0], q + 7, hs)


func _index_names() -> void:
	roofy.resize(Atlas.NAMES.size())
	for q in Atlas.NAMES.size():
		var n: String = Atlas.NAMES[q]
		_name_idx[n] = q
		roofy[q] = 1 if (n.begins_with("house_") or n.begins_with("hut_") or n in ["church", "temple", "stall", "longhouse",
			"tavern", "shop", "store", "warehouse", "chandler", "shack", "leanto", "governor", "magazine"]) else 0
	tropic = CData.pack == "west" or "--tropic" in OS.get_cmdline_user_args()


## A land-only kit (rocks and cliffs outside any settlement), a child of the land layer.
func setup_land(p_sim, p_k: float) -> void:
	sim = p_sim
	k = p_k
	shadow_cell = 1.0
	_index_names()
	var ld: Dictionary = sim.map_info.get("land", {})
	for r in ld.get("rocks", []):
		_rock(r)
	low = Quality.is_low()
	_make_nodes()


static func _hf(a: int, b: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 0x5bd1e995
	return float(((x ^ (x >> 15)) & 0x7FFFFFFF) % 10000) / 10000.0


## One outcrop [seed, height dm, x, y, r, ...]: a rock piece per boulder.
func _rock(r: Array) -> void:
	var sd := int(r[0])
	var hgt := float(int(r[1])) / 10.0
	for d in (r.size() - 2) / 3:
		var rad := float(int(r[4 + d * 3]))
		var pname := "rock_a" if rad < 2.6 else ("rock_b" if rad < 3.6 else "rock_c")
		var a := _hf(sd, d * 31) * TAU
		var p: int = _name_idx[pname]
		var s := rad * 2.3 / float((Atlas.ANCHOR[p] as Array)[2])
		_add(pname, Vector2(float(int(r[2 + d * 3])), float(int(r[3 + d * 3]))), Vector2(cos(a), sin(a)), s, s,
			clampf(hgt / 2.2, 0.5, 1.6))


## One cliff: pieces along its brow, each turned so its lower side faces downhill.
func _cliff(c: Dictionary) -> void:
	var pts: PackedInt32Array = c["p"]
	var dn: PackedInt32Array = c["dn"]
	var hh: PackedInt32Array = c["h"]
	var n := pts.size() / 2
	if n < 2:
		return
	var carry := 0.0
	for q in n - 1:
		var a := Vector2(pts[q * 2], pts[q * 2 + 1]) / 100.0
		var b := Vector2(pts[q * 2 + 2], pts[q * 2 + 3]) / 100.0
		var l := a.distance_to(b)
		var t := carry
		while t < l:
			var pos := a.lerp(b, t / maxf(l, 0.01))
			var ang := float(dn[q]) / 1024.0 * TAU
			var nrm := Vector2(cos(ang), sin(ang))
			var e := Vector2(nrm.y, -nrm.x)
			var face := float(hh[q]) / 10.0
			var sy := clampf(face / 4.4, 0.7, 1.5)
			var jv := _hf(int(pos.x * 3.0), int(pos.y * 3.0))
			_add("cliff_m", pos + nrm * (0.3 + jv * 0.8), e if jv > 0.5 else -e, 0.58 + jv * 0.12, sy * (0.92 + jv * 0.2), sy)
			t += 6.5
		carry = t - l


func _build_houses() -> void:
	if not lay.has("buildings"):
		return
	for b in lay["buildings"]:
		var a: Array = b
		var kind: int = a[4]
		if kind == MapGen.B_PIECE:
			continue  # (a town plan's landmark: drawn as its piece, game/city_draw.gd draw_pieces)
		var style := clampi(int(a[5]) if a.size() > 5 else 0, 0, 5)
		if cul_override >= 0:
			style = cul_override
		var shape := int(a[6]) if a.size() > 6 else MapGen.SH_RECT
		var h := (int(a[0]) * 73 + int(a[1]) * 151) % 100
		var pos := Vector2.ZERO
		var e := Vector2(1, 0)
		var fw := 0.0
		var fh := 0.0
		if shape == MapGen.SH_ROUND:
			pos = Vector2(float(int(a[7])), float(int(a[8])))
			fw = float(int(a[9])) * 2.0
			fh = fw
			var ar := float(h) * 0.0628
			e = Vector2(cos(ar), sin(ar))
		elif shape == MapGen.SH_QUAD:
			var q0 := Vector2(float(int(a[7])), float(int(a[8])))
			var q1 := Vector2(float(int(a[9])), float(int(a[10])))
			var q2 := Vector2(float(int(a[11])), float(int(a[12])))
			var q3 := Vector2(float(int(a[13])), float(int(a[14])))
			pos = (q0 + q1 + q2 + q3) * 0.25
			fw = q0.distance_to(q1)
			fh = q1.distance_to(q2)
			e = (q1 - q0).normalized()
			if fh > fw:
				var tmp := fw
				fw = fh
				fh = tmp
				e = Vector2(-e.y, e.x)
		else:
			pos = Vector2(float(int(a[0]) + int(a[2])), float(int(a[1]) + int(a[3]))) * 0.5
			fw = float(int(a[2]) - int(a[0]))
			fh = float(int(a[3]) - int(a[1]))
			if fh > fw:
				var tmp2 := fw
				fw = fh
				fh = tmp2
				e = Vector2(0, 1)
		if h % 2 == 0:
			e = -e
		if kind == MapGen.B_MARKET:
			_stalls(pos, e, fw, fh, style)
			continue
		var pname := _house_piece(kind, style, shape, fw, fh, h)
		var an: Array = Atlas.ANCHOR[_name_idx[pname]]
		var sx := (fw + 0.8) / float(an[2])
		var sy := (fh + 0.8) / float(an[3])
		if shape == MapGen.SH_ROUND:
			sx = (fw + 0.6) / float(an[2])
			sy = sx
		_add(pname, pos, e, sx, sy, 1.0, -1, style)
	# The agora: a well for the fountain, a few stalls at its corners.
	var ag: Array = lay.get("agora", lay.get("plaza", []))
	if ag.size() >= 3:
		var ac := Vector2(float(int(ag[0])), float(int(ag[1])))
		var hs2 := float(int(ag[2]))
		_add("well", ac, Vector2(1, 0), 0.75, 0.75, 1.0, -1, culture)
		if hs2 >= 9.0:
			for q in 4:
				var sg := Vector2(1.0 if q % 2 == 0 else -1.0, 1.0 if q < 2 else -1.0)
				_add("stall", ac + sg * hs2 * 0.72, Vector2(1, 0) if q % 2 == 0 else Vector2(-1, 0), 0.9, 0.9, 1.0, -1, culture)


## A West open town (phase W): every building by its kind, turned so its street front is the piece's
## outer side (records from sim/mapgen.gd _w_put: corners front-left, front-right, back-right,
## back-left); houses in the founder's manner (Spanish flat roofs and hips, English, French and Dutch
## gables) and painted by a hash of their place; the harbour fort, the stake palisade, yard walls,
## goods in the streets, the jetties.
func _build_west() -> void:
	var founder := clampi(int(lay.get("founder", 0)), 0, 7)
	for b in lay.get("buildings", []):
		var a: Array = b
		var kind: int = a[4]
		if kind == MapGen.B_FORT or kind == MapGen.B_PIECE or (a.size() > 17 and int(a[17]) == 1):
			continue  # (a town plan's landmarks are drawn as their pieces: game/city_draw.gd draw_pieces)
		var h := absi(int(a[0]) * 73 + int(a[1]) * 151) % 100
		var q0 := Vector2(float(int(a[7])), float(int(a[8])))
		var q1 := Vector2(float(int(a[9])), float(int(a[10])))
		var q3 := Vector2(float(int(a[13])), float(int(a[14])))
		var q2 := Vector2(float(int(a[11])), float(int(a[12])))
		var pos := (q0 + q1 + q2 + q3) * 0.25
		var fw := q0.distance_to(q1)
		var fh := q0.distance_to(q3)
		var n := (q3 - q0).normalized()
		var e := Vector2(n.y, -n.x)    # (image down into the lot: the front, image up, on the street)
		if kind == MapGen.B_STAKES:
			continue  # (_west_stakes: the palisade as smooth runs)
		if kind == MapGen.B_MARKET:
			_stalls(pos, e, fw, fh, W_CUL)
			continue
		var cul := W_CUL if h < 40 else (6 if h < 72 else 7)
		var pname := ""
		if WEST_PIECE.has(kind):
			pname = WEST_PIECE[kind]
		elif kind == MapGen.B_TEMPLE:
			pname = "church"
			cul = W_CUL
		elif kind == MapGen.B_BARRACKS:
			pname = "warehouse"  # (a stone block under a tiled roof: the guardhouse, the fort's barracks)
		else:
			var ratio := maxf(fw, fh) / maxf(minf(fw, fh), 0.1)
			if founder == MapGen.CUL_LATIN and h % 2 == 0:
				pname = "house_flat_s" if fw < 9.5 and fh < 8.0 else "house_flat_m"
			elif ratio < 1.14:
				pname = "house_hip_s" if fw < 9.0 else "house_hip_m"
			elif ratio < 1.5:
				pname = "house_gable_s" if fw < 9.5 else "house_gable_m"
			else:
				pname = "house_gable_l"
		var an: Array = Atlas.ANCHOR[_name_idx[pname]]
		var sx := (fw + 0.6) / float(an[2])
		var sy := (fh + 0.6) / float(an[3])
		if pname == "church" or pname.begins_with("house_"):
			# (Pieces without a street front: laid along their long side.)
			if fh > fw:
				e = n
				sx = (fh + 0.6) / float(an[2])
				sy = (fw + 0.6) / float(an[3])
			if h % 2 == 0:
				e = -e
		_add(pname, pos, e, sx, sy, 1.0, -1, cul)
	_west_fort()
	_west_stakes()
	for pr in lay.get("props", []):
		var p2: Array = pr
		var kd := clampi(int(p2[0]), 0, PROP_PIECE.size() - 1)
		var ang := float(int(p2[3])) * TAU / 1024.0
		var sc := 0.9 if kd != MapGen.P_CART else 0.95
		# (A cart's shafts run along the street: its long side is the image's vertical.)
		var pe := Vector2(sin(ang), -cos(ang)) if kd == MapGen.P_CART else Vector2(cos(ang), sin(ang))
		_add(PROP_PIECE[kd], Vector2(float(int(p2[1])), float(int(p2[2]))), pe, sc, sc, 1.0, -1, W_CUL)
	for lw in lay.get("lowwalls", []):
		var w2: Array = lw
		var la := Vector2(float(int(w2[0])), float(int(w2[1])))
		var lb := Vector2(float(int(w2[2])), float(int(w2[3])))
		var ll := la.distance_to(lb)
		if ll < 0.5:
			continue
		var cnt2 := maxi(roundi(ll / 8.0), 1)
		for q in cnt2:
			_add("lowwall", la.lerp(lb, (q + 0.5) / cnt2), (lb - la) / ll, (ll / cnt2 + 0.6) / 8.0, 1.0, 1.0, -1, W_CUL)
	var sea: Dictionary = lay.get("sea", {})
	for pq in sea.get("piers", []):
		var pp: PackedInt32Array = pq
		var p0 := Vector2(float(pp[0] + pp[2]) * 0.5, float(pp[1] + pp[3]) * 0.5)
		var p1 := Vector2(float(pp[4] + pp[6]) * 0.5, float(pp[5] + pp[7]) * 0.5)
		var pl := p0.distance_to(p1)
		var pw := Vector2(float(pp[0]), float(pp[1])).distance_to(Vector2(float(pp[2]), float(pp[3])))
		var cnt3 := maxi(roundi(pl / 12.0), 1)
		for q in cnt3:
			_add("pier", p0.lerp(p1, (q + 0.5) / cnt3), (p1 - p0) / maxf(pl, 0.1), pl / cnt3 / 12.0, pw / 4.4, 1.0, -1, W_CUL)
	# The plaza: its well and a few stalls (as the agora's).
	var ag: Array = lay.get("agora", lay.get("plaza", []))
	if ag.size() >= 3:
		var ac := Vector2(float(int(ag[0])), float(int(ag[1])))
		var hs2 := float(int(ag[2]))
		_add("well", ac, Vector2(1, 0), 0.85, 0.85, 1.0, -1, W_CUL)
		for q in 4:
			var sg := Vector2(1.0 if q % 2 == 0 else -1.0, 1.0 if q < 2 else -1.0)
			_add("stall", ac + sg * hs2 * 0.6, Vector2(1, 0) if q % 2 == 0 else Vector2(-1, 0), 0.9, 0.9, 1.0, -1, 6 + q % 2)


const W_CUL := 4   # the West towns' colonial palette (STONE_TINT / PAL_*)


## The stake palisade (walls 2): its records are stretches of one 2 m cell row each, stepping with
## the landward edge; drawn as a smooth line through their middles, run by run (a road's gap ends a
## run), the stakes' points outward (away from the town).
func _west_stakes() -> void:
	var recs: Array = []
	for b in lay.get("buildings", []):
		var a: Array = b
		if int(a[4]) == MapGen.B_STAKES:
			recs.append(a)
	if recs.is_empty():
		return
	recs.sort_custom(func(p, q): return int(p[0]) < int(q[0]))
	var cy := float(int(lay.get("cy", 0)))
	var runs: Array = []
	var cur: Array = []
	for r in recs:
		var a2: Array = r
		if not cur.is_empty() and int((cur[cur.size() - 1] as Array)[2]) < int(a2[0]):
			runs.append(cur)
			cur = []
		cur.append(a2)
	runs.append(cur)
	for run in runs:
		var pts := PackedVector2Array()
		var first: Array = run[0]
		var last: Array = run[run.size() - 1]
		pts.append(Vector2(float(int(first[0])), (float(int(first[1])) + float(int(first[3]))) * 0.5))
		for r2 in run:
			var a3: Array = r2
			pts.append(Vector2((float(int(a3[0])) + float(int(a3[2]))) * 0.5, (float(int(a3[1])) + float(int(a3[3]))) * 0.5))
		pts.append(Vector2(float(int(last[2])), (float(int(last[1])) + float(int(last[3]))) * 0.5))
		var o := Vector2(0, 1) if pts[0].y > cy else Vector2(0, -1)
		for q in pts.size() - 1:
			var a4 := pts[q]
			var b4 := pts[q + 1]
			var l := a4.distance_to(b4)
			if l < 0.3:
				continue
			var d := (b4 - a4) / l
			if d.dot(Vector2(-o.y, o.x)) < 0.0:
				d = -d   # (the piece's outer side, image up, away from the town)
			_add("stakes", (a4 + b4) * 0.5, d, (l + 0.5) / 12.0, 1.0, 1.0, -1, W_CUL)


## The harbour fort (lay "fort": centre, half side h, bastion half diagonal b, turn dir): a curtain
## along each side of its square between the bastions, a bastion at each corner pointing out along
## the diagonal, a keep and a flag in the middle. The sim's fort is solid (not garrisoned).
func _west_fort() -> void:
	var f: Dictionary = lay.get("fort", {})
	if f.is_empty() or not (lay.get("cit", {}) as Dictionary).is_empty():
		return  # (slice 2c: a fort with an inside is drawn as walls, _build_instances)
	var c := Vector2(float(int(f["x"])), float(int(f["y"])))
	var fh := float(int(f["h"]))
	var fb := float(int(f["b"]))
	var ang := float(int(f["dir"])) * TAU / 1024.0
	var ux := Vector2(cos(ang), sin(ang))
	var uy := Vector2(-ux.y, ux.x)
	var corners := [c - ux * fh - uy * fh, c + ux * fh - uy * fh, c + ux * fh + uy * fh, c - ux * fh + uy * fh]
	for q in 4:
		var a: Vector2 = corners[q]
		var b: Vector2 = corners[(q + 1) % 4]
		var mid := (a + b) * 0.5
		var o := (mid - c).normalized()
		var d := Vector2(-o.y, o.x)
		var run := a.distance_to(b) - fb * 1.4
		var cnt := maxi(roundi(run / WALL_LEN), 1)
		for q2 in cnt:
			var t := (q2 + 0.5) / cnt
			var p := a.lerp(b, 0.5) + (b - a).normalized() * (t - 0.5) * run
			_add("wall_10_2", p - o * 3.0, d, run / cnt / WALL_LEN, 1.0, 1.1, -1, W_CUL)
	for q in 4:
		var cp: Vector2 = corners[q]
		var o2 := (cp - c).normalized()
		# (The piece is 18 m wide, its tip 13 m out from its origin: scaled to the sim's diamond,
		# fb out from the corner, its base in the core.)
		var s2 := fb * 1.4 / 18.0
		_add("bastion", cp + o2 * (fb - 13.0 * s2), Vector2(-o2.y, o2.x), s2, s2, 1.0, -1, W_CUL)
	_add("house_flat_m", c, ux, fh * 0.9 / 11.0, fh * 0.7 / 8.0, 1.0, -1, W_CUL)


func _stalls(pos: Vector2, e: Vector2, fw: float, fh: float, style: int) -> void:
	var an: Array = Atlas.ANCHOR[_name_idx["stall"]]
	var nx := maxi(roundi(fw / 6.5), 1)
	var ny := maxi(roundi(fh / 6.5), 1)
	var dn := Vector2(-e.y, e.x)
	var cw := fw / nx
	var ch := fh / ny
	for j in ny:
		for i in nx:
			var u := (float(i) + 0.5 - float(nx) * 0.5) * cw
			var v := (float(j) + 0.5 - float(ny) * 0.5) * ch
			_add("stall", pos + e * u + dn * v, e, (cw + 0.3) / float(an[2]), (ch + 0.3) / float(an[3]), 1.0, -1, style)


func _house_piece(kind: int, style: int, shape: int, fw: float, fh: float, _h: int) -> String:
	if kind == MapGen.B_TEMPLE:
		if style == 4:
			return "church"
		if style == 3 or style == 5:
			return "longhouse"
		return "temple"
	if kind == MapGen.B_BARRACKS or kind == MapGen.B_STABLES or kind == MapGen.B_RANGE:
		return "longhouse"
	if kind == MapGen.B_WORKSHOP:
		return "house_gable_l"
	if shape == MapGen.SH_ROUND:
		return "hut_round"
	if style == 3 or style == 5:
		return "hut_thatch" if fw / maxf(fh, 0.1) < 1.9 else "longhouse"
	var ratio := fw / maxf(fh, 0.1)
	if style == 2:   # Punic: flat roofs with a parapet
		return "house_flat_s" if fw < 9.5 and fh < 8.0 else "house_flat_m"
	if ratio < 1.14:
		return "house_hip_s" if fw < 9.0 else "house_hip_m"
	if ratio < 1.45:
		return "house_gable_s" if fw < 9.5 else "house_gable_m"
	if ratio < 1.95:
		return "house_gable_l"
	return "longhouse"


func _gate_name(st: int) -> String:
	var c := "c"
	if st == BattleSim.GATE_OPEN:
		c = "o"
	elif st == BattleSim.GATE_BROKEN:
		c = "b"
	return ("pgate_" if _timber else "gate_") + c


func _tower(tw: Array, q: int, hs: float) -> void:
	var r := float(tw[2])
	var pos := Vector2(float(tw[0]), float(tw[1]))
	if _timber:
		var a := float((q * 37) % 100) * 0.0628
		_add("tower_timber", pos, Vector2(cos(a), sin(a)), r / 6.5, r / 6.5, hs)
	elif tw.size() > 3 and int(tw[3]) != 0:
		var ang := float(int(tw[4])) * TAU / 1024.0 if tw.size() > 4 else 0.0
		_add("tower_sq", pos, Vector2(cos(ang), sin(ang)), r / 6.1, r / 6.1, hs)
	else:
		var a2 := float((q * 37) % 100) * 0.0628
		_add("tower_round", pos, Vector2(cos(a2), sin(a2)), r / 6.4, r / 6.4, hs)


## One wall ring as a mitred strip (appended to the strip triangles): a quad per stretch along the
## polygon, the texture's tile repeating along it (the stretch's length cut to whole tiles), its outer
## edge `strip_vo` and inner edge `strip_vi` from the polygon line (scaled by `sy`, the sim's thickness over the
## variant's). At each vertex the outer edge runs to where the two neighbouring outer faces meet and the
## inner edge to where the inner faces meet (a mitre); a mitre longer than MITRE_MAX thicknesses is bevelled
## (the two faces' own end points, a triangle between them). No end caps: the ring is closed (a gate piece
## stands over the wall at a gate, a tower at a corner).
func _wall_ring(poly: PackedInt32Array, sy: float) -> void:
	var si := Strips.NAMES.find(strip_name)
	var info: Array = Strips.INFO[si]
	var tile := float(info[0])
	strip_vo = float(info[1]) * sy
	strip_vi = float(info[2]) * sy
	var thick := strip_vi - strip_vo
	# The vertices, close points merged; counter-clockwise (area > 0) so that the inside is on the left.
	var p := PackedVector2Array()
	for e in poly.size() / 2:
		var q := Vector2(poly[e * 2], poly[e * 2 + 1])
		if p.is_empty() or p[p.size() - 1].distance_to(q) >= 0.5:
			p.append(q)
	while p.size() > 1 and p[0].distance_to(p[p.size() - 1]) < 0.5:
		p.remove_at(p.size() - 1)
	var nv := p.size()
	if nv < 3:
		return
	var area := 0.0
	for e in nv:
		var e2 := (e + 1) % nv
		area += p[e].x * p[e2].y - p[e2].x * p[e].y
	if area <= 0.0:
		p.reverse()
	var dirs := PackedVector2Array()
	var nrms := PackedVector2Array()
	for e in nv:
		var dd := (p[(e + 1) % nv] - p[e]).normalized()
		dirs.append(dd)
		nrms.append(Vector2(-dd.y, dd.x))
	# Per vertex and side (0 outer, 1 inner): the end of the stretch before it, the start of the one after.
	var pe := PackedVector2Array()
	var ps := PackedVector2Array()
	var bev := PackedByteArray()
	pe.resize(nv * 2)
	ps.resize(nv * 2)
	bev.resize(nv * 2)
	for e in nv:
		var n0: Vector2 = nrms[(e + nv - 1) % nv]
		var n1: Vector2 = nrms[e]
		var den := 1.0 + n0.dot(n1)
		for side in 2:
			var v := strip_vo if side == 0 else strip_vi
			var m := (n0 + n1) / maxf(den, 0.0001)
			if den < 0.05 or m.length() * absf(v) > MITRE_MAX * thick:
				pe[e * 2 + side] = p[e] + n0 * v
				ps[e * 2 + side] = p[e] + n1 * v
				bev[e * 2 + side] = 1
			else:
				pe[e * 2 + side] = p[e] + m * v
				ps[e * 2 + side] = p[e] + m * v
	for e in nv:
		var e2 := (e + 1) % nv
		var l := p[e].distance_to(p[e2])
		var step := l / float(maxi(roundi(l / tile), 1))
		var q4 := [ps[e * 2], pe[e2 * 2], pe[e2 * 2 + 1], ps[e * 2 + 1]]
		_strip_tri([q4[0], q4[1], q4[2]], p[e], dirs[e], step)
		_strip_tri([q4[0], q4[2], q4[3]], p[e], dirs[e], step)
		# The bevel at the vertex e2 (the stretch e ends there, the stretch e2 starts): fill the wedge.
		var bo := bev[e2 * 2] != 0
		var bi := bev[e2 * 2 + 1] != 0
		if bo:
			_strip_tri([pe[e2 * 2], ps[e2 * 2], p[e2] if bi else pe[e2 * 2 + 1]], p[e], dirs[e], step)
		if bi:
			_strip_tri([pe[e2 * 2 + 1], ps[e2 * 2 + 1], p[e2] if bo else pe[e2 * 2]], p[e], dirs[e], step)


## One strip triangle: its UV from the stretch (origin a, unit direction d, tile step in metres).
func _strip_tri(v: Array, a: Vector2, d: Vector2, step: float) -> void:
	var n := Vector2(-d.y, d.x)
	for q in 3:
		var w: Vector2 = v[q]
		s_vx.append(w)
		s_uv.append(Vector2((w - a).dot(d) / step, ((w - a).dot(n) - strip_vo) / (strip_vi - strip_vo)))
	s_rot.append(d.angle())
	s_a.append(a)
	s_d.append(d)
	s_step.append(step)


## The strip as an ArrayMesh in px: `with_rot` puts the stretch's turn in the vertex colour (the shader's
## normal), else plain (the Low path's draw_mesh).
func _strip_mesh(with_rot: bool) -> ArrayMesh:
	var vx := PackedVector2Array()
	for q in s_vx.size():
		vx.append(s_vx[q] * k)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vx
	arr[Mesh.ARRAY_TEX_UV] = s_uv
	if with_rot:
		var cols := PackedColorArray()
		for q in s_rot.size():
			var c := Color(cos(s_rot[q]) * 0.5 + 0.5, sin(s_rot[q]) * 0.5 + 0.5, 0.0, 1.0)
			cols.append(c)
			cols.append(c)
			cols.append(c)
		arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## The quad's transform in px for instance i drawn as piece p.
func _xform(i: int, p: int) -> Transform2D:
	var an: Array = Atlas.ANCHOR[p]
	var e: Vector2 = i_e[i]
	var dn := Vector2(-e.y, e.x)    # image down on the screen
	var sx := i_sx[i]
	var sy := i_sy[i]
	var o: Vector2 = (i_pos[i] + e * (float(an[0]) * sx) + dn * (float(an[1]) * sy)) * k
	return Transform2D(e * (float(an[2]) * sx * k), dn * (float(an[3]) * sy * k), o)


# ---------------------------------------------------------------- nodes ----

func _make_nodes() -> void:
	if low:
		if TEX_LOW == null:
			TEX_LOW = load("res://assets/battlekit/atlas_low.png")
	elif TEX_ALB == null:
		TEX_ALB = load("res://assets/battlekit/atlas_albedo.png")
		TEX_NRM = load("res://assets/battlekit/atlas_nrm.png")
	if strip_name != "":
		var base := "res://assets/battlekit/strips/" + strip_name
		if low:
			if TEX_S_LOW == null:
				TEX_S_LOW = load(base + "_low.png")
		elif TEX_S_ALB == null:
			TEX_S_ALB = load(base + "_albedo.png")
			TEX_S_NRM = load(base + "_nrm.png")
	for c in get_children():
		c.queue_free()
	_mmi = null
	_mmi_a = null
	_mm_a = null
	_strip_node = null
	_low_node = null
	_shadow = null
	shadow_ms = 0.0
	if not (lay.get("pieces", []) as Array).is_empty():
		# The town plan's landmark pieces (block 2): over the streets' ground, under the walls and houses.
		var pn := _PieceDraw.new()
		pn.kit = self
		add_child(pn)
	if i_piece.is_empty():
		return
	if low:
		_low_node = _LowDraw.new()
		_low_node.kit = self
		if strip_name != "":
			_low_node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			_low_node.strip_mesh = _strip_mesh(false)
		add_child(_low_node)
		return
	shadows_on = not ("--no-kit-shadow" in OS.get_cmdline_user_args())
	if shadows_on:
		var t0 := Time.get_ticks_usec()
		_shadow = Shadow.new()
		_shadow.build(self)
		add_child(_shadow)
		shadow_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", TEX_ALB)
	mat.set_shader_parameter("nrm_tex", TEX_NRM)
	var rects := PackedVector4Array()
	rects.resize(64)
	for p in Atlas.RECT.size():
		var r: Array = Atlas.RECT[p]
		rects[p] = Vector4(float(r[0]) / Atlas.ATLAS_W, float(r[1]) / Atlas.ATLAS_H, float(r[2]) / Atlas.ATLAS_W,
			float(r[3]) / Atlas.ATLAS_H)
	mat.set_shader_parameter("rects", rects)
	mat.set_shader_parameter("stone_tint", PackedVector3Array(STONE_TINT))
	mat.set_shader_parameter("pal_r", PackedVector3Array(PAL_R))
	mat.set_shader_parameter("pal_g", PackedVector3Array(PAL_G))
	mat.set_shader_parameter("pal_b", PackedVector3Array(PAL_B))
	BattleLook.apply(mat)
	# Draw order: the instances before the walls (houses), the wall strip, then the rest (gates, towers).
	if strip_at > 0:
		_mm_a = _make_mm(0, strip_at)
		_mmi_a = MultiMeshInstance2D.new()
		_mmi_a.multimesh = _mm_a
		_mmi_a.material = mat
		add_child(_mmi_a)
	if strip_name != "":
		var smat := ShaderMaterial.new()
		smat.shader = SHADER_STRIP
		smat.set_shader_parameter("albedo_tex", TEX_S_ALB)
		smat.set_shader_parameter("nrm_tex", TEX_S_NRM)
		smat.set_shader_parameter("culture_i", float(culture))
		smat.set_shader_parameter("stone_tint", PackedVector3Array(STONE_TINT))
		smat.set_shader_parameter("pal_r", PackedVector3Array(PAL_R))
		smat.set_shader_parameter("pal_g", PackedVector3Array(PAL_G))
		smat.set_shader_parameter("pal_b", PackedVector3Array(PAL_B))
		BattleLook.apply(smat)
		var sn := MeshInstance2D.new()
		sn.mesh = _strip_mesh(true)
		sn.material = smat
		_strip_node = sn
		add_child(sn)
	_mm = _make_mm(strip_at, i_piece.size())
	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = _mm
	_mmi.material = mat
	add_child(_mmi)


## A MultiMesh of the instances [a, b).
func _make_mm(a: int, b: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _make_quad()
	mm.instance_count = b - a
	var buf := PackedFloat32Array()
	buf.resize((b - a) * 12)
	for i in range(a, b):
		_write(buf, i, (i - a) * 12)
	mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-50, -50, -1), Vector3(sim.field_w / 1024.0 * k + 100, sim.field_h / 1024.0 * k + 100, 2))
	return mm


func _write(buf: PackedFloat32Array, i: int, o := -1) -> void:
	var p := i_piece[i]
	var xf := _xform(i, p)
	if o < 0:
		o = i * 12
	buf[o] = xf.x.x
	buf[o + 1] = xf.y.x
	buf[o + 2] = 0.0
	buf[o + 3] = xf.origin.x
	buf[o + 4] = xf.x.y
	buf[o + 5] = xf.y.y
	buf[o + 6] = 0.0
	buf[o + 7] = xf.origin.y
	buf[o + 8] = float(p)
	buf[o + 9] = i_e[i].angle()
	buf[o + 10] = float(i_cul[i])
	buf[o + 11] = i_flash[i]


static func _make_quad() -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# --------------------------------------------------------------- per tick ----

## Gates: the piece follows the state (closed / open / broken), a flash while struck; a gate
## breaking re-bakes its shadow. Also follows a Graphics quality switch.
func refresh() -> void:
	if i_piece.is_empty():
		return
	if Quality.is_low() != low:
		low = not low
		_make_nodes()
		return
	var changed := false
	var gates: Array = lay.get("gates", [])
	for g in mini(gates.size(), sim.n_gates):
		var st: int = sim.g_state[g]
		var hit := 1 if sim.tick - sim.g_hit_t[g] < 4 else 0
		if st == _gate_state[g] and hit == _gate_hit[g]:
			continue
		var i := _gate_inst[g]
		var broke := st != _gate_state[g]
		_gate_state[g] = st
		_gate_hit[g] = hit
		i_piece[i] = _name_idx[_gate_name(st)]
		i_flash[i] = 1.0 if hit != 0 else 0.0
		changed = true
		if _mm != null:
			var buf := PackedFloat32Array()
			buf.resize(12)
			_write(buf, i, 0)
			var mi := i - strip_at   # (gates stand over the wall: in the second multimesh)
			_mm.set_instance_transform_2d(mi, Transform2D(Vector2(buf[0], buf[4]), Vector2(buf[1], buf[5]), Vector2(buf[3], buf[7])))
			_mm.set_instance_custom_data(mi, Color(buf[8], buf[9], buf[10], buf[11]))
		if broke and _shadow != null:
			_shadow.rebake_instance(i)
	if changed and _low_node != null:
		_low_node.queue_redraw()


## The town plan's landmark pieces (game/city_draw.gd draw_pieces), drawn once.
class _PieceDraw extends Node2D:
	var kit

	func _draw() -> void:
		CityDraw.draw_pieces(self, kit.lay, float(kit.k), Vector2.ZERO)


## The Low path: no shader, no shadow layer; pre-lit 4 px/m atlas, culture tint by modulate.
class _LowDraw extends Node2D:
	var kit
	var strip_mesh: ArrayMesh

	func _draw() -> void:
		var lowk: float = float(kit.Atlas.LOW_PPM) / float(kit.Atlas.PPM)
		var n: int = kit.i_piece.size()
		for i in n + 1:
			if i == kit.strip_at and strip_mesh != null:
				draw_set_transform_matrix(Transform2D.IDENTITY)
				var st: Vector3 = kit.STONE_TINT[kit.culture]
				draw_mesh(strip_mesh, kit.TEX_S_LOW, Transform2D.IDENTITY, Color(st.x, st.y, st.z))
			if i == n:
				break
			var p: int = kit.i_piece[i]
			var an: Array = kit.Atlas.ANCHOR[p]
			var r: Array = kit.Atlas.RECT[p]
			var e: Vector2 = kit.i_e[i]
			var dn := Vector2(-e.y, e.x)
			var sx: float = kit.i_sx[i]
			var sy: float = kit.i_sy[i]
			var w: float = float(an[2]) * sx * float(kit.k)
			var h: float = float(an[3]) * sy * float(kit.k)
			var o: Vector2 = (kit.i_pos[i] + e * (float(an[0]) * sx) + dn * (float(an[1]) * sy)) * float(kit.k)
			draw_set_transform_matrix(Transform2D(e, dn, o))
			var cu: int = kit.i_cul[i]
			var tint: Vector3 = kit.STONE_TINT[cu]
			var c := Color(tint.x, tint.y, tint.z)
			if kit.roofy[p] != 0:
				var rr: Vector3 = kit.PAL_R[cu] / kit.PAL_R[0]
				c = Color(1, 1, 1).lerp(Color(rr.x, rr.y, rr.z), 0.7)
			var col := c
			if kit.i_flash[i] > 0.0:
				c = col.lerp(Color(1.0, 0.62, 0.25), 0.45)
			draw_texture_rect_region(kit.TEX_LOW, Rect2(-w * 0.5, -h * 0.5, w, h),
				Rect2(float(r[0]) * lowk, float(r[1]) * lowk, float(r[2]) * lowk, float(r[3]) * lowk), c)
