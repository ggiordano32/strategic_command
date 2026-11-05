extends SceneTree
## A fleet at the shore, measured (docs/design/battle_sim.md "A fleet at the shore (as built, 2026-11-05)"): the
## port town battle of Scenarios.shore_battle (west_port's map, walls 1; the West attackers landed against its
## garrison), both sides AI at --skill (1 Average), seeds --seed0 .. + --seeds - 1, the 15-minute limit; --def / --att
## the defenders' / attackers' fleet (0 none, 1 a frigate and two sloops, 2 a piragua and two war canoes). Prints a
## line per battle and a SHORE_JSON summary: attacker wins, the ships' shots and kills, the parties landed and lost.
##   godot --headless --path . -s tests/shore_probe.gd -- --def=1 --att=0 [--seeds=8 --seed0=8100 --skill=1]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")


func _init() -> void:
	var df := 1
	var af := 0
	var seeds := 8
	var seed0 := 8100
	var skill := 1
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--def="): df = int(v)
		elif a.begins_with("--att="): af = int(v)
		elif a.begins_with("--seeds="): seeds = int(v)
		elif a.begins_with("--seed0="): seed0 = int(v)
		elif a.begins_with("--skill="): skill = int(v)
	var tot := {"battles": 0, "att_wins": 0, "draws": 0, "shots": [0, 0], "kills": [0, 0], "landed": [0, 0],
		"party_lost": [0, 0], "crew_lost": [0, 0], "silenced": [0, 0], "party_kills": [0, 0], "ticks": 0}
	for k in seeds:
		var sc := Scenarios.shore_battle(df, af)
		sc["ai_skill"] = [skill, skill]
		var sim := BattleSim.new()
		sim.setup(sc, seed0 + k)
		while sim.ended == 0 and sim.tick < sim.time_limit + 700:
			sim.step()
		var res: Dictionary = sim.result()
		tot["battles"] += 1
		if int(res["winner"]) == 0:
			tot["att_wins"] += 1
		elif int(res["winner"]) != 1:
			tot["draws"] += 1
		tot["ticks"] += sim.tick
		var line := "seed %d: winner %d tick %d" % [seed0 + k, int(res["winner"]), sim.tick]
		for r in res.get("ships", []):
			var s := int(r["side"])
			tot["shots"][s] += int(r["shots"])
			tot["kills"][s] += int(r["kills"])
			tot["landed"][s] += int(r["landed"])
			tot["party_lost"][s] += int(r["party_killed"])
			tot["party_kills"][s] += int(r["party_kills"])
			tot["crew_lost"][s] += int(r["killed"])
			tot["silenced"][s] += int(r["silenced"])
			line += " | %d %s shots %d kills %d landed %d lost %d" % [s, str(r["key"]), int(r["shots"]), int(r["kills"]),
				int(r["landed"]), int(r["party_killed"])]
		print(line)
	print("SHORE_JSON def=%d att=%d %s" % [df, af, JSON.stringify(tot)])
	quit(0)
