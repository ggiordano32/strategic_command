# Strategic Command — Status and Handover

Last updated: 2026-10-09 (siege towers built, not committed; the general and his bodyguard built, not committed; camels and elephants built, not committed; ammunition kinds and fire, foraging and the ammunition wagon built, not committed; earlier 2026-10-08: a CPU-fed soldier rendering fallback, picked by the battle's self-check, for Chrome on an Adreno 650 tablet that drew no soldiers; earlier 2026-10-07: any ally can join a fought co-op battle and be given units; the battle screen on the overworld; cities worth defending, part 2b: siege equipment as objects, the ladder shuffle and wall-punching bugs; part 2a: units do not pass through each other, street fights; part 1: tower engines, ladders, a ram, hard gates, the battle time limit; earlier 2026-10-06: deployment phase and custom battles built; the continuous campaign overworld built, state format 6; free campaign movement built; sieges and battle odds built on the campaign map; settlement variety built 2026-10-05). Read this first, then `docs/DESIGN.md` for the full
design and `CLAUDE.md` for working rules. Update this file whenever a
milestone lands or the plan changes.

## What this is

A 2D, top-down, co-op grand strategy game inspired by Rome 2: Total War, in
Godot 4 (GDScript), played in a browser on phones and desktops. Two friends
play an asynchronous turn-based campaign against AI factions and fight
real-time battles solo or together. Built for two players first; accounts,
anti-cheat and original art only if it proves fun.

## Where we are

| Milestone | State |
|---|---|
| 1. Battle sandbox | Done, committed (`6b3a1cf`), playtested on an Android phone |
| 2. Full battle mechanics | Done, committed (`49c1022`), playtested; tuning pass included |
| Unit symbols and unit book | Done, committed (`49c1022`) |
| Artillery (bolt and stone throwers) | Committed (`49c1022`), not yet playtested |
| Terrain height | Built, committed, playtested ("feels good so far") |
| Playtest round (HUD scale, stones, ammo, refill) | Built, committed, not yet playtested |
| 3. Minimal campaign | Built 2026-10-05, committed, not yet playtested (see below) |
| 4. Async backend (Go + SQLite) | Committed (`fad7399`); port 8060 runs it; first phone playtest done (live battles were missing) |
| 5. Live co-op battles (lockstep) | Built 2026-10-05, committed; tested headless, end to end and in two headless Chromiums; the 8060 server binary is not yet updated; not yet played on phones |
| Battle maps with character (woods, city maps, palettes, shading) | Committed (`3522fd2`); not yet played on phones |
| Settlement variety (plans, sites, coasts, citadels, stairs, owners) | Built 2026-10-05, committed; tested headless; not yet played on phones |
| Sieges and battle odds (campaign, state format 4) | Built 2026-10-06, committed; tested headless and windowed; not yet played on phones |
| Free campaign movement (state format 5) | Built 2026-10-06, committed; tested headless and windowed; not yet played on phones |
| Wall orders, drag clamp, reachability (playtest fixes) | Built 2026-10-06, committed; tested headless and windowed; not yet played on phones |
| Continuous campaign overworld (state format 6) | Built 2026-10-06, committed; tested headless and windowed; not yet played on phones |
| Deployment phase and custom battles (solo, co-op, head-to-head) | Built 2026-10-06 on a branch; tested headless, end to end and windowed; not yet played on phones |
| Cities worth defending, part 1 (tower engines, ladders, ram, hard gates, battle time limit) | Built 2026-10-07, committed; tested headless and windowed; not yet played on phones |
| Cities worth defending, part 2a (units do not pass through each other, street fights) | Built 2026-10-07, committed; tested headless (and the windowed input tests); not yet played on phones |
| Cities worth defending, part 2b (siege equipment as objects; ladder and wall-punching fixes) | Built 2026-10-07, committed; tested headless, windowed input test, live_e2e; not yet played on phones |
| Battle screen on the overworld (pre-battle and result, item 4b) | Built 2026-10-07, committed; tested headless (`tests/battle_screen_test.gd`), the windowed input test and online_e2e; not yet played on phones |
| Overworld UI fixes: Deselect button; dialogs and the side panel keep their scroll position when re-rendered | Built 2026-10-07, committed; windowed campaign_input_test; not yet played on phones |
| Text entry on the web (no keyboard on tablets, bad desktop paste): every field is `Kit.text_field`; a finger tap on the web opens the browser's `prompt()` (Godot's web export has no usable on-screen keyboard: `html/experimental_virtual_keyboard` is off, and even on it cannot raise the keyboard on iOS); Ctrl+V and a Paste button beside the online fields read the clipboard through the browser (Godot's web paste returned the previous clipboard); invite key / codes trimmed | Built 2026-10-07, committed; check_scripts, windowed campaign_input_test, touch_scroll_test as on HEAD, custom_battle_test, a scratch web export driven in headless Chromium (stubbed prompt / clipboard: tap, Paste, Ctrl+V); not yet tried on a real tablet / iPhone |
| Join any co-op battle (playtest fix): the owner's card offers Fight together whenever an ally is alive; an ally whose army is not in the battle can **Ask to join** (server choice `ask`, summary `ask_by`, no Discord needed; the owner's card shows "X asks to join", puts Fight together first and confirms a solo Fight) and joins the lobby as a guest (`Lockstep.setup` guests: admitted like anyone, side of the players' units, commands what the host gifts); "Wait for ally" / "Take command" renamed "Leave it to X" / "Fight it for X" | Built 2026-10-07, committed; go test (new `TestRoomGuestAsksAndJoins`), lockstep_test (guest case), live_e2e (new battle 4: ask, seen, Fight together, guest joins, two units gifted and ordered, equal hashes to the end), online_e2e, check_scripts, custom_battle_test, battle_screen_test; **server change: the 8060 server needs a rebuild and restart** (new `battle_asks` table is created on start); not yet played on phones |
| Soldier rendering fallback (2026-10-08). Known issue: Chrome on a Samsung Galaxy Tab S7 (Adreno 650, ANGLE on GLES) draws nothing from the per-man data texture read in the vertex shader (`soldier_probe drawn=0`; Firefox on the same tablet, desktop GPUs and SwiftShader draw fine; removing uint / bit ops / INSTANCE_ID in be147c8 did not help). New CPU-fed path (`game/soldier_layer.gd`, `soldiers_cpu.gdshader` / `projectiles_cpu.gdshader` over shared `.gdshaderinc` bodies): the sim arrays go into the MultiMesh buffers in one bulk upload per tick, no texture fetch in the vertex stage; same pixels as the texture path (native screenshots: soldiers and engines bit-identical, missiles within one edge pixel). The self-check switches to it when the texture path draws 0 pixels, probes again (telemetry `soldier_probe` now has `path`) and remembers `user://settings.cfg [video] soldiers=cpu`; home menu "Soldiers: auto / compatible"; `--soldiers=cpu|gpu` / `?soldiers=` force a path, `--soldier-probe-fail` fakes the failure. Cost at 4,000 men: upload 0.48 ms a tick natively (texture 0.23), ~0.7 ms in headless Chromium (texture ~0.4) | Built 2026-10-08, committed; check_scripts, input_test, `webcheck -soldiers` (both paths, the automatic switch, the remembered choice) on a scratch export; **not yet confirmed on the Tab S7** (look for `soldier_probe` path=cpu drawn>0 in its telemetry) |
| Battle speed slider (2026-10-08): the speed button ("1x") opens a popover with a labelled slider, 0.25x-4x in quarter steps (`Lockstep.SPEED_Q_MIN..MAX` = 1..16; `SPEED_QS` is now the tick labels / key steps 0.25, 0.5, 1, 2, 3, 4), live value label, 30 px handle; drags never pan the map, a tap outside closes it. Solo: applies while dragging. Co-op / head-to-head: the release is the speed vote (`C_SPEED`, nothing applied locally); the chip reads "Rome proposes 2.5x — Accept / Decline". Lockstep's command rule widened from the four old steps to 1..16 (out of range is rejected); hashed state unchanged, but the rules hash changes | Built 2026-10-08, committed; check_scripts, input_test (slider drag / value / keys), lockstep_test (2.5x vote A→B, hash-equal), custom_battle_test; screenshot `docs/screenshots/speed_slider_phone.png`; not yet played on phones |
| Gifting cities and money between co-op players (item 4c, 2026-10-08): orders `gift_region` (free: at resolution; priced: an offer), `buy_region` (offer to buy the ally's city), `gift_money`, `accept_offer` / `decline_offer`; a priced deal is a two-turn handshake in the existing `proposals` list (new keys kind / r / price, no format bump), checks run again at acceptance (still owned, no army of the giver in the city, treasury covers it); region panel "Gift to <ally>" with a price, Diplomacy under the ally: Offer money, Offer to buy, incoming offers Accept / Decline; see CAMPAIGN.md "Gifts between players" | Built 2026-10-08, committed; campaign_test (free gift, handshake accepted / declined / lapsed, army and treasury refusals at acceptance, buyer's offer, money, AI refused, both submission orders hash-equal, JSON round trip), windowed campaign_input_test (gift / Cancel / Undo, the disabled button with its reason, Offer money / Offer to buy / Cancel, Accept / Undo), campaign_solo, online_e2e, check_scripts; campaign_sim 6 seeds x 60 turns hashes unchanged (056bfc4c 7e5be9e9 4ddf4d22 27da886c 892fc13f 01cad53e); the rules hash changes (online clients must update); not yet played on phones |
| 6. Depth (siege towers, tech, more factions) | Not started |
| Cities worth defending, part 2c (defender layout at the attacked gate; routers run inward) | Built 2026-10-08, committed; determinism (new `--only=layout`), lockstep, custom_battle_test, check_scripts pass; campaign_sim 6x60 hashes unchanged; field battles unchanged; not yet played on phones |
| Engines are equipment, crews are men (+ per-unit kills on the battle screen), 2026-10-09: a battery Drops its engines (abandoned, neutral; hp, shots, set-up state kept) and fights on as plain men (light infantry's pace / formation, own arms); any foot unit of either side taps them to take them up and works them as a battery of the engine type (its own arrows put aside until it drops them; spare men stand behind); a routed / dead battery's engines are free to anyone; tower engines fixed; battle AI: missile units out of ammo take up their side's abandoned engines within 60 m (field maps only). Sim `u_kills` (melee, charge, missiles, engines, towers; friendly fire apart), hashed; fought outcomes carry `kills` per unit row (optional key, auto-resolve none), cards show "kills N". See DESIGN.md "Artillery" ("Engines are equipment, crews are men", "Kills per unit"), AI.md 17 | Built 2026-10-09, committed; check_scripts clean; determinism (new `--only=engines`; flat golden digests unchanged; every run's alive / winner unchanged except bench_2000 seed 12345, where an AI javelin unit takes up its side's abandoned bolts at tick 2258), lockstep (full; siege case: B's battery drops, A's archers take up and drop, snapshots across), custom_battle_test, windowed input_test (Drop for a battery, tap to take up), battle_screen_test (fought cards with kills, auto without), campaign_test; campaign_sim 6x60 hashes unchanged (056bfc4c 7e5be9e9 4ddf4d22 27da886c 892fc13f 01cad53e); bench_4000_city same battle, mean 3.20 -> 3.21 ms, state_hash 0.53 -> 0.56 ms; rules hash changes; not yet played on phones |
| Ammunition kinds and fire (item 4d), 2026-10-09: kinds are rows of `UnitTypes.AMMO` (fire arrows, heavy bolts, fire javelins, fire pots, explosive stones; fields dmg / obj / ap / pierce / range / rate / fear / blast / fire / share applied generically); a unit carries one special kind as a share of its load (`sammo` / `e_sammo`), Ammo toggle on the HUD (V, `ORDER_AMMO`, `u_akind`); fire is one burning state on gates, engines / towers, ladders, rams, wagons (`g_burn` / `e_burn` / `q_burn`, chip damage), burning units lose morale; missile troops can shoot a gate (tap it); AI knobs `AK_*` (AI.md 18); campaign `CData.AMMO_AVAIL` (faction + Range / Workshop) stored as unit key `"ak"`, tower engines get the owner's kind; unit book, recruit list and battle screen show the kinds. See DESIGN.md "Ammunition kinds and fire" | Built 2026-10-09, committed; check_scripts clean; determinism full (new `--only=ammo`; golden digests unchanged; every run's alive / winner unchanged), lockstep full (siege case: a kind switch and a wagon refill, snapshot mid-refill), custom_battle_test, battle_screen_test, campaign_test (kinds by building, JSON round trip), windowed input_test (Ammo tap) and campaign_input_test; campaign_sim 6x60 hashes change only through the `"ak"` keys on AI-recruited units (983c2089 7e5be9e9 5ea05001 6b57adbd 95c22663 33de47d2; with the key suppressed: the old 056bfc4c 7e5be9e9 4ddf4d22 27da886c 892fc13f 01cad53e); bench_4000_city same battle, mean 3.18 -> 3.21 ms, state_hash 0.56 -> 0.60 ms; rules hash changes; no balance run; not yet played on phones |
| Resupply: foraging and the ammunition wagon (item 4e), 2026-10-09: `ORDER_FORAGE` (missile troops in woods, a quiver in 2.5 min, stops when hit / moved), wagon units Hand Cart / Ammunition Wagon / Supply Train (`UnitTypes.WAGONS` tiers: horses as hit boxes, paces, stock), the wagon an `EQ_WAGON` piece any foot unit of either side can take, pull (carrier penalty, exposed flanks) and Drop; Refill generalised to missile troops and batteries near a wagon (per-kind stock); it burns; AI `WG_*` / `FORAGE_AI` knobs; campaign: line "siege" in the rosters (Workshop, Stables for horses), 20 % strength + missile bonus in auto-resolve, carries its army's kinds into battle. See DESIGN.md "Resupply" | Built 2026-10-09, committed; same runs as the row above, plus determinism `--only=wagon`, campaign_test (recruit, gift, auto-resolve with a wagon), windowed input_test (Forage, Refill by the wagon, Drop for the crew); the campaign AI does not recruit wagons; not yet played on phones |
| Camels and elephants (item 5), 2026-10-09: rows `UnitTypes.BEASTS` (Camel Riders, Camel Archers, War Elephants) with generic fields (mount, acc, body_r, crew_shoot, woods_pct, trample_*, crush, horse scare `scare_*`, fear aura `fear_*`, burn_pct, amok / amok_r 50 m / amok_calm 20 s, kill_delay 5 s, gate_walls 1); horse scare and fear aura once a second (`u_scare`, `u_awe`: no morale recovery inside); elephants one big body each (blows to its edge, never knocked down, footprint padded, charge through shields / ranks and 50 % through braced points, carries into 4 more men); amok on breaking (erratic, tramples anyone, calms alone: the user's rule), `ORDER_KILL` (HUD "Kill elephant" while ours run amok); AI knobs `CAMEL_HORSE`, `EL_*` (AI.md 19); campaign: Carthage camels / camel archers / elephants, Epirus elephants (Stables 1 / +Range 1 / Stables 3), AI mixes; `Scenarios.army_layout` puts wagons in a rear line and elephants 30 m ahead. See DESIGN.md "Camels and elephants" | Built 2026-10-09, committed; check_scripts clean; determinism full (new `--only=camels`, `--only=elephants`; golden digests unchanged; all 68 runs' alive / winner unchanged), lockstep full (field case: an elephant unit amok from the start, Kill through the lockstep, snapshot mid-kill), custom_battle_test (wagon behind its army), windowed input_test (Kill elephant), campaign_test (recruit requirements, JSON, auto-resolve, a battle with them; the step-4 AI goldens hold with `CAI.no_beasts`); campaign_sim 6x60 hashes change only through the AI recruiting them (7bc352d8 fb21bde9 ababb36f 3dbaaf64 b426c7ec 2851ab87; `--no-beasts` gives the old 983c2089 7e5be9e9 5ea05001 6b57adbd 95c22663 33de47d2); bench_4000_city same battle, mean 3.36 -> 3.25 ms, state_hash 0.66 -> 0.61 ms; rules hash changes; no balance run; not in the custom picker; not yet played on phones |
| Custom battles: wagons and ammunition kinds, 2026-10-09: the picker lists the three wagon tiers (a "Wagons" row); each missile unit / battery line has an "Ammo:" toggle cycling standard / the kinds riding on its weapon (setup unit entry `[key, men, kind key]`, optional); a wagon line stocks its own army's kinds (shown on its line); `CS.build` passes them as scenario `"ak"` / `"aks"` (field and settlement), so the online setup carries them and the scenario hash covers them; kinds are free (no funds cost) | Built 2026-10-09, committed; check_scripts clean; custom_battle_test (wagon + fire arrows + heavy bolts, field and settlement: sim kinds and wagon stocks, JSON round trip, hash changes with the kind); not yet played on phones |
| Missile cavalry and slingers (item 5b, points 1-2), 2026-10-09: data only, no sim change. Rows `UnitTypes.LIGHT_MISSILE` (Light Horse `cav_jav`, line "cav_missile": javelins 40 m, skirmish, 8.6 m/s, mount 1, 480; Slingers `slinger`, line "sling": 150 m, 28 dmg / 0 ap every 3 s, skirmish, archers' sprite, 320) and faction variants `LIGHT_MISSILE_TIERS` (tier 2: Numidian, Tarentine, Gallic, Iberian Light Horse; Balearic, Rhodian, Iberian Slingers) built like `TIERS` (`_derived`); `AMMO` 9 Sling stones (standard, a cart carries 1,600) and 10 Lead bullets (33 %, 130 % dmg, +20 ap, 85 % range); unit icons 13 / 14; campaign rosters, `UNIT_NEEDS` (light horse Stables of its tier + Range 1), `LINE_CHAIN`, `AMMO_AVAIL` (lead bullets: Carthage, Greeks, Range 2), AI mixes 5 each through the mix only (`CAI.BEAST_LINES`); custom picker rows. See DESIGN.md "Missile cavalry and slingers", CAMPAIGN.md rosters | Built 2026-10-09, committed; check_scripts clean; custom_battle_test (new case: one of each of the nine rows builds with its kind, skirmish on, riders mounted, the Balearics' lead bullets, and each shoots on an attack order), campaign_test (rosters per faction, needs, lead / fire kinds by building, recruit turn deterministic + JSON, auto-resolve by price, a battle with them runs; the step-4 AI goldens hold with `CAI.no_beasts`); campaign_sim 6x60 hashes change only through the AI recruiting them (839d1cc1 4fb39dbe 4a76e996 4743b67f 00a23325 31cd8f6d; with their mix weights at 0: the previous 7bc352d8 fb21bde9 ababb36f 3dbaaf64 b426c7ec 2851ab87); determinism / lockstep not run here (a wagon now also stocks sling stones: `q_stock` grows by two kinds); no balance run; gaps: no charge for missile cavalry (`CLS_MISSILE`), light horse / camel archer armies march at the foot's pace (`CState.max_mp`), the sling stone draws as an arrow, no armour-bracket damage field |
| Melee: ranks hold together (2026-10-09; the front rank no longer runs ahead of its unit): a fighting man walks in at most 1.5 m ahead of his place and 3 m to the side (`PLACE_LEAD`, `PLACE_SIDE`, `_cap_lead`; wrapping capped ahead too); the attack advance stops on a new hashed `u_inreach` (a man within reach + 1 m of his man; `u_fighting` unchanged for the AI), may step into its own target's footprint until then, waits for men fighting elsewhere (`ANCHOR_LEAD`), and takes the street path while none is in reach; pursuit is the unit's: men do not run after routers beyond the cap, an attack on a routing unit runs its anchor after it (no AI change needed, AI.md 3.13); flank / rear for the shield, the +25 / +40 to-hit and morale all from one `_zone` (attacker relative to the defender's unit, not the man's facing); on settlement maps a man within reach re-checks his man's reachability every tick. See DESIGN.md "Ranks hold together in melee" | Built 2026-10-09, committed; check_scripts clean; determinism full PASS (golden skirmish / bench_2000 re-baselined; coverage moved: bench_2000 `ai_flank` -> bench_2000@4, siege_punic@ai no longer needs `gate_close`; test_cav_art's light infantry now goes round the spearmen before attacking the bolts; shut inner gate allows 60 single-tick across cases, was 40, now 41), lockstep full, custom_battle_test, campaign_test; campaign_sim 6x60 = HEAD's (839d1cc1 4fb39dbe 4a76e996 4743b67f 00a23325 31cd8f6d); probe (scratch, 2 lines of heavy / spear / heavy): rank-1 to rank-2 gap mean 6.3-9.7 -> 2.6-3.2 m, enemies inside the line up to 45 -> 0-8, rank-1 side / back blows 38-59 % -> 0-20 %, first rout ~800-950 -> ~960-1500 ticks, no man more than 4 m ahead; `--fair=20`: Average mirror 22-17-1, Skilled vs Average 24-16 (was 76-77 %), Average vs Easy 27-10-3 (was 79 %); bench_4000_city engaged 4.33 -> 4.97 ms, bench_2000 1.20 -> 1.34 ms (longer fights, more men alive; neither decided in 6000 ticks now). **Field balance moved (slower, fewer casualties, more draws by time) and belongs to the rebalance block**; rules hash changes; not yet played on phones |
| The general and his bodyguard (item 5b, point 3), 2026-10-09: command aura as generic row fields (`cmd_r` 40 m, `cmd_mor` +5/s held also fighting and under fire up to the recovery cap, `cmd_rally` +40/s for routers, `cmd_loss` 120 to the whole army / `cmd_loss_r` 250 within the radius when he routs or his last man dies, once; `cmd_pct` +8 % auto-resolve) in the once-a-second aura pass (`u_led`, `u_cmdgone` hashed); rows `UnitTypes.GENERAL` (General's Bodyguard: 30 men, 1,200, 44 / 40 / 16 / 160 hp / morale 950, charge 75) and `GENERAL_TIERS` at tier 1 (Legate's Guard, Sufet's Guard, Royal Hetairoi, Strategos' Guard, Chieftain's Guard; Bodyguard Cavalry = the plain, aura-less row); unit icon 15 / UI icon "general" (gold mark on the HUD card and the battle-screen card), unit book "Command aura" row; battle AI `_general_think` + knobs `GEN_*` (post behind the line, rides to a wavering / routing unit, decisive charge on a wavering engaged enemy; Easy: `GEN_THINK` 0, a plain rider); campaign: line "general" (Barracks 1), every starting army has one, recruiting refuses a second for an army (and a second a turn per settlement), armies coming together keep the first and the others become plain Bodyguard Cavalry, AI mixes "general" 4; also: light horse charge (`charge` 30, any mounted row with a charge rides the cavalry charge path, `t_rider`), riders-only armies (light horse, camel archers) march at horse pace (`max_mp`), sling stones / lead bullets drawn as small bullets (projectile kind 4), `--no-beasts` help text, camels / camel archers / elephants (and generals) in the custom picker. See DESIGN.md "The general", AI.md 20, CAMPAIGN.md "The general" | Built 2026-10-09, committed; check_scripts clean; determinism full PASS (new `--only=general`: inside the aura wavered at 995 vs 759 outside, near / far loss 248 / 118, light horse momentum 100 with 45 impacts, Average AI general behind the line / 12 rallies / 3 charges, Easy in at 348 before the lines met at 491; flat golden digests unchanged; all 102 runs' alive / winner unchanged; final state hashes change only by the two new zero arrays), lockstep full (field case: a general's riders fall under the enemy screen, snapshot before the fall runs on equal), custom_battle_test, battle_screen_test, campaign_test (starting generals, Barracks 1, second refused, merge / exchange to Bodyguard, +8 %, JSON, a battle with a general a side, march pace; fragile older checks adjusted: siege_lifted filtered by region, odds range to 30 heavy, Skilled coverage 60 turns); campaign_sim 6x60 ab547684 d65e9749 57e42e2e 555236c4 66bd8aec 3b3d1b45 (`--no-generals --old-mp` gives HEAD's 839d1cc1 4fb39dbe 4a76e996 4743b67f 00a23325 31cd8f6d exactly); battles per seed fewer (mean 53 vs 65); bench_2000 1.31 -> 1.29 ms, bench_4000_city 3.52 -> 3.48 ms (state_hash 0.40 / 0.60 unchanged); input_test not run (the card mark is drawn over the card, no layout change); rules hash changes; no balance run; not yet played on phones |
| Siege towers (item 4f, point 1), 2026-10-09: `EQ_TOWER`, a piece in the existing `q_*` tables; what every piece is now lives in per-kind fields (`EQ_ROOF`, `EQ_ROOF_R`, `EQ_HP`, `EQ_LANES`, `EQ_LANE_GAP`, `EQ_CLIMB`, `EQ_WALLS`, `EQ_PACE`, `EQ_WALK_PCT`, `EQ_MEN`, `EQ_ANY`, `EQ_SHOT`, `EQ_EXPOSED`, `EQ_DEPTH2`, `EQ_SMASH`, `EQ_FOCUS`, `EQ_FIRE_AT`; ladders / ram keep their numbers through them). The tower: ~6 x 6 m, 2,000 hp, roof 70 % within 8 m, pushed at most 0.6 m/s by 40+ men (fewer: pace x men / 40, at least a quarter), planted against walls 2-3 only, then 8 men abreast cross onto the walkway, a man a lane every 1.6 s (5 men/s, any wall height: 3-4x a ladder set), any unit of either side (defenders only from outside); anyone takes it up off the ground (the enemy too: `q_side`), a planted one stays; it burns, is battered by bolts / stones and smashed on the ground even when planted; when it falls, men crossing come back down. No new state arrays (q_* already hashed / snapshotted). Campaign: walls 2-3, 3+ siege turns 1 tower, 4+ 2 (`CBattle.TOWER_TURNS`, derived, VERSION 6); custom battles "Siege towers: 0 / 1 / 2" (walls 2-3); scenario key `towers` (a row 14 m behind the ladders / ram). AI: each tower to the biggest free infantry at once (`S_TOWER_CREW`; Easy: nearest), pushed to the `_ladder_spot` stretch, planted, crossed, then unbar as ladder men; `S_TOWER_FOLLOW` 1 / 2 / 3 followers; tower engines focus its crew like the ram's; wall archers with fire missiles shoot a pushing crew (`AK_FIRE_WOOD`). View: tower drawn with storeys and ramp, fire flicker, marker + dashed ring on the ground, previews PUSH / PLANT / ACROSS THE SIEGE TOWER, card "pushing a tower", battle-screen equipment line, unit book paragraph. See DESIGN.md "Siege equipment as objects", AI.md 15, CAMPAIGN.md "Siege equipment" | Built 2026-10-09, committed; check_scripts clean; determinism full PASS (new `--only=siege_tower`: pushed at 0.60 m/s, planted, 60 men across in 121 ticks, a dropped tower taken by the defenders, a second set alight and burnt down (test shortcut: 300 hp left), snapshot / restore while pushing, burning, crossing; golden digests and every other run's alive / winner / final hash unchanged), lockstep full PASS (siege case: A pushes and plants a tower, snapshots pushing and planted), custom_battle_test (storm with 2 towers; none at walls 1), campaign_test (towers by walls / turns, panel line, scenario), campaign_sim 6x60 unchanged (53a3e555 8d71116b 57e42e2e c4419b68 176dd683 53b5b1f3); bench_4000_city 3.50-3.56 -> 3.54-3.56 ms mean (no towers there). Measured once (`--only=fair-sieges`, 10 seeds, new row "+ 2 towers" at walls 2-3), attacker wins ladders + ram / + 2 towers: ring walls 2 0 / 10 %, walls 3 0 / 0 %; polis walls 2 0 / 0 %, walls 3 10 / 0 % (20 % draws); rows without towers (sim unchanged for them) now read ring walls 1 0 %, polis walls 1 30 % (30 % draws), well below the 40-60 % in this file: that drop predates this change (earlier commits since the measurement). Towers mostly arrive after the gate has fallen (0.5 m/s from the attackers' edge) and are then dropped for the storm. **Needs tuning (not done):** tower pace / start position, crew losses on the approach, whether the AI keeps crossing after the gate breaks; walls 1-3 balance overall. Not yet played on phones |
| Field works and the fortified camp (item 4f, point 2), 2026-10-09: stakes, caltrops, a camp's ditch and palisade as four piece kinds in the `q_*` tables (`EQ_STAKES`, `EQ_CALTROPS`, `EQ_DITCH`, `EQ_RAMPART`) with generic per-kind fields (`EQ_FW_LEN/DEPTH`, `EQ_OWN`, `EQ_SLOW_FOOT/RIDE`, `EQ_CROSS_T`, `EQ_STOP`, `EQ_DMG_FOOT/RIDE/BEAST`, `EQ_KNOCK`, `EQ_USE`, `EQ_HACK`, `EQ_BURN`, `EQ_HIDE`, `EQ_H`, `EQ_COVER`, `EQ_RANGE`); states `Q_FIXED` / `Q_STOWED`; new hashed arrays `q_face`, `q_len`, `q_seen`, `u_fws`, `u_fwc` (only with works, `fw_on`). Stakes 20 x 3 m: charges stop dead (momentum lost, a rider wounded 5 % x (100 + momentum) / 100, a horse thrown 40 % x momentum), foot at half pace unhurt, 400 hp hacked by enemy foot standing in them, burn. Caltrops 10 x 10 m: hidden from the enemy until stepped in (`q_seen`), wound foot 6 % / riders 12 % / beasts 8 %, slow, a 300-man stock. The camp (scenario `fortified`: side; `Scenarios.camp`): a wooden palisade on a 2 m earth bank 14 m round the side's units (front, flanks, back if room) in sections of at most 20 m (900 hp each, they burn: a burnt section is a gap), open gaps only (2 front, 1 back; no gates), a 1.5 m ditch outside; enemies climb its 4 m in 5 s; the height rules (melee, charge uphill, range) read the works' height on any map (`gh_at`); its missile troops get 12 % cover and +8 % range. Entitlement `Scenarios.works_allowance`: Workshop 0 / 1 / 2 = none / 2 lines / 4 lines + 2 fields, a fortified army +2 lines +1 field of its own; campaign by the lead faction's best Workshop (`CBattle.works_of`), field battles only, formula untouched; custom battles "Field works" and "Fortified" options. Deployment `ORDER_WORKS` (through the lockstep with the issuer's side). AI (`FW_PLACE`, `FW_AHEAD`, `FW_CAMP`, `CAMP_HOLD`): Easy none / ignores the camp, Average stakes across the centre, Skilled before missile troops and on the flanks, caltrops beyond them; a fortified side before its gaps, archers on the rampart (`A_WORKS`), foot inside the gaps, holds. View: `game/works_layer.gd` (both soldier paths), palette Stakes n / Caltrops n / Rotate / Remove, drag to lay, second tap to turn, ghosts of pending placements, icons stakes / caltrops / palisade / rotate, pre-battle card line. See DESIGN.md "Field works and the fortified camp", AI.md 22, CAMPAIGN.md "Field works" | Built 2026-10-09, committed; check_scripts clean; determinism full PASS (new `--only=stakes`: the charge 0 impacts vs 45 without stakes, foot through stakes up to 6 m behind, unhurt, riders 2.9x as long in the caltrops, 684 of 6,000 hp lost, stock 262/300, found; stakes hacked down, burnt down; `--only=fortified`: 18 palisade sections + 7 ditch runs, AI archers on the rampart, range 151 vs 140 m, 7 missiles stopped, climbing and height melee, the elephants stopped at the ditch, 2 impacts vs 9; both identical on repeat and across snapshot / restore; golden digests and every other run's alive / winner / final hash unchanged), lockstep full PASS (deploy coop: players place stakes / caltrops and turn one through the lockstep, the AI its own, C joins by snapshot, riders charge across them), custom_battle_test, battle_screen_test, campaign_test (fortified battle carries `fortified`, entitlement by Workshop), input_test (palette, drag, turn, remove, caltrops, ready); campaign_sim 6x60 = HEAD 8847f51's 7dbe4251 a56c5e4f b1ee756c 0e0d3920 9c156d00 b3ae1fa9; bench_2000 1.31 -> 1.31 ms. **Needs tuning (not done):** every field-works number; AI cavalry does not avoid stakes; no balance run; not yet played on phones |
| Light artillery (item 4f, point 3), 2026-10-09: two data rows (`UnitTypes.LIGHT_ART`, appended after the war dogs; no new sim code): **Scorpions** (`scorpions`, line "light_art", CLS_ART): 6 engines x 2 crew (12 men, crew_min 1), carried: packed pace = the row's walk 150 (1.26 m/s measured; Bolt Throwers 0.69), set up 1.5 s / pack 0.8 s (`deploy` 15), 160 m (70 % of 230), 72 dmg (60 % of 120) / 70 ap, `m_pierce` 2 (heavy bolts still 2), 5 s reload, 8 + 8 bolts an engine, e_hp 60, 396 a unit (Archers and Bolt Throwers both 400); Rome, Carthage, Macedon, Epirus, Greeks, Syracuse, Workshop 1 (`ART_LEVEL`); heavy bolts by `AMMO_AVAIL`. **Gastraphetes** (`gastraphetes`, line "belly_bow", CLS_MISSILE): archers' body, 160 m, 48 dmg / 50 ap, 10 s a shot, 20 shots, flat (`m_arc` 0, `m_apex` 3), no skirmish, arrows kind (drawn as arrows), 400; Greeks and Syracuse, `UNIT_NEEDS` Range 2. New generic field `carried` (AI and campaign only): siege AI `_att_art` sets carried batteries up at min(S_ART_OUT, range x `S_LART_PCT` 85 %) of the attacked gate and shoots the wall unit nearest the gate within `S_LART_WALL_R` (80 / 120 m; `_lart_wall_target`), else the gate; Easy (`S_LART_PCT` 0) leaves them where they stand; `_art_ready` ignores them (not gate breakers: ladders and hackers unaffected); armies with them march at the foot's pace (`CState.max_mp`). Campaign: rosters, LINE_CHAIN, LINE_ORDER, mixes light_art 3 / belly_bow 3 through `CAI.BEAST_LINES`, a mix with light_art builds a Workshop, test switch `CData.no_light_art` / `campaign_sim --no-light-art`. View: unit icons 18 / 19, picker rows (belly-bows after archers, scorpions before bolts), unit book (fractional set-up time, "Carried by the crews" pace line), building names. icons.png regenerated (gallery reads `UiIcons.NAMES`). See DESIGN.md "Artillery" (light artillery), AI.md 15, CAMPAIGN.md rosters | Built 2026-10-09, committed; check_scripts clean; determinism full PASS (new `--only=light_art`: packed by tick 9, marched packed at 1.26 m/s, set up 15 ticks after stopping, 48 bolts striking 95 men, at most 2 men a bolt, crews drop them and archers take them up and shoot on, gastraphetes first shot from 132 m (archers stand at 119), 3 shots a man in 30 s, identical on repeat and across snapshot / restore; golden digests unchanged; all 103 runs' alive / winner and final hashes identical to HEAD); lockstep not run (lockstep.gd and engine sim code untouched); custom_battle_test (field case: both rows build and shoot), campaign_test (rosters, needs, kinds, recruit determinism + JSON, auto-resolve by price, march pace, battle runs); campaign_sim 6x60 unchanged 7dbe4251 a56c5e4f b1ee756c 0e0d3920 9c156d00 b3ae1fa9 (also with `--no-light-art`: the AI never recruited them in these runs); bench_2000 1.31 -> 1.30 ms. **Needs tuning (not done):** every number of both rows; the 136 m firing line is inside walls-2/3 archers' reach; no own engine sprite (bolt thrower's); no balance run; not yet played on phones |
| Mantlets (item 4f, point 4), 2026-10-09: `EQ_MANTLET` 9, a piece in the `q_*` tables with a column in every per-kind table and new fields `EQ_SCREEN` 60 % (arrows, slings, javelins), `EQ_SCREEN_BOLT` 30 % (stones 0), `EQ_SCREEN_W` / `EQ_SCREEN_D` 6 x 6 m; `EQ_ROOF` now holds the roof % per kind (ram / wagon / tower 70, mantlet 40 within 6 m). Standing (`Q_GROUND`, facing `q_face`) it stops that share of the missiles about to strike its side's (`q_side`) men in the rectangle behind it when the shooter is in front of its line (`_screen_cover` in `_land` / `_land_bolt`, `stat_mantlet_cover`); carried by any foot unit of either side at its walk (not riders, beasts, dogs, engines); Drop stands it at the unit's anchor facing its way; 600 hp, burns, bolts / stones landing on it batter it. Scenario key `mantlets` [side 0, side 1]: standing 2 m before each side's missile / artillery units (`mt_on`; `q_face` hashed only then). Campaign: assault after 2 siege turns 2, after 3 four, any walls (`CBattle.MANTLETS`, derived, VERSION 6), panel and pre-battle card lines; custom battles "Mantlets: none / 2 / 4" per side, any map. Siege AI (attackers, every level): spare light foot / missile units carry them to 2 m before the missile units' posts on their shooting line, then scorpions, then the heavy batteries (none: 60 m from the gate), drop facing the wall, back to the plan (`A_MANTLET` 36). View: plank bar with posts, carried / charred / burning, "PICK UP THE MANTLET", "carrying a mantlet", UI icon "mantlet" (custom option, card line; icons.png regenerated). See DESIGN.md "Mantlets", AI.md 23, CAMPAIGN.md "Siege equipment" | Built 2026-10-09, committed; check_scripts clean; determinism full PASS (new `--only=mantlets`: field 50 missiles stopped, screened archers lost 42 vs 52, a carried mantlet dropped facing up; walls-1 assault: the AI carried 4 and set them by tick 759, 17 missiles stopped; identical on repeat and across snapshot / restore; golden digests unchanged), lockstep full PASS, custom_battle_test (mantlets 4 / 2 field and settlement), campaign_test, battle_screen_test; campaign_sim 6x60 324307b6 bb0532b7 b9e5ae32 0bf0a9f8 b77014f8 481344a4 = HEAD 60e59b7's own output (the campaign AI build-up commit changed them; nothing here enters the formula). Probe (walls-1 ring fair siege, ladders + ram, seeds 1-3, 4 mantlets vs none), screens before the missile units' posts on the cover line: 11-14 missiles stopped a battle, attacker missile / artillery men lost by the breach 8 / 3 / 9 vs 10 / 1 / 3, by tick 4000 182 / 163 / 159 vs 155 / 157 / 157 (a first placement at the battery line stopped none: out of the wall archers' reach). **Gaps:** defenders and the field AI ignore mantlets; no sheds; numbers untuned; not yet played on phones |
| Campaign AI build-up (AI.md 24), 2026-10-09: the AI never built a Workshop (every capital's slots start full; the Workshop came last in the want list) and few Range 2s (farm / market upgrades first, money spent on cheap level-1 buildings elsewhere). Now `_buildup` builds a Range 2 and then a Workshop (Skilled: Workshop 2) at the first centre that has it or a free slot, first once that centre has a farm and a market, saving for it and keeping its last free slot; each army with 3+ (Skilled 2+) missile / artillery units holding at a Workshop centre gets a wagon; a line the recruiting centre cannot raise is raised at the next centre that can (scorpions, gastraphetes). Knobs `BU_RANGE`, `BU_WORKSHOP`, `BU_BUDGET_PCT`, `BU_SAVE`, `WAGON_MIN` (Easy 0: as before). Kinds need no order (automatic from the buildings). campaign_sim 6x60: turn 40 Range 2 28/29 and Workshop 1 26/29 of the 4+-region factions (before 9/25 and 0/25); at 60: 13 wagons, 5 scorpions, 6 gastraphetes, 141 units with a kind (before 0 / 0 / 0 / 23); pacing of the same order; new hashes `324307b6 bb0532b7 b9e5ae32 0bf0a9f8 b77014f8 481344a4`; `--no-buildup` gives the old ones. Not tuned | Built 2026-10-09, committed (60e59b7); check_mine clean; campaign_test PASS; campaign_sim hashes reproduced by the main session |
| Field rebalance (2026-10-09; bounded: baseline once, one change set, one correction round): `BASE_HIT` 35 -> 40 (`FLANK_BONUS` / `REAR_BONUS` were raised to 35 / 50 in the correction round and put back to 25 / 40 by the main session: with them Skilled vs Average fell to 40 % and bench_2000 stayed undecided) (melee after "ranks hold together" was too slow); **wrap at the anchor level** (`_curl`, `WRAP_GAP` 1 m, no state: the front-rank places of files beyond an engaged target's flank curl forward round it by as far as they stand out, at most its depth, so the men keep their 1.5 m / 3 m caps but lap round a narrower enemy; three units on a 10-man remnant had 3 men in reach); **bolts pin**: a unit an artillery shot strikes does not advance for `PIN_TICKS` 0.8 s (`u_shelled_t`, hashed already; walking units on field maps only: a charge or a rush goes through, wall and tower engines untouched), bolt fear 15 -> 22, scorpion fear 8 -> 15; scorpions 72 -> 90 damage (a bolt now kills a pikeman outright); new generic field `m_spen` (% of the missile shield a missile goes through): javelinmen 15, Light Horse 10 (pilum-style); battle AI: a missile unit back from falling back out of ammunition with no wagon, woods, engines or routers near **withdraws** (such units at their own edge kept beaten sides on the field to the time limit); new `tests/matchups.gd --only=yard` (30 yardsticks: missiles, pinning, camels, elephants, dogs, light horse, the general, stakes, mantlets) and minutes in the FAIR line. Before -> after (`--fair=20`, 40 battles each; scripted 20 seeds):<br>Average mirror 22-17-1 draw, 8.4 / 15.0 min mean / max -> 24-16-0 (bottom-side bias within noise), 6.5 / 9.8; Skilled vs Average 60 % -> **47.5 %** (after the change set alone 55 %, with the 35 / 50 bonuses 40 %; 40 battles carry about 8 points of noise); Average vs Easy 67.5 % (3 draws) -> 76 % (1 draw, at the limit); matchups `full` bench_2000 10 seeds 8.1 / 10.5 min -> 7.0 / 12.2; terrain AI battles 8.1-9.8 min mean, 1 draw -> 6.4-8.2, max 9.8, none; benchmark: bench_2000 (seed 42) undecided at 6000 -> decided 5091, bench_4000 decided 4751 -> 4791, bench_4000_city undecided -> decided 5731.<br>Yardsticks (full load, standing target): arrows vs light 120 at 100 m 71 %, cav 86 %, heavy front 5.3 % (unchanged: far above the "quarter" asked for; not cut against the owner's "a little weak"); slingers vs light at 140 m 51 % (archers at 100 m 71 %: ~2/3), vs heavy 0.2 % (unchanged); javelins vs cav walking in 54 -> 55 %, light 16 -> 19 %, heavy 2.0 -> 3.6 % (asked 15-25 / - / 5-10 %); bolts along a pike block 35.6 % (asked 15-25 %, unchanged), heavy 100 walking 200 m at a battery closes in 157 -> 183 s (bolts) / 180 s (scorpions); scorpions on the pike block 12.5 -> 17.5 % (archers 88, bolts 36); new rows as their tables intend: camels charging cav win 95 %, cav charging camels loses (as a standing cav line), elephants break heavy 100 in 12/20 and break under javelins 20/20, dogs break javelins / slingers 20/20 and lose 32 of 48 on heavy foot, light horse loses to archers (36 of 60, 0 killed), the general flips heavy vs heavy from 30 % to 100 % (never broke), stakes cut a frontal charge's kills 25.6 -> 3.5, 4 mantlets 39 -> 29 archers lost. Scripted matchups otherwise within noise (round robin: javelins now beat spears 90 %, was 40 %); light infantry still wrecks bolts in 3.9 s. **Still off:** Skilled vs Average (47.5 %, target 65: its reserves and rotation seem to cost more than they gain now that melee is faster; an AI-competency pass of its own, by the AI.md 11 ablations, not a sim number) and the javelin / arrow / bolt kill bands (see above; they need the owner's call on the yardsticks); the mirror's longest battle 9.8 min; the AI knobs `WG_EMPTY_PCT`, `AK_WAVER_PCT`, take-up 60 m kept (not measured against). Not changed: sieges, walls, ammunition, resupply, the formula. See DESIGN.md "Ranks hold together in melee" (wrap at the anchor level), "Artillery" (pinning) | Built 2026-10-09; check_scripts clean; determinism full PASS (golden skirmish d618e203..., bench_2000 5a0aadfb..., test_stone_line b9d30256... re-baselined; test_cav_art unchanged; every coverage case still exercised once pinning was limited to walking units on field maps), lockstep full PASS, custom_battle_test, campaign_test, battle_screen_test PASS; campaign_sim 6x60 unchanged 324307b6 bb0532b7 b9e5ae32 0bf0a9f8 b77014f8 481344a4 (auto-resolve by the formula); rules hash changes; not yet played on phones |
| Siege pass, paused (2026-10-09; owner's decision: the siege tuning waits until the settlement movement and ladder bugs are fixed, a separate build, since tuning levers around men who jam at walls is premature). **Kept (harness only, no rule or number changed):** `tests/matchups.gd --only=fair-sieges` row 2 is the **full kit** of a three-turn campaign siege (3 ladder sets, a ram, 4 mantlets as `CBattle.siege_equipment` gives, a tower at walls 2-3, a unit of scorpions; `Scenarios.fair_siege` key `extra` adds attacker units with the defenders' field army reduced by the same strength); `--fair-variants=fort0,fort1` (a side in its fortified camp); 8 missile flank / rear yardsticks in `--only=yard` (archers / slingers 80 at 100 m: pikes 120 flank 99.7 / 94.0 %, rear 99.1 / 89.7 %; heavy 120 flank 77.6 / 69.0 %, rear 72.4 / 49.2 %; front 5.3 / 0.2 %: a stone never outdoes an arrow). **Shelved** (a patch in the session scratchpad, `rebal/siege/SHELVED.patch` + README; to resume after the movement fix): `TOWN_PLACE_LEAD` 10 m, `WALL_COVER` 25 / 25 / 40, `TOWERS_MAX` 3 / 4, `GATE_HP_PCT` 100 / 115, `GATE_FIRE_CHIP` 15 / 8 / 6, Skilled `SK_STORM_STAGGER` 0, the settlement AI taking up crewless engines, the formula's walls term `WALLS_PCT` by walls and kit with `FORTIFY_DEF_PCT` 123, Skilled `SHELTER_PCT` 70. **Findings:** bisect (fair sieges walls 1, ladders + ram, over the day's commits): ring / polis 40 / 50 % until the melee commit 15ef028 ("ranks hold together"), 0 / 30 % from it on; cause: with the field's 1.5 m `PLACE_LEAD` a column coming out of a gateway fights only with the men at its places (they stand in the walls) against the stack's whole frontage (no cap in towns: 70-100 %). Skilled attackers lose more than Average because their staggered storm feeds units one by one into the stack (ablation: stagger off ring / polis walls 1 0 / 20 -> 70 / 40 %). At walls 2-3 the attackers' archers kill almost no wall men (a probe: 2,700 arrows, about 400 landing near a target, mostly at tower crews). Equal-force sieges, attacker wins, both Average, 10 seeds (ladders + ram / artillery only / full kit), HEAD -> shelved state:<br>ring walls 1 0 / 0 / 0 -> 40 / 10 / 40 %; walls 2 10 / 0 / 0 -> 10 / 10 / 30 %; walls 3 0 / 0 / 0 -> 10 / 0 / 10 %;<br>polis walls 1 30 / 20 / 40 -> 60 / 20 / 50 %; walls 2 0 / 0 / 0 -> 0 / 40 / 10 %; walls 3 0 / 0 / 10 -> 10 / 10 / 10 %; the attackers withdraw in most losses, draws 0-20 %, 8-11 min mean.<br>Full kit walls 1 / 2: Average vs Easy defender ring 0 / 0 -> 40 / 0 %, polis 10 / 10 -> 10 (50 % draws) / 10 %; Skilled vs Average defender ring 0 / 0 -> 70 / 0 %, polis 20 / 0 -> 40 / 0 %. Fortified camp (HEAD): an Average army in its camp beat an equal one 13 of 20. Calibration (`campaign_battles --only=calib --n=60`), HEAD -> shelved state: formula favourite won 49 -> 54 of 60 (82 -> 90 %); attacker wins sim 30 / formula 34 -> sim 30 / formula 29 %. campaign_sim 6x60 of the shelved state 704eeec1 96b2efba 3fa67102 3e463360 4263d23c e202ac8c (sieges started / assaulted / won / lifted 84 / 69 / 48 / 32 -> 77 / 61 / 41 / 31). Ladder reports (one ladder at a time, the last men never climbing, the unit refusing orders): not diagnosed here (moved to the movement build; a scratch probe found throughput as designed with no defenders and piecemeal deaths with 60 defenders above) | Harness kept 2026-10-09, not committed; check_scripts clean, determinism full PASS (sim untouched, goldens = HEAD) |

