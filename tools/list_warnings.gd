extends SceneTree
## Prints the GDScript warnings that are on (level 1) by default, as
## "gdscript/warnings/<name>=<level>" lines for tools/check_scripts.sh.


func _init() -> void:
	for p in ProjectSettings.get_property_list():
		var key: String = p["name"]
		if key.begins_with("debug/gdscript/warnings/"):
			var v: Variant = ProjectSettings.get_setting(key)
			if v is int and v == 1:
				print(key.trim_prefix("debug/"), "=", v)
	quit(0)
