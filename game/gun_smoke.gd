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

const LIFE := 7.0           # a bank puff's life, s (the flash and smoke pass, 2026-11-06: was 10; it grows and thins over about 6 s)
const FLASH_S := 0.2        # a gun engine's or ship's flash, s (a man's: Overlay.FLASH_MUSKET_S / FLASH_PISTOL_S)
const TILE := 64
const VARIANTS := 4          # cloud tiles, then the haze's glow tile, then the flash tile (hot core and halo, drawn additively)
const FLASH_TILE := 5
const TILES := 6
const STRIDE := 8            # floats a smoke sprite takes in `buf` (collect)
const HAZE_CAP := 14
const HAZE_MAX := 1.0

static var _tex: ImageTexture

var pos := PackedVector2Array()
var dir := PackedVector2Array()      # roll direction (unit)
var age := PackedFloat32Array()
var size := PackedFloat32Array()     # radius scale in px
var roll := PackedFloat32Array()     # distance it rolls out, px
var life := PackedFloat32Array()
var kind := PackedByteArray()        # 0 smoke (a cluster of three lobes), 1 dust kick, 2 a ring puff (one sprite)
var sd := PackedInt32Array()         # the puff's own shape seed (its lobes' places and tiles)
var buf := PackedFloat32Array()      # the sprites of the last collect
var fl := PackedByteArray()          # 1: this puff carries the muzzle flash (a gun engine's or a ship's shot; a man's flash is the overlay's, per shot)
var cap := 280
var haze_on := true
var hz_pos := PackedVector2Array()
var hz_amt := PackedFloat32Array()
var puffs_made := 0
var gh := PackedFloat32Array()       # the ground height under each puff, metres (the 3D view's collect; -1e9: not read yet)
var _frame := 0


