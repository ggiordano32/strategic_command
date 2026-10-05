extends SceneTree
## Writes the install icons (192 and 512 px PNG, drawn here: no assets) and
## manifest.json into build/web. Run by tools/export_web.sh after the export.
## The manifest makes the game installable (Android "Install app", standalone
## window, landscape). No service worker: nothing is cached for offline use,
## so a playtest never runs a stale build.

const OUT := "res://build/web/"


func _init() -> void:
	for size in [192, 512]:
		_icon(size).save_png(OUT + "icon-%d.png" % size)
	var manifest := {
		"name": "Strategic Command", "short_name": "Strategic", "start_url": "./index.html",
		"scope": "./", "display": "standalone", "orientation": "landscape",
		"background_color": "#1f261f", "theme_color": "#1f261f",
		"icons": [
			{"src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable"},
			{"src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"},
		],
	}
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("wrote icons and manifest.json")
	quit(0)


## Dark green field, a red disc (Rome's colour) with a gold rim, and a white
## sword: readable at launcher size, safe inside the maskable circle.
func _icon(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color("1f261f"))
	var c := Vector2(n, n) * 0.5
	var r := n * 0.34
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r:
				img.set_pixel(x, y, Color("c8402f"))
			elif d <= r + n * 0.025:
				img.set_pixel(x, y, Color("e0b02a"))
	var w := maxi(int(n * 0.05), 2)
	img.fill_rect(Rect2i(int(c.x) - w / 2, int(n * 0.26), w, int(n * 0.42)), Color.WHITE)
	img.fill_rect(Rect2i(int(c.x - n * 0.11), int(n * 0.6), int(n * 0.22), w), Color.WHITE)
	img.fill_rect(Rect2i(int(c.x) - w, int(n * 0.6) + w, w * 2, int(n * 0.1)), Color("e0b02a"))
	return img
