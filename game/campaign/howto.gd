extends RefCounted
## One place for the game's teaching words (docs/design/campaign_rules.md "The tutorial"): the eight "How to play"
## sections, the ten lessons of the guided first campaign ("Your first command"), the battle tutorial's steps and the
## first-time tips. The How to play page (howto_page.gd), the lesson cards (tutorial.gd), the battle steps
## (tutorial_battle.gd) and the tips (tips.gd) all read from here, so they never disagree. Plain words for someone who
## has never played a Rome-style game; one to three sentences a card, one a tip. Static data, view only.

## key -> text. Keys: "<section>_<n>" (a section's lines), "lesson_<n>" / "lesson_<n>_title" / "lesson_<n>_obj",
## "step_<n>" (the battle tutorial), "tip_<key>" (first-time tips), "ui_*" (the cards' buttons and notes).
const T := {
	# 1. The map and the turn
	"map_1": "The map is split into regions, and every region has one town. A colour shows who owns it; yours is the bright one.",
	"map_2": "You play in turns. Give your orders, then press End turn: the armies march, towns grow and the other nations act, all at once.",
	"map_3": "Drag to pan, scroll or pinch to zoom. Tap a town or an army to select it and see what it can do.",
	# 2. Towns and buildings
	"towns_1": "A town earns gold every turn. The bigger it grows, the more it earns and the more it can hold.",
	"towns_2": "Open a town and press Build to add a building: farms, barracks (the natives' war lodge), a range for muskets, stables for horse. Each building has levels, and a higher level lets the town train better soldiers.",
	"towns_3": "A town builds one thing at a time and it takes a few turns. Buildings need a free slot, and a bigger town has more slots.",
	# 3. Armies and recruiting
	"armies_1": "An army is a stack of companies. Soldiers cost gold to raise and a little every turn to keep: that is their upkeep.",
	"armies_2": "Select an army that stands in a town and press Recruit to add companies. A town trains only a few a turn, and its buildings decide which kinds.",
	"armies_3": "Recruits join at the end of the turn, and an army that recruits stays where it is that turn.",
	# 4. Movement and supply
	"move_1": "Select an army and tap the ground to march there. The shaded area is how far it gets this turn; a farther spot takes more turns.",
	"move_2": "Marching costs movement points, and the slowest company sets the pace. A tap on the same spot again cancels the march.",
	"move_3": "You cannot march through the land of a nation you are at peace with, unless it has agreed to let you pass. In enemy land an army can raid, or lay siege to a town.",
	# 5. Sieges
	"siege_1": "To take a town you must be at war with its owner. March next to it and tap it to lay siege: the army camps by the walls and cuts the town off.",
	"siege_2": "A besieged town has supplies for a few turns. When they run out the garrison weakens every turn, but so do the besiegers, so a siege is slow and not free.",
	"siege_3": "Or storm it with Assault: a battle is fought, and the odds bar in the siege panel shows how it looks. The winner takes the town.",
	# 6. Battles and the chips
	"battle_1": "In a battle you place your companies in the blue zone, press Start battle, then give orders by tapping: the ground to move, an enemy to attack.",
	"battle_2": "The buttons along the bottom are chips: Fire at will, Halt, Withdraw and more. Hold your finger or the mouse on a chip to read what it does.",
	"battle_3": "Halt keeps a company where it stands, and Withdraw pulls a hurt one out of the fight. The battle ends when one side is beaten or the time is up. Horse with pistols caracole: they ride up, fire, wheel back and reload (the card says Firing, Wheeling, Reloading; pistols wait 30 s), and set the Caracole chip to Hold or double tap the enemy to charge home instead.",
	# 7. The sea
	"sea_1": "A fleet carries armies over the water. Walk an army to a lit beach beside your fleet, or into a port, and it boards.",
	"sea_2": "Select the fleet and tap the sea to sail: the shaded water is how far it gets this turn, and the wind matters. Tap a lit beach to land the troops aboard.",
	"sea_3": "Enemy fleets can fight yours at sea, and a fleet that lies off an enemy harbour blockades its trade.",
	# 8. Diplomacy and goals
	"dip_1": "Open Diplomacy to see every nation. You can propose trade or an alliance, give a gift, or declare war. The answer comes when the turn ends.",
	"dip_2": "Trust matters: nations that trust you accept more, and breaking a treaty or attacking a friend costs you trust.",
	"dip_3": "Goals shows how to win: hold enough regions and great cities. Realm sums up your gold, income and upkeep, and the chronicle records what happened.",

	# The guided first campaign: ten lessons (title, card text, objective)
	"lesson_1_title": "The map",
	"lesson_1": "Welcome, Governor. Port Royal is your town and the banner beside it is your army. Drag to pan, scroll or pinch to zoom, and tap Port Royal to open it.",
	"lesson_1_obj": "Open Port Royal's panel",
	"lesson_2_title": "Recruiting",
	"lesson_2": "Soldiers cost gold now and a little every turn. Port Royal can train two companies a turn. Tap your army, press Recruit, then press the + button next to Musketeers twice. The ring shows it.",
	"lesson_2_obj": "Recruit two musketeer companies",
	"lesson_2_open": "Done: two companies queued. They join the army at the end of the turn. Close the list, then press End turn.",
	"lesson_3_title": "Building",
	"lesson_3": "Buildings make a town stronger. Tap Port Royal, press Build and upgrade the Range: a higher level trains better musketeers. It takes a couple of turns. The ring shows the Range row.",
	"lesson_3_obj": "Queue a Range upgrade",
	"lesson_3_open": "The Range is queued; it takes a couple of turns. Close the list, then press End turn.",
	"lesson_4_title": "Moving",
	"lesson_4": "Sevilla la Nueva, just west of you, is Spanish and you are at war with Spain. Select your army and tap the lit spot outside its walls; the shaded area is how far you get this turn.",
	"lesson_4_obj": "March the army to the camp outside Sevilla la Nueva",
	"lesson_5_title": "The siege",
	"lesson_5": "Now lay siege: with the army selected, tap Sevilla la Nueva. The army camps by the walls and cuts the town off. The siege panel shows its supplies and the odds of storming it.",
	"lesson_5_obj": "Lay siege to Sevilla la Nueva",
	"lesson_6_title": "The battle",
	"lesson_6": "Starving a town takes time, so storm it. Tap Sevilla la Nueva, press Assault and end the turn. A battle follows, and we will walk through it step by step.",
	"lesson_6_obj": "Order the assault, then win the battle",
	"lesson_6_fight": "Press Fight. We walk through the battle step by step.",
	"lesson_6_auto": "This battle is the lesson: press Fight.",
	"lesson_7_title": "After the battle",
	"lesson_7": "Sevilla la Nueva is yours. A town you hold pays income, and your army costs upkeep. The Realm page sums up your gold, your income and what you hold: open it.",
	"lesson_7_obj": "Open the Realm page",
	"lesson_8_title": "Diplomacy",
	"lesson_8": "Not every nation has to be an enemy. Open Diplomacy, tap the Dutch and press Offer trade; the ring shows each step. Trade pays both sides and builds trust. The answer comes when the turn ends.",
	"lesson_8_obj": "Propose a trade agreement to the Dutch",
	"lesson_8_open": "Done: the offer goes out when the turn ends. Close Diplomacy, then press End turn.",
	"lesson_9_title": "The sea",
	"lesson_9": "Your fleet lies off Port Royal. With the army selected, tap the fleet: the army walks to the lit beach beside it and boards. Then select the fleet and tap the sea toward the Tortuga coast. The army boards at the end of the turn and the fleet waits for it; the voyage begins the turn after.",
	"lesson_9_obj": "Board the fleet and sail toward the Tortuga coast",
	"lesson_9_done": "Done. The army boards when the turn ends, then the fleet sails. Press End turn.",
	"lesson_10_title": "Goals",
	"lesson_10": "Goals tells you how to win: hold enough regions and great cities. Open it, and the lessons are over.",
	"lesson_10_obj": "Open the Goals page",
	"lesson_over_title": "The lessons are over",
	"lesson_over": "From here the campaign is yours, with no more gates. Open How to play in the menu whenever you want a reminder.",
	"ui_skip": "Skip the lesson",
	"ui_leave": "Leave the tutorial",
	"ui_gate": "Finish the lesson first",
	"ui_done": "Got it",
	"ui_first_title": "New here?",
	"ui_first": "Your first command walks you through a campaign in ten turns.",
	"ui_first_yes": "Start the tutorial",
	"ui_first_no": "Not now",
	"ui_objective": "To do: ",
	"ui_left_note": "The lessons have stopped; the campaign goes on as it is.",
	"ui_lesson_of": "Lesson %d of 10",

	# The battle tutorial (lesson 6's battle): six steps and two small cards between them
	"step_1": "Place your line: drag a company into the blue zone to set where it stands.",
	"step_1b": "Happy with the line? Press Start battle.",
	"step_2": "Move it forward: select your companies and tap the ground ahead of them. On a touch screen the tap places a ghost: drag its handles to turn or widen it, then press Go.",
	"step_3": "Fire at will: your musketeers were told to hold fire. Select them, open the Fire chip and choose At will, and they shoot any enemy in range by themselves. Hold the chip to read what it does.",
	"step_4": "Charge with the horse: select the horse and tap an enemy company.",
	"step_5": "Hold: select a company and press Halt to stop it where it stands.",
	"step_6": "Withdraw a company: select one and press Withdraw, then confirm. It leaves the fight before it breaks.",
	"step_win": "That is all the orders you need. Now beat the garrison.",
	"step_title": "Battle lesson %d of 6",

	# First-time tips (one sentence each)
	"tip_army_selected": "Tap the ground to march the selected army: the shaded area is how far it gets this turn.",
	"tip_town_opened": "Press Recruit to raise companies and Build to add buildings; both are ready in a turn or two.",
	"tip_siege_laid": "A siege cuts the town off, and its garrison weakens each turn; press Assault to storm it now instead.",
	"tip_deployment": "Place your companies in the blue zone, then press Start battle.",
	"tip_first_chip": "The buttons along the bottom are chips: hold one to read what it does.",
	"tip_fleet_boarded": "Select the fleet and tap the sea to sail, or a lit beach to land the army.",
	"tip_proposal_received": "Another nation made you an offer: open Diplomacy to accept it or turn it down.",
	"tip_battle_won": "Victory: the town is yours to run, so open it to recruit and build, and keep an army near to hold it.",
}

