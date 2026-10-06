extends RefCounted
## Ground palettes (view only): the battle map's ground shader and trees and
## the campaign map's region tint use the same colours, indexed like
## MapGen.PAL_* (plain, arid, dry, green, rocky). Regions pick theirs in
## campaign/cdata.gd ("ground").

const MapGen := preload("res://sim/mapgen.gd")

## Per palette: base ground, low ground tint, high ground tint, contour line
## colour (rgb + alpha), and two or three tree shades (canopy colours).
const PALETTES := [
	{"name": "Plain", "base": Color(0.27, 0.38, 0.20), "low": Color(0.20, 0.33, 0.21),
		"high": Color(0.37, 0.42, 0.23), "line": Color(0.09, 0.12, 0.05, 0.34),
		"trees": [Color(0.15, 0.30, 0.13), Color(0.19, 0.35, 0.15), Color(0.12, 0.25, 0.12)]},
	{"name": "Arid", "base": Color(0.60, 0.50, 0.32), "low": Color(0.52, 0.43, 0.29),
		"high": Color(0.72, 0.62, 0.42), "line": Color(0.25, 0.17, 0.08, 0.36),
		"trees": [Color(0.36, 0.40, 0.20), Color(0.44, 0.44, 0.25), Color(0.30, 0.34, 0.18)]},
	{"name": "Dry", "base": Color(0.50, 0.48, 0.31), "low": Color(0.41, 0.42, 0.27),
		"high": Color(0.62, 0.58, 0.40), "line": Color(0.20, 0.17, 0.08, 0.34),
		"trees": [Color(0.30, 0.36, 0.19), Color(0.37, 0.41, 0.23), Color(0.20, 0.28, 0.15)]},
	{"name": "Green", "base": Color(0.30, 0.45, 0.22), "low": Color(0.23, 0.39, 0.21),
		"high": Color(0.42, 0.50, 0.27), "line": Color(0.08, 0.13, 0.05, 0.34),
		"trees": [Color(0.15, 0.31, 0.13), Color(0.20, 0.37, 0.15), Color(0.11, 0.24, 0.13)]},
	{"name": "Rocky", "base": Color(0.45, 0.43, 0.36), "low": Color(0.37, 0.39, 0.31),
		"high": Color(0.56, 0.54, 0.47), "line": Color(0.15, 0.14, 0.10, 0.36),
		"trees": [Color(0.15, 0.27, 0.17), Color(0.20, 0.32, 0.19), Color(0.12, 0.22, 0.14)]},
]


static func get_palette(i: int) -> Dictionary:
	return PALETTES[clampi(i, 0, PALETTES.size() - 1)]


## Campaign map: a region's land colour for its palette.
static func land_color(i: int) -> Color:
	return get_palette(i)["base"]
