extends RefCounted
## Gun smoke for the battle view and the sea view (view only, no sim state;
## docs/DESIGN.md "Firearms"). Puffs are soft baked cotton-wool sprites (a small
## atlas generated at first use: 2 to 4 lobes each, lit from above and the left, a shaded
## underside, grey-blue tint; tabletop pass 5) that overlap into a continuous bank:
## each rolls forward from the muzzle, expands, rises and drifts with the
## wind, thinning over LIFE s. A faint haze accumulates over a long
## firefight (capped; not on Graphics Low). All in world px; one texture,
## so the canvas batches the draws. The diorama look reads as soft white
## cotton tufts, the painterly look as grey smoke.

const BoardView := preload("res://game/board_view.gd")

const LIFE := 10.0
const TILE := 64
const VARIANTS := 4          # cloud tiles, then one glow tile
const HAZE_CAP := 14
const HAZE_MAX := 1.0

static var _tex: ImageTexture

var pos := PackedVector2Array()
var dir := PackedVector2Array()      # roll direction (unit)
var age := PackedFloat32Array()
var size := PackedFloat32Array()     # radius scale in px
var roll := PackedFloat32Array()     # distance it rolls out, px
var life := PackedFloat32Array()
var kind := PackedByteArray()        # 0 smoke, 1 dust kick
var cap := 280
var haze_on := true
var hz_pos := PackedVector2Array()
var hz_amt := PackedFloat32Array()
var puffs_made := 0


static func texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(TILE * (VARIANTS + 1), TILE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var half := TILE * 0.5
	# Cotton wool (tabletop pass 5): each tile is a pulled tuft of 2 to 4 round lobes (a smooth sum of their soft discs),
	# its silhouette lumpy and soft all round (no hard alpha edge), lit from above and the left (a bright warm top, a
	# cool shaded underside under every lobe, a darker core), shaded from the field's own slope.
	var lobe_n := [3, 2, 4, 3]
	for v in VARIANTS:
		var lobes: Array = []   # [cx, cy, r]
		var n: int = lobe_n[v]
		var a0 := rng.randf() * TAU
		for b in n:
			var an := a0 + TAU * float(b) / float(n) + (rng.randf() - 0.5) * 0.7
			var rr := 0.34 + rng.randf() * 0.12
			var off := 0.2 + rng.randf() * 0.2
			var cx := cos(an) * off
			var cy := sin(an) * off * 0.8 + 0.06
			lobes.append([cx, cy, rr])
		var fld := PackedFloat32Array()
		fld.resize(TILE * TILE)
		for y in TILE:
			for x in TILE:
				var u := (x - half + 0.5) / half
				var w := (y - half + 0.5) / half
				var f := 0.0
				for lb in lobes:
					var d2: float = (Vector2(u - lb[0], w - lb[1]) / float(lb[2])).length_squared()
					var t := clampf(1.0 - d2, 0.0, 1.0)
					f += t * t
				f += noise.get_noise_2d(x + v * 100, y) * 0.16 * clampf(f * 3.0, 0.0, 1.0)
				fld[y * TILE + x] = f
		for y in TILE:
			for x in TILE:
				var f0 := fld[y * TILE + x]
				var xl := clampi(x - 2, 0, TILE - 1)
				var xh := clampi(x + 2, 0, TILE - 1)
				var yl := clampi(y - 2, 0, TILE - 1)
				var yh := clampi(y + 2, 0, TILE - 1)
				var gx := (fld[y * TILE + xh] - fld[y * TILE + xl]) * 1.6
				var gy := (fld[yh * TILE + x] - fld[yl * TILE + x]) * 1.6
				var nv := Vector3(-gx, -gy, 1.0).normalized()
				var lit := clampf(nv.dot(Vector3(-0.38, -0.62, 0.69).normalized()), 0.0, 1.0)
				# The underside of each lobe: the lower half of its disc is shaded, weighted by its share of the field.
				var under := 0.0
				var tot := 0.0
				var u2 := (x - half + 0.5) / half
				var w2 := (y - half + 0.5) / half
				for lb in lobes:
					var d3: float = (Vector2(u2 - lb[0], w2 - lb[1]) / float(lb[2])).length_squared()
					var q := clampf(1.0 - d3, 0.0, 1.0)
					q *= q
					under += q * smoothstep(-0.1, 0.9, (w2 - float(lb[1])) / float(lb[2]))
					tot += q
				under = under / maxf(tot, 0.001)
				var core := clampf((f0 - 0.7) * 0.5, 0.0, 0.3)
				var sh := clampf(0.5 + 0.5 * lit - 0.32 * under - core, 0.12, 1.0)
				var al := smoothstep(0.03, 0.5, f0)
				al = al * (0.8 + 0.2 * smoothstep(0.4, 1.0, f0))
				var c := Color(0.64 + 0.36 * sh, 0.67 + 0.33 * sh, 0.78 + 0.2 * sh, al)
				img.set_pixel(v * TILE + x, y, c)
	for y in TILE:
		for x in TILE:
			var r := Vector2((x - half + 0.5) / half, (y - half + 0.5) / half).length()
			var g := pow(clampf(1.0 - r, 0.0, 1.0), 2.0)
			img.set_pixel(VARIANTS * TILE + x, y, Color(1, 1, 1, g))
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)
	return _tex