## The eight How to play sections: id, title, the keys of its lines.
const SECTIONS := [
	{"id": "map", "title": "The map and the turn", "lines": ["map_1", "map_2", "map_3"]},
	{"id": "towns", "title": "Towns and buildings", "lines": ["towns_1", "towns_2", "towns_3"]},
	{"id": "armies", "title": "Armies and recruiting", "lines": ["armies_1", "armies_2", "armies_3"]},
	{"id": "move", "title": "Movement and supply", "lines": ["move_1", "move_2", "move_3"]},
	{"id": "siege", "title": "Sieges", "lines": ["siege_1", "siege_2", "siege_3"]},
	{"id": "battle", "title": "Battles and the chips", "lines": ["battle_1", "battle_2", "battle_3"]},
	{"id": "sea", "title": "The sea", "lines": ["sea_1", "sea_2", "sea_3"]},
	{"id": "dip", "title": "Diplomacy and goals", "lines": ["dip_1", "dip_2", "dip_3"]},
]

const TIP_KEYS: Array[String] = ["army_selected", "town_opened", "siege_laid", "deployment", "first_chip", "fleet_boarded",
	"proposal_received", "battle_won"]
const LESSONS := 10
const STEPS := 6


static func text(key: String) -> String:
	return str(T.get(key, ""))


static func lesson(n: int) -> Dictionary:
	return {"title": text("lesson_%d_title" % n), "text": text("lesson_%d" % n), "obj": text("lesson_%d_obj" % n)}


static func step(n: int) -> String:
	return text("step_%d" % n)


static func tip(key: String) -> String:
	return text("tip_" + key)


static func section_text(id: String) -> String:
	for s in SECTIONS:
		if str(s["id"]) == id:
			var parts: Array[String] = []
			for k in s["lines"]:
				parts.append(text(str(k)))
			return " ".join(parts)
	return ""
