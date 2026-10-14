extends RefCounted
## The battle map's look (2026-10-14), a view preference in user://settings.cfg [video] battle_look =
## diorama | painterly ("--battle-look=diorama|painterly" overrides it for the session).
## Diorama (the default): the tabletop miniatures look, rim light, outlines, saturated colour, a sculpted
## board edge round the battlefield with the table beyond, light depth of field at the screen edges (off on
## Graphics Low). Painterly: the grounded, softer look. The kit shader, trees and the terrain read the values
## here; nothing touches the sim.

const SETTINGS := "user://settings.cfg"

const DIORAMA := {"amb": 0.50, "key": 0.88, "rim": 0.22, "outline": 0.55, "sat": 1.22, "contrast": 1.12}
const PAINTERLY := {"amb": 0.66, "key": 0.55, "rim": 0.05, "outline": 0.24, "sat": 0.86, "contrast": 1.04}


static func pref() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--battle-look="):
			var v := str(a).get_slice("=", 1).to_lower()
			if v == "diorama" or v == "painterly":
				return v
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return "diorama"
	var v2 := str(cf.get_value("video", "battle_look", "diorama"))
	return v2 if v2 == "painterly" else "diorama"


static func save_pref(v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("video", "battle_look", v)
	cf.save(SETTINGS)


static func is_diorama() -> bool:
	return pref() == "diorama"


static func params() -> Dictionary:
	return DIORAMA if is_diorama() else PAINTERLY


## Sets the look uniforms on a ShaderMaterial that declares them.
static func apply(mat: ShaderMaterial) -> void:
	var p := params()
	for k in p:
		mat.set_shader_parameter(k, p[k])