### What exists

- **Battle sim** (`sim/`): deterministic, integer-only, per-soldier, 10 Hz.
  Nine unit types (heavy swords, light infantry, spearmen, pikemen, archers,
  javelinmen, shock cavalry, bolt throwers, stone throwers); melee with
  shields, armour and flank/rear bonuses; multi-rank pikes; projectiles with
  friendly fire; cavalry charges with knockdown and brace reflection;
  artillery engines with crews, set-up / pack-up, piercing bolts and
  ploughing stones; morale, routing, withdrawal; a battle
  AI that only issues orders; a plain-data battle result for the campaign.
- **Terrain height** (`sim/terrain.gd`, built 2026-10-05): an integer
  height grid (4 m nodes) generated from kind + seed + a few parameters
  (flat, rolling, ridge, valley, hill, slope, or hand-placed features),
  hashed into `state_hash()`; slopes slow units (cavalry and artillery most),
  higher ground helps in melee, charges hit harder downhill, missiles reach
  further from above, javelins and bolts are blocked by crests, stones
  plough less uphill; the AI uses high ground. Drawn as a contour map with
  hill shading in one shader. Details in DESIGN.md "Terrain height: as built".
- **View and controls** (`game/`): one-draw-call soldier rendering from a data
  texture, touch and mouse controls, multi-select, show-all-orders overlay,
  instant order preview while paused, unit symbols, unit book, HUD, telemetry.