## One cotton tuft at c (world px, radius r) in tint `col` (its alpha the strength), tile v: the fire smoke, a blast's cloud and
## the ruin dust of the overlay draw this instead of a flat circle.
static func tuft(ci: CanvasItem, c: Vector2, r: float, col: Color, v: int) -> void:
	ci.draw_texture_rect_region(texture(), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Rect2((v % VARIANTS) * TILE, 0, TILE, TILE), col)


## Ages everything dt seconds and drops what is spent.
func tick(dt: float, wind: Vector2) -> void:
	var k := 0
	while k < age.size():
		age[k] += dt
		if age[k] >= life[k]:
			_drop(k)
		else:
			k += 1
	var h := 0
	while h < hz_amt.size():
		hz_amt[h] -= dt * 0.012
		hz_pos[h] += wind * 0.25 * dt
		if hz_amt[h] <= 0.0:
			hz_amt.remove_at(h)
			hz_pos.remove_at(h)
		else:
			h += 1


func _drop(k: int) -> void:
	pos.remove_at(k)
	dir.remove_at(k)
	age.remove_at(k)
	size.remove_at(k)
	roll.remove_at(k)
	life.remove_at(k)
	kind.remove_at(k)


func clear() -> void:
	while not age.is_empty():
		_drop(0)
	hz_pos.clear()
	hz_amt.clear()


## One puff at p (world px), rolling along d to `roll_px`, radius scale
## sz px. k 1 is a low ground-dust puff.
func add(p: Vector2, d: Vector2, sz: float, roll_px: float, k: int = 0) -> void:
	while age.size() >= cap:
		_drop(0)
	# A little irregularity so a rank's puffs knit into one ragged bank.
	var j := puffs_made * 7919 % 13
	pos.append(p + Vector2(-d.y, d.x) * sz * (float(j % 5) - 2.0) * 0.18)
	dir.append(d)
	age.append(0.0)
	size.append(sz * (0.85 + 0.05 * float(j % 7)))
	roll.append(roll_px)
	life.append(LIFE if k == 0 else 3.8)
	kind.append(k)
	puffs_made += 1


## A gun engine's or ship's big shot: the main bank puff, a ring of smoke
## thrown out round the muzzle and a ground dust kick (land only).
func add_big(p: Vector2, d: Vector2, sz: float, roll_px: float, dust: bool, ring: int) -> void:
	add(p, d, sz, roll_px)
	for i in ring:
		var a := TAU * (float(i) + 0.3 * (puffs_made % 3)) / ring
		var rd := Vector2(cos(a), sin(a))
		add(p, rd, sz * 0.55, sz * 1.5)
	if dust:
		for i in 3:
			var rd2 := (d + Vector2(((puffs_made + i * 5) % 7 - 3) * 0.18, ((puffs_made + i * 3) % 5 - 2) * 0.15)).normalized()
			add(p + d * sz * 0.2, rd2, sz * 0.5, sz * 1.9, 1)


