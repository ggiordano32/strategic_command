extends RefCounted
## The story campaign "The Brethren's Due" (DESIGN "Story campaign: The
## Brethren's Due"): the script as data, read by campaign/cstory.gd: the
## Prologue (turns 0-3), Act 1 "Brethren" (turns 4-14), Act 2 "The
## Commission" (15-29), Act 3 "The Free Port" (30-44) and the three
## endings (the Republic, the Pardon, the Legend). Turn numbers here are the
## state's (0 = the first turn, summer 1665).
##
## Nothing here is stored in a state: a state keeps event ids, choice
## indices and its pressures (cstory.gd), so the text can be edited freely;
## changing an event's id, a choice's position or an effect changes what a
## saved story means.
##
## EVENTS: in firing order (the engine checks them in this order).
##   id, act (0 prologue, 1 Act 1, 2 ...), title, lines [[speaker, text], ...]
##   (speaker: a CHARS key, "" a narrator), when (trigger conditions, all
##   must hold; absent: the event fires only when scheduled), if (conditions
##   checked when a scheduled event comes due: false = it is dropped), once
##   (default 1), every N (may fire again N turns after it last did, while
##   its conditions hold), tip 1 (a first-sight line: shown once, in the log),
##   chron (a line for the world chronicle), focus (view: what the map
##   centres on: a region key, an actor key, "lair", "flagship"), fx (effects when it fires),
##   choices [{t (button text), hint (what it does, shown under it), need
##   (conditions to be allowed), why (shown when not), say [speaker, reply],
##   fx}] (absent: news, shown once and logged).
## Conditions (cstory.gd _cond): turn [a, b] (b -1 open), flag / noflag (a
##   name or a list), p_ge / p_lt [pressure, v], att_ge / att_lt v (the
##   Armada's attention), near [region, cells] (a captain's fleet), owns /
##   lost region, season 1 (the hurricane season), storm 1 (a storm on the
##   map), siege 1 (a siege by or of a captain), plunder 1 (any plunder yet),
##   plundered_in / not_plundered_in N (turns), actor [key, "alive" | "gone"],
##   gold_ge v, timer name, ships_ge n; step 2: flota / noflota 1 (the
##   treasure fleet on the map), blockaded 1 (a port of ours), capt / nocapt
##   k (a captain of ours the story made from actor k, afloat), fp part
##   ("fort" | "fleet" | "chest": the free port's goal met) / fp_ge n (parts
##   met), walls_ge [region, n], fame_ge n, sea_pending 1 (a sea battle of
##   ours waiting), any [conditions, ...] (one of them holds).
## Effects (cstory.gd _fx): see the list there.

## Who speaks: name, role, badge colour, mark (the faction whose mark stands in until a portrait is drawn, game/story_portrait.gd; a coloured
## initial until there is art).
const CHARS := {
	"mercy": {"name": "Mercy Teague", "role": "Quartermaster", "col": "b8432f", "mark": "brethren"},
	"lindo": {"name": "Isaac Lindo", "role": "Fence of Port Royal", "col": "7b5ea7", "mark": "england"},
	"vane": {"name": "Josiah Vane", "role": "From his logbook", "col": "8a6a3a", "mark": "brethren"},
	"mendoza": {"name": "Don Rodrigo de Mendoza", "role": "Admiral of the Armada de Barlovento", "col": "d9a31f", "mark": "new_spain"},
	"ashby": {"name": "Sir Thomas Ashby", "role": "Governor of Jamaica", "col": "c8402f", "mark": "england"},
	"boucher": {"name": "Jean-Baptiste Nau", "role": "\"Le Boucher\"", "col": "5a1a1a", "mark": "brethren"},
	"crew": {"name": "The crew", "role": "", "col": "5a6b5a", "mark": "brethren"},
	"jeremy": {"name": "Jeremy", "role": "King of the Mosquito Coast", "col": "8a4fc4", "mark": "miskito"},
	"hesketh": {"name": "Tom Hesketh", "role": "Captain of the Brethren", "col": "3f6f8f", "mark": "brethren"},
	"captain": {"name": "The Captain", "role": "Quartermaster turned captain", "col": "4a4a52", "mark": "brethren"},
	"partner": {"name": "Captain Rook", "role": "Captain of the Mosquito Queen", "col": "2f7f6f", "mark": "miskito"},
	"": {"name": "", "role": "", "col": "3a3a3a"},
}

const TITLE := "The Brethren's Due"
const ACTS: Array[String] = ["Prologue", "Act One: Brethren", "Act Two: The Commission", "Act Three: The Free Port"]
## The story's first year (the pack's calendar starts in 1650).
const START_YEAR := 1665
## The player's faction, the haven to reach, the captain's name.
const PLAYER := "brethren"
const HAVEN := "port_de_paix"
const CAPTAIN := "The Captain"
## Co-op (a second human captain, cstory.gd _setup): the partner plays the
## Miskito faction (friends of the English pirates), a captain of the same
## Brethren with a sloop of his own off Port Royal and the haven at the Cabo
## Gracias a Dios; the crew votes every choice between the two captains.
const PARTNER := "miskito"
const PARTNER_CAPTAIN := "Captain Rook"
const PARTNER_START := {
	"treasury": 150, "infamy": 3,
	"ship": {"t": "sloop", "h": 70, "c": 70, "nm": "Mosquito Queen"}, "at": [-7650, 1790],
	"aboard": [["native_warriors", 70]],
	"keep_regions": ["cabo_gracias"],
	"army": ["native_warriors", "native_bowmen"],
	"peace": ["dutch", "england", "france"],
}
## Times the Brethren fish a shipless, landless captain out of the surf.
const MERCY := 3

## The pressures (cstory.gd): start values. purse: how hungry the crew is
## (0-100); owed: shares promised (gold); heat: the Armada's grudge on top
## of infamy (the attention is infamy + heat); favour: the Governor of
## Jamaica's (0-100); haven: how safe Tortuga is (0-100).
const PRESSURES := {"purse": 20, "owed": 0, "heat": 0, "favour": 25, "haven": 60}
## The purse: + a turn without plunder (+ more while shares owed reach
## OWED_HIGH), - plunder / PURSE_PLUNDER_DIV (at most PURSE_PLUNDER_MAX) a turn.
const PURSE_TURN := 6
const OWED_HIGH := 300
const PURSE_OWED := 2
const PURSE_PLUNDER_DIV := 6
const PURSE_PLUNDER_MAX := 60
## Shares owed grow by this % of plunder.
const OWED_PCT := 50
## Lindo's fence (timer "lindo"): this % more for plunder.
const LINDO_PCT := 25
## The haven drifts toward 40 + HAVEN_WALL a walls level + HAVEN_ARMY with
## an army of ours in it - attention / HAVEN_ATT_DIV, HAVEN_STEP a turn.
const HAVEN_BASE := 40
const HAVEN_WALL := 15
const HAVEN_ARMY := 15
const HAVEN_ATT_DIV := 4
const HAVEN_STEP := 5
## The Armada hunts at this attention or more, a captain's fleet within
## ARMADA_RANGE + attention cells; else it lies at its home port.
const ARMADA_HUNT_ATT := 35
const ARMADA_RANGE := 25
## A hunting actor goes home to refit for this many turns after a battle.
const ACTOR_REST := 3
## Map marks (view only): captions over the story's fleets and places.
const MARKS := {"guarda": "Guardacosta San Telmo", "armada": "Armada de Barlovento", "boucher": "Le Boucher",
	"prize": "Spanish trader (prize)", "nao": "Treasure nao", "haven": "Tortuga: your haven", "lair": "Ile-a-Vache: Le Boucher's lair",
	"pinos": "Careened frigate (prize?)", "straggler": "Straggling galleon (prize)", "royal": "Port Royal squadron",
	"hunters": "Ashby's pirate hunters", "flota": "The flota", "free_port": "Tortuga: the free port"}
## Prizes (map captions in gold, not red).
const PRIZES: Array[String] = ["prize", "nao", "pinos", "straggler"]
## Places the story points at (view: a dashed ring and a caption while the
## flags hold): [flag set, flag not set, region key, caption].
const TARGETS: Array = [
	["raid_cartagena", "raided", "cartagena", "Cartagena: the great raid"],
	["raid_portobelo", "raided", "portobelo", "Portobelo: the great raid"],
]
## Le Boucher's lair (Ile-a-Vache, south of Hispaniola), the hunt's reach.
const LAIR := [-7362, 1807]
const HUNT_CELLS := 3
## The free port (Act 3, cstory.gd fp_parts): the haven held FP_HOLD turns
## with walls FP_WALLS+; the captains' fleets' power FP_FLEET_PCT % of the
## Armada's (FP_ARMADA while it is not at sea: in Tortuga road with stone
## walls the batteries make that an even fight or better); FP_GOLD in the
## chest.
const FP_HOLD := 5
const FP_WALLS := 2
const FP_FLEET_PCT := 80
const FP_ARMADA := 1200
const FP_GOLD := 1500
## A captain's fleet within this of a harbour lands its troops in a story assault.
const ASSAULT_CELLS := 5
## The game ends with no ending (every captain gone / a victory): these events end the story.
const END_OVER := "end_fallen"
const END_WON := "end_conquest"
## Isla de Pinos (south of Cuba) and the Florida straits off Havana.
const PINOS := [-8290, 2150]
const STRAITS := [-8180, 2345]

## The start (cstory.gd _setup): the player's sloop off Port Royal, with a
## company aboard; the scripted actors' fleets.
const START := {
	"treasury": 200, "infamy": 5,
	"ship": {"t": "sloop", "h": 70, "c": 70, "nm": "Gallows Bird"}, "at": [-7672, 1772],
	"aboard": [["cutlass", 70]],
	"keep_regions": ["port_de_paix"],
	"peace": ["dutch", "england", "france"],
	"actors": [
		{"k": "guarda", "f": "new_spain", "at": [-7540, 1778], "ships": [{"t": "sloop", "nm": "San Telmo", "h": 65, "c": 65}], "mode": "chase", "until": 2,
			"home": "santiago_de_cuba"},
		{"k": "armada", "f": "new_spain", "at": "havana", "ships": [{"t": "frigate", "nm": "Nuestra Senora de la Soledad"},
			{"t": "frigate", "nm": "San Felipe"}, {"t": "sloop"}], "mode": "hunt", "home": "havana"},
	],
	"settings": {"victory_regions": 30, "victory_capitals": 5},
}

