extends RefCounted
## The view's pack switch: the content pack (CData: tables, grid) and the map
## geometry / relief (Geo, map_geo.gd) change together. Call before any
## MapView / Landscape is built or prepared for a campaign. View only.

const CData := preload("res://campaign/cdata.gd")
const Geo := preload("res://game/campaign/map_geo.gd")

const SETTINGS := "user://settings.cfg"
## Setting names, in menu order: [pack key, "Setting" button text].
const CHOICES: Array = [["rome", "Rome, 280 BC"], ["west", "Caribbean, 1650"]]
## The main menu's subtitle per pack.
const SUBTITLES := {"rome": "The western Mediterranean, 280 BC", "west": "The Caribbean and the Gulf, 1650"}


static func use_pack(key: String) -> void:
	if not CData.has_pack(key):
		key = "rome"
	CData.use_pack(key)
	Geo.use_pack(key)


static func use_state(st: Dictionary) -> void:
	use_pack(str(st.get("pack", "rome")))


## The packs this build has, in CHOICES order.
static func available() -> Array:
	var out: Array = []
	for c in CHOICES:
		if CData.has_pack(str(c[0])):
			out.append(c)
	return out


static func sea_name(key: String) -> String:
	return {"rome": "The Mediterranean", "west": "The Caribbean"}.get(key, "The world")


static func subtitle(key: String) -> String:
	return str(SUBTITLES.get(key, ""))


## The last setting chosen on the new-campaign screen (a convenience only).
static func load_pref() -> String:
	var k := "rome"
	if DisplayServer.get_name() == "headless":
		return k  # tests and tools always start from Rome
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		k = str(cf.get_value("campaign", "pack", "rome"))
	return k if CData.has_pack(k) else "rome"


static func save_pref(key: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("campaign", "pack", key)
	cf.save(SETTINGS)
