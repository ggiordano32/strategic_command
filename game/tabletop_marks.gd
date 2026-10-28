extends RefCounted
## The tabletop battlefield's small marks (pass 1, docs/design/art_pipeline.md): a unit's standard (the overworld's
## pennant language: `draw_banner` in game/campaign/map_overlay.gd, copied here so the two screens keep one look without the
## battle view reaching into the campaign view's file) and the plastic state counters. Both draw in screen pixels about the
## CanvasItem's current transform origin: the caller sets `draw_set_transform(world_point, 0, Vector2.ONE / zoom)`.

const UIIcons := preload("res://game/ui_icons.gd")
const FactionEmblem := preload("res://game/faction_emblem.gd")
const GlyphBake := preload("res://game/glyph_bake.gd")
const COL_OUTLINE := Color(0.05, 0.05, 0.05, 0.95)
const COL_SELECTED := Color(1, 0.95, 0.4, 0.95)
const COL_PARCHMENT := Color(0.93, 0.87, 0.7)
## The standard at scale 1: pole foot at (-9, 8) from the origin, top at (-9, -21), pennant to x = +18, roundel radius 9.
const FOOT := Vector2(-9.0, 8.0)
const BOX := Rect2(-12.0, -27.0, 34.0, 47.0)   # its extent at scale 1 (the roundel and the selected lift included)
const BAKE_SM := 2.0   # the baked textures are drawn at this scale and shrunk
const BAKE_PAD := 4.0
const BAKE_SIZE := Vector2(34.0 * 2.0 + 8.0, 47.0 * 2.0 + 8.0)   # the baked texture's px: BOX x BAKE_SM + 2 x BAKE_PAD

static var _lines := {}


static func text_line(text: String, fs: int) -> TextLine:
	var key := "%d|%s" % [fs, text]
	var tl: TextLine = _lines.get(key)
	if tl == null:
		if _lines.size() > 300:
			_lines.clear()
		tl = TextLine.new()
		tl.add_string(text, ThemeDB.fallback_font, fs)
		_lines[key] = tl
	return tl


## The standard about origin `o` (screen px) at scale sm: pole, swallow-tailed pennant in `col` with the crest where the
## faction has one, a parchment roundel with `text` at the pole's foot. sel: the gold rim and a small lift; own: the white
## rim (the overworld's "human" armies).
static func draw_standard(ci: CanvasItem, o: Vector2, sm: float, col: Color, sel: bool, own: bool, text: String, emblem: String, u := 1.0) -> void:
	var rim := COL_SELECTED if sel else Color(1, 1, 1)
	if sel:
		o += Vector2(0, -3.0 * sm)
	var pole_x := o.x - 9.0 * sm
	var top := o.y - 17.0 * sm
	ci.draw_line(Vector2(pole_x, top - 4.0 * sm), Vector2(pole_x, o.y + 8.0 * sm), COL_OUTLINE, 3.2 * u)
	ci.draw_line(Vector2(pole_x, top - 3.0 * sm), Vector2(pole_x, o.y + 8.0 * sm), Color(0.55, 0.42, 0.26), 1.5 * u)
	ci.draw_circle(Vector2(pole_x, top - 4.0 * sm), 2.0 * u, COL_OUTLINE)
	ci.draw_circle(Vector2(pole_x, top - 4.0 * sm), 1.0 * u, Color(0.85, 0.7, 0.35))
	var pw := 27.0 * sm
	var pts := PackedVector2Array([Vector2(pole_x, top), Vector2(pole_x + pw, top), Vector2(pole_x + pw - 6.0 * sm, top + 8.0 * sm),
		Vector2(pole_x + pw, top + 16.0 * sm), Vector2(pole_x, top + 16.0 * sm)])
	ci.draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, COL_OUTLINE, (3.5 if (own or sel) else 1.8) * u)
	if own or sel:
		ci.draw_polyline(outline, rim, 1.8 * u)
	if emblem != "" and FactionEmblem.has(emblem):
		var es := 13.0 * sm
		FactionEmblem.draw(ci, emblem, Rect2(Vector2(pole_x + 3.0 * sm, top + 8.0 * sm - es * 0.5), Vector2(es, es)))
	var rc := Vector2(pole_x + 4.0 * sm, o.y + 6.0 * sm)
	var rr := 9.0 * sm
	ci.draw_circle(rc, rr + 1.6 * u, COL_OUTLINE)
	if own or sel:
		ci.draw_arc(rc, rr + 1.2 * u, 0, TAU, 24, rim, 1.4 * u)
	ci.draw_circle(rc, rr, COL_PARCHMENT)
	var afs := int(round(14 * maxf(sm, 0.75)))
	var tl := text_line(text, afs)
	if tl.get_size().x > rr * 1.75:
		afs = maxi(int(afs * rr * 1.75 / tl.get_size().x), 9)
		tl = text_line(text, afs)
	var base := rc + Vector2(-tl.get_size().x * 0.5, afs * 0.34)
	tl.draw(ci.get_canvas_item(), base - Vector2(0.0, tl.get_line_ascent()), Color(0.1, 0.06, 0.03))