const EVENTS: Array[Dictionary] = [
	# ------------------------------------------------------------ prologue ---
	{"id": "hanging", "act": 0, "title": "Gallows Point", "when": {"turn": [0, 0]},
		"lines": [
			["", "Port Royal, Jamaica. Summer, 1665. Low tide at Gallows Point."],
			["mercy", "They hanged Josiah Vane at sunrise, at low water, so the crabs could have him when the tide came in. The Governor watched from his carriage. Ashby didn't even get out of it."],
			["mercy", "The crew voted while he was still kicking. Forty-one hands, forty-one votes. You're captain now. Don't make me regret mine."],
			["mercy", "Vane left you his sloop, his debts and his logbook. The sloop leaks, the debts are Lindo's, and the logbook... he wrote something in it the night before. Read it when we're not being chased."],
		]},
	{"id": "chase", "focus": "guarda", "act": 0, "title": "Sails to windward", "when": {"turn": [0, 0]},
		"lines": [
			["mercy", "Guardacosta off the point! Spanish, coming down on us out of the east with the wind behind her. The San Telmo. She's been waiting a week for Vane's sloop to come out without Vane on it."],
			["mercy", "We can run west, before the wind: nothing catches a sloop running free. Or we come about and fight her. She's a sloop like us, but she has a full crew and we have forty men with hangovers. Your call, Captain."],
		],
		"choices": [
			{"t": "Run west, before the wind", "hint": "Your sloop sails west this turn; the Spaniard gives up. The crew calls it sense today and cowardice by Sunday.",
				"say": ["mercy", "Run it is. Shake out every reef, and somebody pour water on that hangover."],
				"fx": [["flag", "ran"], ["voyage", [-7930, 1785]], ["home", "guarda"], ["p", "purse", 8], ["sched", "log_wind", 0]]},
			{"t": "Come about and fight her", "hint": "A sea battle now, sloop against sloop. Win and they'll remember your name.",
				"say": ["mercy", "Ha! Now they'll remember your name. Run out the guns, you lubbers, and grapnels ready!"],
				"fx": [["flag", "fought_guarda"], ["sea_battle", "guarda"], ["sched", "log_wind", 0]]},
			{"t": "Hoist Spanish colours and bluff", "hint": "Vane's old trick: a gamble. If she believes it she bears away; if not, she fights with the first broadside hers.",
				"say": ["mercy", "Vane's old trick. Pray your Castilian is better than his was."],
				"fx": [["gamble", 55, "bluff_won", "bluff_lost"], ["sched", "log_wind", 0]]},
		]},
	{"id": "bluff_won", "act": 0, "title": "False colours",
		"lines": [["mercy", "She dipped her ensign to us and bore away. Bore away! Vane would have laughed himself sick. The lads are calling you a gentleman of Seville."]],
		"fx": [["home", "guarda"], ["p", "purse", -5], ["fame", 3]]},
	{"id": "bluff_lost", "act": 0, "title": "False colours",
		"lines": [["mercy", "She didn't believe a word. Here she comes with her guns run out, and she's fired first. So much for Castilian."]],
		"fx": [["hull", -15], ["sea_battle", "guarda"]]},
	{"id": "log_wind", "act": 0, "title": "Vane's logbook: the trades", "tip": 1,
		"lines": [
			["vane", "The trades blow out of the east every day God sends, steady as a parson. Running west you fly; beating back east you crawl, tack on tack, and a man can lose a week getting to windward of a place he could see from the masthead."],
			["vane", "Mind the wind before you mind the enemy. The wind decides which of you gets to choose the fight."],
			["", "Fleets sail farther downwind (west) and much less far upwind (east). The reach shown when you plan a voyage already counts the wind."],
		]},
	{"id": "won_guarda", "act": 0, "title": "The San Telmo strikes", "when": {"flag": "won_guarda"},
		"lines": [["mercy", "She struck her colours! The lads are cheering your name, Captain. Enjoy it. It lasts till they're hungry again."]],
		"chron": "A new pirate captain fought a Spanish guardacosta off Port Royal and won.",
		"fx": [["fame", 5], ["p", "purse", -15], ["infamy", 3], ["home", "guarda"]]},
	{"id": "lost_guarda", "act": 0, "title": "Beaten off", "when": {"flag": "lost_guarda"},
		"lines": [["mercy", "We ran with our tail between our legs and half the rigging shot away. Nobody died that the sharks didn't want. Tortuga, Captain, before the crew remembers whose idea that was."]],
		"fx": [["p", "purse", 10], ["home", "guarda"]]},
	{"id": "hungry", "focus": "flagship", "act": 0, "title": "The hungry crew", "when": {"turn": [1, 3]},
		"lines": [
			["mercy", "Three days of water, a cask of weevils with some biscuit in it, and no shares since Easter. The crew want something in their pockets before Tortuga, or they'll want a new captain at Tortuga."],
			["mercy", "There's a Spanish trader lying off Cabo Cruz with her mainmast sprung: fat, slow and alone. Or there's the fishing village at Punta de Mulas on the Cuban shore. No guns, no soldiers. Nothing much worth taking, either."],
		],
		"choices": [
			{"t": "Take the Spanish trader", "hint": "She lies off Cabo Cruz for three turns: sail at her and she is yours if you win.",
				"say": ["mercy", "Cabo Cruz, then. Run alongside her and let the lads do what they do best."],
				"fx": [["spawn", "prize", "new_spain", [-7765, 1960], [{"t": "sloop", "nm": "Santa Catalina", "h": 55, "c": 50, "g": 250}], 3, "hold"],
					["flag", "hunting_prize"]]},
			{"t": "Raid the fishing village", "hint": "120 gold of plunder now. Spain's anger, and a little of yours.",
				"say": ["mercy", "We took their nets, their goats and the church plate. One old man spat at the bosun, and the bosun dealt with it. That's the trade, Captain. Don't look at me like that."],
				"fx": [["plunder", 120], ["infamy", 6], ["p", "heat", 5], ["flag", "raided_village"]]},
			{"t": "Tighten belts until Tortuga", "hint": "Nothing gained, nothing lost but the crew's patience.",
				"say": ["mercy", "The crew votes, Captain. Remember that."],
				"fx": [["p", "purse", 15]]},
		]},
	{"id": "prize_taken", "act": 0, "title": "The Santa Catalina", "when": {"flag": "won_prize"},
		"lines": [["mercy", "Cocoa, hides, a strongbox of pieces of eight and a Dominican who wants ransoming. Shares all round tonight, Captain."]],
		"fx": [["p", "purse", -10], ["fame", 3]]},
	{"id": "prize_gone", "act": 0, "title": "She got away", "when": {"flag": "gone_prize", "noflag": "won_prize"},
		"lines": [["mercy", "The trader fished her mast and slipped into Santiago in the night. The lads watched her go and said nothing. That kind of nothing is loud, Captain."]],
		"fx": [["p", "purse", 10]]},
	{"id": "tip_plunder", "act": 0, "title": "Vane's logbook: shares", "tip": 1, "when": {"plunder": 1},
		"lines": [
			["vane", "Plunder is the only pay a free crew knows. Take a ship and her cargo and coin go to the common chest, and the crew reckons its shares from it. Feed them prizes and they will follow you into the mouth of Hell; keep them hungry and they will find another captain on the road there."],
			["", "The crew's purse (top left) rises every turn without plunder; prizes, sacks and treasure bring it down. A hungry crew grumbles, then deserts, then votes."],
		]},
	{"id": "tortuga", "focus": "port_de_paix", "act": 0, "title": "Tortuga", "when": {"near": ["port_de_paix", 6], "owns": "port_de_paix"},
		"lines": [
			["", "Tortuga: a hump of rock off the north coast of Hispaniola, a fort, a hundred taverns, and no law but the Brethren's."],
			["mercy", "Home, such as it is. Every captain in the Caribbean drinks here, and every one of them has heard that Vane hanged and his sloop has a new master. They're watching to see what you're made of."],
			["mercy", "There are men on the beach looking for a ship. Buccaneers off the hills of Hispaniola who can put a ball in a bull's eye at two hundred paces, and some who just want to be somewhere else."],
		],
		"chron": "Vane's sloop came into Tortuga under a new captain.",
		"fx": [["flag", "tortuga"], ["sched", "tip_haven", 0], ["sched", "lindo_letter", 1]],
		"choices": [
			{"t": "Stand the house a round (100 gold)", "need": {"gold_ge": 100}, "why": "Not enough gold in the chest",
				"hint": "Two companies of buccaneers join you at Tortuga, and the crew drinks.",
				"say": ["mercy", "Rum for the house! There isn't a man in Tortuga who'd turn down a captain buying the first barrel."],
				"fx": [["gold", -100], ["unit", "buccaneers", 2, "port_de_paix"], ["p", "purse", -10]]},
			{"t": "Promise them shares from the next prize", "hint": "Two companies of cutlass men now; 300 gold in shares owed.",
				"say": ["mercy", "Three hundred pieces of eight we don't have. I wrote it down, Captain. So did they."],
				"fx": [["unit", "cutlass", 2, "port_de_paix"], ["p", "owed", 300]]},
			{"t": "Take only the volunteers", "hint": "One company of buccaneers, no promises.",
				"say": ["mercy", "Fewer mouths. Fewer opinions."],
				"fx": [["unit", "buccaneers", 1, "port_de_paix"]]},
		]},
	{"id": "tip_haven", "act": 0, "title": "Vane's logbook: havens", "tip": 1,
		"lines": [
			["vane", "A haven is worth ten fleets: somewhere to careen, to sell, to drink, to bury the dead and recruit the living. Lose it and you are a wolf without a den."],
			["", "In a haven of yours buccaneers and cutlass men come cheaper (more so as your infamy and fame grow), ships are mended faster, and a feared name brings more men to the beach. Haven safety (top left) falls as Spain's attention rises."],
		]},
	{"id": "lindo_letter", "act": 0, "title": "A letter from Port Royal",
		"lines": [
			["lindo", "My dear Captain, and I do so hope I may call you that: my condolences on poor Josiah. A great loss. To me especially; he died owing me four hundred pieces of eight, and the dead are such poor correspondents."],
			["lindo", "But let us look forward. You will be taking prizes, and prizes must be sold, and I sell things. Discreetly, at a fair price, give or take. I also speak to certain people in the Governor's house who find pirates distasteful in public and useful in private."],
			["lindo", "Your servant, Isaac Lindo. P.S. Do burn this."],
		],
		"choices": [
			{"t": "Do business with Lindo", "hint": "For 8 turns your plunder fetches a quarter more; the Governor hears your name kindly.",
				"say": ["lindo", "Splendid. You will find me entirely reasonable. Until you don't."],
				"fx": [["flag", "lindo"], ["timer", "lindo", 8], ["p", "favour", 5]]},
			{"t": "Pay half of Vane's debt (200 gold)", "need": {"gold_ge": 200}, "why": "Not enough gold in the chest",
				"hint": "200 gold to Lindo; the Governor's house hears you pay your debts.",
				"say": ["lindo", "Half! From a man who owes me nothing! I am touched, Captain. I shall remember it, in the ledger I keep where my heart should be."],
				"fx": [["gold", -200], ["flag", "lindo_paid"], ["p", "favour", 10]]},
			{"t": "Burn it unread past the first line", "hint": "Nothing, for now. Lindo forgets nothing.",
				"say": ["mercy", "Good. That man would sell his mother's coffin and charge her for the nails."],
				"fx": [["flag", "lindo_snubbed"]]},
		]},
	# ---------------------------------------------------------------- act 1 ---
	{"id": "act1", "act": 1, "title": "Act One: Brethren", "when": {"turn": [4, -1]},
		"lines": [
			["", "Summer, 1667. The Brethren of the Coast drink to Vane's memory and wait to see whether his heir is worth the rum."],
			["mercy", "A captain is only a captain while the crew says so. Keep their purses full, keep Tortuga standing, and keep the Spanish looking somewhere else. Pick two."],
		],
		"fx": [["act", 1]]},
	{"id": "grumble", "act": 1, "title": "Talk in the forecastle", "when": {"p_ge": ["purse", 40]}, "every": 5,
		"lines": [["mercy", "There's talk, Captain. The usual: we sail, we fight, we bleed, and there's nothing in the chest but rats. They're not wrong."]],
		"choices": [
			{"t": "Pay out what's in the chest (150 gold)", "need": {"gold_ge": 150}, "why": "Not enough gold in the chest",
				"hint": "The purse falls a quarter; 150 of the shares owed paid.",
				"say": ["mercy", "That'll hold them a while. Gold has a short memory, though. Shorter than a grudge."],
				"fx": [["gold", -150], ["p", "purse", -25], ["p", "owed", -150]]},
			{"t": "Promise a fat prize within four turns", "hint": "The crew waits. Take plunder within 4 turns, or they remember.",
				"say": ["mercy", "I'll hold you to that. So will they."],
				"fx": [["flag", "promised"], ["sched", "promise_kept", 4], ["sched", "promise_broken", 4], ["p", "purse", -10]]},
			{"t": "Hang the loudest one from the yardarm", "hint": "Quiet now. Fewer hands, and a name for it.",
				"say": ["mercy", "...Aye, Captain. It's done. They're quiet now. Quiet isn't content, and it isn't loyal. Vane never hanged his own."],
				"fx": [["p", "purse", -20], ["crew", -5], ["infamy", 3], ["flag", "hanged_man"]]},
		]},
	{"id": "promise_kept", "act": 1, "title": "A promise kept", "if": {"flag": "promised", "plundered_in": 4},
		"lines": [["mercy", "You said four turns and you meant it. The crew noticed. So did I."]],
		"fx": [["p", "purse", -10], ["unflag", "promised"]]},
	{"id": "promise_broken", "act": 1, "title": "A promise broken", "if": {"flag": "promised", "not_plundered_in": 4},
		"lines": [["mercy", "Four turns, you said. The crew can count to four, Captain."]],
		"fx": [["p", "purse", 20], ["unflag", "promised"]]},
	{"id": "desertion", "act": 1, "title": "Over the side", "when": {"p_ge": ["purse", 65]}, "every": 4,
		"lines": [["mercy", "Six men went over the side last night with the jolly boat and the bosun's good boots. They won't be the last, the way things are."]],
		"fx": [["crew", -15]],
		"choices": [
			{"t": "Let them go: fewer shares", "hint": "The rest grumble a little less.",
				"say": ["mercy", "Fewer shares to argue about, I suppose."],
				"fx": [["p", "purse", -5]]},
			{"t": "Send the hounds after them (50 gold)", "need": {"gold_ge": 50}, "why": "Not enough gold in the chest",
				"hint": "Some come back. A hard name.",
				"say": ["mercy", "We found four. The hounds found the other two first. Nobody's talking about deserting now."],
				"fx": [["gold", -50], ["crew", 8], ["infamy", 2]]},
		]},
	{"id": "mutiny", "act": 1, "title": "The crew votes", "when": {"p_ge": ["purse", 85]}, "every": 6,
		"lines": [["mercy", "They've called a council, Captain. Ship's articles: any man may call a vote on the captain. I can't stop it and I won't lie to you. I don't know how it goes."]],
		"choices": [
			{"t": "Pay full shares (300 gold)", "need": {"gold_ge": 300}, "why": "Not enough gold in the chest",
				"hint": "The vote is called off; the purse falls by more than half.",
				"say": ["mercy", "Funny how a vote goes away when there's silver on the table."],
				"fx": [["gold", -300], ["p", "purse", -60], ["p", "owed", -300]]},
			{"t": "Stand before them and talk", "hint": "A gamble, better the more famous you are. Lose and some of them take a ship and go.",
				"say": ["mercy", "Then talk, Captain. Make it a good one."],
				"fx": [["gamble_fame", 40, "vote_won", "vote_lost"]]},
			{"t": "A pistol in each hand: dare them", "hint": "They back down. Fear is not loyalty.",
				"say": ["mercy", "They backed down. This time. A captain who rules by the pistol sleeps with one under his pillow. Vane slept like a baby."],
				"fx": [["p", "purse", -35], ["infamy", 5], ["crew", -10], ["flag", "pistols"]]},
		]},
	{"id": "vote_won", "act": 1, "title": "The vote",
		"lines": [["mercy", "Thirty-two for you, nine against. Speech of your life, Captain. The nine are sulking in the cable tier."]],
		"fx": [["p", "purse", -40], ["fame", 3]]},
	{"id": "vote_lost", "act": 1, "title": "The vote",
		"lines": [["mercy", "It went against you, near enough. They didn't put you ashore: they took a ship and sailed off in her instead, and good riddance. Count heads, Captain. We're fewer."]],
		"fx": [["lose_ship"], ["p", "purse", -50]]},
	{"id": "boucher", "focus": "boucher", "act": 1, "title": "Le Boucher", "when": {"turn": [5, 7]},
		"lines": [
			["", "Two black ships stand into Tortuga road under French colours. Something hangs from the larger one's yards that might once have been men."],
			["boucher", "Vane's quartermaster! I heard they hanged your captain and you ran. Wise. I would have run too, if I were small."],
			["boucher", "Jean-Baptiste Nau. They call me Le Boucher. You will hear why. Everyone does, eventually."],
			["mercy", "He sells his prisoners' ears back to their families, Captain. When he's in a good mood."],
		],
		"fx": [["spawn", "boucher", "france", [-7300, 2030], [{"t": "brigantine", "nm": "La Vengeance"}, {"t": "sloop"}], 0, "hold"]],
		"choices": [
			{"t": "Drink with him", "hint": "The crew likes a captain who drinks with legends.",
				"say": ["boucher", "Ha! Vane's boy drinks like a man. We shall be friends, you and I. Or I shall kill you. One or the other."],
				"fx": [["p", "purse", -5], ["flag", "drank_boucher"]]},
			{"t": "Keep your distance", "hint": "Nothing, yet.",
				"say": ["mercy", "Smartest thing you've done since the gallows."],
				"fx": [["flag", "wary_boucher"]]},
			{"t": "Tell him the Brethren don't torture", "hint": "Port Royal hears of it; Le Boucher remembers.",
				"say": ["boucher", "Don't they? Then they are not trying hard enough, mon ami."],
				"fx": [["infamy", -3], ["p", "favour", 3], ["flag", "defied_boucher"]]},
		]},
	{"id": "hurricane", "focus": "flagship", "act": 1, "title": "The glass is falling", "when": {"turn": [6, 10], "season": 1},
		"fx": [["storm"]],
		"lines": [
			["vane", "July, the year of the San Mateo blow. Glass falling all forenoon, a swell out of the south-east with no wind to make it, and the sky the colour of a bruise. Every sailor on these seas knows the signs, and half of them die ignoring them."],
			["mercy", "There's a hurricane making up out of the east, Captain, a big one. And of course that's the day a Spanish nao comes over the horizon, alone, low in the water, her escort scattered. Cargo for the taking. If we're not all drowned taking it."],
		],
		"choices": [
			{"t": "Run for shelter in Tortuga", "hint": "Your flagship sails for Tortuga; in a friendly harbour a storm does a fifth of its harm.",
				"say": ["mercy", "Better poor than drowned. The crew may not agree till the wind starts screaming."],
				"fx": [["voyage_r", "port_de_paix"], ["p", "purse", 5], ["flag", "sheltered"]]},
			{"t": "Go for the nao and damn the weather", "hint": "A treasure ship close by for two turns, in the storm's path.",
				"say": ["mercy", "That's the spirit that drowned better men than us. All hands!"],
				"fx": [["spawn", "nao", "new_spain", ["player", 5, 0], [{"t": "galleon", "nm": "San Pedro y San Pablo", "h": 45, "c": 30, "g": 500}], 2, "hold"],
					["flag", "risked_storm"]]},
			{"t": "Stay at sea with sea-room to leeward", "hint": "Nothing changes. The storm decides.",
				"say": ["mercy", "Sea-room, a good anchor watch and a prayer. Vane rode out the '57 that way. Lost two men and a mast doing it."],
				"fx": [["flag", "rode_storm"]]},
		]},
	{"id": "tip_storm", "act": 1, "title": "Vane's logbook: hurricanes", "tip": 1, "when": {"storm": 1},
		"lines": [
			["vane", "A hurricane is a wheel of wind as wide as Hispaniola, turning against the sun and walking west-north-west faster than any ship can run once she is in its path."],
			["", "The orange cone on the map is where a storm will likely go next turn. Ships at sea in its core may founder (galleons worst, sloops least); ships in a friendly harbour take a fifth of the harm; ports lose trade."],
		]},
	{"id": "nao_taken", "act": 1, "title": "The San Pedro y San Pablo", "when": {"flag": "won_nao"},
		"lines": [["mercy", "Five hundred in silver, and the sea took the rest of her. Best and worst day's work I've ever seen. The crew will drink to you for a month."]],
		"chron": "Pirates took a Spanish treasure nao in the teeth of a hurricane.",
		"fx": [["p", "purse", -20], ["fame", 5], ["infamy", 4]]},
	{"id": "massacre", "focus": "maracaibo", "act": 1, "title": "Maracaibo", "when": {"turn": [8, 10], "actor": ["boucher", "alive"]},
		"lines": [
			["", "News comes in with a Dutch trader: Le Boucher has taken Maracaibo."],
			["lindo", "Took it, sacked it, and stayed a fortnight to be thorough. They say he cut the heart out of a prisoner who would not show him the silver, and bit into it in front of the others. The others showed him the silver."],
			["mercy", "And every Spaniard from here to Seville will say pirates did it. Not Nau. Pirates. Us."],
		],
		"chron": "Le Boucher sacked Maracaibo with horrors that shocked even the Main. Spain swore vengeance on every pirate.",
		"fx": [["place", "boucher", "maracaibo"], ["sack", "maracaibo"], ["p", "heat", 15], ["p", "haven", -20]],
		"choices": [
			{"t": "Pay Lindo to spread the truth (100 gold)", "need": {"gold_ge": 100}, "why": "Not enough gold in the chest",
				"hint": "Spain's grudge cools a little; Port Royal hears you are not Nau.",
				"say": ["lindo", "The truth! How novel. It will cost a little more to make it believable, but leave that to me."],
				"fx": [["gold", -100], ["p", "heat", -8], ["p", "favour", 5]]},
			{"t": "Say nothing. It's not our business", "hint": "Nothing.",
				"say": ["mercy", "It'll be our business when the Spanish come calling."],
				"fx": []},
			{"t": "Drink to him: let them fear us all", "hint": "Infamy, and a happier crew.",
				"say": ["mercy", "The crew liked that. I didn't."],
				"fx": [["infamy", 6], ["p", "purse", -10], ["flag", "toasted_boucher"]]},
		]},
	{"id": "warning", "focus": "port_de_paix", "act": 1, "title": "Sails at Santiago", "when": {"turn": [9, 11], "owns": "port_de_paix"},
		"lines": [
			["mercy", "A fisherman in from the Windward Passage, Captain. He says Santiago de Cuba is full of soldiers and there are boats gathering in the harbour. The Spanish want somebody to hang for Maracaibo, and Tortuga is the nearest pirate nest."],
			["mercy", "They'll land next season. We have one turn."],
		],
		"choices": [
			{"t": "Every man home to Tortuga", "hint": "Your flagship sails for Tortuga; the haven takes heart, and the fort's guns cost the Spanish a boat: fewer of them land.",
				"say": ["mercy", "Aye. I'll have the fort's guns scraped and loaded by the time you're there."],
				"fx": [["voyage_r", "port_de_paix"], ["p", "haven", 10], ["flag", "rushed_home"], ["sched", "reprisal_met", 1]]},
			{"t": "Hire the boucaniers of the hills (150 gold)", "need": {"gold_ge": 150}, "why": "Not enough gold in the chest",
				"hint": "Two companies of buccaneers at Tortuga, and the fort is ready: fewer Spanish land.",
				"say": ["mercy", "Hunters off the hills. They hate the Spanish worse than we do. The Spanish shot their cattle."],
				"fx": [["gold", -150], ["unit", "buccaneers", 2, "port_de_paix"], ["p", "haven", 10], ["sched", "reprisal_met", 1]]},
			{"t": "Let Tortuga look after itself", "hint": "The crew is spared a fight; Tortuga remembers. The Spanish land in full strength.",
				"say": ["mercy", "Tortuga took us in when nobody else would. I'll remember that you didn't, Captain."],
				"fx": [["p", "haven", -15], ["p", "purse", 5], ["sched", "reprisal", 1]]},
		]},
	{"id": "reprisal", "focus": "port_de_paix", "act": 1, "title": "The Spanish land", "if": {"owns": "port_de_paix"},
		"lines": [
			["", "Dawn. Spanish boats ground on the beach below the fort, and a column of pikes and muskets comes up the path under the red saltire of Burgundy."],
			["mercy", "Here they come. Every man who can hold a musket, to the walls!"],
		],
		"chron": "Spain landed at Tortuga to punish the pirates for Maracaibo.",
		"fx": [["raid", "new_spain", "port_de_paix", ["musketeers", "musketeers", "w_pikemen", "rodeleros"], "reprisal"]]},
	# The reprisal when the captain heeded the warning: the fort was ready and one boat is sunk on the way in (three companies).
	{"id": "reprisal_met", "focus": "port_de_paix", "act": 1, "title": "The Spanish land", "if": {"owns": "port_de_paix"},
		"lines": [
			["", "Dawn. The fort's guns sink the first boat in the surf; the rest ground on the beach below it, and a column of pikes and muskets comes up the path under the red saltire of Burgundy."],
			["mercy", "Fewer than they meant to bring. Every man who can hold a musket, to the walls!"],
		],
		"chron": "Spain landed at Tortuga to punish the pirates for Maracaibo.",
		"fx": [["raid", "new_spain", "port_de_paix", ["musketeers", "w_pikemen", "rodeleros"], "reprisal"]]},
	{"id": "tip_siege", "act": 1, "title": "Vane's logbook: walls", "tip": 1, "when": {"siege": 1},
		"lines": [
			["vane", "A siege is a matter of time and bread. Surround a town and it eats its stores; it starves, it surrenders, or it comes out at you. Storm the walls yourself and you pay in men for every turn you saved. We Brethren don't besiege, as a rule. We come over the wall at night or not at all."],
		]},
	{"id": "reprisal_won", "act": 1, "title": "Tortuga holds", "when": {"flag": "won_reprisal"},
		"lines": [["mercy", "They broke at the gate and ran for the boats. The beach is red. The Brethren are buying you drinks you couldn't pay for in a year, Captain."]],
		"chron": "The Brethren threw the Spanish back into the sea at Tortuga.",
		"fx": [["fame", 8], ["p", "haven", 25], ["infamy", 4], ["p", "favour", 5], ["p", "purse", -10]]},
	{"id": "reprisal_lost", "act": 1, "title": "Tortuga burns", "when": {"flag": "lost_reprisal"},
		"lines": [["mercy", "Tortuga's burning. The Spanish hanged whoever they caught, in rows along the beach. We got out with what we could carry. I'm not going to say it was your fault. I'm not going to say it wasn't."]],
		"fx": [["p", "purse", 15], ["flag", "tortuga_lost"]]},
	{"id": "bargain", "focus": "lair", "act": 1, "title": "Le Boucher's bargain", "when": {"turn": [12, 14], "actor": ["boucher", "alive"]},
		"lines": [
			["boucher", "The Spanish came to Tortuga looking for me and found you instead. My apologies! I was in Maracaibo. Busy."],
			["boucher", "Now I go to the Ile-a-Vache to careen, and then: Campeche? Cartagena? Somewhere rich. Come with me, Vane's boy. Your crew, my ships, and the whole Main is a pig for the sticking."],
			["mercy", "Or we catch him at the Ile-a-Vache with his hull on the beach and his guns ashore, and the Governor of Jamaica pays three hundred for his head. Your call, Captain."],
		],
		"fx": [["place", "boucher", "lair"], ["actor_hull", "boucher", 50, 60]],
		"choices": [
			{"t": "Hunt him down at the Ile-a-Vache", "hint": "Sail to his lair south of Hispaniola (marked on the map): close with him and it is a sea battle. Careened, he is half the fighter he was, but two ships of his against one of yours is still a bad bet.",
				"say": ["mercy", "South coast of Hispaniola. Get there before he floats her."],
				"fx": [["flag", "hunt_boucher"]]},
			{"t": "Join him", "hint": "His two ships sail with you under his own flag. Infamy, Spain's grudge, Port Royal's disgust.",
				"say": ["boucher", "Magnifique! You will learn a great deal from me. Some of it you will even wish you hadn't."],
				"fx": [["join", "boucher", "Jean-Baptiste \"Le Boucher\" Nau", 40], ["infamy", 15], ["p", "heat", 10], ["p", "purse", -15],
					["p", "favour", -15], ["flag", "joined_boucher"]]},
			{"t": "Let him go his own way", "hint": "He sails for his lair on the Ile-a-Vache. You have not seen the last of him.",
				"say": ["boucher", "Pity. You will regret it. People usually do. I shall be at the Ile-a-Vache, if you change your mind."],
				"fx": [["goal", "boucher", "lair"], ["flag", "spurned_boucher"]]},
		]},
	{"id": "boucher_beaten", "act": 1, "title": "The Butcher's end?", "when": {"flag": "won_boucher", "turn": [0, 22]},
		"lines": [
			["mercy", "We caught him with his hull on the beach. He fought like the devil, then went over the side in his shirt with a knife in his teeth, and nobody's seen him since."],
			["ashby", "Three hundred pieces of eight, as promised, for ridding His Majesty's seas of a Frenchman nobody will miss. Do not mistake this for friendship, Captain. I pay rat-catchers too."],
		],
		"chron": "Le Boucher's ships were taken at the Ile-a-Vache; the man himself vanished.",
		"fx": [["gold", 300], ["p", "favour", 15], ["fame", 8], ["flag", "boucher_beaten"]]},
	{"id": "boucher_escaped", "act": 1, "title": "Next time, bring more ships", "when": {"flag": "lost_boucher", "turn": [0, 22]},
		"lines": [["boucher", "Vane's boy came all the way to the Ile-a-Vache to kill me. How touching! Next time, bring more ships."]],
		"fx": [["p", "purse", 10], ["unflag", "hunt_boucher"]]},
	{"id": "mendoza", "focus": "armada", "act": 1, "title": "A letter under a flag of truce", "when": {"att_ge": 30},
		"lines": [
			["", "A Spanish pinnace comes alongside under a white flag, hands up a letter sealed in black wax, and leaves without a word."],
			["mendoza", "To the captain of the late Josiah Vane's sloop. Sir: I am Rodrigo de Mendoza y Ribera, admiral of His Catholic Majesty's Armada de Barlovento, and it is my duty to clear these seas of you and yours."],
			["mendoza", "I take no pleasure in it. I hanged Captain Vane's brother at Campeche in fifty-nine, and prayed for him after. I will pray for you too. Until then I remain your servant, and your end. R. de M."],
		],
		"choices": [
			{"t": "Burn it", "hint": "Nothing.",
				"say": ["mercy", "Good. Paper's for wiping."],
				"fx": []},
			{"t": "Answer him, gentleman to gentleman", "hint": "His grudge cools a little.",
				"say": ["mercy", "Very fine words. He'll hang you anyway, but he'll do it politely."],
				"fx": [["p", "heat", -5], ["flag", "wrote_mendoza"]]},
			{"t": "Nail it to the mainmast", "hint": "The crew loves it. Mendoza won't.",
				"say": ["mercy", "The lads are reading it aloud in silly voices. Somebody will tell him."],
				"fx": [["infamy", 4], ["p", "purse", -8], ["p", "heat", 5]]},
		]},
	{"id": "armada_sails", "focus": "armada", "act": 1, "title": "The Armada sails", "when": {"att_ge": 35, "actor": ["armada", "alive"]},
		"lines": [
			["", "Word from Havana: the Armada de Barlovento has put to sea, two frigates and a sloop under Don Rodrigo's own flag."],
			["mercy", "They're looking for us, Captain. The more noise we make, the farther they'll look."],
		],
		"chron": "The Armada de Barlovento put to sea from Havana to hunt pirates."},
	{"id": "haven_danger", "act": 1, "title": "Strangers in Tortuga", "when": {"p_lt": ["haven", 30], "owns": "port_de_paix"}, "every": 6,
		"lines": [["mercy", "Tortuga's jumpy, Captain. Strangers in the taverns asking questions, Spanish gold in the wrong pockets. A haven's only safe while the Brethren believe it is."]],
		"choices": [
			{"t": "Hire musketeers for the fort (120 gold)", "need": {"gold_ge": 120}, "why": "Not enough gold in the chest",
				"hint": "A company of musketeers at Tortuga.",
				"say": ["mercy", "Men on the walls. That's the kind of argument Tortuga understands."],
				"fx": [["gold", -120], ["unit", "musketeers", 1, "port_de_paix"], ["p", "haven", 10]]},
			{"t": "Hang the spies", "hint": "Tortuga feels safer. Whether the spies were spies is another matter.",
				"say": ["mercy", "Three Spanish agents. Or three men who looked like them. Hard to tell, afterwards."],
				"fx": [["p", "haven", 15], ["infamy", 3]]},
			{"t": "Ignore it", "hint": "Nothing.", "say": ["mercy", "Aye. Let's hope they're only drinking."], "fx": []},
		]},
	{"id": "ashby_notice", "act": 1, "title": "Dinner at King's House", "when": {"p_ge": ["favour", 45]},
		"lines": [["lindo", "My friend at the Governor's house tells me Sir Thomas spoke your name at dinner without spitting. From Ashby, that is practically a love letter."]]},
	{"id": "cast_ashore", "act": 1, "title": "Cast ashore",
		"lines": [["mercy", "We lost her, Captain. Every plank. The Brethren fished us out of the surf and found us a leaky sloop for what was left in our pockets. Vane used to say a captain without a ship is just a drunk with opinions. Get us back to sea."]]},
	{"id": "act1_end", "act": 1, "title": "End of Act One", "when": {"turn": [14, -1], "flag": "act1"},
		"lines": [
			["lindo", "The Governor of Jamaica would like a word, Captain. Privately. He finds himself in need of a man who sinks Spanish ships and asks no questions. Shall I tell him you are that man? Think about it. You have until spring."],
			["mercy", "A year ago they hanged our captain for a pirate. Now the man who watched it wants to hire us. Vane would have laughed. Then he'd have asked how much."],
		],
		"fx": [["act", 2], ["flag", "act1_done"]]},
	# ---------------------------------------------------------------- act 2 ---
	{"id": "act2", "act": 2, "title": "Act Two: The Commission", "when": {"turn": [15, -1], "flag": "act1_done"},
		"lines": [
			["", "Port Royal, the wickedest city in Christendom: forty taverns, a church nobody goes to, and a Governor who would like to make a respectable man of you, for a percentage."],
			["mercy", "Respectable. The crew won't know what to do with themselves. Mind, Captain: the more noise we make, the farther Mendoza looks. He's been to Havana for more ships."],
		],
		"fx": [["act", 2], ["actor_att", "armada", 30], ["spawn", "armada", "new_spain", "havana",
			[{"t": "frigate", "nm": "Nuestra Senora de la Soledad"}, {"t": "frigate", "nm": "San Felipe"}, {"t": "sloop"}], 0, "hunt", "havana"]]},
	{"id": "commission", "focus": "port_royal", "act": 2, "title": "A commission from the King", "when": {"turn": [15, 17], "flag": "act2"},
		"lines": [
			["", "King's House, Port Royal. A cool room, a hot Governor, and Isaac Lindo smiling at the window as if he owned the view. He probably does."],
			["ashby", "Captain. You will forgive me if I do not offer you a chair. I am told you sink Spanish ships. His Majesty's government has no opinion on that, officially. Unofficially, here is a commission to take, sink, burn or otherwise destroy the ships and goods of the King of Spain, his subjects and adherents."],
			["ashby", "You will bring your prizes to Port Royal. You will pay His Majesty's tenth, and mine. And you will not, under any circumstances whatsoever, embarrass me."],
			["lindo", "A letter of marque, Captain. With it you are a privateer: the same ship, the same crew, the same throats. Only now the hangman is on your side. Sir Thomas signs for men he trusts. Or for men who pay."],
		],
		"choices": [
			{"t": "Accept the commission", "need": {"p_ge": ["favour", 30]}, "why": "Ashby will not sign for a man he does not trust (patron favour 30)",
				"hint": "A letter of marque from England: peace with England, Port Royal's harbour open to you, and half as much again for Spanish plunder while England fights Spain.",
				"say": ["ashby", "Splendid. Do try not to hang, Captain. It would reflect so poorly on my judgement."],
				"fx": [["dip2", "england", "new_spain", "war"], ["dip2", "england", "tierra_firme", "war"], ["marque", "england"], ["flag", "marque"],
					["p", "favour", 10], ["sched", "tip_marque", 0]]},
			{"t": "Buy his signature (400 gold)", "need": {"gold_ge": 400}, "why": "Not enough gold in the chest",
				"hint": "The same letter of marque, for 400 gold in the right pockets.",
				"say": ["lindo", "Four hundred, of which Sir Thomas sees three. My commission. You understand."],
				"fx": [["gold", -400], ["dip2", "england", "new_spain", "war"], ["dip2", "england", "tierra_firme", "war"], ["marque", "england"],
					["flag", "marque"], ["flag", "bought_marque"], ["p", "favour", 5], ["sched", "tip_marque", 0]]},
			{"t": "No flag but ours", "hint": "No letter, no master. The crew cheers; Ashby does not forget an insult.",
				"say": ["mercy", "Vane said the same to the last Governor. The crew will drink to that tonight. Ashby will remember it longer than they will."],
				"fx": [["flag", "no_marque"], ["fame", 4], ["p", "purse", -5], ["p", "favour", -10]]},
		]},
	{"id": "tip_marque", "act": 2, "title": "Vane's logbook: letters of marque", "tip": 1,
		"lines": [
			["vane", "A letter of marque is a pirate's licence with a seal on it. It makes you a lawful enemy of the King's enemies, which is a fine thing until the kings make friends. Kings always make friends in the end. Then the paper is a rope."],
			["", "While you hold England's letter you are at peace with England, your ships refit in Port Royal, and plunder from nations England is at war with pays 50 % more. It lapses after 12 turns, or the day England makes peace with Spain."],
		]},
	{"id": "flota_news", "focus": "havana", "act": 2, "title": "The flota", "when": {"turn": [16, 18], "flag": "act2"},
		"lines": [
			["lindo", "A little bird in Havana, Captain. This summer the flota gathers there: the silver of Peru and Mexico in great galleons, with the King's warships around them like hens round a chick. It sails for Seville through the Florida straits."],
			["lindo", "One galleon would buy Tortuga. All of them would buy Jamaica, and its Governor. But you cannot take a flota with a sloop and good intentions."],
			["mercy", "He's right, damn him. We need ships. Real ones, and men who know how to sail them."],
		],
		"choices": [
			{"t": "Buy a brigantine from Lindo (450 gold)", "need": {"gold_ge": 450}, "why": "Not enough gold in the chest",
				"hint": "A brigantine joins your flagship's fleet now.",
				"say": ["lindo", "She was a Dutch slaver once. I had her scrubbed. Twice. One gets used to the smell below."],
				"fx": [["gold", -450], ["ship", "brigantine", "Lindo's Folly"], ["flag", "bought_ship"]]},
			{"t": "Send word to the Miskito", "hint": "The Mosquito Coast hates Spain worse than you do. Their king will come to talk next turn.",
				"say": ["mercy", "Jeremy's people have fought the Spanish for a hundred years. They'll fight beside anyone who'll fight beside them."],
				"fx": [["flag", "asked_miskito"], ["sched", "miskito", 1]]},
			{"t": "Look for a ship to steal", "hint": "Every harbour has a ship whose owner is asleep. Mercy will find one.",
				"say": ["mercy", "Now you're talking like a pirate. Give me a turn."],
				"fx": [["sched", "pinos", 1], ["flag", "look_ship"]]},
		]},
	{"id": "pinos", "focus": "pinos", "act": 2, "title": "A frigate on the beach", "when": {"turn": [17, 19], "flag": "act2"},
		"lines": [
			["mercy", "A Spanish frigate lies careened at Isla de Pinos with her guns ashore and her bottom in the air, helpless as a turtle on its back. Thirty guns, Captain, for the taking."],
			["lindo", "Or thirty guns for the taking that the Armada happens to have left lying exactly where a greedy pirate would find them. I have sold a great many things in my life, Captain. Bait is one of them."],
		],
		"choices": [
			{"t": "Cut her out", "hint": "She lies off Isla de Pinos for three turns: sail at her and she is a sea battle. Half her crew is ashore. If it is a trap, you will know soon.",
				"say": ["mercy", "Boats away at midnight, muffled oars, knives in teeth. Like the old days."],
				"fx": [["spawn", "pinos", "new_spain", "pinos", [{"t": "frigate", "nm": "Santa Rosa", "h": 45, "c": 35}], 3, "hold"], ["flag", "hunt_pinos"],
					["gamble", 50, "pinos_clear", "pinos_bait"]]},
			{"t": "Sell the tip to someone else (100 gold)", "hint": "Lindo knows a buyer. 100 gold, and if it is bait, somebody else is caught in it.",
				"say": ["lindo", "A Dutchman with more guns than sense. I shall light a candle for him."],
				"fx": [["gold", 100]]},
			{"t": "Leave her", "hint": "Nothing. The crew calls it caution, then cowardice.",
				"say": ["mercy", "Aye. There'll be other ships. That's what they said about the last one too."],
				"fx": [["p", "purse", 6]]},
		]},
	{"id": "pinos_clear", "act": 2, "title": "No trap", "fx": [],
		"lines": [["mercy", "Lookouts on every headland and not a Spanish sail in sight. Lindo's getting old. She's ours if we're quick."]]},
	{"id": "pinos_bait", "act": 2, "title": "The bait", "fx": [["place", "armada", "pinos"], ["hunt", "armada"], ["actor_att", "armada", 0],
		["sched", "bait_over", 3]],
		"lines": [
			["mercy", "Topsails over Cape San Antonio. Two frigates and a sloop, under Mendoza's own pennant. Lindo was right, curse him: she was bait, and the Armada was waiting behind the island."],
			["mendoza", "My compliments, Captain. I did not think you would be so easily led. Neither did my officers. I have won a great deal of money from them."],
		]},
	{"id": "bait_over", "act": 2, "title": "The trap is sprung", "fx": [["actor_att", "armada", 30]],
		"lines": [["mercy", "The Armada's given up waiting at Pinos and gone back to its old ways. Lindo's laughing at us. Quietly, mind. He knows I carry a knife."]]},
	{"id": "pinos_taken", "act": 2, "title": "The Santa Rosa", "when": {"flag": "won_pinos"},
		"lines": [["mercy", "She's ours, keel to truck, if she's still afloat. Thirty guns, Captain. Now we're somebody."]],
		"chron": "Pirates cut out a Spanish frigate careened at Isla de Pinos.",
		"fx": [["fame", 5], ["infamy", 4], ["p", "purse", -10]]},
	{"id": "miskito", "focus": "cabo_gracias", "act": 2, "title": "The King of the Mosquito Coast", "when": {"turn": [19, 21], "flag": "act2"},
		"lines": [
			["", "A long canoe comes alongside, paddled by twenty men in red paint and English hats. In the stern sits an old man with a crown of silver wire and a Bible he cannot read."],
			["jeremy", "The Spaniard burns our towns and sells our sons in Cartagena. The English give us muskets and call me king. I like the muskets better."],
			["jeremy", "My canoes go where your ships cannot: up the rivers, over the reefs, into the lagoons. My warriors can strike a fish under the water with a harpoon. A Spaniard is easier. What will you give?"],
		],
		"choices": [
			{"t": "Muskets, powder and a red coat (200 gold)", "need": {"gold_ge": 200}, "why": "Not enough gold in the chest",
				"hint": "Two war canoes sail with you under the king's son; two companies of Miskito warriors come to Tortuga.",
				"say": ["jeremy", "A red coat! Now I am a proper king. My son goes with you. Bring him back, or bring back the Spaniards who killed him."],
				"fx": [["gold", -200], ["spawn", "miskito", "miskito", "cabo_gracias", [{"t": "war_canoe"}, {"t": "war_canoe"}], 0, "hold"],
					["join", "miskito", "Prince Oldman", 10], ["unit", "native_warriors", 2, "port_de_paix"], ["flag", "miskito_allies"]]},
			{"t": "Promise him Spanish heads", "hint": "The canoes come for nothing; the Miskito will remember what you promised, and Spain will remember who brought them.",
				"say": ["jeremy", "Heads I understand. Heads are better than gold: they do not get spent."],
				"fx": [["spawn", "miskito", "miskito", "cabo_gracias", [{"t": "war_canoe"}, {"t": "war_canoe"}], 0, "hold"],
					["join", "miskito", "Prince Oldman", 10], ["p", "heat", 6], ["flag", "miskito_allies"], ["flag", "promised_heads"]]},
			{"t": "Thank him, and send him home", "hint": "Nothing.",
				"say": ["mercy", "He'll go to the next pirate who asks. There's always a next pirate."],
				"fx": []},
		]},
	{"id": "captains_offer", "focus": "port_de_paix", "act": 2, "title": "Captains for hire", "when": {"turn": [19, 22], "flag": "act2"},
		"lines": [
			["hesketh", "Tom Hesketh, of the Ranger, brigantine, fourteen guns. I hear you're going after the flota. I hear it in every tavern on Tortuga, which you might want to think about."],
			["hesketh", "My lads will sail with you for a share of what we take. Equal shares, ship for ship, the way Vane did it. Or for gold now, if you'd rather. I'd rather."],
			["mercy", "Hesketh's honest, for a pirate. He's never left a man behind that I know of, and he only cheats at cards."],
		],
		"choices": [
			{"t": "Shares from the next prize (400 owed)", "hint": "The Ranger joins you under her own captain; 400 gold in shares owed.",
				"say": ["hesketh", "Done. Don't make me regret it. I'm a bad loser and a worse creditor."],
				"fx": [["spawn", "hesketh", "brethren", "port_de_paix", [{"t": "brigantine", "nm": "Ranger"}], 0, "hold"],
					["join", "hesketh", "Tom Hesketh", 15], ["p", "owed", 400], ["flag", "hesketh"]]},
			{"t": "Pay him now (300 gold)", "need": {"gold_ge": 300}, "why": "Not enough gold in the chest",
				"hint": "The Ranger joins you; nothing owed.",
				"say": ["hesketh", "Gold in the hand. You're a captain after my own heart, and my own purse."],
				"fx": [["gold", -300], ["spawn", "hesketh", "brethren", "port_de_paix", [{"t": "brigantine", "nm": "Ranger"}], 0, "hold"],
					["join", "hesketh", "Tom Hesketh", 15], ["flag", "hesketh"]]},
			{"t": "Sail alone", "hint": "Nothing shared, nothing gained.",
				"say": ["hesketh", "Suit yourself. I'll drink to your memory."],
				"fx": []},
		]},
	{"id": "flota_gathers", "focus": "havana", "act": 2, "title": "The flota at Havana", "when": {"turn": [18, 27], "flota": 1, "flag": "act2"},
		"lines": [
			["", "Havana. The galleons come in one by one from Veracruz and Cartagena and Portobelo, low in the water, and lie under the guns of El Morro while the escorts water and the priests bless everything that floats."],
			["mercy", "There she is, Captain. The flota. Every man in the crew has dreamed of this since he was a boy. Most of them also dreamed of being eaten by sea monsters, so mind how much you listen."],
			["vane", "Never take on the flota whole. Pick off the one that falls behind. If you must fight the escorts, fight them to windward, and fight them once."],
		],
		"fx": [["flag", "flota_seen"]],
		"choices": [
			{"t": "Hunt the flota", "hint": "Sail at the treasure fleet (marked on the map): close with it and it is a sea battle. You will need every ship you have.",
				"say": ["mercy", "All hands! Tell the crew there's silver in it. Don't tell them how much iron."],
				"fx": [["flag", "hunt_flota"]]},
			{"t": "Shadow it for a straggler", "hint": "A gamble: one galleon may fall behind in the straits. If she does, she is alone for three turns.",
				"say": ["mercy", "Patience. The pirate's least favourite virtue."],
				"fx": [["gamble", 55, "straggler_found", "straggler_none"]]},
			{"t": "Let it go: too strong", "hint": "Nothing gained. The crew remembers what you didn't try.",
				"say": ["mercy", "Maybe next year. Every year it's maybe next year."],
				"fx": [["p", "purse", 12]]},
		]},
	{"id": "tip_flota", "act": 2, "title": "Vane's logbook: the flota", "tip": 1, "when": {"flota": 1, "flag": "act2"},
		"lines": [
			["vane", "Twice a year the King of Spain's silver comes up from the Main and down from Mexico, gathers at Havana, and goes home through the Florida straits. It is the richest prize in the world, and the best defended."],
			["", "The flota's galleons gather at Havana, wait for the others, then sail north for the straits and off the map. Each carries treasure; the capitana carries the most. More infamous pirates mean more escorts."],
		]},
	{"id": "straggler_found", "focus": "straggler", "act": 2, "title": "A straggler", "fx": [["spawn", "straggler", "new_spain", "straits",
		[{"t": "galleon", "nm": "Santisima Trinidad", "h": 55, "c": 40, "g": 600}], 3, "hold"], ["flag", "hunt_straggler"]],
		"lines": [["mercy", "One of them's sprung her foremast and fallen behind in the straits, and the escort never even looked back. A galleon, Captain, alone. Three days, maybe four, before they come back for her."]]},
	{"id": "straggler_none", "act": 2, "title": "No straggler",
		"lines": [["mercy", "They kept station like soldiers on parade. Mendoza's had a word with their captains, I'll wager. Nothing for us."]],
		"fx": [["p", "purse", 6]]},
	{"id": "straggler_taken", "act": 2, "title": "The Santisima Trinidad", "when": {"flag": "won_straggler"},
		"lines": [["mercy", "Six hundred in silver, a hold full of cochineal and a bishop's nephew who weeps when he's spoken to. Best day's work since the hanging."]],
		"chron": "Pirates took a straggling galleon of the flota in the Florida straits.",
		"fx": [["p", "purse", -20], ["fame", 6], ["infamy", 6], ["p", "heat", 6]]},
	{"id": "flota_taken", "focus": "flagship", "act": 2, "title": "The flota is ours", "when": {"flag": "won_flota"},
		"lines": [
			["mercy", "Silver, Captain. Silver in bars like firewood, in chests that four men can't lift, in the captain's cabin and the bilges and the hollow of the mainmast. The crew are dancing on it."],
			["mercy", "Mendoza will never forgive this. Not the silver. The shame. Spain will want somebody's head on a pike for it, and every man here knows whose."],
		],
		"chron": "Pirates fell on the Spanish treasure fleet and took its silver.",
		"fx": [["fame", 10], ["infamy", 8], ["p", "heat", 15], ["p", "purse", -25], ["p", "favour", 5], ["flag", "flota_taken"],
			["actor_add", "armada", [{"t": "frigate", "nm": "San Jose"}]], ["sched", "mendoza_vow", 1]]},
	{"id": "flota_beaten", "act": 2, "title": "The escorts", "when": {"flag": "lost_flota"},
		"lines": [["mercy", "The escorts were waiting for us, and they knew their business. We got out with our lives and not much else. Vane said fight them once. He didn't say we had to lose."]],
		"fx": [["p", "purse", 10], ["unflag", "hunt_flota"]]},
	{"id": "flota_gone", "act": 2, "title": "The flota sails", "when": {"flag": "flota_seen", "noflag": ["won_flota", "lost_flota"], "noflota": 1},
		"lines": [["mercy", "The flota's through the straits and gone for Seville, every galleon of it. That silver will be cannon in Flanders by Christmas. The crew don't say anything. They don't have to."]],
		"fx": [["p", "purse", 8], ["unflag", "hunt_flota"]]},
	{"id": "mendoza_vow", "focus": "armada", "act": 2, "title": "A second letter", "fx": [["actor_att", "armada", 20]],
		"lines": [
			["mendoza", "Captain. You have robbed my King, and that I could forgive: kings are robbed every day. But you did it under my eyes, in my waters, and men I have known twenty years are dead of it."],
			["mendoza", "I will find you. Not today, perhaps, nor this year. But I have nothing else to do now, and I am a very patient man. R. de M."],
		]},
	{"id": "armada_blockade", "focus": "port_de_paix", "act": 2, "title": "The Armada off Tortuga",
		"when": {"turn": [18, 40], "flag": "act2", "att_ge": 40, "owns": "port_de_paix", "actor": ["armada", "alive"]}, "every": 8,
		"fx": [["blockade", "armada", "port_de_paix", 3], ["p", "haven", -10]],
		"lines": [
			["", "The Armada de Barlovento stands in for Tortuga road and anchors there, out of range of the fort, as if it had all the time in the world. Nothing goes in. Nothing comes out."],
			["mercy", "A blockade. They'll starve the town of trade and wait for us to come out. Or for the town to hand us over. I don't know which they'd prefer."],
		],
		"choices": [
			{"t": "Break it: attack them now", "hint": "Your flagship's fleet fights the Armada now, whatever the odds.",
				"say": ["mercy", "Every man to his gun. If we're going to die, let's do it in front of Tortuga where they can see it."],
				"fx": [["sea_battle", "armada", "blockade"]]},
			{"t": "Wait behind the fort's guns", "hint": "The Armada stays three turns, cutting Tortuga's trade. The town grumbles.",
				"say": ["mercy", "We wait. The town won't like it. Towns never like it."],
				"fx": [["p", "haven", -5]]},
			{"t": "Bribe a Spanish captain to look away (200 gold)", "need": {"gold_ge": 200}, "why": "Not enough gold in the chest",
				"hint": "The blockade has a gap in it, and Spain's grudge cools a little.",
				"say": ["lindo", "Every Armada has one captain who has not been paid since Lent. I know his name. It is a very expensive name."],
				"fx": [["gold", -200], ["p", "heat", -5], ["p", "haven", 5], ["hunt", "armada"]]},
		]},
	{"id": "tip_blockade", "act": 2, "title": "Vane's logbook: blockades", "tip": 1, "when": {"blockaded": 1, "flag": "act1"},
		"lines": [
			["vane", "A port is only as rich as the ships that come into it. Lie off a harbour with more guns than it can answer and you starve it of trade without firing a shot. That works both ways, mind."],
			["", "A port is blockaded when an enemy fleet stronger than its defenders' lies within 3 cells of its harbour at the end of a turn: its owner loses most of its sea trade and the blockader takes a share. Beat the fleet, or outnumber it, to lift it."],
		]},
	{"id": "won_blockade", "act": 2, "title": "The blockade broken", "when": {"flag": "won_blockade"}, "every": 1,
		"lines": [["mercy", "They're running for Havana with their tails between their legs! Tortuga saw it all from the walls. You'll never pay for a drink in this town again."]],
		"chron": "The pirates of Tortuga broke a Spanish blockade.",
		"fx": [["fame", 8], ["p", "haven", 20], ["p", "purse", -10], ["home", "armada"], ["unflag", "won_blockade"]]},
	{"id": "lost_blockade", "act": 2, "title": "Beaten back", "when": {"flag": "lost_blockade"}, "every": 1,
		"lines": [["mercy", "They beat us back into the harbour. The town saw that too."]],
		"fx": [["p", "haven", -10], ["p", "purse", 8], ["unflag", "lost_blockade"]]},
	{"id": "tip_seafight", "act": 2, "title": "Vane's logbook: a fight at sea", "tip": 1, "when": {"sea_pending": 1, "flag": "act2"},
		"lines": [
			["vane", "A sea fight is decided before the first gun: by who has the wind, who has the guns, and whose crew wants it more. Get the weather gauge, rake her stern, and board when she is sick of it."],
			["", "A sea battle can be fought in real time (you sail and fire your own ships, with the wind) or resolved at once. Fought, a smaller fleet with the wind and a good captain can beat a bigger one."],
		]},
	{"id": "treaty", "focus": "port_royal", "act": 2, "title": "The Treaty of Madrid", "when": {"turn": [22, 23], "flag": "act2"},
		"lines": [
			["", "News from Europe, three months old and already too late: at Madrid the ambassadors of England and Spain have signed a treaty of peace and friendship in the Indies. Every commission against Spain is revoked."],
			["ashby", "BY THE GOVERNOR. A PROCLAMATION. Whereas peace is concluded between His Majesty and the Catholic King, all persons whatsoever who shall henceforth commit any act of hostility against the subjects of Spain shall be deemed pirates and enemies of mankind."],
			["ashby", "And whereas a certain captain, late of the sloop of Josiah Vane, has done such acts, a reward of two thousand pieces of eight is offered for his body, quick or dead. God save the King."],
			["mercy", "The ink wasn't dry on our letter. Port Royal's shut to us, Captain, and every Englishman with a boat just became a bounty hunter. Kings make friends. Vane said it. I didn't believe him."],
		],
		"chron": "England and Spain made peace at Madrid. Every commission against Spain was revoked, and Port Royal turned on its pirates.",
		"fx": [["dip2", "england", "new_spain", "peace"], ["dip2", "england", "tierra_firme", "peace"], ["unmarque", "england"],
			["dip", "england", "war"], ["p", "favour", -100], ["flag", "treaty"], ["actor_att", "armada", 20],
			["actor_add", "armada", [{"t": "sloop", "nm": "Santo Cristo"}]], ["sched", "price", 1], ["sched", "lindo_test", 1]]},
	{"id": "escape", "focus": "port_royal", "act": 2, "title": "Run the gauntlet", "when": {"flag": "treaty", "turn": [22, 24], "near": ["port_royal", 6]},
		"lines": [
			["", "Port Royal. The chain is up across the harbour mouth, the fort's guns are run out, and His Majesty's frigate Assurance, half her crew still ashore, is warping across the channel to close it."],
			["mercy", "They mean to take us at anchor, Captain! We have the land breeze for another hour. After that we're dead men or prisoners, which is the same thing slower."],
		],
		"fx": [["spawn", "royal", "england", "port_royal", [{"t": "frigate", "nm": "HMS Assurance", "h": 70, "c": 45}], 4, "hold", "port_royal"]],
		"choices": [
			{"t": "Run the gauntlet past the fort", "hint": "The fort's guns rake you as you pass, then the frigates: a sea battle now, hull battered before it starts.",
				"say": ["mercy", "Cut the cables! All sail! Lie flat on the deck when we pass the fort, and pray they aim like Englishmen."],
				"fx": [["hull", -15], ["sea_battle", "royal", "escape"]]},
			{"t": "Cut the cables and slip out in the dark", "hint": "A gamble: in the dark, past the chain, with no lights. If they see you, they fight you at the harbour mouth.",
				"say": ["mercy", "Not a word, not a light, not a lit pipe. Any man who sneezes goes over the side."],
				"fx": [["gamble_fame", 40, "escape_clean", "escape_caught"]]},
		]},
	{"id": "escape_clean", "act": 2, "title": "Out in the dark",
		"lines": [["mercy", "We were past the chain before the watch on the fort woke up. They fired at shadows for an hour. One day the crew will tell that story and the chain will be a mile long."]],
		"fx": [["fame", 5], ["voyage", ["player", 12, 0]], ["remove", "royal"]]},
	{"id": "escape_caught", "act": 2, "title": "Seen",
		"lines": [["mercy", "A sentry with good eyes and a lantern. Here they come!"]],
		"fx": [["hull", -10], ["sea_battle", "royal", "escape"]]},
	{"id": "escaped", "act": 2, "title": "Clear of Port Royal", "when": {"flag": "won_escape"},
		"lines": [["mercy", "We're through! The Assurance is aground on the Rackham Cay with her foremast over the side. Ashby will be eating his wig."]],
		"chron": "A pirate captain fought his way out of Port Royal under the guns of the fort.",
		"fx": [["fame", 8], ["p", "purse", -10], ["remove", "royal"]]},
	{"id": "not_escaped", "act": 2, "title": "Beaten in the channel", "when": {"flag": "lost_escape"},
		"lines": [["mercy", "They mauled us in the channel and we only got out because the tide turned. Count the dead later, Captain. Sail now."]],
		"fx": [["p", "purse", 10], ["remove", "royal"]]},
	{"id": "price", "focus": "hunters", "act": 2, "title": "A price on your head",
		"fx": [["spawn", "hunters", "england", "port_royal", [{"t": "frigate", "nm": "HMS Oxford", "h": 80, "c": 70}], 6, "chase", "port_royal"], ["until", "hunters", 4]],
		"lines": [
			["ashby", "To Captain Thomas Whetstone of His Majesty's frigate Oxford. Sir: you will take, sink or destroy the pirate described in the enclosed proclamation, and bring me his head in a cask of rum. Keep the rum."],
			["mercy", "Ashby's sent the Oxford after us. A King's frigate, with a crew of Port Royal men who drank with us at the Sign of the Mermaid. They know all our anchorages, Captain."],
		]},
	{"id": "lindo_test", "act": 2, "title": "Lindo's loyalty",
		"lines": [
			["lindo", "My dear Captain. Sir Thomas asked me this morning, over a very good Madeira, where you careen and where you water and which of your men drink too much. I told him nothing. Yet."],
			["lindo", "I am a businessman. Ashby can make me rich, or hang me; you can only make me rich. I find myself torn. Do help me decide."],
			["mercy", "He's selling us, Captain, and asking us to bid. That's Lindo all over. I'd cut his throat, but he's the only man in the Caribbean who can sell what we take."],
		],
		"choices": [
			{"t": "Outbid the Governor (250 gold)", "need": {"gold_ge": 250}, "why": "Not enough gold in the chest",
				"hint": "Lindo stays yours: his fence and his tongue.",
				"say": ["lindo", "There, you see? Nobody had to be hanged. I do so prefer it when nobody has to be hanged."],
				"fx": [["gold", -250], ["flag", "lindo_loyal"], ["timer", "lindo", 10]]},
			{"t": "Trust him: he never lied to Vane", "hint": "A gamble on a fence's heart. Better if you once paid Vane's debt to him, worse if you burned his letter.",
				"say": ["mercy", "Vane trusted him. Vane's dead. I'm only saying."],
				"fx": [["gamble", 55, "lindo_true", "lindo_false"]]},
			{"t": "Cut him off: he is Ashby's man", "hint": "No more fence. Lindo will tell Ashby what he knows, and he knows Tortuga.",
				"say": ["mercy", "Good. I'll sleep better. Tortuga won't."],
				"fx": [["flag", "lindo_gone"], ["p", "haven", -10], ["p", "heat", 5]]},
		]},
	{"id": "lindo_true", "act": 2, "title": "A fence's word",
		"lines": [["lindo", "You trusted me! How very unwise of you, and how very touching. I find I cannot sell a man who trusts me. It is a weakness. Please do not tell anyone."]],
		"fx": [["flag", "lindo_loyal"], ["timer", "lindo", 10]]},
	{"id": "lindo_false", "act": 2, "title": "Sold",
		"lines": [
			["mercy", "Lindo sold us. Ashby's men were waiting at our watering place on the Ile-a-Vache, and the Navy knows every rock of Tortuga road now. I should have cut his throat when I had the chance."],
		],
		"fx": [["flag", "lindo_gone"], ["flag", "lindo_sold"], ["p", "haven", -20], ["crew", -10]]},
	{"id": "boucher_cruelty", "act": 2, "title": "What Le Boucher did", "when": {"turn": [24, 27], "capt": "boucher"},
		"lines": [
			["", "Le Boucher's crews took a little Spanish town on the coast of Cuba while you were watering. When you came up, the church was burning with the townsfolk inside it."],
			["boucher", "They would not say where the silver was. Now they will never say anything. Do not look at me like that, mon ami: the Spanish do worse to us, and nobody calls them butchers."],
			["mercy", "This is the man whose flag flies next to ours, Captain. The crew sees it. Spain sees it. God sees it, if He's looking."],
		],
		"choices": [
			{"t": "Look away", "hint": "He stays. Infamy, Spain's grudge, and a crew that knows what you will put up with.",
				"say": ["boucher", "Bon. You are learning."],
				"fx": [["infamy", 6], ["p", "heat", 8], ["flag", "boucher_kept"]]},
			{"t": "Rebuke him before the crews", "hint": "A gamble, better the more famous you are: he backs down, or he sulks and remembers.",
				"say": ["mercy", "In front of everyone? You've got stones, Captain. Let's hope they're bigger than his."],
				"fx": [["gamble_fame", 35, "boucher_cowed", "boucher_sulks"]]},
			{"t": "Cast him out of the Brethren", "hint": "His ships and his men leave you, and he goes over to whoever pays. You have made an enemy who knows all your secrets.",
				"say": ["boucher", "You cast me out? Me? You will see me again, Vane's boy. I promise you that."],
				"fx": [["desert", "boucher", "new_spain"], ["goal", "boucher", "lair"], ["flag", "boucher_cast"], ["p", "favour", 5], ["infamy", -4]]},
		]},
	{"id": "boucher_cowed", "act": 2, "title": "Le Boucher backs down",
		"lines": [["boucher", "...As you wish, Captain. Prisoners will be ransomed, churches will be robbed in the proper way. You have made your point. I will remember who made it."]],
		"fx": [["fame", 5], ["flag", "boucher_cowed"]]},
	{"id": "boucher_sulks", "act": 2, "title": "Le Boucher laughs",
		"lines": [["boucher", "Ha! Did you hear that, mes enfants? The little captain has a conscience. Let us see how long it keeps him warm."]],
		"fx": [["p", "purse", 8], ["flag", "boucher_kept"]]},
	{"id": "boucher_rival", "focus": "boucher", "act": 2, "title": "Le Boucher's way", "when": {"turn": [24, 27], "actor": ["boucher", "alive"], "noflag": "joined_boucher"},
		"lines": [
			["", "Le Boucher has been busy: a Spanish town on the coast of Cuba burned with its people in the church, and a prize you were stalking off Cabo Cruz taken from under your bowsprit."],
			["boucher", "Vane's boy! You were too slow. You are always too slow. That is why your captain hangs and I drink."],
			["mercy", "Every Spaniard he burns, they'll hang one of ours for. We could tell Mendoza where he careens. It would be a filthy thing to do. It might also be the smartest thing we ever did."],
		],
		"choices": [
			{"t": "Hunt him down", "hint": "Close with his fleet and it is a sea battle.",
				"say": ["mercy", "Good. Some men need killing. He's most of them."],
				"fx": [["flag", "hunt_boucher"], ["flag", "hunt_boucher2"], ["unflag", "won_boucher"], ["unflag", "lost_boucher"]]},
			{"t": "Sell his careening place to Mendoza", "hint": "The Armada mauls Le Boucher and Spain's grudge against you cools. A Brother sold to Spain: the Brethren will hear of it.",
				"say": ["mendoza", "I accept your information, Captain, with thanks and without respect. Do not imagine this changes anything between us."],
				"fx": [["actor_hull", "boucher", 50, 50], ["p", "heat", -12], ["flag", "sold_boucher"], ["p", "haven", -5]]},
			{"t": "Let him be", "hint": "Nothing.",
				"say": ["mercy", "He won't let us be, Captain. Men like him never do."],
				"fx": []},
		]},
	{"id": "boucher_hunted", "act": 2, "title": "Le Boucher's ships taken", "when": {"flag": ["won_boucher", "hunt_boucher2"], "turn": [23, 29]},
		"lines": [["mercy", "We took his ships, Captain! He went over the side again with a knife in his teeth. That man's harder to kill than a cockroach in a biscuit."]],
		"chron": "Le Boucher's ships were taken by a rival pirate.",
		"fx": [["fame", 8], ["p", "purse", -10], ["unflag", "hunt_boucher"]]},
	{"id": "boucher_slipped", "act": 2, "title": "He got away again", "when": {"flag": ["lost_boucher", "hunt_boucher2"], "turn": [23, 29]},
		"lines": [["boucher", "Again, Vane's boy? You never learn. I like that in an enemy."]],
		"fx": [["p", "purse", 8], ["unflag", "hunt_boucher"]]},
	{"id": "armada_grows", "focus": "armada", "act": 2, "title": "Mendoza's ships", "when": {"turn": [25, 27], "flag": "act2", "actor": ["armada", "alive"]},
		"lines": [
			["", "Word from Havana: Mendoza has had the Armada's officers flogged for their failures. He flogged himself as well, they say, in his cabin, every night for a week. Then he put to sea again."],
			["mercy", "He's serious now, Captain. He hunts at the faintest rumour of us."],
		],
		"fx": [["actor_att", "armada", 20]]},
	{"id": "act2_end", "act": 2, "title": "End of Act Two", "when": {"turn": [29, -1], "flag": "act2"},
		"lines": [
			["mercy", "A price on your head in Port Royal, the Armada in Havana, half the Brethren drunk on what we took and the other half waiting to see if you'll hang. That's where we are, Captain."],
			["mercy", "And there's something you should read. Vane's logbook. The last pages, the ones he wrote the night before they hanged him. I've had them sewn into my coat for three years. It's time."],
		],
		"fx": [["act", 3], ["flag", "act2_done"]]},
	# ---------------------------------------------------------------- act 3 ---
	{"id": "act3", "act": 3, "title": "Act Three: The Free Port", "when": {"turn": [30, -1], "flag": "act2_done"},
		"lines": [["", "Tortuga, the year the Brethren decided what they were."]],
		"fx": [["act", 3], ["unflag", "hunt_boucher"]]},
	{"id": "vane_pages", "focus": "port_de_paix", "act": 3, "title": "The last pages", "when": {"turn": [30, 32], "flag": "act3"},
		"lines": [
			["vane", "They will hang me in the morning. I find I mind less than I thought. What I mind is that all of it, every prize, every town, every man I ever buried at sea, was for rum and nothing."],
			["vane", "There is a better thing. A free port, where no flag but ours flies. Fortified, so the kings cannot take it. With a fleet, so the kings dare not try. With gold enough that the Dutch and the French will trade with it, and a thing that trades is a thing that is recognised. A republic of the Brethren. They did it at Sale. We could do it at Tortuga."],
			["vane", "Tell whoever comes after me: hold it, arm it, pay for it. Then let Mendoza come."],
			["mercy", "That's it, Captain. That's what he died wanting. The question is whether you want it too."],
		],
		"chron": "Pirates at Tortuga spoke of a free port: a republic of the Brethren of the Coast.",
		"fx": [["free_port"], ["flag", "goal"], ["sched", "tip_goal", 0], ["sched", "lindo_plan", 1], ["sched", "mercy_plan", 1]],
		"choices": [
			{"t": "Raise the walls with gold (600 gold)", "need": {"gold_ge": 600, "owns": "port_de_paix"}, "why": "Not enough gold in the chest, or Tortuga is not ours",
				"hint": "Masons from Saint-Domingue: Tortuga's walls rise to stone bastions now.",
				"say": ["mercy", "Stone, by God. Vane would weep."],
				"fx": [["gold", -600], ["build", "port_de_paix", "walls", 2], ["p", "haven", 10]]},
			{"t": "Every hand to the walls", "need": {"owns": "port_de_paix"}, "why": "Tortuga is not ours",
				"hint": "The crew builds them themselves: the walls stand in two turns. They will grumble the whole time.",
				"say": ["mercy", "Pirates hauling stone. I never thought I'd see it. Neither did they."],
				"fx": [["p", "purse", 15], ["sched", "walls_done", 2]]},
			{"t": "Rum and nothing suits us fine", "hint": "The goal stands; nothing more for now. Mercy says nothing. Loudly.",
				"say": ["mercy", "...Aye, Captain."],
				"fx": [["p", "purse", -5]]},
		]},
	{"id": "walls_done", "act": 3, "title": "The walls stand", "if": {"owns": "port_de_paix"},
		"lines": [["mercy", "Stone walls and a bastion on the point, built by the worst masons in Christendom. They'll hold. Probably."]],
		"fx": [["build", "port_de_paix", "walls", 2], ["p", "haven", 10]]},
	{"id": "tip_goal", "act": 3, "title": "Vane's logbook: the free port", "tip": 1,
		"lines": [
			["", "The free port has three parts (the Port gauge, top left; tap it for the details): hold Tortuga with stone walls (walls 2) for 5 turns, unblockaded and unbesieged; a fleet with at least 60 % of the Armada's power; and 1500 gold in the chest (plunder taken from now on counts). Mendoza will come for it before the end. Each part you have then makes the last fight easier."],
		]},
	{"id": "lindo_plan", "act": 3, "title": "Lindo's arithmetic", "if": {"flag": "lindo_loyal"},
		"lines": [
			["lindo", "A republic! How wonderfully impractical. Let me tell you how it is done. The Dutch at Curacao and the French at Petit-Goave will recognise anyone who pays his bills in silver and can keep his harbour open. Fifteen hundred pieces of eight would be a respectable bill."],
			["lindo", "And a good wall, and enough ships that Mendoza must think twice. Recognition is a matter of looking like a country, Captain. Countries are only pirates who stayed."],
		]},
	{"id": "mercy_plan", "act": 3, "title": "Mercy's arithmetic", "if": {"noflag": "lindo_loyal"},
		"lines": [["mercy", "I've no head for figures, Captain, but I asked around. A wall that'll stand a siege, enough ships to make the Armada think twice, and silver enough that the Dutch will sell to us. Fifteen hundred pieces of eight, the Dutch factor at Curacao says, and he's honest, for a Dutchman."]]},
	{"id": "haven_retake", "focus": "port_de_paix", "act": 2, "title": "Tortuga in other hands", "when": {"flag": "act1_done", "lost": "port_de_paix", "near": ["port_de_paix", 5]}, "every": 4,
		"lines": [["mercy", "There's Tortuga, and there's somebody else's flag over the fort. A pirate without a haven is a wolf without a den, Captain. We take it back."]],
		"choices": [
			{"t": "Storm it", "hint": "A landing party of the crews and everyone aboard goes over the wall now: a land battle.",
				"say": ["mercy", "Grapnels and ladders. Same as Vane did it in fifty-eight."],
				"fx": [["assault", "port_de_paix", ["cutlass", "cutlass", "buccaneers", "buccaneers", "buccaneers", "musketeers"], "retake"]]},
			{"t": "Not yet", "hint": "Nothing.", "say": ["mercy", "We'll come back with more."], "fx": []},
		]},
	{"id": "retaken", "act": 2, "title": "Tortuga is ours again", "when": {"flag": "won_retake"},
		"lines": [["mercy", "The black flag's back over the fort. Now let's keep it there."]],
		"fx": [["fame", 5], ["unflag", "won_retake"]]},
	{"id": "boucher_back", "focus": "boucher", "act": 3, "title": "Le Boucher returns", "when": {"turn": [31, 33], "flag": "act3", "actor": ["boucher", "gone"], "noflag": ["joined_boucher", "boucher_dead"]},
		"fx": [["spawn", "boucher", "france", [-7290, 2018], [{"t": "frigate", "nm": "La Revanche"}, {"t": "brigantine"}], 0, "hold"], ["unflag", "won_boucher"],
			["unflag", "lost_boucher"]],
		"lines": [
			["", "A black frigate comes into Tortuga road, a brigantine in her wake, with a familiar figure on the quarterdeck: thinner, burned brown, with a new scar from ear to chin."],
			["boucher", "Vane's boy! Did you think the sea would keep me? The sea spat me out. Even the sea has taste. I hear you want to be a king now. Kings need executioners. I am available."],
		]},
	{"id": "boucher_betrays", "focus": "boucher", "act": 3, "title": "Le Boucher turns his coat", "when": {"turn": [31, 33], "flag": "act3", "capt": "boucher", "noflag": "boucher_cowed"},
		"fx": [["desert", "boucher", "new_spain"], ["p", "heat", 12], ["flag", "boucher_traitor"]],
		"lines": [
			["", "In the night Le Boucher's ships cut their cables and slip out of Tortuga road. In the morning a letter is found nailed to the church door."],
			["boucher", "Mon ami: the Spanish pay better than you, and they do not lecture. Don Rodrigo was most interested in your walls, your guns and your fine republic. I told him everything. Until we meet. N."],
			["mercy", "We should have hanged him at the Ile-a-Vache. I said so. I'll say it at your funeral too."],
		]},
	{"id": "council", "focus": "port_de_paix", "act": 3, "title": "The Brethren in council", "when": {"turn": [33, 35], "flag": "goal"},
		"lines": [
			["", "The great room of the Sign of the Pig and Whistle, Tortuga. Forty captains, a hundred quartermasters, three barrels of rum and one table, which has been fought over twice since noon."],
			["hesketh", "A republic? Laws, and courts, and taxes? I went on the account to get away from all that."],
			["mercy", "The captains have to agree, Captain. A free port's only free if the Brethren hold it. Talk them round, buy them, or show them who's strongest. They respect all three. The third one most."],
		],
		"choices": [
			{"t": "Make them a speech", "hint": "A gamble, better the more famous you are: they follow you, or the council splits and half of them sail away.",
				"say": ["mercy", "Stand on the table. They like it when you stand on the table."],
				"fx": [["gamble_fame", 30, "council_won", "council_split"]]},
			{"t": "Buy their votes (600 gold)", "need": {"gold_ge": 600}, "why": "Not enough gold in the chest",
				"hint": "Rum, shares and a little silver in the right hands. They follow you.",
				"say": ["mercy", "A republic bought and paid for. Like every other one, I suppose."],
				"fx": [["gold", -600], ["sched", "council_won", 0]]},
			{"t": "Call out Le Boucher before them all", "need": {"actor": ["boucher", "alive"]}, "why": "Le Boucher is not here to beat",
				"hint": "Your flagship fights Le Boucher's ships now, in Tortuga road, with the Brethren watching. Win and they are yours.",
				"say": ["boucher", "At last! In front of everyone. You do me too much honour, Vane's boy. I shall return it with interest."],
				"fx": [["sea_battle", "boucher", "duel"], ["flag", "duel"]]},
		]},
	{"id": "council_won", "act": 3, "title": "The Brethren follow you",
		"lines": [
			["hesketh", "Well. I came for the rum and I'm leaving with a country. My Ranger's yours, and my lads, and God help us all."],
			["mercy", "They're cheering you in the street, Captain. Tomorrow they'll be complaining about the taxes. That's how you know it's a real country."],
		],
		"chron": "The Brethren of the Coast in council at Tortuga chose one captain to lead them.",
		"fx": [["spawn", "council", "brethren", "port_de_paix", [{"t": "brigantine", "nm": "Revenge"}, {"t": "sloop", "nm": "Swift"}], 0, "hold"],
			["join", "council", "Black Ned Corbin", 20], ["unit", "cutlass", 2, "port_de_paix"], ["unit", "buccaneers", 2, "port_de_paix"],
			["fame", 6], ["flag", "council_won"]]},
	{"id": "council_split", "act": 3, "title": "The council splits",
		"lines": [
			["mercy", "They walked out, Captain. Half of them. Took their ships and their men and their rum, and some of them are saying Le Boucher's way is better. The rest are here, for now."],
		],
		"fx": [["p", "haven", -15], ["unit", "cutlass", 1, "port_de_paix"], ["actor_add", "boucher", [{"t": "sloop"}]], ["flag", "council_split"]]},
	{"id": "duel_won", "act": 3, "title": "The Butcher's last fight", "when": {"flag": "won_duel"},
		"lines": [
			["", "Le Boucher's flagship strikes in Tortuga road in front of the whole Brethren. They bring him to you in chains, laughing."],
			["boucher", "Well fought, Vane's boy. Hang me high, so they can all see. I always wanted an audience."],
			["mercy", "We hanged him at low tide, at Gallows Point, Tortuga. So the crabs could have him. Vane would have liked that."],
		],
		"chron": "Le Boucher was beaten in Tortuga road before the assembled Brethren and hanged.",
		"fx": [["fame", 10], ["flag", "boucher_dead"], ["remove", "boucher"], ["sched", "council_won", 0], ["p", "heat", -5]]},
	{"id": "duel_lost", "act": 3, "title": "Beaten before them all", "when": {"flag": "lost_duel"},
		"lines": [["boucher", "Ha! Look at your little republic, mes amis. It cannot even win a fight in its own harbour. Who sails with me?"]],
		"fx": [["sched", "council_split", 0], ["p", "purse", 10]]},
	{"id": "great_raid", "act": 3, "title": "The great raid", "when": {"turn": [34, 36], "flag": "goal"},
		"lines": [
			["mercy", "The chest's not filling itself, Captain, and the Dutch won't recognise a republic of beggars. We need one great raid. Morgan-sized. Bigger."],
			["lindo", "Cartagena: the richest city on the Main, behind walls a mile round and forts on every point. Or Portobelo: a pestilent little town where the silver of Peru waits for the galleons, with three castles and a garrison of fever. Cartagena would fill the chest to the brim; Portobelo most of the way. Either might fill a graveyard."],
			["vane", "A town is taken in the first hour or not at all. Go in at dawn, through the side they think is safe, and do not stop to loot until the fort is yours."],
		],
		"choices": [
			{"t": "Cartagena", "hint": "Sail for Cartagena (marked on the map). Off its harbour, choose how to go in: a land battle against its walls and forts.",
				"say": ["mercy", "The Queen of the Indies. If we're going to hang, let's hang for something worth it."],
				"fx": [["flag", "raid_cartagena"], ["voyage_r", "cartagena"], ["sched", "tip_forts", 0]]},
			{"t": "Portobelo", "hint": "Sail for Portobelo (marked on the map). Off its harbour, choose how to go in: a land battle against its castles.",
				"say": ["mercy", "Morgan took it with four hundred men and a bad attitude. We've got both."],
				"fx": [["flag", "raid_portobelo"], ["voyage_r", "portobelo"], ["sched", "tip_forts", 0]]},
			{"t": "No: small prizes, many of them", "hint": "No great raid. The chest fills only as fast as you take prizes.",
				"say": ["mercy", "Slow and steady. Never knew a pirate get rich that way. Never knew one get hanged that way either."],
				"fx": [["flag", "no_raid"]]},
		]},
	{"id": "tip_forts", "act": 3, "title": "Vane's logbook: walls and forts", "tip": 1,
		"lines": [
			["vane", "A walled town fights twice: once at the wall and again in the streets. The forts sweep the beaches and the harbour; the streets are narrow and every window is a loophole. Land where the guns cannot reach, take the wall by surprise, and keep your men together in the streets or they will be killed one house at a time."],
			["", "Storming a settlement is a land battle: the attackers come over the walls (ladders) or through a breach while the defenders hold the walls, gates and towers; inside, it is street fighting. Higher walls give the defenders more height and more men."],
		]},
	{"id": "raid_cartagena_at", "focus": "cartagena", "act": 3, "title": "Off Cartagena", "when": {"flag": "raid_cartagena", "noflag": "raided", "near": ["cartagena", 5]},
		"lines": [
			["", "Cartagena de Indias at dawn: the forts of Bocachica on the channel, the walls of the city gold in the sunrise, the bells ringing for matins. Nobody on the walls looks out to sea."],
			["mercy", "There she is. We go in now, or we go home and tell lies about it for the rest of our lives."],
		],
		"choices": [
			{"t": "Storm the city",
				"hint": "At dawn, by surprise (a quarter of the defenders are caught asleep): everyone aboard your ships off the harbour and six companies of the Brethren go over the wall now. A land battle.",
				"say": ["mercy", "Ladders! Grapnels! Follow the Captain and don't stop for anything shiny!"],
				"fx": [["flag", "raided"], ["weaken", "cartagena", 25], ["assault", "cartagena", ["cutlass", "cutlass", "buccaneers", "buccaneers", "buccaneers", "musketeers"], "cartagena"]]},
			{"t": "Bribe a gate open first (300 gold)", "need": {"gold_ge": 300}, "why": "Not enough gold in the chest",
				"hint": "A sergeant of the garrison opens a postern at night: half the defenders are caught asleep and the walls count a level lower. Then the same assault.",
				"say": ["lindo", "Every city has a sergeant who has not been paid. Cartagena has several hundred. I need only one."],
				"fx": [["gold", -300], ["flag", "raided"], ["weaken", "cartagena", 50], ["slight", "cartagena", 1], ["assault", "cartagena", ["cutlass", "cutlass", "buccaneers", "buccaneers", "buccaneers", "musketeers"], "cartagena"]]},
			{"t": "Turn back", "hint": "No raid. The crew will not forget the sight of those walls.",
				"say": ["mercy", "...Aye. Bring her about."],
				"fx": [["flag", "raided"], ["p", "purse", 10]]},
		]},
	{"id": "raid_portobelo_at", "focus": "portobelo", "act": 3, "title": "Off Portobelo", "when": {"flag": "raid_portobelo", "noflag": "raided", "near": ["portobelo", 5]},
		"lines": [
			["", "Portobelo: a wet green bay, three castles, a customs house with the King's silver in it, and a town of fever and sweat that empties into the hills when it sees a pirate sail."],
			["mercy", "Morgan went over the walls of the Santiago castle with the nuns and the friars carrying his ladders in front of him. We needn't go that far. Unless we must."],
		],
		"choices": [
			{"t": "Storm the town", "hint": "Everyone aboard your ships off the harbour and a landing party of the crews go over the wall now: a land battle.",
				"say": ["mercy", "Ladders! And somebody find me a friar."],
				"fx": [["flag", "raided"], ["weaken", "portobelo", 25], ["assault", "portobelo", ["cutlass", "cutlass", "buccaneers", "buccaneers", "buccaneers", "musketeers"], "portobelo"]]},
			{"t": "Bribe a gate open first (300 gold)", "need": {"gold_ge": 300}, "why": "Not enough gold in the chest",
				"hint": "Half the garrison is down with fever and the other half can be bought: half the defenders are out of it and a gate stands open (the walls count a level lower). Then the same assault.",
				"say": ["lindo", "In Portobelo the dead outnumber the living two to one. The living are very reasonable."],
				"fx": [["gold", -300], ["flag", "raided"], ["weaken", "portobelo", 50], ["slight", "portobelo", 1], ["assault", "portobelo", ["cutlass", "cutlass", "buccaneers", "buccaneers", "buccaneers", "musketeers"], "portobelo"]]},
			{"t": "Turn back", "hint": "No raid.",
				"say": ["mercy", "...Aye. Bring her about."],
				"fx": [["flag", "raided"], ["p", "purse", 10]]},
		]},
	{"id": "raid_won", "focus": "flagship", "act": 3, "title": "The sack of Cartagena", "when": {"flag": "won_cartagena"},
		"lines": [
			["", "The town is yours. For three days the Brethren go through it like a fever: the churches, the counting houses, the Governor's cellar. The bells stop ringing on the second day."],
			["mercy", "Chests of silver, Captain. Plate, pearls, cochineal, a bishop's mitre with stones in it the size of quail's eggs. The chest is full. Fuller than full. Every pirate in the Caribbean will know your name by Sunday."],
			["mendoza", "You have sacked a city of the King of Spain. Now I am coming for yours."],
		],
		"chron": "Pirates stormed a great city of the Spanish Main and sacked it for three days.",
		"fx": [["plunder", 1500], ["fame", 12], ["infamy", 10], ["p", "heat", 15], ["p", "purse", -30], ["flag", "raid_done"]]},
	{"id": "raid_won_pb", "focus": "flagship", "act": 3, "title": "The sack of Portobelo", "when": {"flag": "won_portobelo"},
		"lines": [
			["", "Portobelo is yours: the three castles, the customs house, the King's silver waiting for the galleons. The townsfolk flee into the hills and the fever stays behind to keep you company."],
			["mercy", "Silver bars stacked in the customs house like cordwood, Captain, waiting for a flota that'll never take them now. Not Cartagena, but it'll fill the chest. Now let's get out before the fever fills the graveyard."],
			["mendoza", "You have sacked a city of the King of Spain. Now I am coming for yours."],
		],
		"chron": "Pirates stormed Portobelo and carried off the King's silver.",
		"fx": [["plunder", 1000], ["fame", 10], ["infamy", 8], ["p", "heat", 12], ["p", "purse", -25], ["flag", "raid_done"]]},
	{"id": "raid_lost", "act": 3, "title": "Thrown back", "when": {"any": [{"flag": "lost_cartagena"}, {"flag": "lost_portobelo"}]},
		"lines": [["mercy", "They were waiting on the walls. We left a lot of good men in the ditch, Captain. The ones who got back aren't talking to anybody."]],
		"fx": [["p", "purse", 15], ["flag", "raid_done"]]},
	{"id": "raid_late", "act": 3, "title": "Too late for the Main", "when": {"turn": [39, 40], "any": [{"flag": "raid_cartagena"}, {"flag": "raid_portobelo"}], "noflag": "raided"},
		"lines": [["mercy", "We'll never make the Main and back before Mendoza comes, Captain. The raid's off. The crew are almost relieved."]],
		"fx": [["flag", "raided"]]},
	{"id": "pardon", "act": 3, "title": "The King's pardon", "when": {"turn": [36, 41], "flag": "goal", "noflag": "pardon_refused"}, "every": 3,
		"lines": [
			["ashby", "BY THE GOVERNOR. His Majesty, of his abundant mercy, offers a free pardon to any pirate who shall surrender himself before the first day of next year, and shall give such information as will bring the rest of that wicked fraternity to justice. Such a person shall keep whatever goods he has, and want for nothing."],
			["lindo", "A private word, Captain. Sir Thomas wants Tortuga. Its anchorage, its guns, its captains' names. Give him that, and you walk into Port Royal a gentleman with a fortune, and never look over your shoulder again. Only at the Brethren, from a very great distance."],
			["mercy", "You know what that is, Captain. That's every man in this town on a rope, so you can sleep in a bed. I won't stop you. I'll just never speak to you again."],
		],
		"choices": [
			{"t": "Take the pardon and name the anchorage", "hint": "THE STORY ENDS: the Pardon. Rich, safe, despised.",
				"say": ["ashby", "A wise choice, sir. Possibly the first you have ever made. Do come to dinner."],
				"fx": [["flag", "pardon"], ["sched", "end_pardon", 0]]},
			{"t": "Keep the letter, for now", "hint": "Nothing yet. The offer stays open until Mendoza comes.",
				"say": ["mercy", "You kept it. I saw you. I won't forget that either."],
				"fx": [["flag", "pardon_kept"]]},
			{"t": "Burn it before the crew", "hint": "No pardon, ever. The crew will follow you anywhere after this.",
				"say": ["mercy", "That's my captain. Burn it slowly, so they can all see."],
				"fx": [["flag", "pardon_refused"], ["unflag", "pardon_kept"], ["fame", 4], ["p", "purse", -15]]},
		]},
	{"id": "recognition", "act": 3, "title": "Recognised", "when": {"turn": [36, 41], "fp": "chest"},
		"lines": [
			["", "A Dutch merchantman comes into Tortuga road and salutes the fort with seven guns. Then a Frenchman. Then another Dutchman, with a factor from the West India Company who wants to talk about tobacco."],
			["lindo", "There, you see? Silver talks, and what it says is: here is a country. The Dutch have sent a squadron to anchor in your road, purely to protect their trade, you understand. Mendoza will have to sail round it."],
		],
		"chron": "Dutch and French merchants traded openly at the pirate free port of Tortuga.",
		"fx": [["actor_lose", "armada", 1], ["unit", "musketeers", 2, "port_de_paix"], ["flag", "recognised"], ["p", "haven", 15]]},
	{"id": "armada_gathers", "focus": "armada", "act": 3, "title": "Mendoza comes", "when": {"turn": [38, 40], "flag": "goal"},
		"fx": [["spawn", "armada", "new_spain", "havana", [{"t": "frigate", "nm": "San Felipe"}, {"t": "frigate", "nm": "San Antonio"}, {"t": "sloop"}],
				0, "hold", "havana"],
			["actor_add", "armada", [{"t": "galleon", "nm": "Nuestra Senora de Atocha"}]], ["hold", "armada"], ["p", "heat", 10], ["sched", "eve", 2],
			["sched", "eve_homeless", 2]],
		"lines": [
			["mendoza", "To the captain who calls himself the master of Tortuga. Sir: in two seasons I will come to your free port with every ship of the Armada de Barlovento and every soldier the Viceroy can spare me. I tell you so that you cannot say you were not told."],
			["mendoza", "You may leave before I come. I will not follow, this time. I would rather not kill brave men for a rock. But if you are there, I will take it, and I will hang everyone I find. I remain, as ever, your servant, and your end. R. de M."],
			["mercy", "Two seasons. That's what we have. Whatever we haven't done by then, we won't do."],
		]},
	{"id": "eve", "focus": "port_de_paix", "act": 3, "title": "The night before", "if": {"owns": "port_de_paix"},
		"lines": [
			["", "Tortuga, the last night. Fires on the beach, the fort's guns loaded with grape, the Brethren drinking quietly for once. Out in the dark, beyond the point, the lanterns of the Armada."],
			["mercy", "Whatever happens tomorrow, Captain, they'll sing about it. I'd rather they sang about us winning, mind."],
			["lindo", "I have a boat ready, of course. I always have a boat ready. I find I do not want to get into it. How very strange."],
		],
		"fx": [["sched", "finale_sea", 1], ["sched", "finale_walls", 1]],
		"choices": [
			{"t": "Meet them at sea", "hint": "Tomorrow your fleet fights the Armada in Tortuga road, under the fort's guns if it lies there: a sea battle. Win it and only a remnant lands; lose it and they land in force.",
				"say": ["mercy", "To sea, then. Better to die with a deck under you than a roof."],
				"fx": [["flag", "meet_sea"]]},
			{"t": "Fight from the walls", "hint": "Every man ashore: three companies of your sailors join the garrison, and the Armada lands in force under your guns: a land battle.",
				"say": ["mercy", "Behind stone, then. Let them come to us and pay for every step."],
				"fx": [["flag", "walls_stand"], ["unit", "musketeers", 2, "port_de_paix"], ["unit", "cutlass", 1, "port_de_paix"], ["p", "haven", 10]]},
			{"t": "Take the King's pardon after all", "need": {"flag": "pardon_kept"}, "why": "You have no pardon to take",
				"hint": "THE STORY ENDS: the Pardon. In the night, a boat to Port Royal and a letter to Ashby.",
				"say": ["mercy", "...I'll tell them you died bravely. It's the last lie I'll ever tell for you."],
				"fx": [["flag", "pardon"], ["flag", "pardon_late"], ["sched", "end_pardon", 0]]},
		]},
	{"id": "eve_homeless", "focus": "flagship", "act": 3, "title": "Nowhere to stand", "if": {"lost": "port_de_paix"},
		"lines": [
			["mercy", "The Armada's out, Captain, and we've no port to fight from. Mendoza says he'll hunt us across every sea God made. I believe him."],
		],
		"choices": [
			{"t": "Turn and fight", "hint": "A last sea battle against the Armada, wherever you are.",
				"say": ["mercy", "Then let's make it a good one."],
				"fx": [["sea_battle", "armada", "last"]]},
			{"t": "Take the King's pardon after all", "need": {"flag": "pardon_kept"}, "why": "You have no pardon to take",
				"hint": "THE STORY ENDS: the Pardon.",
				"say": ["mercy", "...Go, then. Don't look back. We won't."],
				"fx": [["flag", "pardon"], ["sched", "end_pardon", 0]]},
		]},
	{"id": "finale_sea", "focus": "port_de_paix", "act": 3, "title": "The battle of Tortuga road", "if": {"flag": "meet_sea", "owns": "port_de_paix"},
		"lines": [
			["", "Dawn. The Armada de Barlovento comes round the point in line ahead, Mendoza's galleon in the van, the red cross of Burgundy at every masthead. Your ships beat out to meet it with the whole of Tortuga on the walls."],
			["mendoza", "Give them a broadside for the King, and one for every man they hanged. Then give them one for me."],
		],
		"chron": "The Armada de Barlovento attacked the pirate free port of Tortuga.",
		"fx": [["dip", "new_spain", "war"], ["spawn", "armada", "new_spain", "port_de_paix", [{"t": "galleon"}, {"t": "frigate"}, {"t": "frigate"}], 0, "hold", "havana"],
			["place", "armada", "port_de_paix"], ["sea_battle", "armada", "fsea", 1]]},
	{"id": "finale_walls", "focus": "port_de_paix", "act": 3, "title": "The Armada lands", "if": {"noflag": "meet_sea", "owns": "port_de_paix"},
		"lines": [
			["", "Dawn. The Armada anchors off the beach below the fort and the boats go in, row after row of them, pikes upright like a moving wood."],
			["mendoza", "No quarter for the officers. Quarter for any man who throws down his arms. Forward, for God and the King!"],
		],
		"chron": "The Armada de Barlovento landed its soldiers to storm the pirate free port of Tortuga.",
		"fx": [["dip", "new_spain", "war"], ["place", "armada", "port_de_paix"],
			["raid", "new_spain", "port_de_paix", ["musketeers", "musketeers", "w_pikemen", "w_pikemen", "rodeleros", "musketeers"], "finale"]]},
	{"id": "landing_after_win", "act": 3, "title": "A remnant lands", "when": {"flag": "won_fsea", "noflag": "bt_finale"},
		"lines": [
			["mercy", "We broke their line, Captain! Mendoza's galleon is burning and half his frigates have struck. But he's put his soldiers in the boats anyway. Stubborn old devil. Everyone to the walls!"],
		],
		"fx": [["raid", "new_spain", "port_de_paix", ["musketeers", "w_pikemen", "rodeleros"], "finale"]]},
	{"id": "landing_after_loss", "act": 3, "title": "They land in force", "when": {"flag": "lost_fsea", "noflag": "bt_finale"},
		"lines": [
			["mercy", "They beat us at sea. Now they're landing, all of them, and every man who came back alive is on the walls. This is it, Captain."],
		],
		"fx": [["raid", "new_spain", "port_de_paix", ["musketeers", "musketeers", "w_pikemen", "w_pikemen", "rodeleros", "musketeers", "lancers"], "finale"]]},
	{"id": "landing_late", "act": 3, "title": "They land at last", "when": {"turn": [42, 43], "flag": "act3", "noflag": "bt_finale", "owns": "port_de_paix",
		"any": [{"flag": "meet_sea"}, {"flag": "walls_stand"}]}, "every": 1,
		"lines": [["mercy", "Here they come at last, Captain: Mendoza's boats, every one he has, making for the beach below the fort. Everyone to the walls!"]],
		"fx": [["dip", "new_spain", "war"],
			["raid", "new_spain", "port_de_paix", ["musketeers", "musketeers", "w_pikemen", "w_pikemen", "rodeleros", "musketeers"], "finale"]]},
	# ------------------------------------------------------------- endings ---
	{"id": "end_republic", "focus": "port_de_paix", "act": 3, "title": "The Republic", "when": {"flag": "won_finale"},
		"lines": [
			["", "By noon it is over. The Spanish columns break at the breach and run for the boats, and the Brethren run after them into the surf, and then stop, because there is no one left to fight."],
			["mendoza", "Captain. I have lost. I did not expect to say those words in this life. I will tell the King that Tortuga cannot be taken. He will not believe me, and I will be disgraced, and I find that I do not mind. You fought like Christians. R. de M."],
			["mercy", "We did it, Captain. We actually did it. A free port. No flag but ours. Vane would have... no. Vane would have got drunk. Let's do that."],
		],
		"chron": "The Armada was beaten at Tortuga. The pirates declared a free republic of the Brethren of the Coast.",
		"fx": [["ending", "republic"]]},
	{"id": "end_legend", "focus": "port_de_paix", "act": 3, "title": "The Legend", "when": {"any": [{"flag": "lost_finale"}, {"flag": "won_last"}, {"flag": "lost_last"}]},
		"lines": [
			["", "They fight in the breach until there is no breach, only men. They fight in the streets, and in the church, and on the beach with their backs to the sea. The black flag comes down over the fort at sunset. Nobody who was there ever agrees on how."],
			["mendoza", "I have taken Tortuga. I promised to hang everyone I found. I find I cannot bring myself to do it. Let it be said that they died as free men, which is more than most of us will."],
			["", "And in every tavern from Nassau to Maracaibo, they still sing of the captain who held Tortuga against the Armada, and of the free port where no flag but theirs flew. The song does not say how it ended. Songs never do."],
		],
		"chron": "The Armada stormed Tortuga. The pirates' free port fell, and passed into legend.",
		"fx": [["ending", "legend"]]},
	{"id": "end_pardon", "focus": "port_royal", "act": 3, "title": "The Pardon",
		"lines": [
			["", "The Royal Navy sails into Tortuga road on a fine morning with your chart of the anchorage on its quarterdeck. They hang the captains on Gallows Point at low tide, so the crabs can have them, as is the custom."],
			["ashby", "His Majesty's thanks, sir, and mine. A house in Spanish Town, a seat on the Council, and nobody will ever ask where the money came from. Do try the Madeira."],
			["mercy", "..."],
		],
		"chron": "A pirate captain took the King's pardon and sold the Brethren of the Coast to the Royal Navy.",
		"fx": [["gold", 1500], ["dip", "england", "peace"], ["dip", "new_spain", "peace"], ["infamy", -100], ["p", "favour", 100], ["ending", "pardon"]]},
	{"id": "end_late_republic", "act": 3, "title": "The Republic", "when": {"turn": [44, -1], "owns": "port_de_paix", "fp_ge": 2},
		"lines": [
			["", "Mendoza never comes. The Viceroy keeps his soldiers for Mexico; the King has other wars. The free port of Tortuga simply goes on being, until one day it has always been."],
			["mercy", "No battle, no glory, no song. Just a town that's ours. I'll take it, Captain."],
		],
		"chron": "The pirate free port of Tortuga stood, and the nations learned to trade with it.",
		"fx": [["ending", "republic"]]},
	{"id": "end_late_legend", "act": 3, "title": "The Legend", "when": {"turn": [44, -1]},
		"lines": [
			["", "The free port never quite comes to be. The Brethren scatter, the captains go their ways, and the Captain sails on into the stories they tell about him: that he still sails, that he died at Tortuga, that he sits in a tavern in Nassau waiting for the free port to need him again."],
		],
		"chron": "The pirate captain who dreamed of a free port passed into legend.",
		"fx": [["ending", "legend"]]},
	{"id": "end_fallen", "act": 3, "title": "The Legend",
		"lines": [
			["", "The last ship goes down, the last company is cut down, and the Captain with them, somewhere between the sea and the sand. They never find the body. That is how legends start."],
		],
		"chron": "The last of Vane's crew went down fighting, and passed into legend.",
		"fx": [["ending", "legend"]]},
	{"id": "end_conquest", "act": 3, "title": "The Republic",
		"lines": [["", "The black flag flies over half the Caribbean. Nobody calls it a free port any more. They call it a kingdom, and you its king."]],
		"chron": "The Brethren of the Coast became a power the nations had to treat with.",
		"fx": [["ending", "republic"]]},
]

