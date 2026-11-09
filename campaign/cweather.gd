extends RefCounted
## The weather of a campaign battle (2026-11-09; docs/design/campaign_rules.md "Weather on the campaign (as built,
## 2026-11-09)"). Decided by the rules when a pending battle is created (CRules, CFleet): from the turn's season, the
## content pack and the state's RNG (one CState.rand draw), stored on the pending battle as "weather" (a string in
## game/weather.gd's token form, read by sim/wx.gd as the fought battle's scenario "weather"; a pending battle without
## the key, from an older save, is a clear day). The formula's auto-resolve has no weather term.
##
## The mapping (ported from the view's former Weather.for_campaign, 2026-11-06): two turns a year, the even turns
## summer, the odd winter (campaign/cstorm.gd season).
## Rome: summer clear (a quarter overcast); winter snow, fog, overcast, or snow lying with no snowfall (half the turns).
## The West (no snow): the summer turns the wet season (rain, drizzle, a storm, now and then the heavy one, a wet field
## under an overcast sky); the winter turns the dry (clear, a quarter overcast).

const CState := preload("res://campaign/cstate.gd")


## The weather string for a battle of state st's turn (draws once from the state's RNG).
static func pick(st: Dictionary) -> String:
	return for_turn(int(st["turn"]), str(st.get("pack", "rome")), CState.rand(st, 100))


## The mapping: turn, pack and a roll h in 0..99.
static func for_turn(turn: int, pack: String, h: int) -> String:
	var summer := turn % 2 == 0
	if pack == "west":
		if summer:
			if h < 12:
				return "tempest,summer" if h < 5 else "storm,summer"
			if h < 40:
				return "rain,summer"
			if h < 58:
				return "overcast,summer,wet"
			return ("drizzle" if h < 80 else "overcast") + ",summer"
		return ("overcast" if h < 25 else "clear") + ",spring"
	if summer:
		return ("overcast" if h < 25 else "clear") + ",summer"
	if h < 25:
		return "snow,winter"
	if h < 33:
		return "fog,winter"
	if h < 50:
		return "overcast,winter"
	return ("overcast" if h < 75 else "clear") + ",winter,snowcover"


## Set pending battle b's weather (at its creation): the current rules (state version 10) only; the legacy formats' play
## (6, 8: campaign_sim's pinned rows, kept exact) has none, and draws nothing.
static func set_on(st: Dictionary, b: Dictionary) -> void:
	if int(st.get("version", 0)) >= 10:
		b["weather"] = pick(st)


## Pending battle b's weather ("" for a battle from before the weather rules: a clear day).
static func of(b: Dictionary) -> String:
	return str(b.get("weather", ""))