## A plastic counter of radius r at c: a dark rim, the body colour with a lit top, a small shadow to the lower right and
## the glyph (a UIIcons name, or "shaken" / "disordered" drawn here) on it. A glyph ending "!" is struck through (an ability on
## Hold); ending "*" is a gold target (Use now).
static func draw_token(ci: CanvasItem, c: Vector2, r: float, glyph: String, body: Color, direct := false) -> void:
	var gname := glyph
	var cross := false
	var gold := false
	if gname.ends_with("!"):
		gname = gname.trim_suffix("!")
		cross = true
	elif gname.ends_with("*"):
		gname = gname.trim_suffix("*")
		gold = true
	ci.draw_circle(c + Vector2(0.9, 1.3), r + 0.6, Color(0, 0, 0, 0.35))
	ci.draw_circle(c, r + 0.8, COL_OUTLINE)
	ci.draw_circle(c, r, body)
	ci.draw_arc(c, r * 0.72, PI * 1.05, PI * 1.75, 8, Color(1, 1, 1, 0.38), maxf(r * 0.2, 1.0), true)
	var gcol := Color(0.98, 0.97, 0.92)
	if gold:
		gcol = Color(1.0, 0.86, 0.35)
	var rect := Rect2(c - Vector2(r, r) * 0.78, Vector2(r, r) * 1.56)
	if gname == "shaken":
		var d := r * 0.5
		ci.draw_polyline(PackedVector2Array([c + Vector2(-d, -d * 0.7), c + Vector2(-d * 0.3, d * 0.7), c + Vector2(d * 0.3, -d * 0.7),
			c + Vector2(d, d * 0.7)]), Color(0.12, 0.08, 0.02), maxf(r * 0.3, 1.2), true)
	elif gname == "disordered":
		for p in [Vector2(-0.45, -0.3), Vector2(0.4, -0.45), Vector2(0.0, 0.1), Vector2(-0.3, 0.5), Vector2(0.5, 0.4)]:
			ci.draw_circle(c + p * r, maxf(r * 0.2, 0.8), gcol)
	elif UIIcons.has(gname):
		var gt: Texture2D = null if direct else GlyphBake.get_tex(UIIcons.resolve(gname))
		if direct:
			UIIcons.draw_icon(ci, gname, rect, gcol)
		elif gt != null:
			ci.draw_texture_rect(gt, rect, false, gcol)
		else:
			ci.draw_circle(c, r * 0.35, gcol)
	if cross:
		ci.draw_line(c + Vector2(-0.7, 0.7) * r, c + Vector2(0.7, -0.7) * r, Color(1.0, 0.45, 0.4), maxf(r * 0.28, 1.2), true)


## The baked standard (a texture made once per colour, number, rim and crest; null while it bakes and in headless runs): the
## same picture as draw_standard at scale BAKE_SM, so one draw call stands for about thirty.
static func standard_tex(col: Color, sel: bool, own: bool, text: String, emblem: String) -> Texture2D:
	var key := "std:%s|%s|%d|%d|%s" % [col.to_html(false), text, 1 if sel else 0, 1 if own else 0, emblem]
	var px := Vector2i(BAKE_SIZE)
	return GlyphBake.bake(key, px, func(c: Control) -> void:
		draw_standard(c, -BOX.position * BAKE_SM + Vector2(BAKE_PAD, BAKE_PAD), BAKE_SM, col, sel, own, text, emblem, BAKE_SM))


## The plain pole and pennant drawn while a standard bakes (o: its origin, sm: its scale, both in world px).
static func draw_standard_tex(ci: CanvasItem, _tex: Texture2D, o: Vector2, sm: float, col: Color) -> void:
	var pole_x := o.x - 9.0 * sm
	var top := o.y - 17.0 * sm
	ci.draw_line(Vector2(pole_x, top - 4.0 * sm), Vector2(pole_x, o.y + 8.0 * sm), Color(0.55, 0.42, 0.26), 1.5 * sm)
	ci.draw_rect(Rect2(pole_x, top, 27.0 * sm, 16.0 * sm), col)


## A token baked (null while it bakes): the counter of glyph / body colour at radius TOK_R in a TOK_PX square.
const TOK_PX := 48
const TOK_R := 20.0


static func token_tex(glyph: String, body: Color) -> Texture2D:
	return GlyphBake.bake("tok:%s|%s" % [glyph, body.to_html(false)], Vector2i(TOK_PX, TOK_PX), func(c: Control) -> void:
		draw_token(c, Vector2(TOK_PX, TOK_PX) * 0.5, TOK_R, glyph, body, true))