- **Tests** (`tests/`): determinism, benchmark, scripted input (needs a
  window), balance matchups across seeds.
- **Tools** (`tools/`): web export, HTTPS dev server with telemetry logging,
  playtest report, script warning check, server build / run scripts.
- **Server** (`server/`, milestone 4): one Go binary with SQLite that serves
  the web build (brotli), the telemetry endpoint and the online co-op
  campaign API; Discord notifications; Dockerfile and deployment files.
  Reference: `docs/SERVER.md`. Client side: `game/net/`,
  `game/campaign/online_ui.gd`.

### What has been proven

- GDScript is fast enough: 4,000 soldiers cost about 9 ms mean, 30 ms worst
  per 100 ms tick on a Snapdragon 865 phone browser (milestone 1 build).
- The sim is deterministic across devices: an Android phone, a Linux desktop
  browser and the native Linux build produced identical hashes for the
  fixed-seed benchmark (milestone 1 build).
- The touch control scheme works; the user likes it.

### In progress right now

**Battle screen on the overworld (built 2026-10-07, item 4b below).**
`game/campaign/battle_screen.gd`, one screen in two states for the solo
and online Battles dialogs. *Pre-battle* (replaces the old auto / fight
card): the settlement's map preview from its seed (`city_preview.gd`; the
arrow is the attackers' approach) or, for field battles (sally, relief,
interception), a ground panel (ground colour, relief, woods %, attackers'
band at the bottom, defenders' at the top); the siege equipment line
(ladder sets / ram from `CBattle.siege_equipment`, towers at walls 2-3);
the odds bar; the buttons right under it (Auto-resolve / Fight; online:
Fight together / Wait for ally / Take command / Join battle, status lines
above them); then both sides as unit cards (symbol with tier mark, men,
tier, short name, a green health bar of men against full strength),
grouped by army with faction colour, support armies marked, the garrison
as its own group, units past the 24-per-side cap shown as "(reserve)".
Attackers left, defenders right (stacked below 640 logical px). *Result*
(after auto-resolve and after a fought battle, campaign only): VICTORY /
DEFEAT / DRAW for the viewer (ATTACKERS / DEFENDERS WIN if not in it),
"Auto-resolved" / "Fought" / "Fought (left the field)" / "Fought
together", the one-line outcome (city taken / held, beaten but not taken,
siege continues / broken, who holds the field, armies destroyed), the same
cards with survivors against fielded (lost part red, "-N"), per-side totals
"Fielded, back, lost (dead, fled). Kills", the event reports, Continue.
Both auto-resolve and fought battles run the sim, so both take the sim's
per-unit tallies from the outcome; the sim counts kills per side, not per
unit (no sim change), so cards show each unit's losses and the side's
kills are the enemy's dead (said on the screen). No rules change: the
outcome dictionary, campaign_sim hashes and `CState.VERSION` unchanged; a
snapshot of the battle (`BattleScreen.snapshot`) is taken when it starts
(`_battle_snap`). Testing aids `--camp-assault=key`, `--camp-auto`.
Screenshots `docs/screenshots/battle_screen_pre_phone.png`,
`battle_screen_pre_cards_phone.png`, `battle_screen_result_phone.png`. Open: play it on the phones (the
landscape phone dialog is short: the preview shrinks to keep the buttons
in sight, the cards are a scroll away).

