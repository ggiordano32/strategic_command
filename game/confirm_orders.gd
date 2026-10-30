extends RefCounted
## The "Confirm orders" setting (view only): user://settings.cfg [ui] confirm_orders = auto | on | off
## ("--confirm-orders=auto|on|off" overrides it; tests set `force`). On: with units selected a tap on the ground or a
## line drag places a ghost of the selection (the placement tool, game/battle.gd "placement tool") and the order is
## sent only by Go. Auto: on while the last input was a touch, off for the mouse. Nothing here reaches the sim.

const SETTINGS := "user://settings.cfg"
const VALUES := ["auto", "on", "off"]

static var force := ""   # tests: "auto" / "on" / "off" (overrides the setting and the command line)


static func pref() -> String:
	if VALUES.has(force):
		return force
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--confirm-orders="):
			var v := str(a).get_slice("=", 1).to_lower()
			if VALUES.has(v):
				return v
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and (q as String).contains("confirm-orders=on"):
			return "on"
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return "auto"
	var s := str(cf.get_value("ui", "confirm_orders", "auto"))
	return s if VALUES.has(s) else "auto"


static func save_pref(v: String) -> void:
	if not VALUES.has(v):
		return
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "confirm_orders", v)
	cf.save(SETTINGS)


## Whether orders are confirmed now; `last_touch`: the last input on the field was a finger.
static func active(last_touch: bool) -> bool:
	var p := pref()
	return p == "on" or (p == "auto" and last_touch)