static func texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(TILE * TILES, TILE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var half := TILE * 0.5
	# Cotton (the flash and smoke pass, 2026-11-06): each tile is a pulled tuft of 3 to 5 round lobes with BODY: every lobe is a
	# little sphere (its own height, the lobes summed), lit from above and the left with a wrapped Lambert, a cool shaded underside,
	# the thin rim brighter (light passing through the fibres) and a fibrous noise on the edge, so the silhouette is lumpy and soft.
	var lobe_n := [3, 4, 3, 5]
	for v in VARIANTS:
		var lobes: Array = []   # [cx, cy, r]
		var n: int = lobe_n[v]
		var a0 := rng.randf() * TAU
		for b in n:
			var an := a0 + TAU * float(b) / float(n) + (rng.randf() - 0.5) * 0.7
			var rr := 0.30 + rng.randf() * 0.12
			var off := 0.16 + rng.randf() * 0.24
			lobes.append([cos(an) * off, sin(an) * off * 0.85 + 0.04, rr])
		var fld := PackedFloat32Array()
		var hgt := PackedFloat32Array()
		fld.resize(TILE * TILE)
		hgt.resize(TILE * TILE)
		for y in TILE:
			for x in TILE:
				var u := (x - half + 0.5) / half
				var w := (y - half + 0.5) / half
				var f := 0.0
				var hh := 0.0
				for lb in lobes:
					var d2: float = (Vector2(u - lb[0], w - lb[1]) / float(lb[2])).length_squared()
					var t := clampf(1.0 - d2, 0.0, 1.0)
					f += t * t
					hh += sqrt(t) * float(lb[2])
				var fib := noise.get_noise_2d(x + v * 100, y) * 0.5 + noise.get_noise_2d(x * 2.3 + v * 57, y * 2.3 + 31) * 0.25
				f += fib * 0.2 * clampf(f * 3.0, 0.0, 1.0)
				fld[y * TILE + x] = f
				hgt[y * TILE + x] = hh
		var ldir := Vector3(-0.38, -0.62, 0.69).normalized()
		for y in TILE:
			for x in TILE:
				var f0 := fld[y * TILE + x]
				var xl := clampi(x - 2, 0, TILE - 1)
				var xh := clampi(x + 2, 0, TILE - 1)
				var yl := clampi(y - 2, 0, TILE - 1)
				var yh := clampi(y + 2, 0, TILE - 1)
				var gx := (hgt[y * TILE + xh] - hgt[y * TILE + xl]) * 2.4
				var gy := (hgt[yh * TILE + x] - hgt[yl * TILE + x]) * 2.4
				var nv := Vector3(-gx, -gy, 1.0).normalized()
				var lit := clampf((nv.dot(ldir) + 0.35) / 1.35, 0.0, 1.0)
				var w2 := (y - half + 0.5) / half
				var edge := 1.0 - smoothstep(0.08, 0.75, f0)
				var sh := clampf(pow(lit, 0.9) - 0.16 * smoothstep(0.0, 1.0, w2) + 0.12 * edge, 0.0, 1.0)
				var cool := Color(0.54, 0.58, 0.70)
				var warm := Color(1.0, 0.99, 0.96)
				var c := cool.lerp(warm, sh)
				var al := smoothstep(0.03, 0.42, f0)
				al = al * (0.82 + 0.18 * smoothstep(0.4, 1.0, f0))
				c.a = al
				img.set_pixel(v * TILE + x, y, c)
	for y in TILE:
		for x in TILE:
			var r := Vector2((x - half + 0.5) / half, (y - half + 0.5) / half).length()
			var g := pow(clampf(1.0 - r, 0.0, 1.0), 2.0)
			img.set_pixel(VARIANTS * TILE + x, y, Color(1, 1, 1, g))
			# The flash (drawn additively): a white-hot core, yellow, orange, then a dim red halo, the edge broken a little.
			var rf := r * (1.0 + 0.16 * noise.get_noise_2d(x * 3.1 + 500, y * 3.1))
			var fa := pow(clampf(1.0 - rf, 0.0, 1.0), 2.1)
			var fc := Color(1.0, 0.98, 0.9).lerp(Color(1.0, 0.82, 0.42), smoothstep(0.04, 0.28, rf)).lerp(Color(1.0, 0.45, 0.12), smoothstep(0.22, 0.65, rf))
			fc.a = fa
			img.set_pixel(FLASH_TILE * TILE + x, y, fc)
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
	fl.remove_at(k)
	sd.remove_at(k)
	gh.remove_at(k)


func clear() -> void:
	while not age.is_empty():
		_drop(0)
	hz_pos.clear()
	hz_amt.clear()


## One puff at p (world px), rolling along d to `roll_px`, radius scale
## sz px. k 1 is a low ground-dust puff.
func add(p: Vector2, d: Vector2, sz: float, roll_px: float, k: int = 0, with_flash := true) -> void:
	while age.size() >= cap:
		_drop(0)
	# A little irregularity so a rank's puffs knit into one ragged bank.
	var j := puffs_made * 7919 % 13
	pos.append(p + Vector2(-d.y, d.x) * sz * (float(j % 5) - 2.0) * 0.18)
	dir.append(d)
	age.append(0.0)
	size.append(sz * (0.85 + 0.05 * float(j % 7)))
	roll.append(roll_px)
	life.append(LIFE if k != 1 else 3.8)
	kind.append(k)
	fl.append(1 if with_flash else 0)
	gh.append(-1e9)
	sd.append((puffs_made * 2654435761 + int(p.x * 7.0) + int(p.y * 13.0)) & 0x7fffffff)
	puffs_made += 1


## A gun engine's or ship's big shot: the main bank puff, a ring of smoke
## thrown out round the muzzle and a ground dust kick (land only).
func add_big(p: Vector2, d: Vector2, sz: float, roll_px: float, dust: bool, ring: int) -> void:
	add(p, d, sz, roll_px)
	for i in ring:
		var a := TAU * (float(i) + 0.3 * (puffs_made % 3)) / ring
		var rd := Vector2(cos(a), sin(a))
		add(p, rd, sz * 0.55, sz * 1.5, 2, false)   # (kind 2: a ring puff, one sprite, as before)
	if dust:
		for i in 3:
			var rd2 := (d + Vector2(((puffs_made + i * 5) % 7 - 3) * 0.18, ((puffs_made + i * 3) % 5 - 2) * 0.15)).normalized()
			add(p + d * sz * 0.2, rd2, sz * 0.5, sz * 1.9, 1, false)


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


## The smoke sprites of every live puff, into `buf` (STRIDE floats each: the ground point x, y px; the height px; the offset x, y px in
## the screen's plane; the radius px; the alpha; the code, tile + 4 for dust); returns their count. A bank puff is a CLUSTER of three
## soft lobes that spread apart as it ages (it billows), each its own tile and size; ring puffs and dust kicks are one sprite as before.
## `up`: heights as the oblique and 3D views stand them (the top view only lifts a puff by its rise). Cull: vr (the ground point's
## rect, or the lifted point in the top view). Both the overlay's sprites and the 3D view's billboards draw from this.
func collect(wind: Vector2, vr: Rect2, up: bool, ppm := 0.0) -> int:
	var need := age.size() * 3 * STRIDE
	if buf.size() < need:
		buf.resize(need)
	var n := 0
	_frame += 1
	var wx := wind.x
	var wy := wind.y
	for k in age.size():
		var a := age[k]
		var f := a / life[k]
		var sz := size[k]
		var sf := sqrt(f)
		var kd := kind[k]
		var dk := kd == 1
		var rl := roll[k] * (1.0 - exp(-a * 1.7))
		var wa := minf(1.0, 0.4 + a * 0.3) * a
		var gx := pos[k].x + dir[k].x * rl + wx * wa
		var gy := pos[k].y + dir[k].y * rl + wy * wa
		var r := sz * (0.8 + 2.6 * sf * 0.8 if dk else 1.45 * (1.0 + 2.6 * sf))
		var h := 0.0
		if up:
			h = r * 0.3 if dk else sz * 0.7 + sz * 1.4 * sf
		elif not dk:
			h = sz * 1.4 * sf
		if up:
			if not vr.has_point(Vector2(gx, gy)):
				continue
		elif not vr.has_point(Vector2(gx, gy - h)):
			continue
		if ppm > 0.0:
			# The 3D view: the ground's height under the puff (metres, seen again every 6th frame: it drifts slowly) in px.
			if (_frame + k) % 6 == 0 or gh[k] < -1e8:
				gh[k] = BoardView.ground_m(Vector2(gx, gy))
			h += gh[k] * ppm
		var one := 1.0 - f
		var al := 0.8 * one * sqrt(one) * minf(1.0, a * 9.0)
		if dk:
			al *= 0.55
		var sdv := sd[k]
		var vi := sdv % VARIANTS
		if kd != 0:
			var o := n * STRIDE
			buf[o] = gx
			buf[o + 1] = gy
			buf[o + 2] = h
			buf[o + 3] = 0.0
			buf[o + 4] = 0.0
			buf[o + 5] = r
			buf[o + 6] = al
			buf[o + 7] = float(vi + (4 if dk else 0))
			n += 1
			continue
		var a0 := float(sdv % 628) * 0.01
		var spread := r * 0.34 * (0.45 + 0.55 * sf)
		var subs := 3 if f < 0.55 else 2   # (a thinning puff is two lobes: fewer draws, the bank still reads)
		for j in subs:
			var an := a0 + TAU * float(j) / 3.0 + a * 0.12 * (1.0 if j % 2 == 0 else -1.0)
			var o := n * STRIDE
			buf[o] = gx
			buf[o + 1] = gy
			buf[o + 2] = h + float(j) * r * 0.05
			buf[o + 3] = cos(an) * spread
			buf[o + 4] = sin(an) * spread * 0.75
			buf[o + 5] = r * (0.84 - 0.12 * float(j))
			buf[o + 6] = al * (0.88 - 0.06 * float(j))
			buf[o + 7] = float((vi + j * 3 + 1) % VARIANTS)
			n += 1
	return n


## True while a gun engine's or ship's flash still shows.
func has_engine_flash() -> bool:
	for k in age.size():
		if age[k] < FLASH_S and fl[k] != 0 and kind[k] == 0:
			return true
	return false


## The gun engines' and ships' flashes still showing (a puff that carries one, younger than FLASH_S), six floats each: the muzzle's x, y
## px, the direction, the size px, the strength 0 .. 1.
func engine_flashes() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in age.size():
		if age[k] < FLASH_S and fl[k] != 0 and kind[k] == 0:
			var q := pos[k] - dir[k] * size[k] * 0.5
			var fa := 1.0 - age[k] / FLASH_S
			out.append_array(PackedFloat32Array([q.x, q.y, dir[k].x, dir[k].y, size[k], fa]))
	return out


## Draws the banks and haze on canvas item ci (and the gun engines' and ships' flashes on `add_ci`, an additive layer, or on ci itself when
## there is none). wind: px/s; vr: the visible rect (cull); haze_px: haze radius px; diorama: look.
func draw(ci: CanvasItem, wind: Vector2, vr: Rect2, haze_px: float, diorama: bool, upright := false, add_ci: CanvasItem = null) -> void:
	var tex := texture()
	var tint := Color(1.0, 1.0, 0.99) if diorama else Color(0.8, 0.82, 0.86)
	var dust := Color(0.78, 0.66, 0.48)
	var gl := Rect2(TILE * VARIANTS, 0, TILE, TILE)
	# The oblique view (tabletop pass 3 leftovers): the haze lies on the board (squashed with the ground); every puff stands up
	# as a billboard at its ground point (draw_set_transform_matrix(BoardView.up_xf): the offsets from the anchor stay
	# screen-aligned), lifted by its height.
	var up := upright and BoardView.oblique   # (the land battle's overlay passes it; the sea view's smoke lies as before)
	if haze_on:
		for h in hz_pos.size():
			if vr.grow(haze_px).has_point(hz_pos[h]):
				var hc := Color(tint.r, tint.g, tint.b, 0.2 * minf(1.0, hz_amt[h]))
				ci.draw_texture_rect_region(tex, Rect2(hz_pos[h] - Vector2(haze_px, haze_px) * 0.8, Vector2(haze_px, haze_px) * 1.6), gl, hc)
	var n := collect(wind, vr, up)
	var last := Vector2(1e30, 1e30)
	for i in n:
		var o := i * STRIDE
		var g := Vector2(buf[o], buf[o + 1])
		var code := int(buf[o + 7])
		var r := buf[o + 5]
		var c := dust if code >= 4 else tint
		c.a = buf[o + 6]
		if up and g != last:
			ci.draw_set_transform_matrix(BoardView.up_xf(g))
			last = g
		var p := g + Vector2(buf[o + 3], buf[o + 4] - buf[o + 2])
		ci.draw_texture_rect_region(tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), Rect2((code % 4) * TILE, 0, TILE, TILE), c)
	if up:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if add_ci == null:
		draw_engine_flashes(ci, vr, up)