## The endings (the view's ending screen): title, a line under it, a
## paragraph.
const ENDINGS := {
	"republic": {"title": "The Republic", "sub": "You hold the free port. No flag but ours.",
		"text": "For a generation Tortuga was a free port of the Brethren of the Coast: a republic of thieves with a council of forty captains, Dutch factors, French priests, a court that hanged pirates who robbed its friends, and a harbour that no king's ship entered without permission. Then, like every republic, it began to argue about taxes."},
	"pardon": {"title": "The Pardon", "sub": "Rich, safe, despised.",
		"text": "You lived to be old, in a big house in Spanish Town with a view of the sea you never looked at. You sat on the Council, you dined with Governors, and you were never once invited back. In the taverns of Tortuga they still spit when they say your name. They say it often."},
	"legend": {"title": "The Legend", "sub": "You went down fighting. The chronicle sings of it.",
		"text": "Nobody knows for certain what became of the Captain. The Spanish said they hanged him; the English said he drowned; the Brethren said he got away, and drank to him for fifty years in every free port from Nassau to Madagascar, where, as you may have heard, there was later a pirate republic called Libertalia. Some say he founded it."},
}

## The epilogue's fates (cstory.gd fates): the first entry for each speaker
## whose "end" lists the ending (absent: any) and whose "if" holds.
const FATES: Array[Dictionary] = [
	{"who": "mercy", "end": ["republic"], "text": "Mercy Teague was elected the first Speaker of the Brethren's council and spent the rest of her life telling forty captains to sit down. She was very good at it."},
	{"who": "mercy", "end": ["pardon"], "text": "Mercy Teague led what was left of the Brethren out of Tortuga the night the Navy came, and never spoke your name again. A quartermaster named Teague signed the articles at Nassau forty years later. She kept a pistol for you until she died."},
	{"who": "mercy", "end": ["legend"], "text": "Mercy Teague was not among the dead. Some say she got out on the last boat; some say she went back for the logbook. A crew at Nassau voted an old woman named Teague their captain in the year ninety-eight."},
	{"who": "lindo", "if": {"flag": "lindo_gone"}, "text": "Isaac Lindo died rich in Port Royal when the town slid into the sea in the great earthquake, clutching his ledgers. Nobody mourned him. He would have found that very sensible."},
	{"who": "lindo", "end": ["pardon"], "text": "Isaac Lindo brokered your pardon, took his commission, and sold your house in Spanish Town twice before you had moved in."},
	{"who": "lindo", "end": ["republic"], "text": "Isaac Lindo became the Republic's first Treasurer, and its last honest one, which is to say he stole only from foreigners."},
	{"who": "lindo", "end": ["legend"], "text": "Isaac Lindo did not get into his boat. He paid the widows of Tortuga their shares out of his own ledger, every piece of eight, and never told anyone why."},
	{"who": "vane", "end": ["republic"], "text": "Josiah Vane's logbook lies in the council house at Tortuga, open at the last page, under glass. The captains swear on it, and then argue."},
	{"who": "vane", "end": ["pardon"], "text": "You burned Josiah Vane's logbook the night before you sailed for Port Royal. You still dream about the last page."},
	{"who": "vane", "end": ["legend"], "text": "Vane's logbook went down with the fort. The Spanish never found it. The song remembers what was in it anyway."},
	{"who": "mendoza", "end": ["republic"], "text": "Don Rodrigo de Mendoza was recalled to Spain in disgrace and died in a monastery at Burgos, praying, they say, every night, for the soul of a pirate."},
	{"who": "mendoza", "end": ["legend"], "text": "Don Rodrigo de Mendoza was offered a marquisate for Tortuga. He refused it, and asked to be buried at sea off the island."},
	{"who": "mendoza", "end": ["pardon"], "text": "Don Rodrigo de Mendoza read of your pardon in a Jamaica gazette and laughed, for the only time anyone could remember. \"So he was a merchant after all.\""},
	{"who": "ashby", "end": ["pardon"], "text": "Sir Thomas Ashby was made a baronet for the destruction of the Brethren, and a fool of by the next Governor, who brought the pirates back."},
	{"who": "ashby", "end": ["republic"], "text": "Sir Thomas Ashby was recalled to London for losing a war nobody had told him about, and spent his retirement writing furious letters to the Gazette about pirates."},
	{"who": "ashby", "end": ["legend"], "text": "Sir Thomas Ashby claimed the fall of Tortuga as his own doing in every dispatch, and died believing it."},
	{"who": "boucher", "if": {"flag": "boucher_dead"}, "text": "Le Boucher hangs in chains at Gallows Point, Tortuga, where the crabs had him at last."},
	{"who": "boucher", "if": {"flag": "boucher_traitor"}, "text": "Le Boucher sailed for Spain with Mendoza's gold and was knifed in a tavern in Cadiz by a man who had been at Maracaibo. Nobody was ever charged."},
	{"who": "boucher", "if": {"capt": "boucher"}, "text": "Le Boucher sailed under your flag to the end, and was hanged at Port Royal the year after, still laughing."},
	{"who": "boucher", "text": "Le Boucher was never caught. Mothers on the Main still frighten their children with his name."},
	{"who": "crew", "end": ["republic"], "text": "The crew of the Gallows Bird got their shares, every man, and most of them drank them. The rest bought land on Tortuga and became the dullest men in the Caribbean."},
	{"who": "crew", "end": ["pardon"], "text": "Forty-one men voted you captain at Gallows Point. Nineteen of them were hanged on the same beach, on your information."},
	{"who": "crew", "end": ["legend"], "text": "The crew of the Gallows Bird went down with their captain, or swam ashore and lied about it for the rest of their lives. The ones who lied were the better singers."},
]