## Adds to the long-firefight haze near p (cell_px apart, radius grows
## with the build-up; capped).
func feed_haze(p: Vector2, cell_px: float, amt: float) -> void:
	if not haze_on:
		return
	var best := -1
	var bd := cell_px * cell_px
	for h in hz_pos.size():
		var dd := hz_pos[h].distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = h
	if best >= 0:
		hz_amt[best] = minf(HAZE_MAX, hz_amt[best] + amt)
		hz_pos[best] = hz_pos[best].lerp(p, 0.04)
	elif hz_pos.size() < HAZE_CAP:
		hz_pos.append(p)
		hz_amt.append(amt)


## Draws the banks, flashes and haze on canvas item ci. wind: px/s; vr: the
## visible rect (cull); haze_px: haze radius px; diorama: look.
func draw(ci: CanvasItem, wind: Vector2, vr: Rect2, haze_px: float, diorama: bool, upright := false) -> void:
	var tex := texture()
	var tint := Color(1.0, 1.0, 0.99) if diorama else Color(0.8, 0.82, 0.86)
	var amax := 0.8 if diorama else 0.78
	var dust := Color(0.78, 0.66, 0.48)
	var gl := Rect2(TILE * VARIANTS, 0, TILE, TILE)
	# The oblique view (tabletop pass 3 leftovers): the haze lies on the board (squashed with the ground); every puff stands up
	# as a billboard at its ground point (draw_set_transform_matrix(BoardView.up_xf): the offsets from the anchor stay
	# screen-aligned), lifted by its height, and the muzzle flash at the muzzle's height.
	var up := upright and BoardView.oblique   # (the land battle's overlay passes it; the sea view's smoke lies as before)
	if haze_on:
		for h in hz_pos.size():
			if vr.grow(haze_px).has_point(hz_pos[h]):
				var hc := Color(tint.r, tint.g, tint.b, 0.2 * minf(1.0, hz_amt[h]))
				ci.draw_texture_rect_region(tex, Rect2(hz_pos[h] - Vector2(haze_px, haze_px) * 0.8, Vector2(haze_px, haze_px) * 1.6), gl, hc)
	for k in age.size():
		var a := age[k]
		var f := a / life[k]
		var sz := size[k]
		var grow := 1.0 + 2.6 * sqrt(f)
		var rl := roll[k] * (1.0 - exp(-a * 1.7))
		var p := pos[k] + dir[k] * rl + wind * a * minf(1.0, 0.4 + a * 0.3)
		var g := p
		var dk := kind[k] == 1
		var r := sz * (0.8 + (grow - 1.0) * 0.8 if dk else 1.45 * grow)
		if up:
			p = g + Vector2(0.0, -(r * 0.3 if dk else sz * 0.7 + sz * 1.4 * sqrt(f)))
		elif not dk:
			p.y -= sz * 1.4 * sqrt(f)
		if not vr.has_point(g if up else p):
			continue
		var al := amax * pow(1.0 - f, 1.5) * minf(1.0, a * 9.0)
		if dk:
			al *= 0.55
		var c := dust if dk else tint
		c.a = al
		var vi := (k * 5 + int(pos[k].x * 0.13)) % VARIANTS
		if up:
			ci.draw_set_transform_matrix(BoardView.up_xf(g))
		ci.draw_texture_rect_region(tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), Rect2(vi * TILE, 0, TILE, TILE), c)
		if a < 0.09 and not dk:
			# The muzzle flash (a frame or two): a flame tongue along the
			# shot and a brief glow.
			var d := dir[k]
			var q := pos[k] - d * sz * 0.5
			if up:
				ci.draw_set_transform_matrix(BoardView.up_xf(q))
				d = Vector2(d.x, d.y * BoardView.OBLIQUE_COS).normalized()   # the shot's direction on the screen
				q += Vector2(0.0, -sz * 0.6)
			var w := Vector2(-d.y, d.x) * sz * 0.38
			var fl := 1.0 - a / 0.09
			ci.draw_texture_rect_region(tex, Rect2(q - Vector2(sz, sz) * 1.5, Vector2(sz, sz) * 3.0), gl, Color(1.0, 0.7, 0.3, 0.6 * fl))
			ci.draw_colored_polygon(PackedVector2Array([q - w, q + d * sz * 1.9, q + w]), Color(1.0, 0.55, 0.15, 0.85 * fl))
			ci.draw_colored_polygon(PackedVector2Array([q - w * 0.5, q + d * sz * 1.3, q + w * 0.5]), Color(1.0, 0.92, 0.5, 0.95 * fl))
	if up:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