## The engines' flashes on ci (an additive layer, or the plain one).
func draw_engine_flashes(ci: CanvasItem, vr: Rect2, up: bool) -> void:
	var fe := engine_flashes()
	for i in fe.size() / 6:
		var q := Vector2(fe[i * 6], fe[i * 6 + 1])
		if vr.has_point(q):
			flash(ci, q, Vector2(fe[i * 6 + 2], fe[i * 6 + 3]), fe[i * 6 + 4], fe[i * 6 + 5], up, -1.0, true)
	if up:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## One muzzle flash at q (world px): a FLASH of light, not a sprite: a wide soft orange halo (about 6 times sz in radius for a man's
## shot, so a few metres on the ground and the men round him), a yellow glow, a white-hot core and a short flame spike along d, strength
## fa 0 .. 1 (it falls off as fa squared: a snap). Meant for an ADDITIVE layer (the overlay's, GunSmoke's flash tile carries the colour
## in its alpha falloff); on a plain layer it shows as a bright blob. `big`: a gun engine's or a ship's, a smaller halo for its size
## (sz is its puff's). In the oblique view (up) it stands at the muzzle's height with its spike along the shot's screen direction.
static func flash(ci: CanvasItem, q: Vector2, d: Vector2, sz: float, fa: float, up: bool, lift := -1.0, big := false) -> void:
	var tex := texture()
	var rect := Rect2(TILE * FLASH_TILE, 0, TILE, TILE)
	if up:
		ci.draw_set_transform_matrix(BoardView.up_xf(q))
		d = Vector2(d.x, d.y * BoardView.OBLIQUE_COS).normalized()
		q += Vector2(0.0, -(sz * 0.6 if lift < 0.0 else lift))
	var k := fa * fa
	var halo := sz * (1.4 if big else 6.0)
	ci.draw_texture_rect_region(tex, Rect2(q - Vector2(halo, halo), Vector2(halo, halo) * 2.0), rect, Color(1.0, 0.6, 0.25, 0.26 * k))
	ci.draw_texture_rect_region(tex, Rect2(q - Vector2(halo, halo) * 0.42, Vector2(halo, halo) * 0.84), rect, Color(1.0, 0.85, 0.55, 0.5 * k))
	ci.draw_texture_rect_region(tex, Rect2(q - Vector2(halo, halo) * 0.15, Vector2(halo, halo) * 0.3), rect, Color(1.0, 1.0, 0.95, 1.0 * k))
	var w := Vector2(-d.y, d.x) * sz * 0.3
	ci.draw_colored_polygon(PackedVector2Array([q - w, q + d * sz * 2.2, q + w]), Color(1.0, 0.7, 0.3, 0.6 * k))
