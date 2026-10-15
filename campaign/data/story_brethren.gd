extends RefCounted
## The story campaign "The Brethren's Due" (DESIGN "Story campaign: The
## Brethren's Due"): the script as data, read by campaign/cstory.gd. Built so
## far: the Prologue (turns 0-3) and Act 1 "Brethren" (turns 4-14). Turn
## numbers here are the state's (0 = the first turn, summer 1665).
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
##   gold_ge v, timer name, ships_ge n.
## Effects (cstory.gd _fx): see the list there.

## Who speaks: name, role, badge colour (portrait placeholder: a coloured
## initial until there is art).
const CHARS := {
	"mercy": {"name": "Mercy Teague", "role": "Quartermaster", "col": "b8432f"},
	"lindo": {"name": "Isaac Lindo", "role": "Fence of Port Royal", "col": "7b5ea7"},
	"vane": {"name": "Josiah Vane", "role": "From his logbook", "col": "8a6a3a"},
	"mendoza": {"name": "Don Rodrigo de Mendoza", "role": "Admiral of the Armada de Barlovento", "col": "d9a31f"},
	"ashby": {"name": "Sir Thomas Ashby", "role": "Governor of Jamaica", "col": "c8402f"},
	"boucher": {"name": "Jean-Baptiste Nau", "role": "\"Le Boucher\"", "col": "5a1a1a"},
	"crew": {"name": "The crew", "role": "", "col": "5a6b5a"},
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
## Times the Brethren fish a shipless, landless captain out of the surf.
const MERCY := 2

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
## Map marks (view only): captions over the story's fleets and places.
const MARKS := {"guarda": "Guardacosta San Telmo", "armada": "Armada de Barlovento", "boucher": "Le Boucher",
	"prize": "Spanish trader (prize)", "nao": "Treasure nao", "haven": "Tortuga: your haven", "lair": "Ile-a-Vache: Le Boucher's lair"}
## Le Boucher's lair (Ile-a-Vache, south of Hispaniola), the hunt's reach.
const LAIR := [-7362, 1807]
const HUNT_CELLS := 3

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
		"fx": [["sched", "reprisal", 1]],
		"choices": [
			{"t": "Every man home to Tortuga", "hint": "Your flagship sails for Tortuga; the haven takes heart.",
				"say": ["mercy", "Aye. I'll have the fort's guns scraped and loaded by the time you're there."],
				"fx": [["voyage_r", "port_de_paix"], ["p", "haven", 10], ["flag", "rushed_home"]]},
			{"t": "Hire the boucaniers of the hills (150 gold)", "need": {"gold_ge": 150}, "why": "Not enough gold in the chest",
				"hint": "Two companies of buccaneers at Tortuga.",
				"say": ["mercy", "Hunters off the hills. They hate the Spanish worse than we do. The Spanish shot their cattle."],
				"fx": [["gold", -150], ["unit", "buccaneers", 2, "port_de_paix"], ["p", "haven", 10]]},
			{"t": "Let Tortuga look after itself", "hint": "The crew is spared a fight; Tortuga remembers.",
				"say": ["mercy", "Tortuga took us in when nobody else would. I'll remember that you didn't, Captain."],
				"fx": [["p", "haven", -15], ["p", "purse", 5]]},
		]},
	{"id": "reprisal", "focus": "port_de_paix", "act": 1, "title": "The Spanish land", "if": {"owns": "port_de_paix"},
		"lines": [
			["", "Dawn. Spanish boats ground on the beach below the fort, and a column of pikes and muskets comes up the path under the red saltire of Burgundy."],
			["mercy", "Here they come. Every man who can hold a musket, to the walls!"],
		],
		"chron": "Spain landed at Tortuga to punish the pirates for Maracaibo.",
		"fx": [["raid", "new_spain", "port_de_paix", ["musketeers", "musketeers", "w_pikemen", "rodeleros"], "reprisal"]]},
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
			{"t": "Let him go his own way", "hint": "He sails for Saint-Domingue. You have not seen the last of him.",
				"say": ["boucher", "Pity. You will regret it. People usually do."],
				"fx": [["goal", "boucher", "leogane"], ["flag", "spurned_boucher"]]},
		]},
	{"id": "boucher_beaten", "act": 1, "title": "The Butcher's end?", "when": {"flag": "won_boucher"},
		"lines": [
			["mercy", "We caught him with his hull on the beach. He fought like the devil, then went over the side in his shirt with a knife in his teeth, and nobody's seen him since."],
			["ashby", "Three hundred pieces of eight, as promised, for ridding His Majesty's seas of a Frenchman nobody will miss. Do not mistake this for friendship, Captain. I pay rat-catchers too."],
		],
		"chron": "Le Boucher's ships were taken at the Ile-a-Vache; the man himself vanished.",
		"fx": [["gold", 300], ["p", "favour", 15], ["fame", 8], ["flag", "boucher_beaten"]]},
	{"id": "boucher_escaped", "act": 1, "title": "Next time, bring more ships", "when": {"flag": "lost_boucher"},
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
			["", "Act Two, \"The Commission\", is still being written. The sea is yours: play on."],
		],
		"fx": [["act", 2], ["flag", "act1_done"]]},
]
