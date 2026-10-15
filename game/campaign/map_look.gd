extends RefCounted
## The shared "map look" textures and uniforms (map_look.gdshaderinc): a small gradient-map LUT and a tiling
## grain, made once in code and given to every material of the map-table style (terrain, town pieces, ships,
## landscape trees). Graphics Low: the LUT only (no band snapping, no grain). View only.

const Quality := preload("res://game/quality.gd")

static var _lut: ImageTexture = null
static var _grain: ImageTexture = null


## Lightness 0..1 -> a tint (about 1.0): cool brown shadows, neutral mids, warm cream lights.
static func lut() -> ImageTexture:
	if _lut == null:
		var img := Image.create(64, 1, false, Image.FORMAT_RGB8)
		var stops := [[0.0, Color(0.86, 0.80, 0.86)], [0.35, Color(0.97, 0.92, 0.88)], [0.6, Color(1.04, 1.0, 0.90)], [1.0, Color(1.10, 1.06, 0.92)]]
		for i in 64:
			var t := float(i) / 63.0
			var c: Color = stops[0][1]
			for k in range(stops.size() - 1):
				var a: float = stops[k][0]
				var b: float = stops[k + 1][0]
				if t >= a and t <= b:
					c = (stops[k][1] as Color).lerp(stops[k + 1][1], (t - a) / (b - a))
			# an image holds 0..1: store half the tint (the shader reads it back doubled below)
			img.set_pixel(i, 0, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5))
		_lut = ImageTexture.create_from_image(img)
	return _lut


static func grain() -> ImageTexture:
	if _grain == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.16
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.seed = 11
		var img: Image = n.get_seamless_image(128, 128)
		img.convert(Image.FORMAT_L8)
		_grain = ImageTexture.create_from_image(img)
	return _grain


## Give a material of the map-table style the shared textures and the quality's switches.
static func apply(m: ShaderMaterial) -> void:
	m.set_shader_parameter("look_lut", lut())
	m.set_shader_parameter("look_grain", grain())
	var low := Quality.is_low()
	m.set_shader_parameter("look_bands", 0.0 if low else 1.0)
	m.set_shader_parameter("look_grain_on", 0.0 if low else 1.0)