**Cities must be worth defending, part 2b: siege equipment as objects
(built 2026-10-07).** As built in DESIGN.md "Siege equipment and wall
towers" (the "Siege equipment as objects" and "No blows at walls"
bullets). In short:
- Ladders (sets of 5) and the ram are objects on the ground behind the
  attackers' line (scenario `equip`; campaign: 2 sets after a turn of
  siege, 3 sets and a ram after two; custom Ladders: 3 sets, Ram: 1;
  sandbox kit 1 / 2 likewise). Any attacking foot unit picks one up (tap
  it; `ORDER_PICKUP`), carries it slowly (no running, no attacking, 60 %
  melee), puts it down (Drop button, X; `ORDER_DROP`; routing leaves it);
  ladders are planted on the stretch the carriers are sent to (for the
  battle) and any infantry / missile unit ordered onto that stretch then
  climbs them; the ram's carriers batter a gate (outer, or the citadel's
  from the town) and put it down when it breaks; towers can wreck the ram
  (2,500 hp). The RAM unit type and the per-unit ladders flag are gone;
  co-op: no commander for equipment (whoever's unit carries it), only the
  towers' trailing home entry. UI: pieces drawn on the ground / carried /
  planted, previews "PICK UP LADDERS / THE RAM", "PLANT LADDERS HERE",
  "RAM THE GATE", cards "carrying ladders / ram", refusals, unit book.
  AI (every level): `_assign_equip` gives the ram to the least street-worthy
  foot (pikes first) and ladder sets to the heaviest infantry (S_LADDER_UNITS),
  `S_LADDER_FOLLOW` more infantry climb each planted set, ladder spots are
  scored by the walk too, `S_LADDER_AFTER` 300 (was 1200: carrying is slow).
- Bug B fixed (the unit marched along the wall to the foot and shuffled: its
  anchor never "arrived", its men could not form between it and the wall,
  it regrouped; a foot by a tower got no clear line to a path node): the
  climb starts within 8 m of the foot, units march to an approach point out
  from it. `tests/ladder_probe.gd`: 108 maps (5 plans x 4 sites x coast x
  walls 1-3), 2,432 points the rule allows, 2,432 climbed, 0 failed; 250
  refused (225 tower / gate / sea, 21 citadel, 4 no ground out there).
- Bug C fixed: walls-2/3 gates do not yield to swords (order rule, sim and
  AI); men drop a target they cannot reach within two ticks (was eight;
  1,758 man-ticks "fighting across a wall" in the reproduction -> ~0); the
  AI facing a shut citadel gate brings the ram, hacks only a walls-0/1 gate,
  else waits 50 m out (`S_CIT_WAIT`). Determinism `--only=equipment`
  (scripted pick-up / drop / plant / climb / ram with snapshot mid-carry;
  the shut inner gate), lockstep `--only=siege` (late joiner mid-carry, a
  set dropped by one peer picked up by the other).
- Measured (`--only=fair-sieges`, both Average, 10 seeds, ladders + ram
  row now 3 sets and a ram; attacker wins, mean / max min; da9ff24 ->
  now): ring walls 1 100 % (7.2 / 8.9) -> 100 % (7.2 / 8.0), walls 2 60 %
  -> 50 % (8.8 / 10.7), walls 3 20 % -> 20 %, 10 % draws (10.1 / 15.0);
  polis walls 1 90 % -> 80 %, 20 % draws (11.0 / 15.0), walls 2 70 % ->
  50 % (11.0 / 13.9), walls 3 10 % -> 20 %, 10 % draws (11.9 / 15.0).
  Artillery only: ring 100 / 20 / 40 % (was 100 / 60 / 10), polis 100 /
  40 / 0 % (was 100 / 30 / 0). Walls 3 at 30 min, ladders + ram /
  artillery: ring 20 / 40 %, polis 30 / 10 %. Gates at walls 2-3 now fall
  mostly to the ram (walls 3: 10 of 10). No tuning was done (scope).
  Field battles hash exactly as before (golden digests), so `--fair` is
  unchanged. Tick cost (same session, alternating, worst of two runs):
  bench_4000_city mean 3.35-3.44 -> 3.26-3.27 ms, p95 5.5 -> 5.8-6.0, worst
  7.4 -> 8.3-9.3; polis 3.19-3.28 -> 3.05-3.07, p95 5.6-5.8 -> 6.6-6.7,
  worst 7.0-9.3 -> 10.1-12.1; castrum 3.48-3.56 -> 2.85-2.90, p95 6.7-6.8
  -> 6.0-6.2, worst 8.5-8.8 -> 8.7-9.5 (different battles: no hacking at
  iron gates, the ram; the two-tick reach recheck alone costs ~0.05 ms).
- **Next (decided): part 2c, the walls-1 defender layout (former D: hold the
  attacked gate's inner mouth early, quiet gates' guards to the breach,
  plaza reserve) and the fair-sieges calibration**; then artillery engines
  as pick-up-able equipment with crews as men (decided with the user;
  built 2026-10-09, see "Where we are").

**Cities must be worth defending, part 2a: units do not pass through each
other (built 2026-10-07).** As built in DESIGN.md "Unit blocking and street
fights", AI.md section 14. In short: every ready ground unit's footprint
(its formation rectangle, clipped to its men) is marked in 4 m cells per
side, every other tick, per unit; an anchor never steps into an enemy's
footprint (it steers 30-60 degrees round it where there is room, else stops
and its men fight, a move included), passes through friends at half speed,
and an attacking unit waits behind friends already fighting (or waiting)
near its target: a 10 m street holds one unit a side, the rest queue. Men's
places a cell deep in an enemy are moved back; no soldier-level separation
was needed. The street squeeze (frontage clamped to the corridor) already
existed. Deployment placements inside another unit are refused ("Another
unit stands there"). Skilled defenders hold the inside of a breached gate
(posts either side of it) and bring the idle gate guards to the breach
(knobs `S_BREACH_HOLD`, `S_GUARD_JOIN`, off at Easy / Average: at Average
they did not move walls 1 and cost the defenders above it).
- Measured (`--only=fair-sieges`, both Average, 10 seeds; attacker wins,
  draws, mean / max minutes; before -> after):

  | City | Ladders + ram | Artillery only |
  |---|---|---|
  | ring, walls 1 | 100 % (6.4 / 6.9) -> 100 % (7.2 / 8.9) | 100 % (6.3 / 7.4) -> 100 % (7.1 / 8.1) |
  | ring, walls 2 | 60 % (8.6 / 11.2) -> 60 % (8.6 / 9.6) | 10 % (8.7 / 10.1) -> 60 % (10.4 / 11.9) |
  | ring, walls 3 | 50 % (9.2 / 10.3) -> 20 % (9.5 / 10.7) | 0 % (10.0 / 12.8) -> 10 %, 10 % draws (9.7 / 15.0) |
  | polis, walls 1 | 100 % (8.2 / 10.6) -> 90 %, 10 % draws (10.5 / 15.0) | 100 % (8.7 / 12.6) -> 100 % (9.1 / 11.0) |
  | polis, walls 2 | 50 %, 10 % draws (11.2 / 15.0) -> 70 %, 10 % draws (12.5 / 15.0) | 10 % (9.1 / 14.3) -> 30 %, 30 % draws (10.8 / 15.0) |
  | polis, walls 3 | 10 %, 20 % draws (10.9 / 15.0) -> 10 %, 40 % draws (12.7 / 15.0) | 0 %, 10 % draws (9.2 / 15.0) -> 0 %, 40 % draws (12.0 / 15.0) |

  Walls 3 with a 30 minute limit (before -> after): ring 50 / 0 % -> 20 /
  20 %, polis 10 % (20 % draws) / 0 % (10 %) -> 30 % (20 %) / 30 % (0 %).
  **Walls 1 still misses its 45 % target (100 %)**: blocking works (the
  attackers queue through the gateway and fight a unit at a time) but the
  defenders lose the exchange about 2.4 : 1 anyway: a third of their
  strength (the guards of the three gates not attacked, about 300 men)
  never fights, their reserves march down the main street into the
  attackers spread out inside the gate (the narrow end is theirs, not the
  attackers'), and the plaza capture then breaks everyone. That is AI
  disposition, not movement rules (the Skilled breach hold / guard join did
  not fix it at Average either); next step for the main session.
- Field (`--fair=50`, 100 battles each): Average vs Average 50 / 50, no
  draws, 5.14 -> 5.40 min mean (+5 %), max 8.2 -> 8.0; Average vs Easy 74
  % (1 draw) -> 79 %; Skilled vs Average 77 -> 76 %. bench_4000 (one seed)
  now meets 96 s later (the lines pass through their own missile screen and
  second line at half speed) and lasts 9.3 instead of 5.7 min.
- Tick cost (desktop, same session, before -> after; different battles, so
  the whole-run figures move with what happens): the unit phase +0.18 ms
  (bench_4000 0.26 -> 0.43, bench_4000_city 0.76 -> 0.95: the footprints
  ~0.08 ms a tick averaged, the anchor probes the rest); bench_4000 mean
  2.91 -> 2.35 ms, p95 4.8 -> 5.0, worst 6.5-6.8 -> 6.5-7.1; city 3.31 ->
  3.42, p95 6.0 -> 5.6, worst 8.6-8.7 -> 7.5-8.2; polis 3.23 -> 3.25, worst
  8.4-9.6 -> 7.1; castrum 3.02 -> 3.55, p95 5.5 -> 6.8, worst 8.0-9.0 ->
  9.0-9.6.
- Tests: determinism `--only=blocking` (street fight, pass-through, gate
  jam, gate rush in the gateway and 14 m inside, foot and riders) and the
  re-recorded skirmish / bench_2000 golden digests; lockstep street fight
  with a late joiner; campaign_sim hashes unchanged.

**Cities must be worth defending, part 1: attrition at the wall (built
2026-10-07).** As built in DESIGN.md section 4 "Siege equipment and wall
towers", AI.md section 13, CAMPAIGN.md "Siege equipment". No stat bonus
for standing inside walls. In short:
- Walls-2/3 cities mount **tower engines** (UT `tower_bolt` / `tower_stone`):
  bolt throwers on the towers by the gates and at intervals (6 / 8), at
  walls 3 two stone throwers on the biggest towers; immobile, fixed shots
  (+50 % with a Workshop), crews that can be shot, towers batteries can
  batter down (counter-battery); a card each for the defending player
  (fire / hold, target by tap); the AI defender focuses the ram, batteries,
  men at the gate and on ladders; the AI attacker batters the towers by the
  gate first.
- **Hard gates**: walls-2/3 gates 130 % hit points and 1 % of the old sword
  rate (walls 0-1 unchanged). **Ladders**: attacking foot carrying them tap
  a stretch of wall from outside, march to its foot and climb, a man per
  ladder every 2 / 3 / 4 s (walls 1 / 2 / 3), arriving on the walkway one
  at a time and fighting there, exposed to the walls and towers; once up,
  down into the town to unbar a gate from inside. **Ram**: a slow roofed
  engine unit; at a gate's face it breaks a walls-3 gate in about a
  minute and a half. Battlement cover 25 / 45 / 70 % (was 25 / 35 / 65),
  wall archers reach 15 % further at men below at walls 2-3 (walls 1
  unchanged). AI at every skill uses and answers all of it (knobs
  `S_LADDER_*`, `S_TOWER_FOCUS`, `S_COUNTER_BAT`, `S_ESC_REPLY`,
  `S_RAM_WAIT`).
- **Campaign**: an assault after a siege of a turn brings ladders, of two
  a ram (derived from the siege entry's turn; no state change, VERSION 6);
  siege panel line "Siege equipment: ..."; auto-resolve formula untouched
  (campaign_sim 6 x 60 hashes equal HEAD's). **Battle time limit**:
  scenario `time_limit` (absent = 900 s, hashed only when not), campaign
  `settings.time_limit` ("Battle time: 15 / 20 / 30 / 45 min"), custom
  battles (Battle time; Ladders / Ram toggles), sandbox settlement row
  (siege kit, minutes); HUD clock "m:ss / limit".
- Measured (`tests/matchups.gd -- --only=fair-sieges`, equal strength,
  both AI Average, 10 seeds; attacker wins, mean / max minutes):

  | City | Ladders + ram (siege of 2 turns) | Artillery only (on arrival) |
  |---|---|---|
  | ring, walls 1 | 100 % (6.4 / 6.9) | 100 % (6.3 / 7.4) |
  | ring, walls 2 | 60 % (8.6 / 11.2) | 10 % (8.7 / 10.1) |
  | ring, walls 3 | 50 % (9.2 / 10.3) | 0 % (10.0 / 12.8) |
  | polis, walls 1 | 100 % (8.2 / 10.6) | 100 % (8.7 / 12.6) |
  | polis, walls 2 | 50 %, 10 % draws (11.2 / 15.0) | 10 % (9.1 / 14.3) |
  | polis, walls 3 | 10 %, 20 % draws (10.9 / 15.0) | 0 %, 10 % draws (9.2 / 15.0) |

  Walls 3: about 30 % with ladders and a ram (target 25 %), none on
  arrival; walls 2: 55 % / 10 %. **Walls 1 misses its target (100 %
  against 45 %)**: walls 1 has no towers and its gate falls to artillery
  in about two minutes, so the battle is decided in the street fight and
  the plaza capture; the wall levers moved it 10 points at most (cover 50
  / 60 %, range +20 / 30 % tried) and were left at the old values (walls-1
  battles hash as before). That is part 2's job (units that do not pass
  through each other, the slow street fight). The polis's walls-3 draws
  are stand-offs at the acropolis: a 30 minute limit leaves the same 20 %
  undecided. Ladder parties go up (80-140 men a battle) but rarely live to
  unbar a gate (towers and wall archers shoot the queues); the ram
  breaks most walls-3 gates.
- The 1.5-2:1 sets changed as expected (attackers have artillery but no
  ladders or ram there): `--only=plans` walls 3 attacker wins (before ->
  after) ring plain 100 -> 20 %, ring hill 80 -> 30 %, castrum 90 -> 70 %,
  polis coastal 60 -> 10 %, polis plain 90 -> 10 %, punic 60 -> 0 %,
  oppidum spur 80 -> 20 %, oppidum plain 60 -> 30 %; walls 2 ring 100 ->
  80 / 100 %, castrum 100 -> 100 %, polis 100 -> 40 / 40 %, punic 90 -> 10
  %, oppidum 90 -> 50 / 70 %; walls 1 unchanged. `--only=sieges`:
  garrison-only walls 2 / 3 with artillery 100 -> 90 / 50 % (draws 10 /
  50 %), without artillery 100 -> 0 % (all draws: no way in without a ram
  or engines, by design); city walls 2 90 -> 60 %, hill city walls 3 100
  -> 20 %. Battles run longer (walls 3 9-14 min mean, several to the 15
  minute limit).
- Tick cost (`benchmark.gd`, same session, base / new): bench_4000_city
  mean 2.84 / 3.15 ms, p95 5.54 / 5.72, max 7.18-8.11 / 7.01-7.08 (the
  6.5 ms target is missed by the base too on this machine today);
  bench_4000_polis max 6.64 / 7.52, castrum (walls 3) 5.99 / 7.64;
  bench_4000 unchanged (6.14 / 6.22).
- Determinism: every golden digest and the final hash of every field
  battle and walls-0/1 city (`siege_village`, `gate_ops`, `cit_ops`,
  `siege_oppidum`) equal HEAD's; walls-2/3 cities changed (towers, gates,
  cover). New runs `siege_eq_ring3` (walls 3, ladders, ram, towers, 20 min
  limit) and `siege_eq_polis2~sa` (ladders, a Workshop, Skilled attacker),
  snapshot / restore; lockstep: snapshot mid-climb, two peers plus a late
  joiner on the walls-3 siege.
- **Open / next:** walls 1 (part 2); escalade rarely unbars a gate in AI
  play (the parties die at the wall; a Skilled timing or more ladders may
  help); the polis's acropolis stand-offs; in live co-op the towers belong
  to nobody (they fire at will); play it on phones (tower cards, ladder
  taps, the ram). Screenshot `docs/screenshots/siege_ladders_ram_phone.png`.

**Deployment phase and custom battles (built 2026-10-06).** As built in
DESIGN.md section 4 "Deployment phase" and section 5 "Custom battles and
head-to-head"; server: SERVER.md section 18. In short:
- Battles may open with a Total War deployment phase (scenario
  `deploy_time`): the clock stands at 0, nothing moves or shoots, players
  place their units inside their zone (`ORDER_PLACE`: the ordinary tap /
  line / group gestures, clamped into the zone on the field, inside the
  walls or onto a walkway in a defended town) and press Start battle /
  Ready (`ORDER_READY`); it ends when every player is ready or the
  countdown runs out. AI sides show their line from the start (field
  maps). Zones drawn; a bar with the countdown and who is ready. Campaign:
  new-campaign "Deployment time: none / 1 / 2 min" (default 1 min;
  `settings.deploy_time`, no VERSION bump; older and online campaigns
  made before have none; auto-resolve ignores it); live co-op goes from
  the lobby into the deployment.
- Custom battles (start screen and sandbox page): field or settlement
  map, two sides of 1-3 armies of up to 12 units from the whole roster with
  campaign prices and optional equal funds, controllers Player 1 / Player
  2 / AI (skill and personality per side), deployment time, templates (the
  sandbox's battles and test matchups). Solo at once; online by a custom
  battle room (code, lobby where Player 2 may edit Player 2's armies, both
  Ready, the host starts): co-op on one side or head-to-head.
- Head-to-head in the lockstep layer: players have sides; gifts only to
  the same side; a dropped / leaving / absent player's units go to a
  player of their side, else the battle AI takes the side (handed back on
  return); votes unchanged.
- Server: `POST /api/custom`, `POST /api/custom/join`, WebSocket
  `/api/custom/{code}/ws` (lobby `setup` / `lobby` messages, then the live
  relay); memory only; `api: 3`.
- Tests: determinism_test (deployment: field and town, repeat and
  snapshot / restore mid-deployment and mid-battle, clamping, refusals,
  walls, AI line, countdown; golden digests unchanged), lockstep_test
  (deploy co-op with an early ready and a join during the deployment;
  head-to-head with the countdown, refused enemy placements and gifts, a
  drop with AI takeover and return; a drop during the deployment),
  custom_battle_test (every template and hand-made setups build
  identically and run), live_e2e (the three campaign battles now with a
  10 s deployment, plus a custom head-to-head and a custom co-op battle
  over the real server), go test (custom rooms), check_scripts,
  input_test, campaign_input_test.
- Decisions to know: the battle AI commands whole sides, so an "AI" army
  on a side with a player's army is commanded by that player, and AI
  skill / personality is per side; the side-2 player sees the map
  unrotated (their army at the top); the server never checks the setup
  (the clients' scenario hashes must agree before the start).
- **Open / next:** play it on the phones (placing by touch, the zone and
  bar on a small screen, the lobby); per-army AI on a mixed side; turning
  the view for the top side; mirrored-fairness (53-55 % bottom bias)
  matters more head-to-head; a lobby chat / rematch button.

**Continuous campaign overworld (built 2026-10-06, uncommitted).** Design
agreed with the user; rules, numbers, grid format, orders, state, AI and
pacing as built in CAMPAIGN.md "The continuous overworld (version 6)". In
short:
- A static nav grid (`campaign/data/grid_data.gd`, 138 x 70 cells of 20 map
  px, generated from the map by `tools/campaign_grid.gd`): armies stand on
  cells and march A* paths (foot 200 points, cavalry 300, artillery 150; a
  cell 10-20 by terrain, diagonals 14/10; Roma -> Tarentum two turns on
  foot, one for cavalry), continuing on later turns; sea lanes port to
  port.
- Zones of control (2 cells, 3 fortified): paths keep out of enemy zones
  unless attacking; a step next to an enemy army is a field battle on its
  cell (rounds, armies by id: the lower id attacks head-on); one battle
  per region. Moving onto a hostile city lays siege from its ring (or
  storms it on arrival); onto your own: inside the walls; inside a
  besieged city onto a besieger: a sally; on your own besieged city: a
  relief. Besiegers lose 5 % a turn once the city starves. Support within
  4 cells (6 fortified), deploying from its bearing. Stances: default,
  forced march, fortify, raiding (takes half the region's income).
- AI with static distance fields per settlement: sieges, hunting enemy
  field armies, attacks with gathering a march short of the target,
  raids, screens, forced marches, fortifying; ~16-19 ms a full AI turn
  (first turn ~130 ms for the fields). Pacing (6 seeds x 60 turns):
  largest at turn 30 median 8 (before 10), no faction reaches the victory
  size by 60, field battles 6-27 a campaign (before 1-7); deterministic.
- State format 6; 5 -> 6 migration (local saves); unmigrated online
  campaigns of formats 1-5 play exactly as before (6 AI campaigns x 60
  turns from format 5 give HEAD's hashes; format 4 HEAD's table). No server
  change; the server binary needs no restart.
- The battle sim gained an optional per-unit `morale_pct` scenario key (an
  army caught on a forced march); existing scenarios unchanged
  (determinism_test PASS).
- View (phone first): armies at their cells, the reach area, enemy zones,
  yellow support and red attack lines, tap-then-tap planning (enemy army =
  attack, city = siege or inside, land = march; same spot = cancel) with
  Undo, drag from an army to plan (elsewhere pans), paths solid / dashed
  with the end-of-turn ring and an intent badge, one stance selector, the
  siege panel's Assault / Continue siege / Withdraw, a skippable replay of
  the turn's steps. The move-mode toast, the stance toggle, Maintain and
  Sally are gone for format 6. Screenshots
  `docs/screenshots/overworld_phone_*.png`.
- Tests: campaign_test (format 6 suite: grid, paths, zones, turns, contact,
  sieges, sally / relief, support, stances, raiding, migration, step log,
  determinism; the older suites on format 5 states), campaign_sim
  (`--format=5`, `--twice`), campaign_solo, campaign_battles,
  campaign_input_test (windowed; v6 and v5 parts), check_scripts,
  determinism_test, online_e2e (scratch port 8077), go test.
  `tests/touch_scroll_test.gd` fails two recruit-list scroll checks, the
  same on HEAD (not from this change).
- **Merging, exchanging and gifting (fixed after the playtest "lots of 1
  and 2 stacks at the same location", 2026-10-06, uncommitted):** tap your
  other army to merge (marches to it and follows it over the turns), the
  `exchange` order and panel (also gifts to the allied player), Merge into /
  Exchange units at the top of the army card, recruits and idle armies in a
  city gather into one army at the end of the turn (CAMPAIGN.md "Merging,
  exchanging, gifts"). No version bump; AI pacing unchanged within noise.
  Open: try it on the phones.
- **AI and the mustering rule; merge glyphs (2026-10-06, uncommitted):** the
  campaign AI (format 6) plans moves before recruits and never recruits
  into an army it marches (holds a small one or raises a new army):
  refused "mustering" AI moves 37-57 per seed -> 0 (CAMPAIGN.md
  "Recruiting into armies"); the merge plus only shows where a tap would
  merge (`merge_why`: the real merge / join / path checks, cached per
  selection and plan).
- **Reordering units by drag and drop (2026-10-06, commit 0babb12):** battle
  card strip: drag a card (touch: long press until it lifts, then drag) to
  a new place; a view-only display order per player and battle (nothing in
  the sim or lockstep), All / Inf / Missile / Cav select in it. Campaign
  army card: the same gesture on unit rows plans an `arrange` order
  (step 2, any format, one per army and turn, Undo per drag); it sets the
  order units take the field in. Shared helper `game/drag_reorder.gd`;
  `TouchScroll.hold` keeps a lifted row from scrolling. On a touch screen
  the long press on a card or army row now opens the unit page on release
  (after the lift) instead of while held. No state version bump (a new
  order type). Controls page rows `card_reorder`, `map_army_reorder`.
  Screenshot `docs/screenshots/reorder_phone.png`. Open: try it on the
  phones (the 0.35 s lift, the long press -> book on release).
- **Gate doorway taps (phone playtest fix, 2026-10-07, view only):** gate
  doorway taps win over unit markers and toggle for the defender whatever
  is selected (`game/battle.gd` `_gate_doorway`; tests in `input_test.gd`).
- **Open / next:** play it on the phones (tap-tap planning, drags, the
  replay; whether a tap inside an enemy zone should become an attack
  instead of a refusal); the version 5 testing aids `--camp-raid`,
  `--camp-intercept`, `--camp-attack` are not adapted to format 6;
  fortify has no real-battle effect yet (odds and formula only);
  forced march: morale only, no smaller deployment; siege equipment over
  turns; roads / rivers / fords as grid overrides; Epirus still falls in
  most AI-only seeds and Rome in 2 of 6.

**Wall orders (phone playtest fixes, built 2026-10-06, uncommitted).**
Report: "loading on or off a wall is difficult. It doesn't display where
the units may go, and they don't seem to fit; once I pulled the javelins
down I couldn't get them back on the wall." Found: (1) only a tap within
3 m of a walkway's centre line counted as "up the wall" (a 6 m band of an
8-16 m wall plus towers); a tap on the parapet, inner face or a tower was a
ground move to a blocked spot; (2) a unit standing near the wall (inside
the 12 m reform distance, e.g. just pulled down) ordered up only reformed
in place and never climbed; (3) wall units stood in up to 3 ranks of 2 m
(off the 4 m walkway: 25-60 % of the men of every garrison unit stood in
wall cells) and the whole line turned with its target; on stretches of
12-20 m they piled 5-6 deep. Fixed (rules in `sim/battle_sim.gd`, DESIGN.md
"Walls" / "Stairs"):
- any tap on a wall's body, walkway, stair, tower or gate tower snaps to
  the nearest walkway point of its stretch (`wall_snap`, in the order rule:
  preview and sim agree; lockstep peers snap the same raw input); the way
  up is always a march to the stair;
- the wall line: two ranks (at most 1.2 m apart) along the walkway, centred
  on the tap, clamped to the stretch, spilling through a tower onto the
  joined stretch (towers passable to wall units only), surplus at the
  ends; garrison units start in it; men never jittered off the walkway;
- coming down: in the unit's normal block (`ground_files`); men on a stair
  move follow the stair's trail (junction, walkway, stair, foot);
- view: the predicted wall line, stretch(es), stair (ringed) and route
  (dashed) going up and coming down, and the ground footprint below;
  stretch under the mouse lit; refusals ("Cavalry cannot man walls", "No
  ladders yet...", "No way to a stair..."); buttons "Man the wall" (M:
  nearest stretch within 60 m, the one nearest the enemy) and "Come down"
  (Shift+M: the nearer stair's foot); Controls page and unit book updated.
  Screenshots `docs/screenshots/walls_order_up_phone.png`, `..._down_phone.png`.
- Drag clamp: a formation line is at most one rank long (men x file
  spacing, a group: the sum plus gaps); the line stops following the finger
  there (solid end caps, "ONE RANK"); the order rule already capped files
  at the men alive.
- Reachability (same playtest, attacking a city: "the formation goes past
  the walls ... sliding along the wall in clumps"): pieces of open ground
  with the gates as connectors; moves to unreachable ground go to the
  nearest own ground (a tap on a house / wall) or to the gate on the unit's
  side and hold there; attacks on a unit inside: melee to the gate (attacking
  foot hack it, go in once it breaks), missile troops only as far as their
  ground goes and shoot from range; places kept to the anchor's ground.
  Captions "No way in: moving to the gate", "Moving into range". DESIGN.md
  "Settlements (rules)" / Reachability. Benchmarks (run side by side with
  HEAD, so noisy): city 2.71 -> 2.87 ms mean (p95 5.1 -> 5.6), polis 2.87
  -> 3.05, castrum 2.76 -> 2.98; setup +20-30 ms.
- Tests: determinism_test "wall orders" (down and back up by walkway,
  parapet, tower and Man the wall; spill; repeat + snapshot), "drag
  clamp" and "reachability" (tap into a shut town holds at the gate with no
  man strung out; attack on a unit inside: to the gate, hack, in once
  broken; archers shoot from outside; no place off its ground); flat golden
  digests unchanged; every settlement hash changed (the open village too,
  from the reachability rules); lockstep (both sides, both maps) and
  input_test pass.

**Free campaign movement (built 2026-10-06, uncommitted).** Design agreed
with the user; rules, orders, state, AI, pacing as built in CAMPAIGN.md
"Free movement (version 5)". In short:
- Movement points by the slowest arm (foot 20, cavalry only 30, with
  artillery 15); entering a region costs 10 open / 15 hill or ridge, +5 in
  heavy woods; a sea lane needs full points and takes them all. A move is
  a destination: cheapest path (Dijkstra, ties by region index), walked in
  rounds (every army's k-th hop, by id), continued on later turns
  (`persist`, `dest` on the army; `cancel_move`).
- Enemy field armies stop armies entering their region: a field battle
  (kind "field", no garrison). Entering enemy land raids it (owner gets
  half the income); `siege` / `assault` are orders from inside, a move's
  mode is the "on arrival" shortcut (field armies there are fought first).
  Stance: in the field / inside the walls (`stance` order).
- Support by range over land within a turn's points; reinforcements deploy
  on the map edge they come from in field battles (explicit positions; no
  sim change).
- AI: multi-hop targets, concentrate before attacking, raids, screens,
  stances, no dithering (idle 3 turns). Pacing close to format 4 (largest
  at turn 30 median 10 vs 11 over 10 seeds, eliminations median 4); AI turn
  ~13 ms mean, ~19 ms worst.
- State format 5; 4 -> 5 migration; unmigrated online campaigns of formats
  1-4 play exactly as before (6 AI campaigns x 60 turns from format 4 give
  HEAD's hashes). No server change; the server binary needs no restart.
- Tests: campaign_test (paths, rounds, interception, raiding, siege start
  in the field, support by range with edges, retreat, persistence, 4 -> 5
  migration), campaign_sim (`--format=4`, pacing table, `--twice`),
  campaign_solo, campaign_input_test, online_e2e, go test. Screenshots
  `docs/screenshots/move_phone_*.png`.
- **Open / next:** play on the phones (is raiding by default right; toast
  and army card on a small screen); reinforcements arriving mid-battle;
  edge arrival in settlement battles; Epirus now falls in every AI-only
  seed; interceptions are few in AI-only play (1-7 a campaign).

**Sieges and battle odds (built 2026-10-06, uncommitted).** Design agreed
with the user; rules, orders, state and AI as built in CAMPAIGN.md
"Sieges and battle odds". In short:
- A move into a hostile settlement lays siege by default (no battle); the
  move toast and the army panel make Assault (today's battle at once) one
  tap away. Besiegers stay until ordered away, cannot merge / split /
  disband; armies of their side that move in later join. Each turn the
  besieger may order `assault` (settlement battle, every besieger
  attacks), the defender `sally` (field battle on the region's terrain,
  garrison and armies inside riding out); an army of the owner's side
  moving in is a relief (field battle, the garrison and the armies inside
  on its side). Lost sally / relief by the besiegers lifts the siege and
  sends them home (or to the nearest friendly region); a beaten relief
  falls back or is destroyed.
- Besieged: no income, no recruits, construction and growth paused, no
  garrison recovery; supplies 2 / 3 / 4 turns (village / town / city, +1
  with farms 2: granaries), then the garrison loses 25 points and the
  armies inside 10% of their men a turn; no garrison and no army inside =
  surrender to the besiegers ("surrendered" event).
- `CBattle.odds()`: the formula's prediction (strengths, chance, expected
  losses, band) for any two groups of armies; shown as a two-colour
  balance-of-power bar in the siege panel (assault / sally / relief), the
  pending-battle cards and the region panel of an enemy settlement with
  armies ordered into it. Map: a ring of tents in the besieger's colour;
  siege moves drawn orange, assaults red.
- AI: assault at its attack ratio, else lay siege when another army can
  join within two turns; assault a starving city with a relief near; lift
  before a stronger relief; maintain at most supplies + 3 turns; sally at
  the ratio; relieve at 60%.
- State format 4 (top-level `sieges`); 3 -> 4 migration adds an empty list.
  Online campaigns of formats 1-3 stay as they are and play without sieges,
  byte-identical to the previous build (checked: 6 AI campaigns x 60 turns
  give the same final hashes as HEAD + the join fix). No server change; the
  live server binary needs no restart for this.
- Tests: campaign_test (sieges: start, join, lift, starvation, surrender,
  economy, assault / sally / relief battles and outcomes, odds against the
  formula, co-op assault, format 4 migration), campaign_input_test (Assault
  now toast, Assault / Maintain, Sally), campaign_sim `--twice` (determinism)
  and `--no-sieges`, campaign_solo (a siege policy), online_e2e, go test.
  Screenshots `docs/screenshots/siege_phone_*.png`.
- **Open / next:** play it on the phones (is the default siege right for
  players who expect a battle; the toast on a small screen); AI sallies are
  rare (0 in 6 AI campaigns: the garrison fights without walls) and AI
  sieges end by assault or lift, not starvation (patience cap); tune after
  play. Pending battles resolve after the end of turn (as before), so a
  siege with a battle pending skips that turn's supplies and starvation.

**Settlement variety (built 2026-10-05, uncommitted).** After the
playtest of the city maps (liked; every walled town looked the same round
hill fort; wall archers could not leave a wall). Design as built: DESIGN.md
section 4 "Settlement plans, sites and owners"; save format: CAMPAIGN.md
"Version 3". In short:
- Wall plan by founding culture (static `culture` per region): castrum
  (latin), polis with acropolis (greek), punic with citadel, oppidum with
  a funnel gate (celtic); the original ring stays for the sandbox tests.
  Sites by terrain: plain (ditch at walls 3), hill (a rise, no plateau),
  spur (posterns); ports have the sea behind (sea wall, scenery sea gate
  and mole, defenders retreat along the shore). Enclosed fields in
  villages and small oppida.
- Bug fixed: towers are stairs. Wall units can be ordered down (and
  defenders up), routers leave the wall by a stair; the AI pulls wall
  archers off a lost stretch.
- Citadels: the capture zone is inside; attackers must break two gates;
  the defenders fall back into it (as many as fit) and shut it.
- Owner dressing (view): banners, the owner's shrine, roofs by who built
  what (state format 3 with builder data; online formats 1-3 readable).
- Path tables at most 2 a tick; several street-fighting fixes (squeeze
  centring, regroup, reachable attack goals, routers not walking the
  trail, stair stragglers, rate-based stall).
- Verified: determinism PASS (golden digests and every flat / hill / woods
  hash unchanged; new runs per plan, a scripted citadel / stairs set
  piece, sea / ditch / style checks; settlement runs changed: stairs,
  street fixes); lockstep PASS (coastal polis, players attacking and
  defending with stair moves); campaign_test / solo / input tests,
  input_test, check_scripts, go test, online_e2e, live_e2e PASS.
- Balance pass (2026-10-06, uncommitted): diagnosed freezes and grinds
  fixed (melee over walls, cut-off units, everyone on one target, hunting
  instead of taking the plaza, a citadel cut off the street graph) plus
  "the town is lost" morale, weaker citadel gates, a shallower oppidum
  funnel without ditch, quicker withdrawal when beaten. Draws now at most
  1 in 8, battles 5-10 min; see DESIGN.md "Balance pass".
- Round 3: breach searches and paths made cheaper (p95 4.7-5.2 ms, worst
  6.4-6.7 ms on the city benches); battlement cover by wall level; the
  stall clock waits out the approach; check_scripts no longer writes an
  override.cfg into the shared checkout.
- **Open / next:** walls 3 was still easy for ring / castrum / polis (87-100 %
  attacker wins); since 2026-10-07 the tower engines, hard gates and
  stronger battlements make walls 2-3 cost the attacker (see "Cities must
  be worth defending, part 1" above; walls 1 open); breach melee
  still 5.4-5.9 ms p95 and 7.5-8.5 ms worst at 4,000 soldiers (volume of
  men in contact: per-man contact gating is the next step); play it on
  phones (look of the sea, shrines, banners; the stair orders by touch).

**Battle maps with character (built 2026-10-05, committed in `3522fd2`).** CAMPAIGN.md
"Later" item 1. Design as built: DESIGN.md section 4 "Battle maps: woods
and settlements" (rules, numbers, AI, view, measurements). In short:
- Woods on any map (region coverage 0-100, density 0-3 per 4 m cell): slow
  units (artillery and cavalry most), disorder formed units (pike walls
  drop), blunt charges, stop arrows and stones, block flat shots; riders
  fight badly in them. The field AI keeps cavalry, pikes and batteries out
  and shelters archers from cavalry in them.
- Every settlement battle on the settlement's own map from a fixed
  `city_seed` (+ level, walls, buildings, region ground): streets and
  houses, plaza, walls with walkway and towers, 2-4 gates with hp,
  orchards and fields outside; paths through the streets, squeeze in
  narrow streets, missile troops on the walls, gates shut / opened /
  broken (artillery or hacking foot), plaza capture (60 s) breaks the
  defenders. Siege AI for both sides (`sim/siege_ai.gd`). The campaign's
  ridge stand-in for walls is gone.
- Ground palettes by region (arid / dry / green / rocky) on the battle map
  and the campaign map; stronger height shading; trees as one MultiMesh
  fading over soldiers; the city drawn in one static layer; gate taps;
  sandbox Ground and Settlement battle choices; unit book pages; the region
  panel's "View battle map".
- Campaign state format 2 (`city_seed`), local saves migrated on load;
  online campaigns stay format 1 on the server and play identically (no
  server change; see CAMPAIGN.md "State format").
- Verified: determinism test PASS (golden digests and every earlier run's
  hash unchanged; woods / village / city / hill city / scripted gate runs
  identical on repeat and across snapshot / restore); lockstep test PASS
  (with a walled town, players attacking and defending); live_e2e PASS and
  online_e2e PASS on scratch servers; campaign tests PASS (v1 save
  migrates); matchups `--only=maps` (no draws, settlement battles decided
  in 4-12 min); benchmarks bench_4000 2.65 / 6.0 ms, hills 3.0 / 6.2,
  bench_4000_city 2.69 / 7.8 (max over budget: first path tables after a
  gate falls).
- **Not yet done / next:** play it on the phones (look of the ground,
  trees and city on real screens; WebGL2 cost of the tree quads and the
  second ground texture; ground texture build 0.1 s on the desktop, maybe
  0.3-0.4 s on a phone); city benchmark spikes on phones; sallies; siege
  equipment.

**Milestone 5, live co-op battles (built 2026-10-05, uncommitted).** Why:
in the first online playtest one player started a battle and the other's
join button only returned them to the map. Now a battle with both armies is
fought live: the host opens a lobby (the ally is pinged), the ally taps
"Join battle", each commands their own army, as in Rome 2 co-op. Design as
built: DESIGN.md section 5 "Live battles: as built"; relay protocol:
SERVER.md section 17. In short:
- Deterministic lockstep over the server's WebSocket relay: only inputs
  travel, each for a frame a few frames ahead (delay from the round trip,
  2-12 frames of 100 ms; none while alone), the sim waits for a missing
  player's input. `sim/lockstep.gd` holds the frame, pause / speed and their
  votes, who takes part, and the command table, all hashed;
  `BattleSim.snapshot()` / `restore()` for joins, reconnects and desyncs.
  Golden digests unchanged.
- Gifts and gifts back, pause and speed by vote (chips under the controls:
  Accept / No), ally's unit cards framed in their colour and not orderable,
  a co-op strip (players, host, connection, round trip), waiting / catching
  up / resync indicators, lobby, Continue / Wait when the ally has been gone
  10 s (their units come to you, held for them; they get them back when they
  return), mid-battle join and rejoin by snapshot, host handover, result
  uploaded once by the host (any seat that took part may upload it).
- Server: rooms in memory (`rooms.go`) holding the battle's claim while in
  use, sequence-numbered stream with replay buffer, snapshot cache, roles,
  rate and size limits; battle list shows "Live now" with Join battle;
  `api: 2`. New table `battle_live` (created at start, nothing else changes
  in the database).
- Verified: `go test ./...` (rooms: entry and auth, ordering, reconnect and
  replay, drop / continue / ready, snapshots and cache, leave and host
  handover, lease renewal, upload by a seat that took part);
  `tests/lockstep_test.gd` (snapshot round trips on 6 scenarios up to 4,056
  soldiers; two peers through a simulated relay with different latencies
  and timing, every frame equal, with refused orders, gifts, votes, a drop,
  takeover and readmission, and a third peer joining mid-battle; solo
  through the lockstep layer = plain sim); `tests/live_e2e.py` (the Go
  server and two headless Godot clients fight three battles over real
  WebSockets: lobby join, mid-battle join, disconnect + takeover + return;
  hash equal on every frame on both, results uploaded once, both end on the
  server's state: PASS); `server/cmd/webcheck -live` (the web export in two
  headless Chromiums: lobby join, 600 frames hash-equal every frame,
  rejoin mid-battle from a snapshot: PASS); `tests/live_shots.py`
  (screenshots, and the real game as host uploading through its campaign
  screen). Screenshots `docs/screenshots/live_phone_*.png`.
- Numbers: snapshot 86-89 KB at 4,056 soldiers (36 KB at 2,000; 15-30 KB
  for small battles), ~10 ms to take and 2 ms to restore natively; on the
  local machine round trips 6-7 ms and no waits at delay 2; in headless
  Chromium 40-45 ms round trips (frame time included) and waits of up to
  ~170 ms when frames were run 4x faster than real time.
- **Not yet done / next:** restart the 8060 server with the new binary (the
  web build is already the new one); play it on the two phones; watch
  `coop_*` telemetry (round trips and waits on cellular, iOS Safari with
  the screen locked, backgrounded tabs); reinforcements arriving from the
  map edge; spectating without an army.

**Milestone 4, async backend and online co-op (built 2026-10-05,
committed in `fad7399`; 8060 runs the Go server behind Caddy, WebSocket
upgrade checked on the real domain).** Everything is in `docs/SERVER.md` (API, data model,
concurrency, notifications, deployment, security) and `docs/CAMPAIGN.md`
"Online play" (the screens). In short:
- Server: Go 1.27.1 (installed at user level in `~/.local/go`, checksum
  verified) + `modernc.org/sqlite`; static files with no-cache + ETag and
  precompressed wasm (39.5 MB -> 7.1 MB brotli); telemetry identical to
  `serve_web.py`; campaigns with every state version kept, join codes,
  per-device seat tokens (hashed), device codes, submissions with
  unsubmit, compare-and-swap uploads (one per version wins, an identical
  replay is "already"), turn deadline from the first submission with forced
  resolution, battle leases with heartbeats, Wait for ally / Take command /
  Ask to join, per-seat session blobs, long-poll change feed, WebSocket echo
  (milestone 5 relay goes there), history and rollback, determinism reports,
  Discord webhook notifications (queued, rate limited, deduplicated),
  invite key, rate limits, same-origin only, backups every 6 h.
- Client: Online co-op / Join / Continue-with-badges on the main menu, the
  share page, Submit turn and the waiting panel, the online battles list,
  the Online dialog (device code, Discord, timeout, history, rollback),
  Play online for a local campaign, offline cache, battle-result outbox,
  determinism check of the ally's results. Local play unchanged.
- Fixed on the way (affects every browser build): `main.gd` compared the
  iOS check's result `== true`, but this Godot build returns a JS boolean as
  an int, and int == bool is a runtime error that silently aborted the
  start screen's `_ready` before the URL shortcuts (`?scenario=` etc.). Also
  on the web `HTTPRequest` must not gunzip again what the browser already
  decompressed.
- Verified: `go test ./...` (API, races, timeouts, leases, rate limits,
  notifier); `python3 tests/online_e2e.py` (two headless Godot clients, 10
  turns, battles, a resolve race, a device switch, a forced turn, network
  failures, Discord messages: PASS); `server/cmd/webcheck` (two headless
  Chromium browsers on the web export: create, join, WebSocket echo,
  submit, resolve, long-poll pickup: PASS); the container image builds and
  runs (Podman). Screenshots `docs/screenshots/online_*.png`.
- **Not yet done / next:** (8060 is switched and an invite key is set.)
  Keep playing it on the Android phone and the iPhone (share link, typing a code, device code to the
  desktop, background tabs and long-poll on iOS Safari); move to the
  Proxmox host. No token
  revocation UI, no campaign deletion yet.

**Milestone 3, campaign layer (built 2026-10-05, uncommitted, not yet
playtested).** Everything is in `docs/CAMPAIGN.md` (as built: rules,
numbers, map and adjacency, tier table, state and order formats for
milestone 4). In short:
- `campaign/` pure deterministic rules: 36 regions, 45 land routes, 14 sea
  lanes, 8 factions + 12 independent regions, two turns a year from 280 BC,
  simultaneous orders then AI, economy with buildings / trade / upkeep /
  debt / corruption, settlement growth, 7 building chains, recruitment by
  building level and tier, replenishment, merge / split / disband, 12-unit
  armies, reinforcements, garrisons and walls, conquest, retreat,
  elimination, victory; campaign AI and diplomacy; state as one JSON blob
  with a hash.
- Unit tiers: 31 derived unit types (tiers 2-3 of the seven core lines plus
  faction elites: principes, triarii, phalangites, silver shields,
  companions, sacred band, hoplites, scutarii, Gallic nobles...), with
  gold-chevron tier marks; the nine base types are unchanged (golden
  digests unchanged).
- `game/campaign/`: map screen (drawn coastlines, territories, routes,
  armies, planned moves), region / army / realm / diplomacy / battles /
  summary / goals panels, hot seat with hand-over, save slots with autosave,
  export / import as text, new-campaign screen; battles fought in the
  battle view or auto-resolved by the battle sim AI vs AI.
- Main menu reorganised (Campaign / Battle sandbox / Unit book / Controls);
  Controls page from one bindings table; battle additions: Shift / Ctrl
  click multi-select (also on cards), symbol markers as hit targets first,
  None (deselect) button, keyboard shortcuts, mouse drag-box select,
  three-finger / Alt+drag (or G+drag) group move with rotation and ghost
  preview, field long-press / right-click for the unit book.
- Web: manifest + icons for install (no service worker, so never a stale
  build); iPhone Safari tab told to use Share > Add to Home Screen.
- Playtest fixes (2026-10-05, after the first phone playtest, which went
  well): every list scrolls by dragging anywhere in it, buttons included
  (`game/touch_scroll.gd`, used by all scroll areas; taps fire on release
  only if the finger did not scroll; fling; long press on unit rows opens
  the unit page; scroll bars thin on touch); neighbouring regions an army
  cannot enter are shown dark and crossed, and tapping one explains why with
  a Diplomacy shortcut; the region panel says whether its owner is at war or
  peace with you. Test: `godot --resolution 1560x720 --script
  res://tests/touch_scroll_test.gd`.
- Needs: a phone playtest of everything above; three-finger gestures on real
  phones; auto-resolve time on a phone; campaign pacing with real players.

Playtest feedback round (2026-10-05, built, uncommitted):
1. HUD scaled by device (`game/ui_scale.gd`: touch 0.88, mouse 0.82 CSS px
   per logical px, menu "UI size" S / M / L), compact unit cards wrapping
   into rows (no scrolling: 26 units in 2 rows on the phone, 1 on a
   desktop), actions in one row above the cards, Withdraw army in the top
   bar, one-line collapsible readout, grouped start menu with folded Tests.
   Screenshots `docs/screenshots/hud_*.png` (phone 780x360 CSS, 1920x1080,
   3840x2160). Unverified on the real phone and the 4K monitor.
2. Stone throwers aim at the near face of the target, lead its movement and
   land short rather than over (beyond-the-rear 28-82% -> 1-27%).
3. More ammunition (archers 40, javelins 6, bolts 11, stones 15 per engine).
4. Artillery Refill order: one more load in the baggage, ~70-90 s to bring
   up, cannot move or shoot meanwhile; the AI uses it.
Details and numbers in DESIGN.md (Artillery "Stone aim", "Refill";
Missiles "Ammunition"; section 7 "HUD as built").

Terrain height (built 2026-10-05, uncommitted): needs a phone playtest of
the look (contours, shading, readability of units on top) and of the
WebGL2 terrain shader on the Android phone and an iPhone; the playable
battles now get random terrain (menu "Terrain:" button to choose, "Replay"
for the same seed and ground, `?terrain=ridge&seed=N` on the URL). Four
terrain test scenarios are on the menu. Flat battles play exactly as
before (checked against the previous build).

Earlier (committed in `49c1022`):

A tuning pass from playtest feedback (built, uncommitted):

1. Cavalry charges resolve per rider and lap around the enemy front instead of
   the whole unit stopping when a few riders make contact.
2. Archers must be able to kill cavalry in the open (suspected cause: arrows
   aimed at where a fast target was, not where it will be).
3. Units rout later and mainly because of casualties taken: heavy infantry,
   spears and pikes hold to roughly 50-60% losses in an even frontal fight,
   light and missile troops to 30-35%. Flank and rear attacks should break
   units by killing soldiers, not by a large instant morale penalty.
4. Follow-up (2026-10-05): cavalry was too strong against the front of
   formed heavy infantry. Fixed by causes: impact direction judged per
   victim (men who face or can turn to the rider take it frontally), frontal
   impacts into a steady unit meet shields / full armour / support from the
   ranks behind and a strike back, a full charge needs ~18 m of run-up (no
   momentum from running away), and turning away from a melee costs a free
   blow; a horse only carries on into a second man when it breaks through.
   60 cavalry into a standing heavy 100 at 30 / 60 degrees: 97 / 100 killed
   -> 35 / 47, and the riders mostly lose; repeated frontal charging went
   from a 100% cavalry win to a costly loss. Details and the keep-list
   in `docs/DESIGN.md` (Cavalry charge).
5. Mirrored fairness: the bottom army won ~58% of 420 mirrored AI battles.
   Causes found and removed (each confirmed with its own probe): the AI
   armies thought 5 ticks apart; unit think phases followed the global unit
   index (the army listed second reacted sooner); unit processing order
   alternated by tick parity, which the mirrored geometry fixed at contact
   (one side always struck first in cavalry clashes); the scenario left the
   top army 1-6 m off the mirror image; and some direction-dependent
   rounding / scan order. Now 50.6% top over 840 battles (both unit orders).
   Check with `godot --headless --script res://tests/matchups.gd -- --fair=N`.

### Open items

- Campaign bug fixed (2026-10-05, from play): two armies ordered into the
  same enemy region in one turn (Lilybaeum -> Carthago by sea) fought
  separately: the second was bounced by "battle pending there". Now an
  army entering a region whose battle started this turn joins it (attackers
  or defenders, 24 field units a side, else "battle side full"); AI attacks
  that commit several armies now arrive together too. Sea-lane neighbours
  still do not reinforce passively (open: whether they should).
- iPhone Safari (iOS 18.7) ran the 4,000 benchmark on the terrain build at a
  steady 60 fps (sim 3.1 ms mean, 7 ms worst per tick) and the terrain shader
  works there. It only rotates to landscape when opened from the home screen
  ("Add to Home Screen"); a Safari tab cannot force orientation.
- **iPhone determinism is not yet cross-checked** against another device on
  the same build. Run the same fixed-seed benchmark on the iPhone and one
  other device and compare with `tools/playtest_report.py`.
- The user reports performance is good on every device tried so far.
- Occasional frame hitches at 4,000 soldiers (a whole sim tick runs inside one
  frame). Fix by spreading tick work across frames if it becomes annoying.
- "A unit with a move order does not fight" was chosen so cavalry can pull out
  and units can retreat. Unconfirmed that it feels right in play.
- The game is reachable at `https://strategiccommand.ggior32.dev` through the
  user's Caddy reverse proxy, which holds a real certificate and forwards
  plain HTTP to the dev server on port 8060. The dev server is not hardened
  and only lives as long as the session that started it.
- Install support (2026-10-05): the export writes `manifest.json` and
  192 / 512 px icons (tools/make_web_icons.gd), standalone, landscape. No
  service worker: Godot's PWA worker answers from its cache first, which
  could serve a stale build, so there is no offline play. Android Chrome
  offers install without a worker (unverified on the user's phone).
- A mild top/bottom bias may remain in mirrored AI battles (53-55% on some
  seed ranges, 50.6% on another). Settle before head-to-head play.
- Deferred battle features: fatigue, horse archers, a manual brace
  toggle, siege equipment (ladders, towers) and climbing walls, sallies,
  spreading tick work across frames; terrain visibility (hiding behind
  hills or in woods).
- Terrain: phone GPU behaviour of `game/terrain.gdshader` is unverified
  (desktop GL only); the AI's high-ground behaviour (hold, detour, rises)
  is unplaytested; menu buttons are 44 px tall to fit the new entries.
- Artillery is unplaytested: look and readability of engines, bolts, stones
  and impact marks on a phone; whether the Deploy button and set-up times
  feel right; whether AI batteries and guards behave sensibly in play.
- bench_4000 (two armies a side) now runs ~10 min to a decision (2,000:
  ~5 min); the AI's second line and batteries could be looked at.

## Next session (2026-10-10, the co-op campaign)

Where 2026-10-09 ended (build 20261009T124650Z live; everything up to
8fea8b1 committed; the user pushes to origin himself):
- **Landed today, in order:** siege part 2c (defender layout, routers
  run inward); engines as equipment with crews as men + per-unit kills;
  UI icon pass (both phases); ammunition kinds, fire, foraging, the
  wagon; custom picker for all rows; camels and elephants; the melee fix
  (ranks hold together, in-reach advance, pursuit as a unit move, flank /
  rear by unit); missile cavalry and slingers; the general (no upkeep);
  war dogs; siege towers; field works and the fortified camp (palisade,
  no gates); light artillery. The rules hash changed many times: both
  machines must reload before an online turn.
- **For Friday:** set the campaign battle limit to 30 (field battles are
  slower and less lethal since the melee fix; 15 min can draw). Manual
  sieges at walls 2-3 at equal force are hard; bring artillery or
  numbers. Nothing has been played on phones since the icon pass.
- **Next (agreed):** mantlets (4f.4) built 2026-10-09 (sheds not); then the
  rebalance block with the whole roster present: the tuning backlog
  under "Where we are headed" (walls 1-3 AI sieges now 0-30 %, field
  lethality and battle length, AI skill margins 60 / 68 %, missile feel,
  every new row's numbers, the wrap rule at the anchor level, the AI
  reading enemy works, the campaign AI's Workshop / Range build-up so it
  fields wagons / scorpions / kinds). Then roads and rivers, the
  N-player campaign (every faction AI or human; asked 2026-10-09), audio,
  Proxmox, the sprite pipeline (West pack as its test); the shared empire
  last (two empires working together already plays well).
- **Next after the siege pass (user, 2026-10-09): settlement movement,
  units flow into the space.** Playtest: units still get stuck at walls
  and buildings (a unit 87 of 90 up a wall and frozen; units wedged
  between a building and a friend); not a tuning matter. Today a unit is
  a rigid rectangle (frontage clamped to the corridor, footprint blocking
  in 4 m cells, men within PLACE_LEAD of their slots). To build (sim core,
  Opus): (1) slots that flow: when the rectangle is cut by walls,
  buildings or units, lay the slots out by a flood over the reachable
  free cells nearest the anchor (men spread along a wall, pack into a
  gateway mouth, crowd the ladder foot, reform in the open); (2) stuck
  detection and release: a hashed per-unit no-progress counter; past a
  threshold re-route, re-flow, or let the men outside the blockage go
  on; (3) queue zones at gateways, ladders and towers where waiting men
  pack and move up; (4) measurement first: a stuck counter and a flow
  probe on the city maps in determinism_test, pass criterion "no unit
  stuck more than 20 s in the fair-sieges set". Shares ground with the
  ladder bugs (one ladder at a time; the last men never climb) the siege
  pass is fixing: brief after that lands.
- **Then (user, 2026-10-09): siege equipment usability.** (1) Pick up
  and drop siege equipment in the deployment phase (a unit assigned to a
  piece starts the battle carrying it; drop before the start too), today
  battle orders only. (2) Mantlets sized for a unit: a dropped mantlet
  becomes a line of panels along the carrying unit's front at its full
  frontage (cover = that line's depth behind it), one piece per unit
  still; the 6 m single panel covers a few files and nothing shows where
  to stand (the attacker's view of it is unclear in play). (3) A preset
  pattern on pick-up, drawn in the order preview: ladders one file per
  ladder behind the set; ram a column behind it, crew at the beam; tower
  a column behind it ready to cross; mantlets two ranks behind the
  panels; wagon a column alongside; the unit snaps into it on pick-up
  and reforms on drop. Sim formation / order parts Opus; mantlet data
  and the preview Sonnet. After the settlement-movement item (same code).
- **Open from playtests:** the co-op Ask-to-join flow unconfirmed; the
  general's upkeep decision (none) is in; the Leave button fix is in.
- **Region panel overflow fixed (2026-10-09, user's PC screenshot):** the
  side panel grew past the window edge on a besieged city on every
  display: `side_scroll` had horizontal scrolling DISABLED, which makes a
  ScrollContainer take its content's minimum width, and the siege row's
  three fixed-width icon buttons (~400 px) exceeded `PANEL_W` 360 / the
  48 % phone cap. Now `SCROLL_MODE_SHOW_NEVER`, `side_box` pinned to the
  panel width (minus the scrollbar), the siege rows and the army card's
  move row are `Kit.flow` rows that wrap. Screenshots desktop / tablet /
  phone checked. **Known:** `tests/campaign_input_test.gd` has 7 failures
  at HEAD (merge glyph, Diplomacy scroll, ...) that predate this fix,
  from earlier today's UI changes; a pass is due.

## Previous session notes (2026-10-08, 14:00)

Where the evening of 2026-10-07 ended (build 20261008T010923Z live,
server rebuilt with the battle "ask" / guest room changes):
- **To confirm on the user's devices:** (1) Galaxy Tab S7 in Chrome: one
  battle on the new build should log `soldier_probe path=gpu drawn=0`
  then `path=cpu drawn>0` (nothing logged on this build yet; Firefox on
  the tablet draws fine on the texture path); (2) the co-op join flow in
  the running online campaign: Syracuse "Ask to join" -> Carthage sees
  "Syracuse asks to join" -> Fight together -> Join battle -> gift units.
- **Queue, in the agreed order:** part 2c (walls-1 defender layout, the
  fair-sieges target), ~~artillery engines as pick-up-able equipment with
  crews as men (+ a per-unit kills counter for the battle screen)~~ (built
  2026-10-09), gifting cities and money (4c, built 2026-10-08), part 3 (fit the formula, shelter knob back on,
  re-run the AI tables), then the rest of the list below.
- Known: city benches' worst ticks 8-12 ms on this machine (needs a cold
  measurement); walls-3 polis fights can stall at the acropolis;
  touch_scroll_test's two recruit-list failures and menu script error
  pre-exist.

## Where we are headed

**Agreed order on 2026-10-08 (evening):** engines as pick-up-able equipment
with crews as men + per-unit kills (running); then 4d ammunition types and
4e resupply / wagon together (shared ammo and pick-up code); then 5
elephants and camels; then Friday 2026-10-10's co-op campaign as the phone
round (item 2). **No balance tables until those are in**: siege part 3
(fit the formula), the walls 2-3 attacker-side fix and the AI follow-ups
are one rebalance block after Friday. 8c icons may be pulled forward ahead
of the rebalance so Friday has icons. Audio and icons fit thin-budget
evenings (no sim changes).

**Tuning backlog for the rebalance block** (numbers chosen once, never
tuned; collected 2026-10-09):
- Walls 2-3 equal-force sieges 0-20 % attacker (targets 50 / 25 %): an
  attacker-side fix (more escalade at high walls or wall attrition); the
  1.5-2:1 sets moved the same way. Easy defenders about as good as
  Average in the polis; Skilled vs Average at ring walls 1 is 0-10 %.
- Ammunition kinds: fire arrows weak against gates (780 arrows took a
  walls-1 gate down 57 %); fear values; the explosive's 1.5 m blast and
  its free price (late and rare only by building / faction).
- Resupply: forage rate (~37 ticks per arrow per man), wagon refill
  30 s a load, the 30 % horse-hit chance, wagon stocks (100 / 150 /
  220 %), the 20 % strength and +6-12 % auto-resolve bonus.
- AI knobs: `WG_EMPTY_PCT` (15 % Average), `AK_WAVER_PCT` (35 %),
  engine take-up radius 60 m (kept by the field rebalance, not measured).
- Left by the field rebalance (2026-10-09, STATUS row): Skilled vs Average
  40 % (target 65; Skilled's reserves / rotation after the faster melee);
  the missile yardsticks' bands (arrows 71 / 86 % on light / cav, javelins
  55 % on cav, bolts 36 % on a pike block: far above the bands asked for,
  owner's call whether to cut).
- Mantlets (2026-10-09): standing cover 60 % of arrows / slings /
  javelins, 30 % of bolts, 0 % of stones for men in the 6 x 6 m behind
  it; carried cover 40 % within 6 m (roof rule); 600 hp (two stones);
  campaign grants 2 after 2 siege turns, 4 after 3 (any walls); custom 0
  / 2 / 4 a side; the siege AI's screens before the cover archers stop
  11-14 missiles a walls-1 battle with no clear gain in losses; field /
  defender AI use.
- Known AI gaps (not tuning): the settlement AI never takes up engines
  and no AI recaptures enemy engines; the wagon AI has no dedicated guard
  unit; ammunition kinds go only on units raised at the building's centre
  (no refit of older units; AI.md 24); the defenders and the field AI
  ignore mantlets.

Agreed with the user on 2026-10-06, in this order (milestones 1-5, battle
maps, settlement variety, sieges, free movement and the wall/reachability
fixes are all landed; see "Where we are"):

1. **Continuous overworld** (in progress): Rome 2-style positions on a
   campaign grid, paths and range shapes, zones of control, siege by moving
   onto a city, support by radius with lines, stances (forced march,
   fortify, raiding), turn animation; campaign layer kept data-driven so it
   can be reused for a different setting (the user has an American West
   game in mind on the same engine).
2. **Phone round on the overworld**, then a tuning pass from what it shows.
3. **Roads, rivers and crossings** as grid-cell overrides (historic roads,
   rivers as barriers with fords and bridges; ford battles on the battle
   map). **Design (user, 2026-10-09):** a river crossing gets its **own
   dedicated battle map**, generated from a **frozen seed per crossing**
   (rivers do not change within the period: the same crossing is the same
   map every time, so it can be learnt and planned for, as settlements
   are from their seed). A **fortified army at a crossing sets up its
   camp at the crossing** (the fortified camp placed against the ford /
   bridge mouth, its ditch and palisade covering the exit), so attacking
   a fortified army at a river is clearly more dangerous than meeting an
   unfortified one there: the defender holds the bank, the attacker
   crosses under fire into works. Ties into the formula (fortified at a
   crossing) as the camp does.
   **Pontoon bridges** (user idea, 2026-10-09; agreed in principle): a
   field work the attacker (or defender) lays during the battle, never a
   prerequisite: a foot unit ordered to a bank stretch builds it a section
   at a time (seconds per section, as foraging), the allowance by Workshop
   level like stakes / caltrops; finished, a narrow one-unit lane, slow to
   cross as a ladder lane, wooden (fire arrows and artillery take it).
   The ford is free but defended, the bridge undefended but costs time, a
   unit and an allowance. Balance by a crossing row in the equal-force
   harness (fortified defender vs attacker with / without spans); must
   never be faster than marching to the ford.
4. **Cities must be worth defending** (agreed 2026-10-07, moved ahead of
   everything else after the Skilled campaign AI found that an army is
   better off fortified outside a city than inside it: in the formula
   only the garrison gets the wall bonus (+15 % a level) while a fortified
   field army gets +25 %, 88 % of attacked cities fall, no AI siege has
   ever ended in surrender; in the sim walls-3 attackers win 87-100 % of
   the 1.5-2:1 `siege_test` battles). Principles: **no stat bonus for
   standing inside walls**; defence is attrition at the wall and a slow,
   narrow street fight. In three parts, all sim-first, the formula fitted
   to the sim afterwards, none a save-format change:
   1. **Done 2026-10-07: attrition at the wall** (see "In progress right
      now" for the table: walls 3 about 30 % with ladders and a ram, none
      on arrival; walls 1 missed, 100 %). As agreed: wall archers hit
      harder from the battlements (cover / height levers), **arrow towers
      at walls 2** shooting siege bolts and **two stone throwers mounted
      on walls 3**, immobile garrison engines with a fixed ammunition
      load (+ammo from a building inside), crews that can be shot and
      towers that batteries can duel; walls-2/3 gates nearly immune to
      hand weapons and somewhat tougher; **attacker siege equipment:
      ladders** (foot units climb the wall from outside, slower the higher
      the wall level) **and a ram** (a slow engine unit the gate yields
      to), earned by siege turns in the campaign (optional key on the
      siege entry, no format bump) and chosen in custom battles, so
      without artillery you bring ladders and a ram or starve them (added
      2026-10-07); a **battle time limit setting** (today a fixed 15 min
      `BattleSim.TIME_LIMIT`) in the campaign settings, custom battles
      and the sandbox so long sieges can run. Calibration target: an
      **equal-force siege matchup set**, walls 3 equal strength ->
      attacker about 25 %, walls 1 about 45 %.
   2. **Units do not pass through each other** (part 2a done 2026-10-07:
      blocking, queueing, street frontage, gate rush; walls 1 still 100 %,
      see "In progress right now"; open: the defenders' disposition at
      walls 1, the rest of this item): unit-level blocking first (an enemy unit's footprint is impassable
      in the 4 m pathing grid, frontage clamps to the corridor a unit is
      in, friendly units pass through each other at half speed so streets
      never deadlock), soldier-level separation only at the contact seam
      if it still reads wrong; walls thicker and walls-2/3 cities 15-20 %
      larger inside, measured against the city tick budget; stone
      throwers over the walls at the army inside. Then siege equipment
      over turns (ladders / towers after 2-3 turns), suburbs and river
      sites, sallies from inside.
      **Part 2c done 2026-10-08: the defender layout** (AI.md 16,
      DESIGN.md "Unit blocking and street fights"): the attacked gate read
      from the field, the foot stacked in its inner mouth (front across
      the gateway, the rest behind and falling on whatever comes out),
      quiet gates' guards to the stack (tokens left, re-garrison on a
      second attack), plaza reserve, relief (Average while fighting under
      40 %, Skilled between waves; Easy keeps the old reserves), gates
      shut with nobody in their mouth; sim rule: defending routers inside
      the walls run to the shut gate farthest from the enemy
      (`ROUT_INWARD`), not out through the breach. Fair sieges (both
      Average, 10 seeds, attacker wins ladders + ram / artillery only;
      HEAD -> now): ring walls 1 100 / 100 -> 40 / 30 %, walls 2 50 / 20
      -> 20 / 20 %, walls 3 20 / 40 -> 0 / 0 %; polis walls 1 80 / 100 ->
      50 / 60 % (20 % draws each), walls 2 50 / 40 -> 20 / 0 %, walls 3
      20 / 0 -> 10 / 0 % (30 seeds walls 1: ring 46 / 46, polis 53 / 60 %).
      **Open:** walls 2-3 now far below their targets (50 % / 25 %): the
      attackers lose 200-300 men at the wall and can no longer win the
      street; wall levers alone do not restore it (AI.md 16). Easy
      defenders do about as well as Average in the polis.
   3. **Fit the formula** to the measured siege results across force
      ratios (a walls term for the armies inside is a prediction of the
      sim, not a bonus), turn the campaign AI's shelter knob back on and
      re-run the AI tables.
4b. **Battle screen on the overworld** (**done 2026-10-07**, see "In progress right now"; agreed 2026-10-07, next build
   after part 2b, before part 2c): one screen in two states, used for
   auto-resolve and fought battles alike. *Pre-battle* (replaces the
   auto / fight choice): a map preview at the top (the settlement drawn
   from its seed via `city_preview.gd`, or the field's terrain kind and
   woods, with both deployment edges marked); both sides' compositions
   as rows of unit cards (icon, men, tier) with a **health bar under
   each card** (current men vs full strength), attackers left, defenders
   right, grouped by army and faction, garrison and support armies
   included; a siege equipment line (ladder sets, ram, towers); the odds
   bar and the existing buttons (Auto-resolve / Fight / siege choices).
   *Result* (after auto-resolve, and after a fought battle): a big
   VICTORY / DEFEAT / DRAW with the one-line outcome (city taken / held,
   army destroyed, withdrew), labelled "Auto-resolved" or "Fought"; below
   it, per side, the same card rows with survivors vs fielded as the
   health bar (lost part marked) and kills beside each unit, totals at
   the foot; Continue. Fought battles take the sim's tallies, auto-resolve
   the formula's per-unit losses.
4c. **Done 2026-10-08** (see "Where we are" and CAMPAIGN.md "Gifts between
   players"; the receiver's offer to buy is its own order, `buy_region`).
   **Gifting cities and money between co-op players** (asked
   2026-10-07). A player may gift a region they own to the other human
   when **no army of theirs stands in the city** (garrison stays with the
   city); the offer carries an optional price either way (the giver may
   ask for payment, or the receiver may offer it), so money can also be
   gifted on its own. Orders like the existing treaty / exchange orders:
   `gift_region` (r, to, price) and `gift_money` (to, amount), resolved in
   `cturn` as rules (both humans alive, owner check, army check at
   resolution, treasury check, refused otherwise), visible on the region
   dialog and the Diplomacy screen for the ally, with an accept step for a
   priced offer (two-turn handshake like a treaty) and immediate for a
   free gift. No format bump if the pending offer lives in the existing
   diplomacy / proposal structures; else an optional key.
4d. **Done 2026-10-09 (not committed; see "Where we are").** **Ammunition types** (asked 2026-10-08): a second missile kind per
   shooter, chosen per unit in battle (a toggle on the card like Fire /
   Skirmish, with a fixed share of the load, e.g. a third fire arrows),
   available by faction / building and balanced against the standard
   kind, never strictly better:
   - **Fire arrows** (archers; Greeks, Syracuse, Carthage first): less
     damage, more morale shock, −range; ignite wooden things they land
     on (towers, gates, ladders, rams, engines) for chip damage over
     time; a burning unit's morale drains until the fire is out.
   - **Heavy bolts** (bolt throwers and arrow towers; Rome, Syracuse):
     more damage and pierce, shorter range, slower rate.
   - **Fire javelins** (javelin and light foot of Iberia, Gaul): as fire
     arrows for the thrown kind.
   - **Stones**: standard; **fire pots** (more damage to buildings and
     towers, set them alight, less to men); **explosive** (bursts: a
     blast radius against men and engines, less against walls; late,
     expensive, rare by building).
   Sim: ammunition kind per unit (hashed), a per-kind row in
   sim/unit_types.gd's missile fields (damage, pierce, range, rate,
   fear, blast, incendiary), fire as a per-object state on gates / towers
   / equipment with a burn timer and chip damage; AI uses the kinds
   (fire at wooden targets and wavering units, heavy bolts at engines
   and armour) through profile knobs. Campaign: which kinds a faction's
   units carry comes from the faction roster and a building (Fletcher /
   Workshop chain), no state format change if stored on the unit entry
   as an optional key. Battle screen and unit book show the kinds.
4e. **Done 2026-10-09 (not committed; see "Where we are").** **Resupply: foraging in woods and an ammunition wagon** (asked
   2026-10-08). Builds on the artillery refill that exists (ORDER_REFILL:
   a battery settles for REFILL_FULL ticks and draws shots from its finite
   reserve, shown "44+44" on the card).
   - **Foraging:** an archer (and javelin) unit standing in woods can be
     told to make arrows: it cannot move or shoot while doing it, takes
     real time (slower than the wagon, e.g. a quiver in 2-3 minutes),
     stops when attacked or ordered away, and fills only the unit's own
     quiver (not its reserve). Card button "Forage" shown only in woods;
     AI uses it when idle and empty behind the line (knob).
   - **Ammunition wagon:** a unit type recruited from the standard siege
     building (Workshop chain) that takes an army slot; a slow, unarmed
     crew with a wagon (sprite/marker like an engine), roofed like the
     ram, capturable / destroyable (fire). In battle, missile units and
     batteries within a short radius refill their quiver and reserve
     from the wagon's finite stock when told to refill (the artillery
     refill order generalised: a unit near the wagon, not moving, takes
     REFILL_FULL ticks to settle, then draws from the wagon until full or
     the wagon is empty). One wagon carries a fixed stock per missile kind
     (ties into 4d ammunition types: the wagon can carry the special
     kinds). AI brings it behind the line, guards it, and sends empty
     missile units to it (knobs). Campaign: it is a unit (`unit_types`
     row, roster line "siege"), so it costs upkeep, can be gifted and
     exchanged, and auto-resolve counts it as a small strength plus a
     missile bonus for the army; no format change.
     **Tiers and handling (decided 2026-10-08):** level 1 a hand cart the
     crew pulls at walking pace or slower; level 2 one horse (marching
     pace; the horse is a shootable hit box, dead -> crew pace); level 3
     two horses (trot; one dead -> level-2 pace). Crew dead: the wagon
     stands, anyone may harvest it, nobody moves it. **Any foot unit may
     take the wagon** like the ram: it becomes the crew, moves at the
     wagon's current pace (horses alive -> horse pace), cannot attack or
     shoot, fights at the carrier penalty and is badly exposed to flank
     and rear hits; Drop at any time. The enemy may take an abandoned
     wagon too: refill from it or burn it (4d fire). Guarding it matters.
5. **Elephants and camels done 2026-10-09 (not committed; see "Where we
   are" and DESIGN.md "Camels and elephants")**; chariots and war dogs to
   come. **Elephants**, then camels, chariots, war dogs. Roles agreed
   2026-10-08 (shock cavalry as the yardstick: mass 400, charge 70, run
   ~8 m/s, 90 degrees in 1.6 s):
   - **Camels**: slower (run ~6.5 m/s, 90 degrees in ~2.2 s), weaker
     charge (~45), better rider defence against foot, tire slower; their
     job is the **horse scare**: enemy cavalry within ~30 m takes a
     control penalty (lower charge, slower turns, a morale tick) and
     horses charging camels suffer for it; camels vs spears lose like any
     rider; unaffected by arid ground penalties, slow in woods. Carthage
     and Numidian / eastern rosters; a camel-archer missile variant.
   - **Elephants**: mass 2,000+, wide knock-down charge that breaks
     formations (spears still hurt them), slow to accelerate and turn
     (~4 s), run ~6 m/s; a **fear aura** (~25 m, horses more than men);
     one big body with hit points and a crew (driver + 2-3 shooters from
     height); missiles chip, fire (4d) is the counter; batter walls-0/1
     gates only, kept out of narrow streets. On breaking they **run
     amok**: erratic, trample anyone including their own side; the
     driver can be ordered to kill it (delay). **Calming (user,
     2026-10-08): a panicked elephant that ends up on its own, with no
     enemy and no friendly units nearby, cools down and the rider takes
     control again; while any units are near it stays amok.** Carthage,
     Epirus (Pyrrhus).
   - **Horses** stay speed and shock; camels the anti-cavalry screen;
     elephants the slow terror that breaks lines or breaks you.
4f. **Siege towers, field works, light artillery, mantlets** (agreed
   2026-10-09; field works also asked for by the co-op partner). In this
   order, the first two before the walls 2-3 rebalance because they bear
   on it:
   1. **Siege towers** (built 2026-10-09, not committed; see "Where we
      are") (the helepolis): a rolling tower given to the
      attacker by siege turns like ladders / the ram (walls 2+, e.g. 3+
      siege turns), moved into place by a unit like the ram, planted
      against a stretch; then whole units cross onto the wall through it
      (a wide, fast "ladder"), the escalade the walls 2-3 attacker is
      missing. Wooden: it burns (fire kinds are its counter); towers and
      stones wreck it. Icon exists (siege_tower).
   2. **Field works** (built 2026-10-09, not committed; see "Where we
      are"): in the deployment phase a stakes line and caltrops
      as placeable pieces (limited by the army's siege building / an
      engineer count), stopping or wrecking a cavalry / elephant charge
      across them and slowing foot; the **fortify stance** puts a ditch
      and rampart on the battle map for the fortified army (a low wall
      with no gate: attackers climb it slowly, defenders on it get the
      wall missile bonus), giving fortify teeth against horse and
      elephants. Ties into the formula (fortified field army bonus).
   3. **Light artillery** (built 2026-10-09, not committed; see "Where we
      are") (scorpions, the gastraphetes): a small bolt
      engine row between archers and bolt throwers that a unit carries
      and sets up fast, for the ladder-and-ram army.
   4. **Mantlets** (built 2026-10-09, committed; see "Where we
      are"): a moveable missile shelter piece (the ram's roof
      generalised) a unit stands behind. Sheds (a roofed mantlet against
      stones) not built.
   **Later / campaign:** mining (undermining a wall over several siege
   turns as a campaign action), a Syracusan tower upgrade (Archimedes'
   engines: range and reload). Not of the period: onagers, cart
   ballistae, scythed chariots.
5b. **More units before the rebalance** (agreed 2026-10-09, in this
   order, so the field is tuned once with the whole roster present):
   1. **Missile cavalry** (built 2026-10-09 with point 2, see "Where we
      are") (javelins from the saddle, skirmish mode, fast,
      weak in melee): Numidian horse for Carthage, Tarentines for the
      Greeks, Epirus and Syracuse, light horse for Gauls and Iberians.
      Data rows on the existing cavalry / missile / mount fields (camel
      archers with mount 1).
   2. **Slingers** (built 2026-10-09) (long range, low damage, good against unarmoured men;
      lead bullets as an ammunition kind): Balearic for Carthage, Rhodian
      for the Greeks, native for Iberia. A "sling" base missile row.
   3. **A general and his bodyguard** (built 2026-10-09, not committed; see
      "Where we are"): a command aura (the fear aura
      inverted: morale held up within a radius, a rally bonus, a big hit
      when he falls); campaign armies get a leader.
   4. **War dogs** (built 2026-10-09, not committed; see "Where we are"): a handler unit (weak light foot) that releases its
      pack as an order; the pack is a fast, fragile unit strong against
      skirmishers, missile troops, routers and crews, useless against
      formed heavy foot and spears; it fights until dead or until no enemy
      is near, then returns to the handlers (the elephant calming rule
      reused); never routs; a small scare on light troops only. Epirus,
      the Greeks, Rome, Gauls. Dogs are the pursuit tool now that ranks
      hold together and men no longer chase routers on their own.
   Not for these factions: chariots (Britons, Pontus, Seleucids), naval.
   Mercenaries are a campaign recruitment feature for later.
6. **AI competency** (`docs/AI.md`): Easy / Average / Skilled on two
   independent axes (battle, campaign) plus personality, no cheats ever;
   skill is reaction, perception, planning, execution and deliberate
   plausible mistakes. Decided 2026-10-06: AI obeys fog of war if it ever
   exists; difficulty global with per-faction Advanced overrides;
   personalities and army composition styles per faction by default.
   **Step 1 done (2026-10-06): profiles as data, no behaviour change.**
   `sim/ai_profile.gd` (148 battle / settlement knobs) and
   `campaign/cai_profile.gd` (60 campaign knobs), Average / Balanced = the
   old values exactly (Easy and Skilled rows are copies for now); scenario
   `ai_skill` / `ai_style` per side (hashed only when not default, kept by
   snapshots), campaign `settings.ai_battle_skill` / `ai_campaign_skill`
   and `factions[i].ai_skill` / `ai_battle_skill` / `ai_style` (written
   only when not default: no `CState.VERSION` bump); new-campaign
   "Difficulty" row and sandbox "AI:" button (Easy / Skilled marked
   "soon"); per-competency counters (`BattleSim.stat_aic`, campaign
   `CP.count`, printed by `campaign_sim`); `cdata` FACTIONS `ai_style`
   (all Balanced) and `composition` placeholders. Verified: determinism
   golden digests and all final hashes, campaign_sim 6x60 per-seed
   hashes, sieges, campaign_test / solo / battles equal to HEAD.
   **Step 2 done (2026-10-06): Easy, battle and campaign** (`docs/AI.md`
   section 10). Battle: slower thinking, narrower perception, no terrain
   sense, marches straight in, archers never in skirmish mode, no
   fall-back of mauled units, chases routers, plus a deliberate-mistake
   roller on the sim RNG (9 mistakes, per-side cooldowns in hashed
   `BattleSim.ai_mist`; lockstep and snapshot tested). Average beats Easy
   74 % (flat) / 71 % (hill) of mirrored battles; Easy vs Easy 50 / 50,
   no draws. Campaign: cheapest builds, one recruit a turn, nearest
   targets, no gathering / screens / relief / stances, storms on arrival,
   no peace, 5 mistakes on `CState.rand`; an Easy faction ends about as
   big as at Average (target not met: Average's caution costs it as much,
   see AI.md). Several "Easy" behaviours (no pull-outs, unguarded
   batteries, nearest targets, early charge) beat Average and were kept
   at Average: a lead for step 3. Average / Balanced byte-identical
   (determinism, sieges, campaign_sim hashes). UI: Easy without "(soon)".
   **Step 3 done (2026-10-06): Skilled battle and settlement AI** (`docs/AI.md` section 11; reserves, rotation, matchups, focus fire, siege wall shift / breach / sally; beats Average 72 % flat, 67 % hill, Easy 89-95 %; Easy / Average byte-identical).
   **Step 4 done (2026-10-07): Skilled campaign AI** (`docs/AI.md` section 12; `SK_*` knobs in `campaign/cai_profile.gd`, 0 at Easy / Average): never shelters inside the walls (fortifies outside), support-aware hunting at two to one, spare armies merge into / stand by the main army, staging and falling back out of the enemy's reach next turn, storming before a relief, counter-composition, war when the neighbour's armies are away from the border, peace offers to close a second front; no mistakes. One faction Skilled ends turn 60 with +47 % regions over 24 seeds (6.58 against 4.48; +44 % on 6) and 41 eliminations against 70; Macedon not better (3.7 against 4.0, noise). ~0.8 ms per Skilled faction-turn. Average / Easy byte-identical (campaign_sim hashes; golden hash and RNG in campaign_test); no state change, VERSION 6. UI: Campaign AI Skilled without "(soon)". `campaign_sim --knob=` for ablations. Next: step 5 (personalities and composition styles per faction, the Advanced per-faction UI, the split setting).
7. **Mid-battle reinforcements** from the map edge; ambush stance once
   hidden information in an async game is designed.
8. **N-player campaign** (asked 2026-10-09; moved ahead of the shared
   empire: two empires working together already plays well): three or
   more players in one campaign, with the end goal that **every faction
   can be an AI or a real player**. The state already keeps `humans` as a
   sorted list (permanently allied today). **Design (user, 2026-10-09):**
   **teams** as a campaign setting rather than a fixed human alliance:
   every faction starts as a team of its own and may join or be joined by
   others; the new-campaign screen shows a dropdown per faction with the
   team it is on, plus two buttons, "all humans one team" and "everyone
   on their own"; the permanent-alliance rule becomes "factions on one
   team". Once the campaign runs, **the diplomacy screen offers a team
   (alliance) proposal** to any faction, human or AI; accepted, it grants
   movement through the ally's territory and repair / resupply of armies
   standing in allied zones (today's co-op perks generalised). Open
   points: humans on different teams at war with each other (hidden
   information, diplomacy between humans), the turn deadline with N
   submitters, battles with several humans on one or both sides (the
   co-op join flow generalised), seats and invites per faction on the
   server, AI / human per faction on the new-campaign screen, leaving a
   team (notice turns, as the AI's war declarations work).
8a. **Heroes and agents** (asked 2026-10-09, after the N-player campaign;
   Warhammer 3 style). **Heroes**: characters attached to an army without
   taking a unit slot (a character list on the army, not a unit: a
   `CState.VERSION` bump), one hero per army; a single man with a large
   health pool and an **area buff by kind**: foot (steadiness, to-hit),
   missile (range, accuracy), cavalry (charge, rally), siege (ladders,
   reloads, ram / tower toughness); each fights well in his own field and
   is a prime target for wall bolts. The general is the first hero
   (command aura) and the model to generalise. Fallen: wounded for N
   turns rather than dead (to decide). The AI must use them (an aura knob
   per kind). **Agents** (the co-op partner's ask): an **assassin** and a
   **diplomat**, one each per army, playable on the field as support
   pieces when attached. Assassin: a single hidden man; orders Sabotage
   (wreck an engine; in a siege open a gate from inside) and Attempt
   (adjacent to the enemy hero / general: roll to wound or kill, the
   general-falls morale hit). Diplomat: Parley on a broken or nearly
   broken enemy unit so it surrenders instead of dying (prisoners:
   ransom / recruits), a steadying aura on wavering friends, a beaten
   garrison surrendering to him for the city intact. Hidden characters
   and parley need hidden information: design with the N-player campaign
   and the ambush stance (item 7).
8b. **Audio** (asked 2026-10-07; the game has no sound at all today).
   Battle: melee clash, charge impact, volleys and artillery release /
   impact, gate blows and the gate breaking, ladders and towers, unit
   breaking / rallying, a battle horn at start and at the result; mixed by
   distance to the camera and capped per category so 4,000 men do not
   stack 4,000 sounds (one emitter per event bucket per tick). Overworld:
   taps and button clicks, order placed / refused, end of turn, a turn
   resolved and a battle pending (also the notification sound), treaty and
   trade. A light ambient bed per screen (march drums / wind for battles,
   a quiet loop for the map). Music optional and last. Web constraints:
   audio starts only after a user gesture (unlock on the first tap),
   Compatibility renderer and threads off mean the sample player, not the
   worklet; keep total asset size small (OGG, short clips). Sources:
   generated or CC0 packs; settings row for volumes (master / effects /
   ambient) in `user://settings.cfg [audio]`. Nothing in the sim: sounds
   are driven from the view reading sim events, as the animation pipeline
   will be.
8c. **UI icon pass** (asked 2026-10-07): icons where a word stands alone
   today — the top bar (treasury, income, turn / season), the map key
   entries, order kinds on the army card (move, siege, assault, sally,
   stances, merge, exchange, recruit, gift), the overworld buttons
   (Battles, Realm, Diplomacy, Goals, Units, Menu, Undo, Deselect, End
   turn), region dialog buildings and the recruit list, battle HUD
   buttons (fire / hold, skirmish, run, deploy, wall orders, pick up /
   drop, withdraw), the battle screen's outcome banner and totals,
   siege equipment and towers. One consistent line style and size at the
   touch scale, drawn in code or a small SVG set under `assets/icons/`,
   reused by `unit_icons.gd`'s approach; text labels kept beside icons on
   buttons where a bare icon would be unclear. Includes a pass on
   spacing / alignment of the rows that gained buttons this week.
   Phase 1 built 2026-10-09, committed (9d7ddf3): `game/ui_icons.gd`, Kit
   helpers, icons on the overworld (top bar, buttons, army card, region
   panel, recruit lists, diplomacy / gifts, map key, dialogs), online UI and
   custom battle setup; bottom-right row and diplomacy deal rows aligned
   (DESIGN section 8 "Icons"). Tested: check_scripts, icon_gallery,
   windowed campaign_input_test, touch_scroll_test (only its known
   failures), custom_battle_test. Phase 2 built 2026-10-09 (not
   committed): battle HUD buttons with icons (Menu and Deselect bare; fire /
   hold fire swap; on a narrow screen the order toggles drop the order word
   and keep icon + state, e.g. "hold"), battle screen Auto-resolve / Fight,
   equipment line, result banner between two icons, totals as an icon row
   (men, dead, fled, kills). Tested: check_scripts, windowed input_test,
   battle_screen_test, custom_battle_test, windowed campaign_input_test.
   Screenshots `docs/screenshots/icons_{before,after}_phone_battle_*.png`.
9. **Server to Proxmox** via `server/deploy/docker-compose.yml` (Podman),
   plus delete-campaign and revoke-device admin. Independent; whenever the
   user wants the server off the dev machine.
10. **Sprite animation pipeline**: parts + procedural motion workflow and
    tooling, written up in `docs/ART_PIPELINE.md`. Last on purpose: the
    symbolic soldiers stay until the game is in a good state.

Further out: the American West game as a data set and roster on the same
campaign engine; a 3D client remains possible without sim or campaign
changes (view-only), but art cost, not code, is the deciding factor.

## Decisions already made (do not reopen without the user)

- Co-op only for now; head-to-head and controlling the enemy army come later.
- Simultaneous turn planning; the turn resolves when both have submitted.
  Turn timeout is a campaign setting (off, or one of several durations).
- Battles never block silently: they become pending and are resolved by
  auto-resolve, solo real-time, or live co-op.
- If the ally's army is in range and they are offline, the present player
  chooses per battle: wait for them, or take command of their army.
- In co-op battles each player commands their own army; units can be gifted
  and gifted back. Pause and speed changes need both players to agree.
- Per-soldier combat (health, blocking, individual hits) is a hard requirement.
- Live battles use deterministic lockstep, so the sim must stay integer-only.
- Game rules run on the clients; the server stores saves and relays traffic.
- No generals, family, politics, agents or naval combat in the first version.
- Web first (Godot export with threads off). Notifications through Discord.

Last of all (moved 2026-10-09): **shared empire** (both humans running one
faction); two empires working together plays well enough that this waits
behind the N-player campaign.

## How to run things

```sh
# Campaign tests
godot --headless --script res://tests/campaign_test.gd      # rules, determinism, JSON
godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60   # AI pacing (format 6; --format=5 the region-hop rules)
#   campaign_sim: --skill=easy|average|skilled, --skill-f=rome:s (one faction), --knob=s:ID=VALUE (ablation), --twice
godot --headless --script res://tools/campaign_grid.gd [-- --check --png=/tmp/grid.png]  # regenerate / check the nav grid
godot --headless --script res://tests/campaign_solo.gd      # 20 turns of a player policy
godot --headless --script res://tests/campaign_battles.gd   # auto-resolve timing, formula calibration
godot --script res://tests/campaign_input_test.gd           # needs a window
godot --headless --script res://tests/battle_screen_test.gd  # battle screen: pre-battle, auto / fought result, field battle
godot --headless --script res://tests/matchups.gd -- --only=tiers   # tier balance
# Campaign testing aids: -- --campaign=rome[,greeks][:seed] --sim-turns=N
#   --camp-attack=N:region --camp-siege=N:region:turns --camp-assault=region --camp-auto --camp-fight --select-army=N --select-region=key
#   --cam-zoom=Z --dialog=battles|summary|diplomacy|realm|goals --new-campaign
#   --controls --ios-tab; battle: --demo-ghost=deg

# Tests
godot --headless --script res://tests/determinism_test.gd
godot --headless --script res://tests/benchmark.gd
godot --headless --script res://tests/matchups.gd
godot --headless --script res://tests/matchups.gd -- --fair=100   # mirrored AI battles
godot --headless --script res://tests/matchups.gd -- --only=terrain  # terrain effect sizes
godot --headless --script res://tests/matchups.gd -- --fair=50 --fair-terrain=4  # mirrored, symmetric hill map
godot --headless --script res://tests/matchups.gd -- --only=maps     # woods, streets, gates, settlement battles
godot --headless --script res://tests/matchups.gd -- --only=sieges   # settlement battles only
godot --headless --script res://tests/matchups.gd -- --only=plans --seeds=8 [--plans=0,4]   # each wall plan at walls 1-3
godot --headless --script res://tests/matchups.gd -- --only=fair-sieges [--plans=4 --walls=3 --rows=0 --time-limit=1800 --tune=WALL_COVER=0,25,45,70]
#   equal-force sieges, ladders + ram (row 0) or artillery only (row 1); shard by plan / walls / row
godot --headless --script res://tests/probe_maps.gd -- --scen=siege_town --png=1500 --out=/tmp  # siege debug pictures
godot --headless --script res://tests/ladder_probe.gd [-- --walls=2 --plans=4 --quick]   # every stretch climbable as the preview says (~7 min)
godot --headless --script res://tools/city_dump.gd -- --out=/tmp --seed=1234   # generated settlements to PNG
# Sandbox URL / command line: --siege=seed:level:walls[:ground[:kind[:defend[:plan[:coast[:equip[:time]]]]]]], --ground=N, --no-trees
#   (equip 0 none, 1 three ladder sets, 2 three ladder sets and a ram; time = battle time limit in s)
godot --script res://tests/input_test.gd        # needs a window
tools/check_scripts.sh                           # GDScript warnings as errors (in a scratch copy of the
                                                 # project: safe while other Godot runs use this checkout)

# Live co-op battles (milestone 5)
godot --headless --script res://tests/lockstep_test.gd   # snapshots, two peers, mid-battle join (-- --quick)
python3 tests/live_e2e.py --port 8077            # two headless clients, three live battles + two custom battles
python3 tests/live_e2e.py --port 8077 --only-custom   # just the custom head-to-head and co-op battles (~90 s)
godot --headless --script res://tests/custom_battle_test.gd   # custom setups build and run
godot --headless --script res://tests/deploy_view_test.gd     # deployment through the battle view
python3 tests/custom_shots.py --port 8081         # phone screenshots: setup, deployment, head-to-head lobby (needs a window)
# Testing aids: -- --custom (the custom battle screen), --custom-solo, --custom-template=test_cav_archers,
#   --custom-join=CODE; web: ?custom=CODE
python3 tests/live_shots.py                      # phone screenshots of the co-op UI (needs a window)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8074 -live)
                                                 # two headless Chromiums, live battle (serve a web export there)

# Server (milestone 4; see docs/SERVER.md)
tools/build_server.sh --test                     # go vet + go test + build build/server/scserver
SC_BUILD_OUT=build/server-test/scserver tools/build_server.sh   # elsewhere (tests do this)
tools/run_server.sh 8070                         # serve build/web + API + telemetry on a port
python3 tests/online_e2e.py                      # two headless clients against a test server (~30 s)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8070)
                                                 # the web export in two headless Chromiums

# Web build and playtest server
tools/export_web.sh                              # writes build/web
python3 tools/serve_web.py 8060                  # plain HTTP, behind Caddy
python3 tools/serve_web.py 8443 --cert .certs/dev.crt --key .certs/dev.key
                                                 # self-signed, direct on the LAN
python3 tools/playtest_report.py                 # summarise playtest_logs/
```

- Godot's web build needs a secure context, so phones must use HTTPS. The
  self-signed certificate in `.certs/` (gitignored) is created with
  `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout .certs/dev.key
  -out .certs/dev.crt -subj "/CN=strategic-command-dev"
  -addext "subjectAltName=IP:<lan ip>,IP:127.0.0.1,DNS:localhost"`.
  Each browser shows a warning once; accept it.
- `?scenario=bench_4000` on the URL jumps straight into a scenario;
  `&seed=N&terrain=ridge` fixes the seed and ground of a playable battle
  (flat, rolling, ridge, valley, hill, slope, random). The battle's seed
  and terrain kind are shown in the top-left readout. Benchmark
  scenarios use a fixed seed so hashes can be compared between devices, but
  only between builds with the same `sim:` hash in the build stamp.
- Web export templates for Godot 4.7.2 (no-threads variants only) are in
  `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Playtest telemetry lands in `playtest_logs/` (gitignored).

## How we work

- Design, architecture and review happen in the main session with the user.
  Code generation is delegated to the latest Opus model (see `CLAUDE.md`).
- The loop: build, re-export, the user playtests on their phone against the
  dev server, telemetry plus their impressions drive the next change.
- Commit only when the user says so.
