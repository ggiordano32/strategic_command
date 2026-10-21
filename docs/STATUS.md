# Strategic Command — Status and Handover

Last updated: 2026-10-17 (distribution milestone D: standalone game server image, Server field, Host a server, desktop exports, built, not committed; slice 2c: harbour forts with an inside, fighting from buildings, the musket line's reserve, built, not committed; balance pass T: firearm AI, per-man fire in cover, street posts, siege rally rule, built, not committed; pathing phase J, fight jitter and stuck units, built, not committed; pathing phase W, West open towns, built, not committed; 2026-10-15 pathing phases C1-C7, street fighting, built, not committed; earlier 2026-10-09: siege towers built, not committed; the general and his bodyguard built, not committed; camels and elephants built, not committed; ammunition kinds and fire, foraging and the ammunition wagon built, not committed; earlier 2026-10-08: a CPU-fed soldier rendering fallback, picked by the battle's self-check, for Chrome on an Adreno 650 tablet that drew no soldiers; earlier 2026-10-07: any ally can join a fought co-op battle and be given units; the battle screen on the overworld; cities worth defending, part 2b: siege equipment as objects, the ladder shuffle and wall-punching bugs; part 2a: units do not pass through each other, street fights; part 1: tower engines, ladders, a ram, hard gates, the battle time limit; earlier 2026-10-06: deployment phase and custom battles built; the continuous campaign overworld built, state format 6; free campaign movement built; sieges and battle odds built on the campaign map; settlement variety built 2026-10-05). Read this first, then `docs/DESIGN.md` for the full
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
| Hunyuan3D character models (2026-10-20; owner's turnaround sheets for the captain, Mercy and Rook; the silhouettes judged "great"): `tools/hunyuan/gen.py` (Hunyuan3D-2mv-turbo fp16 on the 8 GB card, front + left + back crops, ~50k tris) and the projection-texture paint pass `tools/hunyuan/texture.py` + `paint_render.py` (sheet views projected per chart onto a 1024 px albedo, labels snapped to the character's palette with band / head / hat-zone rules, detail and ink only on skin and hair, flat cloth, mask R = coat / G = sash) into `assets/characters/NAME/mesh.glb` (~1.6 MB), `assets/minis/characters/` (96 / 48 px + masks) and `assets/portraits/` (256 px busts). Non-commercial Tencent licence (README). Then the Hunyuan paint model route (`hy_paint.py`: gen with CPU offload 4.07 GiB / ~95 s a character, bake = raw paint reprojected into the same chart layout + k-means colour lift onto the sheet anchors, hybrid = the sheet bake's head above `head_z` over the paint's body; the captain's hat from the paint): the shipped assets since 2e29ccb. **Not wired into the game.** Open: the captain's hem blotches, Mercy's throat tone step, the silhouette fit (deform the mesh to the sheet's four outlines: the first custom-tool step agreed 2026-10-20), part-based generation from body + clothing sheets, a permissive shape / texture pair before any itch release, then miniatures on the overworld and busts as portraits, the rest of the cast | Committed 106fdb3 (shapes), 44821ee (texture pass), 2e29ccb (paint route + hybrid); no game test touched |
| Mitred wall strips (2026-10-20; owner: the Morro's bastions were rectangles with no point and stuck out at the joins; BUILT, view only): walls are one strip mesh per ring (`BattleKit._wall_ring`), mitred at every vertex (bevel beyond 2.5 thicknesses), from repeating strip textures `assets/battlekit/strips/` (`build.py` `ws_*` / `ps_*`, `tools/battlekit/pack_strips.py`, `game/battlekit_strips.gd`, `game/battlekit_strip.gdshader`); kit instances split around it (houses, strip, gates / towers); shadow bake rasterises the strip; Low path `draw_mesh`. README 'Mitred wall strips'. **Open:** no end-cap pieces (every ring is closed), palisade and timber wall share the `ps_*` strip, Low has the fixed light, the legacy West harbour fort path (`_west_fort`) still tiles `wall_10_2` | Built 2026-10-20, not committed; battle_screen_test, custom_battle_test, sea_screen_test PASS; check_scripts blocked by `tr` shadowing in sim/mapgen.gd (another agent), my files raise nothing; bench_4000_city 1080p vsync off mean 10.33 / 9.97 -> 10.06 / 10.02 ms (old / new, 2 runs); screenshots `samecity/walls/` in the session scratchpad |
| Cities worth defending, part 2a (units do not pass through each other, street fights) | Built 2026-10-07, committed; tested headless (and the windowed input tests); not yet played on phones |
| Cities worth defending, part 2b (siege equipment as objects; ladder and wall-punching fixes) | Built 2026-10-07, committed; tested headless, windowed input test, live_e2e; not yet played on phones |
| Battle screen on the overworld (pre-battle and result, item 4b) | Built 2026-10-07, committed; tested headless (`tests/battle_screen_test.gd`), the windowed input test and online_e2e; not yet played on phones |
| Overworld UI fixes: Deselect button; dialogs and the side panel keep their scroll position when re-rendered | Built 2026-10-07, committed; windowed campaign_input_test; not yet played on phones |
| Overworld command bar (user, 2026-10-15: "just a big list on the right ... move the army display to the bottom like Rome ... icons for actions"; BUILT, view only): `game/campaign/command_bar.gd`; a selection (army / city / fleet) shows as cards along the bottom (leader card, unit or garrison cards with strength bar, tier pips and trait glyphs, building chips, a grid of icon actions with labels); the side panel opens only on **Details** (and Build / Recruit into an army scroll to their section in it), its Close keeps the selection; the map key, End turn row, hint and toasts rise above the bar; phones (under 700 wide or 560 high logical) get one scrolling row; icons `details`, `embark`, `more`. Testing aids `--details`, `--no-bar`; `--side-scroll` opens the panel itself; the input tests set `cs.details_on_select` (new `_g_bar` checks). See DESIGN.md "The command bar". **Open:** the army has no morale / supply in the campaign (supply shown only in a siege), no "..." fold on phones (the row scrolls), Recruit into an army and Build open the full panel at their section instead of a picker, "armies here" list of a city is only in Details, no sprite-atlas frames on the cards (the symbol disc), not played on a phone or tablet | Built 2026-10-15, not committed; campaign_test, campaign_input_test (+`_g_bar`), touch_scroll_test, webcheck; screenshots in the session scratchpad |
| Command bar round 2 (owner's tablet playtest 2026-10-16; BUILT, view only): Recruit popup tabs Army / Shipyard (`show_raise(r, tab)`, `ship_tab`, `raise_tab_for`; fleet in port: Shipyard action), drag-reorder of the unit cards on the bar (`DragReorder`, `_arrange`), Build popup (`show_build`), army Recruit popup (`show_army_recruit`), Details thinned (army: units, stance, split, disband, exchange, merge, recruits, board gone; city: garrison, buildings, raise, shipyard gone; siege / voyage buttons gone), `--popup=` aid. Tests: input test steps use `_bar_press` / `_bar_has` (bar switched on only for the step) and the popups; `_a_*` drags the bar's cards; touch_scroll_test's army section is the bar's row. **Open:** drag onto another army / Exchange is not built; cards have no tap hint on a trait glyph (hover row only); not played on the tablet | Built 2026-10-16, not committed; check_scripts, campaign_test, campaign_input_test, touch_scroll_test, town_tap_test, webcheck; screenshots in scratchpad/campaign_ui2 |
| Fog of war on the overworld, rules half (owner's decisions 2026-10-17; state format 8; built, not committed): `campaign/csight.gd` (`class_name CSight`): sight per team computed from the state (own regions + land neighbours, armies 1 cell / 2 on a hill or ridge, fleets 1, agents in a city 1, cities 2), per-faction memory `factions[f].mem` {own, turn per region; markers, max 400, oldest dropped} written at the end of `resolve_turn` and `apply_battle`, at creation (`new_campaign`, `new_story`) and by the 7 -> 8 migration; top-level `fog` 1 / 0 (creation option `settings.fog`, default on; view only); view filters `battles_for`, `shown_armies`, `armies_in_for`, `hostile_field_for`, `zone_armies_for`, `raider_for`, `event_seen` / `events_for`; the AI sees everything (no rule reads sight). `CState.VERSION` 7 -> 8, server `StateVersion` 8; online format 7 campaigns are not migrated and play without fog. See CAMPAIGN.md "Fog of war", DESIGN.md "Fog of war on the overworld" | Built 2026-10-17, not committed; campaign_test (+`_sight`: own / neighbour / two cells away / hill / team union, memory keeps the old owner, markers shown / dropped / capped, events and list filters, migration = fresh update, JSON, two loads, format 7 untouched, West fleets), pack_test (ROME_20 575e23d5 -> d60c218a; as format 7 still 575e23d5), story_test, server go test; the AI goldens hold as format 7 (`as_format(st, 7)`: 3007c1ab, bd76985b); campaign_sim 6x60 (format 6 by default) unchanged both packs; `--format=8`: Rome 4d21f126 1c4a86e9 286a3c80 d53713d6 605c409f 77cfbf4c, West d8cded2d d73b8c5d e64845ba 8eea9504 7c3efd9e 679e2092 (turn time +~0.5 ms); rules hash changes; the playtest server needs the rebuilt binary (state version 8) |
| Fog of war, view half (BUILT 2026-10-17, not committed): `game/campaign/fog_view.gd` (sight cache, helpers), `fog_layer.gd` (fog texture), map owner fill / borders from the last known owner, overlay pieces / sieges / blockades / wrecks / battles only when seen, last-seen markers (tap says the turn), zones / links / raids / replay filtered, region panel and bar card for unseen regions, Diplomacy / chronicle / Battles / Goals filtered, "Fog of war: on / off" on the new-campaign page, `--all-seeing`. **Open:** town models still show true buildings / culture, AI-less sandbox has no toggle but `--all-seeing`, not played on a device | Built 2026-10-17; campaign_input_test 319 PASS (+12 fog), campaign_test, pack_test, touch_scroll_test, town_tap_test, deploy_view_test; tap latency West t10 select army handler 2.6 -> 2.2 ms; shots in scratchpad fog/shots |
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
| Siege pass (2026-10-10; resumed after the movement build; the paused row's harness kept: full-kit row 2, `--fair-variants=fort0,fort1`, the flank yardsticks). **Bugs first.** (a) Defended escalades after "Units flow into the space": probe (b) re-run over 8 sim seeds (men up / defenders killed) before the build walls 1 88 / 42, walls 2 66 / 16; at HEAD 78 / 22, 56 / 4; the old `_ladder_step` spliced into HEAD restores 90 / 44, 66 / 15, so the cause is in the ladder rewrite: the queues were assigned in slot order and every death refills slots from behind, so under fire the first man of each queue changed every few ticks (360 idle lane-ticks a climb, the first man 3.1 m off the foot on average); fix: men nearest a foot first, `LADDER_AT` 1.5 -> 8 m (the old reach): 88 / 38, 60 / 7 (probe seed 77: walls 1 69 / 14 -> 90 / 39, walls 2 55 / 2 -> 60 / 8; no defenders 369 / 548 ticks all up, as before). The rest at walls 2 came from the old step's arrivals repeating the top of the ladder whose man had just died (friends within 3 m of an arrival 3.4-5.1 against 1.6): unphysical, not rebuilt. (b) Stuck columns: the longest (2,600-4,200 ticks) were batteries that had broken and rallied with every engine abandoned, their men held at dead engines: on settlement maps such a battery (or one with all engines wrecked) goes on as plain men (field unchanged: it re-records field battles); 60 polis acropolis archers sent by `_wall_shift` across the shut citadel gate: citadel wall units are not shifted, and the stuck release ends a march to a stair's foot or any move with no way through the street graph (`route_to` empty: an alley narrower than the 3 m line). Left: a heavy unit in a 2 m alley (polis walls 1 seed 5), defenders moving through their own stack. (c) "Ladder men up 0.0": gone at walls 2-3 (8-140 a battle); at walls 1 the batteries break the gate (about 125 s) before the ladder units reach the wall, by the AI's choice. **Change set** (the shelved patch docs/patches/siege_pass_shelved_2026-10-09.* applied, conflicts by hand, then removed with `git rm`): `TOWN_PLACE_LEAD` 10 m kept (re-measured off, i.e. 1.5 m: ring / polis walls 1 full kit 10 / 30 % against 40 / 40 %), `WALL_COVER` 25 / 25 / 40, `TOWERS_MAX` 3 / 4, `GATE_FIRE_CHIP` 15 / 8 / 6, Skilled `SK_STORM_STAGGER` 0, the settlement AI taking up crewless engines, all as shelved; `GATE_HP_PCT` 100 / 100 at walls 2 / 3 (shelved 100 / 115; correction round: walls-3 gates fall to the ram 8-9 in 10, polis walls 3 full kit 30 -> 50 %; walls-2 gates fall to the batteries and their time did not move at 100 / 85 / 70 %: the walls-2 value stays 100). Determinism layout hunk dropped (the movement build had moved that case already). **Equal-force sieges** (both Average, 10 seeds, attacker wins ladders + ram / artillery only / full kit, HEAD -> final):<br>ring walls 1 10 / 10 / 10 -> 20 / 60 / 40 %; walls 2 0 / 10 / 10 -> 0 / 20 / 20 %; walls 3 0 / 0 / 0 -> 0 / 0 / 0 %;<br>polis walls 1 30 / 40 / 30 -> 40 / 40 / 40 %; walls 2 0 / 0 / 0 -> 30 / 30 / 10 %; walls 3 0 / 10 / 0 -> 30 / 10 / 50 %; mean 8-11 min (max 15: the polis cells' 0-20 % draws), attackers withdraw in most losses.<br>Full kit walls 1 / 2: Easy defender ring 30 / 0 -> 80 / 0 %, polis 10 (50 % draws) / 20 -> 40 / 20 %; Skilled attacker ring 0 / 0 -> 50 / 10 %, polis 10 / 10 -> 40 / 30 %. **Why walls 2-3 still miss** (measured): deaths by place (full kit) 290-350 attackers outside the walls (their archers to the last man, 110-130; the ram's and ladders' carriers) against 55-65 defenders outside and 60-110 on the walls; inside the attackers win (ring walls 2 394 killed / 208 lost); the gate falls at about 125 / 200 / 290 s (walls 1 / 2 / 3, ring) with 840 / 740 / 660 attackers left; counter-battery off: 20-30 s sooner, no more wins. **Formula** (`campaign/cbattle.gd` `WALLS_PCT` by walls x kit, `kit_of`, `walls_pct`, the whole defending side; fitted to the final table, 20 battles a cell, (lost / won)^(1/3), pooled where noise inverted it): walls 1 115 / 115 / 114, walls 2 162 / 162 / 158, walls 3 262 / 178 / 158 % (on arrival / ladders + ram / full kit); `FORTIFY_DEF_PCT` 125 -> 119 (the camp: 13 / 20 on 2026-10-09 and 12 / 20 now against a mirrored 10 / 20; pooled 25 / 40). Crossings (`matchups --only=crossing-fort`, Scenarios.crossing, side 1 holding, 10 crossings): ford open holder 8 / 10, fortified 7 / 10; bridge open 10 / 10, fortified 3 / 10: the fortified holder stays in its camp at the mouth and lets the attacker cross and form, so fortifying at a crossing does not help; a crossing term in the formula is not built. Calibration (`campaign_battles --only=calib --n=60`) HEAD -> now: formula favourite won 47 -> 52 of 60 (78 -> 87 %), attacker wins sim 33 / formula 34 -> sim 30 / formula 31 %. Skilled `SHELTER_PCT` 0 -> 70. campaign_sim 6x60 hashes 6d277ec7 7837ac77 c6407e37 28ede655 a1836fb1 803bf309 -> 27f2b11a ddf58d21 f63ff00c 2af11059 6fb73bfe 59a136d0; sieges started / assaulted / won / lifted / surrendered 68 / 57 / 43 / 22 / 0 -> 53 / 41 / 35 / 17 / 0; battles a campaign 47-59 -> 21-50 (seed 1231 21), field 5-11 -> 1-10, eliminations 10 -> 9, largest at 60 10-14 -> 8-16 | Built 2026-10-10, not committed; check_scripts: only the uncommitted campaign-screen edits fail (my files check clean one by one); determinism full PASS (field goldens unchanged; settlement coverage hashes moved, e.g. siege_eq_ring3 0cb56c88 -> 118f3552, siege_eq_polis2~sa ad010bfc -> a549e54c; `--only=flow` probe walls 1 / 2 defended 90 up / 39 killed, 60 / 8); lockstep, custom_battle_test, campaign_test, battle_screen_test PASS (battle_screen aborts in the allocator at exit after its PASS, as at HEAD); not yet played on phones |
| Units flow into the space (2026-10-09; settlement movement, built after the siege pass paused; maps with buildings or walls only, field battles hash as before): **measurement** a hashed no-progress counter `u_stuck` (+ `u_srx`, `u_sry`, `u_sprog`; diagnostics `stat_stuck_max` / `stat_stuck_u` / `stat_stuck_t`), probe `determinism_test --only=flow` (ladders at walls 1-2 with and without 60 defenders above, four units through a gate, a street fight, a unit across a house's corner), stuck columns in `matchups --only=fair-sieges`; **ladders** queue at every ladder of the set (nearest / shortest queue, two abreast), each ladder takes its own man every `LADDER_TICKS` (hashed `q_lt` per lane replaces `q_acc`; same set throughput) (a "crowded top holds the ladder" rule tried and dropped: defended escalades fell to 55 men up / 4 killed), a move is taken while climbing (`_ladder_move`: along the stretch, outward = all down the ladders, inland = the rest climb then it goes on), a free ladder nobody comes to for `LADDER_STALL` 30 s gives the climb up (all down); **slots that flow** (`_flow_slots`: cut places flood the free 2 m cells nearest the anchor, a queuing or squeezed fighting unit packs, `u_flow` / `u_flt`, budget `FLOW_EVERY` 10 ticks, `FLOW_CELLS` 160); **stuck release** at 50 / 100 / 150 ticks of a 150-tick cycle (re-flow, re-plan or end a hopeless move, regroup); and the movement bugs the counter found (the squeeze's middle shift at a move's end, AI retargets replanning paths, stair-foot places on the walkway, stair trails through walls, anchors cutting wall corners, waypoints reached past a corner, short moves snapped behind houses, path tables starved for high-index units, moves to ground a shut gate cut off; DESIGN.md lists them). New constants: `STUCK_DIST` 2 m, `STUCK_CYCLE` 150, `STUCK_FLOW` 50, `STUCK_ROUTE` 100, `STUCK_NEAR` 8 m, `FLOW_EVERY` 10, `FLOW_AHEAD` 4 m, `FLOW_PACK` 125 %, `FLOW_CELLS` 160, `LADDER_AT` 1.5 m, `LADDER_QSP` 1 m, `LADDER_QW` 0.6 m, `LADDER_QCOST` 1.2 m, `LADDER_STALL` 300, `LANES_MAX` 8 (no balance number changed; the shelved patch untouched). Probe before -> after: ladders, no defenders, walls 1 / 2: all 90 up in 360 / 540 -> 369 / 568 ticks, 5 ladders in use at once (mean 4.7 -> 4.6), a move at the end refused -> taken, walls 2 left split 40 up / 50 below -> whole; with 60 defenders both rout down whole after ~50 lost (men up 77 / 57 -> 75 / 56, defenders lost 20 / 12 -> 17 / 2); house corner never formed (53 men off their places) -> formed at 1080; gate jam and street fight unchanged. Fair sieges (full kit, both Average, 10 seeds; measured before the crowded-top rule was dropped), ring / polis walls 1 / 2: units stuck past 20 s 8 / 20 / 29 / 31 -> 2 / 3 / 6 / 12, longest 3629 / 4255 / 2232 / 2906 -> 257 / 368 / 2466 / 854 ticks (**criterion "none above 200" not met**: narrow alleys the 3 m path line cannot use, stair approaches with stragglers far behind, defenders moving through their own stack); attacker wins (side effect, not tuned) ring 0 / 0 -> 0 / 10 %, polis 40 / 0 -> 40 / 0 %. Tick cost (desktop, HEAD -> this, same machine back to back): first 1,500 ticks (same opening) bench_4000_city 2.87 -> 3.10 ms (+8 %), castrum 3.05 -> 3.18 (+4 %), polis 3.35 -> 3.37 (+1 %), the unit update +0.1 ms; full benches (the battles now differ) city 3.59 -> 4.23 ms (+18 %: contact 1,220 ticks earlier, march +20 %, engaged +8 %), polis 4.37 -> 4.35, castrum 3.44 -> 3.46; flowed layouts about 0.25 a tick. See DESIGN.md "Units flow into the space", AI.md 25 | Built 2026-10-09, not committed; check_scripts clean; determinism full PASS (golden digests unchanged; `--only=flow` new, also in the full run; `--only=layout` moved to fair-siege seed 2: seed 1 no longer reaches the plaza reserve in 4,500 ticks), lockstep full PASS, custom_battle_test, campaign_test, battle_screen_test PASS; campaign_sim 6x60 unchanged 324307b6 bb0532b7 b9e5ae32 0bf0a9f8 b77014f8 481344a4 (the formula is untouched); rules hash changes; not yet played on phones **Open for the siege pass:** at walls 2 a defended escalade kills far fewer defenders than before this build (probe b: 12 -> 2 with 56-57 men up under every ladder-top setting; walls 1 back to 75 / 17 with the crowded-top rule dropped): find which movement fix changed the walkway fight before any lever |
| Explosive stones as a real blast (2026-10-09; owner: "is the blast any different from the rocks?"): an ammunition kind with `aoe` 1 (new AMMO field, `t_k_aoe`; only Explosive stones) bursts instead of ploughing (`_land_blast`): its `blast` 1536 -> 3196 (4 m round with the stone's 0.9 m); every man inside struck, energy full at the centre to a third at the edge (`(3R - 2d) / 3R`), armour as for stones, engines inside double; the survivors, nearest first, at most `BLAST_KNOCK_MAX` 30 a landing, thrown outward `BLAST_THROW` 1 m + RNG `BLAST_THROW_RND` 0-1 m (only over the ground they stand on: no wall, gate, building, walkway edge or ditch; else only downed) and down `BLAST_DOWN` 20 + RNG `BLAST_DOWN_RND` 0-10 ticks (riders and beasts half both; elephants not thrown, `BLAST_DOWN_BIG` 10). The down state is the existing `S_DOWN` with its hashed per-man `cooldown` timer (no new array: no moving, no attacking, out of `u_inreach`, no shield, `DOWN_BONUS` 35 in melee kept), slots kept so the hole shows until they get up; drawn lying on both paths already (state 3). Fear 40 unchanged (every man in the blast is struck). Probe `determinism_test --only=blast` (18-man battery, 160 pikes at 150 m, 120 s): 7 bursts, 23 struck / 14 knocked a burst, mean down 25 ticks, 27 men > 1.5 m off their places right after (most 44), 87 killed (the run also fires ordinary stones) vs 35 with ordinary stones (none knocked). Yardstick (`matchups --only=yard`, 20 seeds): the explosive load (8.7 shots) kills 58.0 of 120 pikes (136 struck, 78 knocked) vs 8.1 by as many ordinary stones. `--only=ammo` (explosive into heavies at 130 m): 23 -> 91 struck, 21 -> 48 killed, assertions unchanged. No AI change (it already prefers explosives at dense targets). See DESIGN.md "Explosive stones: blast and knockback" | Built 2026-10-09, not committed; check_scripts clean; determinism full PASS (golden digests unchanged; `--only=blast` new, also in the full run), lockstep full PASS, custom_battle_test, campaign_test, battle_screen_test PASS; campaign_sim 6x60 unchanged 324307b6 bb0532b7 b9e5ae32 0bf0a9f8 b77014f8 481344a4; rules hash changes; not yet played on phones |
| Turn chronicle and diplomacy stance (2026-10-09): optional state key `chronicle` (world-level rows, last 60 turns, written by `CRules.event`, hashed: the campaign_sim 6x60 hashes and the two pinned campaign_test digests changed for that reason only, rng unchanged); Realm -> Chronicle dialog and the start-of-turn summary share `_chronicle_box` (world first, then Yours); UI icon "chronicle"; `CAI.why` (accepts = why is "") and a stance line per proposal on the Diplomacy screen | Built 2026-10-09, not committed; check_scripts clean; campaign_test (new `_chronicle`); not yet played on phones |
| Siege equipment usability (2026-10-10; owner's playtest notes): **deployment pick-up** `ORDER_PICKUP {unit, equip}` accepted in the deployment (`deploy_pick_rule`, shared with the preview like `place_rule` / `works_rule`): the side's own piece in its zone is carried at once, the unit placed at it in its carry pattern, the pair moved by `ORDER_PLACE`, `ORDER_DROP` puts it down and re-forms the men at once; through the lockstep as unit orders, nothing new hashed; the view lets the tap on a piece and Drop through in the deployment and draws the pending pair. **Carry patterns** `EQ_CARRY_F` (ladders `LADDER_SET` 5, ram `RAM_FILES` 4, tower 8, wagon `WAGON_FILES` 4, mantlet its line / file spacing) read by `files_of` while `u_carry` is set (derived each tick, no new hashed array; `u_files` keeps the ordered frontage); HUD "Carrying a ram: column of 4". **Mantlet lines**: put down, `q_len` = the carrier's frontage (6 m `MANTLET_W` .. 40 m `MANTLET_MAX`), cover that long, 600 hp a 6 m (`mantlet_hp`), hit along the line (`_screen_near`); setup lays each at its unit's frontage; `q_len` now hashed with `q_face` in battles with mantlets; overlay bar at the length, cover hints. 80 archers (20 files): a 26 m line, 174 missiles stopped / 18 lost in 60 s vs a 6 m line 42 / 40. The AI does not pre-assign in the deployment | Built 2026-10-10, not committed; `determinism_test --only=carry` (new), full determinism (field goldens unchanged), `lockstep_test` (new siege deploy case), custom_battle_test, battle_screen_test, deploy_view_test PASS; coverage final hashes changed: siege_eq_ring3 cd0c5367 -> 0cb56c88, siege_eq_polis2~sa 0e167e09 -> ad010bfc (others as at HEAD); probes: equipment men up 55 -> 54, siege_tower 60 across in 157 -> 171 ticks (8-file column), mantlets field 49 -> 102 stopped; campaign_sim 6x60 hashes unchanged (auto-resolve); not yet played on phones |
| - **Roads, rivers and hills on the overworld (2026-10-09, built, not   committed; item 3 of "Where we are headed", the overworld half).** Static   data and rules only, state format stays 6 (the rules hash changes).   `map_geo.gd` gains 13 rivers with 25 named crossings (14 fords, 11   bridges; list in docs/CAMPAIGN.md), 17 roads (the Viae Appia,   Latina, Aurelia, Cassia, Flaminia, Aemilia, the Punic, Iberian, Gallic,   Greek and Sicilian roads) and 19 hill / ridge areas (Alps' foot ridge   20, not impassable; Apennines, Pyrenees, meseta edges, Atlas, Pindus,   Peloponnese, Sicily). `tools/campaign_grid.gd` bakes them into   `grid_data.gd` (TERRAIN rows, RIVER masks, CROSS list; checks: mouths   reach the sea, crossings join two cells of one landmass, roads on land   and over rivers only at crossings, landmasses still connected).   `cgrid.gd`: road cell 6, hill 15, ridge 20, river steps impossible but at   a crossing (ford +5, bridge free), diagonals never cross; paths, reach,   the AI and the preview follow. `cbattle.gd`: a field battle fought across   a crossing carries `"river": {id, kind, seed (frozen per crossing),   bank}` (the crossing-map build reads it), and a battle on a hill cell   gets hill ground. View: chevron hatch on hill cells, blue rivers, ford   stepping stones, bridge decks, tan roads; five key rows. Roma to   Tarentum is now one turn on foot along the Via Appia (two before).   campaign_sim 6 x 60 hashes: 013a8734 8550f0d0 1e04d1c1 a3cacfaa 6bb71642   f0026e4a. Battles a campaign 38-59 (57-82 before), field battles 5-15   (11-19), largest at turn 15 8-9 (6-8), at 60 10-19 (9-15), eliminations   median 2 (3); Macedon now falls in 4 of 6 seeds (1 before), Epirus 4   (6); no mustering refusals, every faction's land changes hands. Open: a   tap on a crossing showing its name (`MapView.crossing_near` is there,   the campaign screen does not call it yet); contact still happens across   a river edge without a crossing (no river key then); the "Macedon falls   more" shift is unexamined. Pacing note: AI campaigns fight fewer battles with rivers (57-82 -> 38-59 a seed) and Macedon falls in 4 of 6 seeds (was 1): for the tuning pass **Macedon fix (2026-10-10):** the trace showed the Greek League taking Larissa from the south by the Thermopylae road and Pella 1-4 turns later; a Tempe ford on the lower Peneus, the Tempe road Larissa - Pella and a Haliacmon road Pella - Ambracia (26 crossings, 19 roads, 304 road cells) give Macedon its reinforcement routes: eliminated in 2 of 6 seeds (was 4), pacing of the same order; hashes 6d277ec7 7837ac77 c6407e37 28ede655 a1836fb1 803bf309 |
| Overworld ocean, third pass (2026-10-13; owner: "I want to see waves, and the shoreline should have foam. But not everywhere"; BUILT, view only): `water.gdshader` waves (3 trains, normal-lit, damped near coasts), surf foam only on wind-exposed coasts, whitecaps in exposed open sea; `game/campaign/sea_waves.gd` (CPU twin of the wave height / normal for future ships); `tools/geo_fit.py` `bake_exposure` + `--exposure-only` (config `wind` in `tools/geo/med.json`, new `EXPOSURE`, `SHORE`, `WIND_*` in `relief_data.gd`), `GeoFields.exposure / shore_steep / wind_dir`; `map_view.gd` clock and uniforms. DESIGN.md "Real geography". | Built 2026-10-13, not committed; `check_scripts` clean, `deploy_view_test` PASS, desktop frame time on the map 4.00 -> 4.06 ms (whole map) and 4.09 -> 4.25 ms (zoom 2, vsync off); screenshots in the session scratchpad `ocean3/` |
| Overworld ocean, depth pass (2026-10-17; owner: real depth data, deeper darker, shallows sandy light; BUILT, view only): `tools/geo_fit.py` `bake_depth` + `--depth-only --dem` (DEPTH byte per fine sample from ETOPO 2022: 0 land, 1 m steps to 30 m, then 30 exp((v-31)/48.64) m, about 3000 m at 255; fetched fresh, the cached .dods paths are in the header), `DEPTH` in `relief_data.gd` and `relief_west.gd`, `GeoFields.depth_at / depth_image / depth_code_m`, `map_view.gd` sets the `depth` sampler, `water.gdshader` colours by depth (sand / turquoise under 8 m, shelf blue to 200 m, darker deep, faint 200 m shelf-break line where steep; coast distance still drives waves and foam; table style unchanged; Graphics Low keeps it). DESIGN.md "Real geography". | Built 2026-10-17, not committed; `deploy_view_test` PASS, `check_scripts` shows no errors in these files (a `game/sea_battle.gd` parse error from another agent's edit); frame time Rome map 4.32 / 4.59 -> 4.49 / 4.57 ms before vs after (whole map) and 4.85 / 4.86 vs 4.95 / 4.84 ms (zoom 2): noise; screenshots in the session scratchpad `bathy/` |
| Overworld ocean rework (2026-10-13; owner: currents looked like scratches, shore like a glow; BUILT, view only): `water.gdshader` narrow shallow band, two sharp contour lines (3 / 8 km), advected-noise current (no streaks, no foam), `map_view.gd` COAST outline 1.6 px darker, `landscape.gd` BEACH_KM 3 to 2 (narrower, sharper). DESIGN.md "Real geography" | Built 2026-10-13, not committed; `deploy_view_test` PASS, screenshots in the session scratchpad `ocean/`; `tools/check_scripts.sh` timed out, `touch_scroll_test.gd` fails to compile (other agents' files) |
| Compact unit cards (2026-10-09; user: the UI is busy with the roster; BUILT, view only): `game/unit_traits.gd` (traits, class counters, pips from the rows; rule in its head comment), card glyph lines in `Kit.UnitRow`, 16 new icons (`tr_*`, `cl_*`), recruit / raise lists grouped under class headers with "+n tiers" chips, army composition strip, unit book glyph rows, battle-screen tile glyphs. Open: battle matchup mark (needs a hook in `game/battle.gd`: on hover / finger over an enemy unit with one selected, call `Traits.matchup(sel_ty, enemy_ty)` and draw up / level / down in the HUD). |
| River crossing battles (2026-10-10; STATUS item 3's design, the battle side; pontoons not in it): a field battle with the scenario key `"river": {id, kind 0 ford / 1 bridge, seed, bank}` (set by campaign/cbattle.gd's overworld build; custom battles "River crossing: none / ford / bridge") is fought on the **crossing's own map from its frozen seed** (river 20-40 m, meander apex at the crossing, ford 12-20 m wide or a 6 m bridge, bed 2 m down over 16 m banks, a 3-6 m rise on each bank; the relief and woods from the crossing's seed; the far bank, held by `bank`, at the top, turned round when side 0 holds it); water `C_WATER` (nobody, no melee across, missiles over), the ford slows everyone to `FORD_SPEED` = `DITCH_SPEED` 45 % and takes a charge's momentum (`u_frd` hashed), the bridge is a one-unit lane (squeeze and queue); a graph along the banks and over the crossing for paths and routers; the holder faces the crossing, **fortified there its camp stands at the mouth** (front rampart 14-18 m from the exit, no gap facing the water, flank gaps); the AI holder holds (the camp's rule), the attacker skirmishes from its bank then crosses and forms beyond the far mouth; view: smooth river, ford shallows, stone bridge, the pre-battle crossing preview. DESIGN.md "River crossings" | Built 2026-10-10, not committed; `determinism_test --only=crossing` (new: maps frozen / differ / turned, AI crosses over ford 2100, bridge 1399, fortified ford 1648 ticks, nobody in the water, a ford charge arrives with momentum 0 and no impact vs 51 impacts without the river, the camp at the mouth, repeat and snapshot / restore), full determinism (field goldens unchanged), `lockstep_test`, `custom_battle_test` (river option), `battle_screen_test` PASS; campaign_sim 6x60 (auto-resolve; with the overworld build's changes in the tree) 013a8734 8550f0d0 1e04d1c1 a3cacfaa 6bb71642 f0026e4a; no balance run; not yet played on phones |
| Battlefield visual upgrade, code-drawn pass (2026-10-10; view only, not committed; sprite pass still queued): ground shader with grade in the height texture's A, crest line, patches of lusher / drier ground, rock on steep slopes and above the tree line on hill maps, wet sand, animated ripples and ford current; vegetation variety (stands, sizes, edge bushes) plus <=1900 non-gameplay glyphs (tufts, scrub, bushes under the men at z -1, reeds / willows on river banks, orchards beyond walls); settlement surroundings from `CityDraw.plan_surround` (tracks from gates, ploughed / crop / stubble fields, kept off streets, ditch, zones, approach, equipment); house shadows and ridges, wall footing, gate timbers, worn plaza. Details in DESIGN.md "Terrain height" (Battlefield look). Desktop frame cost +0.0 to +0.3 ms, bakes ground 110-160 ms and trees 70-100 ms; check_scripts, battle_screen_test, custom_battle_test, determinism --only=crossing / flow pass. |
| Graphics High / Low (2026-10-13; owner: Chrome on the Tab S7 is slow; view only, not committed; tablet untested): `[video] quality` auto / high / low in the home settings row, `game/quality.gd`; auto = Low on the CPU soldier path or when a battle's first 3 s average < 40 fps (session toast). Low: plain ground shader, no cover glyphs / orchards, flat fields and tracks, still sea, no map trees below zoom 0.9. Desktop gain small (GPU fast): bench_4000_city CPU path 6.3 ms high vs 7.9 low (noise), siege-coast GPU 4.2 vs 3.8, CPU 5.8 vs 3.5. Owner: try Chrome, Graphics Low, a battle and the map. |
| Heroes and agents, campaign and UI side (item 8a), 2026-10-10: `campaign/cchars.gd`; state `chars` [{id, kind (unit key), f, name, army (-1: in a city), r, wounded (turn he is fit)}] + `next_char` (lazy: absent until the first, so no `CState.VERSION` change), region `cq` (this turn's recruit), faction `ransom` (men; paid at the end of the turn); no unit slot, no upkeep, one hero / assassin / diplomat an army; orders `recruit_char {kind, r, army?}` (Barracks 2 hero, Market 2 assassin, Market 1 diplomat; one a turn a region; paid at once; appears at the end of the turn on the army if it still stands at the settlement with the slot free, else in the city), `attach {id, army}` (army at his city, slot free), `detach {id}` (army at a city of ours); armies merging carry them (a merge with the same slot on both is refused); an army lost: nearest own city, wounded `CHAR_LOST_TURNS` 3; left in a city that falls: captured (chronicle `char_captured`); a hero fallen in a battle: wounded `CHAR_WOUND_TURNS` 5 (`char_wounded`); prisoners: `PRISONER_RANSOM` 5 gold a man to the side that took them, end of turn (`ransom`); `CBattle.build` passes fit characters as scenario `chars` per sim side (+ `char_ids`), `outcome_from_result` reads rows with `char` 1 / `alive` (matched by order per side) and the side's `prisoners` (taken by that side); auto-resolve: a fit hero +`char_pct` 6 %; names 12 a culture (Latin / Punic / Greek / Celtic / Iberian) by `CState.rand`; AI knobs `CHAR_HERO` (8 = min units; Easy 0) and `CHAR_DIPLOMAT` (Skilled 1), never an assassin; UI: army card Characters block (name, glyph, wounded, detach), Recruit character rows, city panel Characters (Attach), pre-battle and result cards list them, HUD card mark, icons crown / dagger / scroll, recruit lists show only what the buildings allow with a folded "Not available here (n)" | Built 2026-10-10, not committed; campaign_test (recruit / limits / attach / detach / merge / capture / army lost / battle with chars + fallen hero + prisoners / ransom / auto-resolve / JSON / determinism / AI), battle_screen_test, campaign_input_test, touch_scroll_test PASS, icon gallery OK; campaign_sim 6x60 Average default 27675291 595a3764 dd6e8ac3 290bd772 fafbaa70 76eb0613 (heroes raised 0 / 7 / 1 / 5 / 7 / 3 per seed: Barracks 2 is rare for the AI), with the hero knobs 0 27675291 ddf58d21 c1463e00 381f7309 c33ac049 e2953371 (= HEAD's before the parallel map-data change); Easy unchanged; Skilled changes; formula battles never wound; sim side (unit rows, battle behaviour) by the other agent |
| Heroes and agents fix batch + Leave confirm + assault drop (2026-10-13; owner: "fix up the heroes and agents"; built, not committed, not exported): **Leave**: campaign battles ignore Leave / Menu taps for `LEAVE_GRACE_SEC` 3 s after the battle is shown (weekend telemetry: two battles forfeited 3 s in, reason "menu", 0 orders), then a modal "Leave the battle? Your army withdraws (a defeat)." [Stay] [Leave] (co-op: "Your units go to" + the team-mate's name) replaces the tap-again banner; the result names it ("Fought (you left the battle)", "You left the battle: your army withdrew (a defeat)."). **Assault**: `CRules.order_assault` drops silently only when one of our besiegers is already in that battle, else "a battle there this turn already"; grid assaults that make no battle say "no besieger free to storm it" (campaign_test `_grid_two_army_attacks`). **Heroes and agents**: Sabotage / Attempt / Parley buttons in the HUD order row (`hud.char_buttons`, the floating bar removed) and keys Shift+B / T / Shift+P, a refused key flashed with `char_refusal`'s reason; the soldier layer skips men of units `hidden_from` the viewer (GPU and CPU paths); an attempt's wound marks `CHF_WOUNDED` (8): a hero's aura at half radius (`_ch_reach`), a general's command gone (`u_cmdgone`, `_cmd_near` skips him); Skilled AI sabotage (`CH_SAB_R` 0 / 0 / 120 m, `CH_SAB_GUARD` 20 m, once: before he acts; counter `C_CH_SABOTAGE`; batteries only); campaign AI wants Barracks 2 at its military centre when `CHAR_HERO` > 0, after Range 2 / Workshop (characters raised in campaign_sim 23 -> 29, barracks finished 93 -> 109). DESIGN "Heroes and agents", AI.md 24 / 27 | Verify 2026-10-13: check_scripts clean; determinism full PASS (field goldens unchanged; `--only=chars` new lines: wounded champion aura 1 -> 0 at 28 m, a miss keeps it, wounded generals "2:gonew"; AI sabotage Skilled 1 sent / 2 wrecked, Average 0, escorted 0); lockstep, custom_battle, campaign_test, battle_screen_test PASS; windowed input_test, campaign_input_test PASS (the known exit-time abort after RESULT); campaign_sim hashes changed (C5): 2187c4a7 efdb73b4 942f7f41 ef96856c 29576afd 06e6f1a8 (were 27675291 595a3764 dd6e8ac3 290bd772 fafbaa70 76eb0613) |
| Deployment and battle time dropdowns, kills by enemy type, loading panel (2026-10-10; owner's three requests; built, not committed, not exported): **dropdowns** `Kit.dropdown(options, value, cb)` (OptionButton, touch-sized popup) in the new-campaign screen, the custom battle setup and the sandbox settlement row: deployment "0 / 30 s / 1 min / 2 min / 5 min / Unlimited" (Unlimited = `deploy_time` -1: `BattleSim._setup_deploy` keeps `dep_ticks` -1, no countdown, starts only when `dep_need` is ready; lockstep unchanged; HUD "Deploying: waiting for players"), battle time "10 / 15 / 20 / 30 / 45 / 60 min / Unlimited" (the sim has no 0 = no limit: Unlimited is 36000 s; campaign `time_limit` kept unless 900, `deploy_time` unless 0: no VERSION change). **Kills by enemy type**: sim `u_kills_ty` (n_units x `kty_n`, hashed, snapshot-safe, filled in `_credit`), `result()` rows carry `kills_by` [[type index, n]] sorted n desc then type; `cbattle.outcome_from_result` passes `kills_by` [[type key, n]] (a pack's merged into its handlers'); campaign result cards show "kills N" with kills per 10 men lost on the right and a tap lists the top 5 enemy types ("30 x Hoplite ... +n others") under the group's cards; the battle's own result panel has a Kills column with the same tap. The four field goldens are unchanged (they hash positions, not `state_hash`). **Loading panel** `game/campaign/loading_panel.gd` ("Preparing the campaign", gold bar, step label, modal) on New campaign (5 steps), a saved game (4) and an online campaign (5, with `OnlineCampaign.prefetch`), and "Preparing the battlefield" when entering a campaign battle the first time and whenever the last build took more than 300 ms (`LoadingPanel.last_battle_ms`; about 410 ms headless). `Landscape.bake()` split into `bake_relief()` / `bake_land()`, `MapView.geometry_lines()` / `prepare_steps()`. Cold relief cache on this machine: map 63 ms, relief 2,060 ms (62 ms cached), landscape 185 ms, screen 20 ms, state 14 ms. Tests: determinism (deploy unlimited, kills by type), lockstep (deploy unlimited), campaign_test, battle_screen_test (tap detail); screenshots `docs/screenshots/{loading_panel,result_kills,newcamp_dropdown,custom_setup_dropdowns}_*.png` |
| The column on the walk (2026-10-10; owner: heavy on a wall walk "fought in 2s", the light "a feeding machine"): yardstick `matchups --only=wall-col` (yard wall 8 attack / 9 move along / 10 open field; 100 light climbing a 5-ladder set onto a 95 m stretch, 100 heavy on the walk ordered at them once 40 are up). Rules on walls and streets only: a wall unit attacking along its stretch (or the joined one) goes as a column, anchor = head (`_wall_col_goal`, `u_flow` 2); a wall line in contact is laid behind an enemy's front ahead (`_wall_front`, `u_flow` 3), two files packed at `FLOW_PACK`, `PLACE_SIDE` cap along the walk, no wrap; reach cap `WALK_REACH_MAX` 3 for men on a walk or in a squeezed unit (`_reach_cap_count`, scratch not in snapshots). New constants: `WALK_REACH_MAX` 3 (the one balance number), `WALL_FRONT_GAP` 1 m, `WALL_PACK_MIN` 0.5 m. Yard 8, 20 seeds, before -> after: reach light / heavy 5 s after the order 23.5 / 7.5 -> 6.7 / 2.7, heavy lost in those 5 s 13.0 -> 6.2, killed light / heavy 35.0 / 22.9 -> 37.8 / 22.1, decided 40 -> 75 s (open field 37.2 / 9.9: the heavy still trade about 1.7 : 1 against 3.8 : 1, the light ~1.5x the men in reach). Fair sieges rows 0 / 2 attacker wins ring w1 20->20 / 40->50, w2 0->20 / 20->20, polis w1 40->60 / 40->60, w2 30->10 / 10->30 %. bench_4000_city 3.77 -> 3.96 ms (+5 %). DESIGN.md "Units flow into the space" | Built 2026-10-10, not committed; check_scripts clean; determinism full PASS (field goldens unchanged; `--only=flow` gains "walk column", repeat + snapshot / restore), lockstep PASS; not yet played on phones. Open: the residual 1.7 : 1 exchange (light pack closer at the ladder tops), yards 5 / 6 (two wall lines overlapping on one walk) still draw with no blows |
| Sprite pipeline step 1a (2026-10-13; owner: AI-made 3D-to-sprite art, bright faction palettes, few frames per action; built, not committed, not wired in): `tools/sprites/` spec.json (3 units, rigs, bodies, 3 palettes), build.py (Blender 5.2 EEVEE, parts parented to bones, shared humanoid / horse actions idle 1 / walk 6 / attack 4 / death 3, 3 passes shade / mask / check at 24 px per m), pack.py (stdlib: outline, crop per action, sheets, manifest), preview scene (3 palettes x 1x / ~12 px / ~7 px a man, iso 8 directions at 32 deg); `assets/sprites/` 184 KB with a .gdignore until step 1b. DESIGN 8 "Sprite pipeline (step 1a)" | Build 14 s, pack 1 s; check_scripts clean (preview script checked with warnings as errors); next: step 1b wiring into soldier_layer / both shader paths |
| Sprite pipeline step 1b (2026-10-13; view only plus a display field; built, not committed): **art fixes** (owner's notes): horse broader from above (barrel 0.74 m, wider chest / rump, thicker neck and head, larger muzzle and ears), legs splay outward in the walk; death = the horse sinks flat on its belly, legs splayed both sides, neck and head laid on their side (no profile; the 1a bug that built the right legs on the left legs' bones is fixed, so the gait is diagonal now); rider thrown clear; infantry heads +7 %, shields +5-8 %; new **Pikemen** (Spearmen with a 5.6 m sarissa, smaller shield). **Atlas**: pack.py packs all sets into `assets/sprites/atlas_{shade,mask}.png` (1024x332, frames on 4 px steps with 4 px gutters, imported lossless with mipmaps; per-unit and iso sheets moved out: iso to `tools/sprites/iso/`) and generates `game/sprite_atlas.gd` (frame table, palettes) and `game/sprite_frames.gdshaderinc` (the same table as constants). **Mapping**: `UnitTypes` display field `sprite_set` (0 procedural, 1 Heavy Swords: heavy / light lines and tiers, 2 Spearmen: spear lines, 3 Pikemen: pike lines, 4 Shock Cavalry: cav, cav_missile, general rows); archers, javelins, slingers, camels, elephants, dogs, artillery, wagons, characters stay procedural. **Palettes** 8 (Macedon saffron / crimson, Epirus violet / cream, Greek League sky blue / white, Syracuse teal / gold, Iberians white with crimson check) per unit faction: CBattle `unit_faction` -> `Battle.unit_faction` -> SoldierLayer; else the side's majority, else faction-only roster units (custom), else Rome / Carthage; the side shows by markers and the selection tint only. **Shaders**: per man action from state (dead: last death frame; knocked down: middle; fighting, or shooting while standing: attack; moving > 2 cm a tick or routing (x1.6 speed): walk; else idle), frame from the view clock `now` + phase fract(index x 0.618); texture path: uniform `frame_tab`, flags bits 3 shoot / 12-15 set / 16-19 palette; CPU path: constants, INSTANCE_CUSTOM.z set + 16 palette, .w index; recolour in the fragment stage from a 4x8 palette texture. Still one draw call per soldier layer; probe unchanged. DESIGN 8 "Sprite pipeline (step 1b)", tools/sprites/README | check_scripts clean; battle_screen_test, custom_battle_test, deploy_view_test, lockstep_test, determinism --only=flow PASS. **Same pixels**: soldiers-only offscreen render of one frame, texture vs CPU path: 0 px differ in 3 states (field close, cavalry, siege wide); bench_4000_city at 2.5x near y = 476 m differs only on sprite edges (12,324 px), as the procedural sprites already did there (7,034 px with sets forced to 0: sub-pixel placement, pre-existing). Frame time (RTX 3070, 1920x1080, vsync off, mean ms over 8 s from tick 600, before -> after): bench_2000 GPU paused 2.44 -> 2.55, running 2.56 -> 2.55; CPU paused 2.47 -> 2.49, running 2.57 -> 2.61; bench_4000_city GPU paused 5.98 -> 5.87, running 6.21 -> 6.23; CPU paused 6.02 -> 5.87, running 6.74 -> 5.03 (noise) : within noise, well under 1 ms. Animation held (`--soldier-anim=0`) vs on: no measurable difference, so Graphics Low keeps the animation. Texture memory +3.6 MB (two 1024x332 RGBA8 with mips) + a 4x8 palette. Screenshots (before / after, both paths) in the session scratchpad sprites1b/; not yet seen on the Tab S7 |
| Sprite pipeline step 1c (2026-10-13; view only plus display fields; built, not committed): sets 5 Archers (archer line, Cretans), 6 Javelinmen, 7 Slingers (whirl on a new `weapon.R` bone), 8 Gastraphetes (archer body, stocked belly-bow); unit pose variants and per-frame cords (bow string, arrow) in build.py; `--factions=a,b` battle testing aid; atlas 1024x424, 8 sets. DESIGN 8 "Sprite pipeline (step 1b)" last paragraph, tools/sprites/README | check_scripts clean; battle_screen_test, custom_battle_test, deploy_view_test, determinism --only=flow PASS; bench_2000 mean ms (machine busy, A/B same session) sets 0 -> 5-8: GPU 2.88 / 2.91 -> 2.80 / 2.82 / 2.90, CPU 2.82 / 2.77 -> 2.81 / 2.77 (noise); screenshots in the session scratchpad sprites_missile/ |
| Sprite pipeline step 1d (2026-10-13; view only plus display fields; built, not committed): sets 9 War Elephant (own rig: trunk 3 bones, ears, tusks; caparison, frontlet, howdah with shields, driver + 2 javelin men as `riders`; walk amble with ear flap, attack trunk swing + tusk gore, death = whole beast rolls on its side; amok = walk at the routing rate), 10 Camel, 11 Camel Archer (horse animation on a camel rig), 12 Engine Crew (cranking attack; batteries, tower engines, wagon crews), engine sets via new row field `engine_set` 13 Bolt Thrower (+ tower), 14 Stone Thrower (+ tower), 15 Scorpion (carried on poles while moving); engines: walk = packed / carried, wreck = death last frame (toppled, scorched), attack frame from `e_reload` (view states 9-12: release frame on the shot tick), abandoned = state 8 (idle, darkened); texture path flags bits 20-23, CPU path engine runs' INSTANCE_CUSTOM.z. Props (cart, wagon, draught horse) in the atlas, drawn by overlay.gd (wagon + horses, dead horses lying, wreck; stock bar kept). Atlas 1024x1184, 15 sets (4-bit fields now full) + 3 props, 613 KB. DESIGN 8 "Sprite pipeline (step 1b)" step 1d paragraph, tools/sprites/README | check_scripts clean; battle_screen_test, custom_battle_test, deploy_view_test, determinism --only=flow / elephants / light_art, lockstep_test full PASS (rules hash changes: new row field); existing sets re-render pixel-identical with the generalized riders code. **Same pixels**: soldiers-only frames, texture vs CPU path: 0 px differ in 8 states (elephants, battery with a wreck, scorpions carried / set up, wagons; zoom 1 and 3). Frame time (RTX 3070, 1920x1080, vsync off, mean ms over 8 s from tick 600, before -> after, 2 runs): bench_2000 GPU 2.90 / 2.77 -> 2.63 / 2.67, CPU 2.82 / 2.80 -> 2.65 / 2.63; bench_4000_city GPU 6.99 / 7.47 -> 5.99 / 5.87, CPU 7.10 / 7.43 -> 6.04 / 5.95 (noise: busy machine before; no worse). Texture memory: two 1024x1184 RGBA8 with mips ~12.9 MB (was ~4.6 MB, +8.3 MB). Screenshots in the session scratchpad sprites_beasts/. **Next / open:** siege equipment (ladders, ram, tower, mantlets) as overlay props like the wagon; scorpion crews walk beside the carried engine rather than under its poles; a further set needs the set field widened; not yet seen on the Tab S7 |
| Mouse controls, Total War: Rome scheme (2026-10-13; owner; built, not committed; real mouse only, touch unchanged): left click selects / empty ground deselects, left drag = box, right click = move the group keeping offsets (`_group_move`) / attack / run on double, right drag = line layout, middle drag pans. `battle.gd` `_right_*`, `_left_click`, `_line_preview`; Keys panel and DESIGN "Controls additions" updated; tests/input_test.gd `_step_rm_*` | see verify in the session report |
| Mid-battle reinforcements (item 7, first half; 2026-10-13; owner: "get a third army into the mix"; built, not committed, not exported): **no bounce**: every army that would join a battle joins it (`crules.gd`: `join_battle`, `_join6`, `start_field_battle`, `start_siege_battle`, `_assault6`, `_act_here`, support by range / radius); `CData.BATTLE_SIDE_MAX` 24 is now the field slots: `CBattle.field_split` (join order: b att / def then reinf, units in index order) fields 24, the rest are **reserves** (scenario key `"reserve": 1`, `"label"` the army's name) waiting at their army's map edge (field) or the attackers' edge / the plaza (settlement). **Sim** (`U_RESERVE` 5, `E_RESERVE` 3, like the kennel: counts fixed at setup): once a second a side's first reserve arrives, formed, when its field units (ready or routing) are below its slots (`rsv_cap`, its field at setup) at most one every `REINF_GAP` 5 s, or from `REINF_TIME` 120 s one every `REINF_SLOW` 10 s up to `REINF_FIELD_MAX` 30 (6 over the cap); stops when the side withdraws; a side with reserves still fights; unarrived reserves report all men remaining. Hashed only with reserves (`rsv_cap`, `rsv_last`, `rsv_stop`, `u_arr`); no new lockstep input. AI: takes arrivals as new line units; `_strength` counts open reserves, `_start_strength` from arrival. View: hidden cards until arrival, HUD "Arriving: n units" + 3 s "Reinforcements: <army>" note, pre-battle card "Arriving: n units". Tests: determinism `--only=reinf` (36 v 24: a slot freed at tick 382 brings a reserve at 390, 3 more by REINF_TIME; restore x3 equal), lockstep `--only=reinf` (two peers + a snapshot joiner), campaign_test (three armies of 12 join, outcome rows; Easy golden moved be6e10a3 -> bd76985b, rng unchanged), battle_screen_test (the Arriving line). Tick cost: bench_4000 3.07 -> 3.13 ms (same battle), `bench_4000_reinf` (36 + 24 units) 3.58 ms. campaign_sim 6x60 hashes moved (armies bounced before now join): cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e (were 2187c4a7 efdb73b4 942f7f41 ef96856c 29576afd 06e6f1a8); battles 39-61 a campaign (42-56). Open: ambush stance; no cap on the number of armies in a battle (every reserve's men are set up); no choice of which units wait. |

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
  `tests/touch_scroll_test.gd` now passes (2026-10-10; it needed to scroll
  its target into view and open the folded army strip).
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
- Forts leftovers (slice 2c), built 2026-10-16 (see "Forts leftovers" under
  the Slice 2c entry): walls 1 59 -> 41 % (the sally, the attackers' guns
  sparing the fort), walls 3 12 -> 25 % (one stone tower), the field AI draws
  all 4 against the charger. Left: walls 1 and 2 both 41 % (45 / 35 wanted:
  walls 2 is now no harder than walls 1); the field AI's draws against the
  charger are 30-minute draws (its empty shooters stay on the field) and its
  musket lines still run dry before the charger's; the second landward
  bastion's gun never bears on the town (measured, not changed).
- Distribution D open items: see "Distribution (D)" below.

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
  units flow into the space.** **Built 2026-10-09, not committed** (row
  "Units flow into the space" in "Where we are"; the stuck criterion is
  not met yet: see there; the shelved siege patch can be tried on top).
  Playtest: units still get stuck at walls
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
- **Right after the movement build (user, 2026-10-09): explosive stones
  as a real blast** (BUILT 2026-10-09, see "Where we are"; before it: a stone with a 2.4 m direct-hit radius
  instead of 0.9, +fear, 85 % range, slower; same damage, six victims at
  most, no knockback: "is the blast any different from the rocks?").
  Numbers chosen once: blast radius 4 m, damage falling from full at the
  centre to a third at the edge (not the stone's plough / pierce);
  **knockback**: every surviving man inside is thrown 1-2 m outward and
  is down ~2.5 s (new per-man down timer, hashed: no move, no attack,
  easy to hit), riders and beasts thrown less, never through a wall or
  off a walk with nothing below; fear 40 as now, downed men count as
  hit; at most 30 men knocked per landing (cost cap). View: the effects
  pass's blast ring; thrown men draw themselves. Opus (sim core, new
  state), about an hour; after the movement build (same landing code).
- **Compact unit cards (user, 2026-10-09: the UI is getting busy with
  the roster).** UI + data tags, Sonnet, after the current builds; no
  sim change. (1) Trait glyphs on every unit card (2-3: shock,
  anti-cavalry, armour-piercing, skirmish, long range, fire, fast,
  fearsome, screen), derived from the row's stats, tap for the meaning;
  (2) counters as glyph pairs: a green and a red row of enemy-class
  icons (foot, spear, horse, missile, beast, engine) from structured
  `good_vs` / `weak_vs` tags that also feed the book's prose; (3) stat
  pips: attack / defence / armour / missile / speed, four pips each,
  scaled per class; (4) lists grouped under collapsible class headers,
  best tier shown with a "+n tiers" chip, army cards with a composition
  strip (class glyphs with counts) expanding to the unit rows; (5) in
  battle, a matchup mark (up / level / down) on the enemy unit under the
  finger for the selected unit, from the same tags. Vocabulary kept to
  ~10 traits and 6 classes.
- **Turn chronicle and diplomacy stance (user, 2026-10-09), BUILT.** UI, Sonnet,
  with the compact-cards item. (1) **Round roll-up**: the "since you
  last played" summary carries only two turns of events and mixes the
  world in with your own; make a turn chronicle shown at the start of
  every turn and reopenable (Realm -> Chronicle, all past turns): the
  world first (cities taken and by whom, factions wiped out, wars and
  peace, sieges begun / lifted / surrendered, trade), then your own
  battles, gains, losses, buildings, recruits, failed orders; the events
  list already records all of it (keep more than two turns: a chronicle
  array in the state is a VERSION 6 optional key). (2) **Diplomacy
  stance**: the AI's answer to peace / trade is a deterministic rule
  (`CAI.accepts`: trade needs `TRADE_ACCEPT_TURNS` turns of peace and
  the asker stronger than `TRADE_ACCEPT_PCT` of its strength; peace after
  `PEACE_MIN_TURNS`, when it is below `PEACE_ACCEPT_PCT` of your strength
  or after `PEACE_ACCEPT_LONG` turns or down to `PEACE_ACCEPT_REGIONS`)
  but the screen shows nothing of it: show the stance next to each
  proposal before it is sent ("Would accept" / "Would refuse: at peace 2
  of 5 turns" / "Would refuse: they see themselves as the stronger"),
  computed from the same rule, no hidden information today. Per-faction
  personalities may blur it later.
- **Battlefield visual upgrade (user, 2026-10-10, after seeing the
  overworld's real relief: "the overworld is gorgeous").** The battle
  maps get the same treatment the overworld just did: the ground from
  the real elevation and ground palette of the battle cell (slopes
  shaded, crest lines, rock above the tree line), vegetation by
  elevation band and water (woods in the valley floors and along the
  river on crossing maps, scrub on dry slopes), fields and tracks near
  settlements, the river's banks and shallows, better walls / houses /
  roofs from the city palette, and the unit sprites when the sprite
  pipeline lands. View-only (terrain_layer / tree_layer / city_layer and
  the terrain shader), nothing in the sim; the code-drawn pass first,
  the sprite pass as the pipeline's second test after the West pack.
- **Order after that (user, 2026-10-09):** roads, rivers (with crossing
  maps and the camp at the crossing, item 3) **and hills on the overworld**
  (hill cells as movement cost and as the battle map's ground, so a
  position on the map means something) come BEFORE the siege tuning pass
  resumes: the tuning should see the terrain the campaign will have.
  So: movement build -> explosive blast -> equipment usability -> roads /
  rivers / hills -> siege tuning (shelved patch) -> N-player campaign ->
  heroes and agents -> audio -> Proxmox -> sprite pipeline -> shared empire.
- **Then (user, 2026-10-09): siege equipment usability.** **BUILT 2026-10-10** (see "Where we are" and DESIGN.md "Siege equipment usability"). (1) Pick up
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
  Tower engines shown (done 2026-10-09): pre-battle card "Wall engines (up to)" line, defender HUD one card per engine kind with shots and crew, tap cycles.
  Ordering into crowds + no field result panel in campaign battles (done 2026-10-13, owner playtest): tap on own unit with a selection = move (long press 350 ms / double tap selects, tight pick); campaign battle end = 1.5 s banner then back to the campaign result (custom / sandbox keep the panel).
  Two-finger tap deselects all units on the battle screen (done 2026-10-10; 120 / 250 ms, 12 px; "Deselected" flash in co-op only, the solo HUD has no hint bar).
  Recruit lists show every unlocked tier per line (done 2026-10-09): region panel, army card and the Raise-new-army picker (one row per tier).
  Overworld relief shading (done 2026-10-10): hillshade texture baked once from the grid (about 40 ms), hatch marks kept lighter, key hills row shaded; view only.
- **Region panel overflow fixed (2026-10-09, user's PC screenshot):** the
  side panel grew past the window edge on a besieged city on every
  display: `side_scroll` had horizontal scrolling DISABLED, which makes a
  ScrollContainer take its content's minimum width, and the siege row's
  three fixed-width icon buttons (~400 px) exceeded `PANEL_W` 360 / the
  48 % phone cap. Now `SCROLL_MODE_SHOW_NEVER`, `side_box` pinned to the
  panel width (minus the scrollbar), the siege rows and the army card's
  move row are `Kit.flow` rows that wrap. Screenshots desktop / tablet /
  phone checked. `tests/campaign_input_test.gd`'s 7 failures were stale
  expectations, fixed 2026-10-10 (it passes, also headless).

## The West pack, slice 1 (started 2026-10-13)

**West faction emblems (2026-10-15, view only).** `game/faction_emblem.gd`:
eight code-drawn multi-colour emblems keyed by the FACTIONS row's "key"
(new_spain Burgundy saltire, tierra_firme saltire + gold castle on silver,
england St George, france three gold lilies, dutch orange-white-blue, brethren
skull in a tricorne over crossed cutlasses, itza gold sun-jaguar disc on jade,
miskito sea turtle with feathers); nothing in campaign/ or sim/ changed (no
"emblem" field). Used by `Kit.faction_mark(f, px)` (replaces the colour
swatch in the new-campaign picker, hot-seat cover, diplomacy rows, key-cities
list, online seats, pre-battle groups; a faction colour frame from 18 px) and
as a flag on the army banner's top edge (`draw_banner(..., emblem)`).
Factions without an emblem (all of Rome's) keep the plain swatch / banner.
Contact sheet: `tests/emblem_gallery.gd`. West traits all already have
glyphs (traits derive from stats; none missing). Open: story panel swatches
are gauges, not factions (left alone); battle HUD has no faction mark.

User's choices: first slice = **map + pack plumbing**; window =
**Caribbean + Gulf of Mexico** (about lon -98.5..-58.5, lat 31.5..8);
pack chosen **in game** (one build, new-campaign screen Rome / West; the
state records it). Not in this slice: firearms, naval movement / sea
battles, West unit art, railroad. Placeholder factions reuse Rome unit
rows.

Architecture (survey 2026-10-13): rules reach content only through
`CData.<TABLE>` and `CGrid`'s grid script, the view through `map_geo.gd`
/ `geo_fields.gd`. Those become static vars set by `CData.use_pack()` /
`use_state(st)` (Rome tables move verbatim to `campaign/data/rome.gd`,
shared enums to `campaign/data/cenums.gd`); derived caches in CGrid,
crules, cai, cbattle rebuild when `CData.gen` changes; `resolve_turn`,
`apply_battle`, `new_campaign`, `migrate` switch the pack from the state
first. The state key `"pack"` is written only when not "rome", so Rome
states, hashes, goldens and the server's format-6 view stay byte-identical;
`CState.VERSION` stays 7; one rules hash covers both packs (pack files
flat in `campaign/data/`, since the hash does not recurse). No server
change.

Steps: 0 plumbing, Rome only, no behaviour change (Opus) | 1 geo_fit
output paths + `tools/geo/carib.json`, wind from 90 (Sonnet) | 4a view
geometry split `geo_rome.gd` / per-pack relief by `load()` (Sonnet) |
2 West content `campaign/data/west.gd` + `geo_west.gd` phantoms / roads
(Sonnet) | 3 `campaign_grid --pack=west` (Sonnet) | 4b screens: pack
choice, blurbs, subtitle, era "AD", save meta, palettes (Sonnet) | 6 West
validation: campaign_sim --pack=west 6 x 60, tests, online e2e (Opus).
Custom-battle pack key deferred (same unit rows).

Defaults taken (user may override): same 22 km cells as Rome (grid about
2.4x Rome), West relief at `fine_per_cell` 6 to keep the texture near
Rome's size for the Tab S7; settlements on islands under about 4 cells
(Tortuga, Barbados, St Eustatius) move to bigger land or wait for naval
play; Spain split in two (New Spain: Havana, Veracruz, Campeche; Tierra
Firme: Cartagena, Portobelo, Maracaibo) so it does not swallow the map;
natives: Maya Itza (Peten) and Miskito (Mosquito Coast); plus England,
France, the Dutch, the Brethren of the Coast.

**As built 2026-10-13 (slice 1 landed and exported):** commits 9a51c2a
(Caribbean bake, `tools/geo/carib.json`, `geo_west.gd`, `relief_west.gd`,
`west_elev_data.gd`), 03671af + 660d3c8 (view geometry per pack,
`geo_rome.gd`; geo_fit's med config writes it), d18a7a3 (CData pack
switch, `rome.gd`, `cenums.gd`, `pack_reset()` in cgrid / crules / cai /
cbattle, `tests/pack_test.gd`, Go `TestStateHashPack`), 07e73d0 (`west.gd`:
32 regions, 29 routes, 38 lanes, 8 factions on borrowed Rome rosters;
`west_grid_data.gd` 188 x 118; `campaign_grid --pack=`), 48e8e3b (Setting
choice, `PackView`, subtitle, save meta, palettes, goal text from
KEY_CITIES), then the start-setup pass (Spain calmer and smaller, 5
opening wars, more garrison and walls for the small powers; the Texas
corridor removed: for packs other than Rome a landmass may split into land
pieces that each have a lane port, so the Gulf-coast pocket is reached by
sea; campaign_sim reports elimination turns and sea crossings;
`online_e2e.py --pack=west`). West 6 x 60: no faction usually dead before
turn 25 (7 of 48 eliminations earlier), largest faction 12-18 regions at
60, 53-69 sea crossings a seed, 19-22 ms a turn. Rome campaign_sim hashes
unchanged (cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e).
Dropped islands under about 4 cells (Lesser Antilles, Curacao, Tortuga,
Barbados, New Providence) wait for naval play. Open: cai treats a whole
landmass as land-reachable (the split pocket relies on the path search's
lane fallback); battle maps use the Rome look; seed swings from AI-declared
wars are a balance question for later. Next slices: firearms (volley,
smoke, cover / line of sight), naval movement and ships (the ocean's CPU
wave twin), West units and sprites.

**Slice 2a, firearms + first West units (started 2026-10-14, user
approved the order firearms -> naval / ships -> West units and sprites):**
flat gun missile (`m_gun`: high armour / shield penetration, range falloff),
volleys (a unit fires as a body, holds fire beyond ~70 % of range), volley
fright via `m_fear` (cavalry +50 %), smoke and muzzle flash view-only (sim
smoke obscuring aim later), pistol cavalry, light and field guns on the
bolt engine path, West rows (musketeers, pikemen, buccaneers, rodeleros,
lancers, pistoleers / cuirassiers, native warriors and bowmen, guns) with
a `pack` field; West rosters switch to them; pickers show the active
pack's rows. Sprites map onto existing sets (the set field is full). Rome
byte-identical. Slice 2b: cover and line of sight.

**Slice 2c, West settlements (user, 2026-10-14): "there were no castles,
so we will have to rework the walls into forts and cities that allow
fighting from buildings and roof tops".** After cover / line of sight (2b),
which it builds on. Sketch to design with the user: (a) **forts**: low
thick bastioned walls (star trace) with guns on the bastions, a ditch and
glacis, hard to escalade, breached by guns; the Spanish walled ports
(Havana, Cartagena, San Juan, Veracruz, Portobelo, St Augustine) get a fort
by the town; (b) **open towns**: no curtain wall (or a palisade), buildings
as garrisonable blocks: a unit occupies a building, its men get cover and
shoot from windows and rooftops with a height gain, the attacker clears it
by melee at the doors (a street fight from house to house) — **note
(user, 2026-10-16):** rooftops and balconies must build on the per-man
fire-at-will model (Cover stance: each man picks his own target by his
own line of sight; volleys only in Line), so a man on a roof or balcony is
just a man with a higher eye and shot line; design 2c's garrisoning around
per-man sight lines from windows / balconies / parapets, not unit-level
cover percentages; (c) native
towns: palisade and jungle cover. Rome's wall levels stay as they are;
the West picks its battle-map settlement kind by pack. **History check (2026-10-14):** around 1650 most Caribbean
towns were open towns guarded by harbour forts (Havana: El Morro, La
Punta, La Fuerza, town walls only from 1674; Portobelo, Maracaibo, Port
Royal, Tortuga: forts only; Veracruz: San Juan de Ulua on its island,
town walls after the 1683 raid; Campeche: walls 1686-1704 after repeated
raids; St Augustine: wooden forts, the stone Castillo 1672-95). Only a
few had real circuits then (Santo Domingo; Cartagena and San Juan
partly). The buccaneer raids of the 1660s-80s are what got the walls
built. So in the West the Walls chain becomes: 1 a harbour battery /
fort beside an open town, 2 a fort plus a partial landward wall or
palisade, 3 a full curtain with bastions; a raid on an unwalled port
makes walling it cheaper (rule of cool with a real anchor).

**Slice 2d, battle-map landforms (user, 2026-10-14): towns need not be
circular, they take a shape; battle maps want more than mounds: cliffs,
rock outcrops and forest that follow the landscape, with towns built
around and using it.** Both packs (Rome battle goldens re-pinned once,
on purpose). Sketch: mapgen places landforms from the campaign cell's
real relief / class (ridge, hill, valley, coast, river): cliff lines on
steep slope breaks (impassable, block missiles and sight later), rock
outcrops (small impassable clusters, cover in 2b), forest in bands along
valleys, slopes and water rather than round blobs; the settlement's
outline follows the ground (along a shore or river bend, up a spur, a
citadel or fort on the high point, streets following contours), walls
or palisade tracing that outline. View: cliff faces and rock sprites,
forest edges. Order: 2a firearms (running) -> 2d landforms -> 2b cover
and line of sight (uses the rocks and forests) -> 2c forts and fighting
from buildings.

**Slice 2d, as built 2026-10-14 (not committed; DESIGN "Battle-map
landforms and shaped settlements").** `sim/landforms.gd` (new) places, on
generated hilly ground (rolling, ridge, valley, hill, slope: the region's
terrain or the cell's hill / ridge override), cliffs along the contour on
the steepest 6 % of the ground (0-3 a map, 26-64 m), outcrops on crests
and rough ground (up to ~18, 2-8 m, in groups), sea cliffs along a rocky
shore beyond a coastal town; new impassable cells `C_ROCK` / `C_CLIFF`
(missiles pass over until 2b; each carries a height for it), kept 12 / 7
m from each other, the deployment areas, walls, the approach, fields,
water and the edges, a flood fill drops any cliff that closes ground
off; a path graph round them on field maps. Woods follow the land: long
blobs along the contour, valley floors, lower slopes, the lee of ridges,
river banks, ragged edges, none on rock or a cliff face (same coverage).
Settlements: `MapGen.shape_of` lobes and stretches the polis, punic and
oppidum outlines (long down a spur, along a hill's contours or the
shore), the hill's brow and the spur's edge follow the wall, the
citadel sits on the high point, hill grids run along the contours; the
gate, tower, stair, ladder and citadel code is the existing polygon code
(gates identical on 1,728 surveyed maps; ladder probe 853 / 853). View:
`game/land_layer.gd` (cliff faces with brow, hachures, scree and drop
shadow; shaded boulders; Low: faces and boulders only); the sea and
ditch are drawn again (a lost shader flag). `terrain.landforms: 0` gives
the old maps byte for byte. No golden needed re-pinning (all pinned
trajectories are on flat or settlement-free maps); campaign_sim hashes
unchanged; verify suite green. Harness (17 scenarios + 30 maps a pack):
no unreachable unit, sieges decide as before, time per tick +2-6 % on
the packs' field maps, +8 % on ridge / hill maps with many outcrops (over
the +5 % aim; the lever is fewer outcrops in the battle band). Open: no
town on a river (needs a city + river map); the campaign preview does not
draw the rocks; cliffs sit on existing slopes (no height step).

**Slice 2b, cover and line of sight, as built 2026-10-15 (not committed;
DESIGN "Cover and line of sight", AI.md 28).** Unit field `cover` (West:
buccaneers, cutlass men, native warriors and bowmen; Rome: the javelin and
sling lines, the skirmishers; line rows 0). Cover men take `COVER_STOP`
45 % (woods) / 60 % (rock, cliff 2-4 m toward the shooter) / 50 % (house,
wall) / 25 % (hedges) fewer soldiers' missiles and balls, go to ground
when still in cover (35 % more stopped, 1.5 s to get up, concealed beyond
40 m) and shoot out of their own woods' edge; line troops get nothing new.
Line of sight on every map with blockers, both packs (decided: woods
hiding men is right for Rome too; scenario `los` 0 turns it off): woods,
outcrops, cliffs and field-map buildings block sight (settlement houses
and walls do not: slice 2c); a unit no enemy sees is hidden (not drawn,
not targeted by the sim or the AI; flat weapons hold on a hidden target,
arrows are lobbed blind); in woods seen only within 40 m or for 5 s after
shooting; a unit seen after 5 s hidden ambushes for 10 s (its first volley
or contact: -200 morale, +40 disorder). Rocks and cliffs now stop flat
shots beyond 5 m of either man. AI: plans from what it sees, cover troops
take cover by their slots (ambush on defence), foot probe the woods. View:
hidden enemies and their thinned canopy not drawn, a leaf (in cover /
gone to ground) and a closed eye (unseen) on own markers, a reveal ring,
"TARGET OUT OF SIGHT". New: terrain key `rocks` (hand-placed outcrops),
scenarios `test_ambush`, `test_cover`, `determinism --only=cover`.
Numbers (6 seeds, 90 s, a musket line 90 m off): buccaneers lose 25.3 /
60 in the open, 15.3 behind rocks standing, 1.3 gone to ground (hidden;
duelling 22.5 / 13.7 / 9.3); line musketeers there 35.0 = 35.0. No pinned
golden moved (flat maps have no blockers); campaign_sim 6x60 hashes
unchanged (cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e,
HEAD-tree copy with these files); unpinned woods / landform / settlement
runs changed (punic siege seed 12345: the assault now fails, coverage
`stair_down` dropped there; seeds 1-6 attacker wins 1 / 6 against 3 / 6
without line of sight, more defenders left). Cost: bench_4000_hills
4.42 -> 4.45 ms a tick, with 45 % forest 4.50 -> 4.61, bench_4000_city
4.23 -> 4.34, bench_2000 1.48 = 1.48. Open: smoke does not block sight;
the AI does not remember last-seen positions or hold fire for an ambush;
artillery shot ignores cover; cover by the unit's centroid for sight
(a unit half in a wood counts as in it); balance not tuned (sieges lean
to the defender; the campaign formula was fitted without line of sight).

**Pathing pass 2 (docs/PATHING_SPEC.md), phases 0 and A, as built
2026-10-15 (not committed; DESIGN "Routs among walls and houses").** Phase
0: `tests/pathing_probe.gd` (`-- --phase=A` gates the exit code on phase
A's thresholds; `--ids=`, `--seed=`, `--quick`): per-man jitter (2 s
windows, path >= 3 m and net < path / 3; rev/step; walk / net) by unit
state and place, routers' stationary share (centroid < 3 m in 10 s, not
huddled), stuck runs over 30 s with routers counted, men inside the drawn
house footprints, tick mean. Phase A: per-man flight down integer exit
fields (per side, per shut gate's refuge; a 4-neighbour flood built 1,000
cells a tick, taking over 25 s after a gate change), routers off the wall
man by man along the stair's trail, refuge kept till its gate opens,
huddle at the refuge or where they are with no way out and surrender of
final routers within 15 m of a ready enemy, rally / regroup / charge
re-form anchored on a reachable man, slide memory (routers and standing
units), separation of slot-followers near obstacles, routers in the stuck
statistics. Probe, seed 7, sieges village / town / city / hill / castrum /
polis / punic / oppidum + battle_2000 + bench_4000_hills, before -> after:

| metric | before | after | threshold |
|---|---|---|---|
| rout jitter, stair / town / near obstacle / field | 78.8 / 6.0 / 1.1 / 0.4 % | 0.0 / 0.3 / 0.3 / 0.2 % | <= 5 % |
| rout rev/step, stair / town | 80.1 / 8.4 % | 1.5 / 0.2 % | (rout-gate < 3 %) |
| routing time stationary (not huddled) | 9.3 % (town 30, city 20, polis 15) | 0.0 % | <= 5 % |
| stuck > 30 s (ready + routers) | 18 (router 149 s, ready 189 s) | 0 (router 0 s, ready 26 s) | 0 |
| idle near obstacles jitter / rev | 2.3 / 22.0 % | 1.3 / 2.6 % | |
| fight near obstacles / in town jitter | 4.2 / 2.6 % | 4.8 / 2.8 % | <= 3 % (phase C) |
| inside drawn footprint / < 0.3 m | 3.53 / 2.38 % | 3.35 / 1.66 % | <= 0.2 % (phase B) |

Seeds 8-10 (six of the maps): rout jitter 75-86 % (stair) / 3-7 % (town)
-> <= 0.5 %, stationary 14-22 % -> 0 %, stuck > 30 s 11-32 -> 0; fights
near obstacles 3.8-4.9 -> 3.9-4.9 % (noise between diverging battles;
slide memory in contact made it 6-7 % and was left out). New determinism
set pieces `--only=rout` (also in the full run; `--only=walls` runs the
wall-order pieces alone): rout-wall (off the walk 9.4 s after breaking,
rout jitter 0 %), rout-gate (a gate broken first; huddled at the refuge
19 s after the break, rev/step 0.1 %, the 60 final routers give up to
heavy foot within 15 m), trapped (huddled in 0.1 s, standing still, none
in a blocked cell), each identical on repeat and across snapshot /
restore taken while exit fields build. Goldens: the four flat digests
unchanged; no settlement / landform trajectory was pinned. One AI
outcome check re-pinned: determinism "crossing ford" (a river map, so it
has exit fields) used battle seed 4242, where the AI attacker no longer
got 50 men across by tick 3000 (a chaotic flip: over battle seeds 1-7 and
4242 it crosses in 7 of 8 both before and after); now seed 5 (tick 927
before, 931 after); and the coverage run `siege_eq_ring3` 4,500 -> 5,600
ticks (it must see a gate broken: with the exit fields the AI's ram is
burnt at 1772 and the battery breaks the gate at 5446, the ram broke it at
2503 before; seeds 1-4 the gate falls at 2499-3493, was 2440-2753, a
balance side effect to watch; without the fields it plays as before);
campaign_sim 6x60 hashes unchanged (cdc1d805 32b83031 23f9ed4f 3237d82d
a42fc685 b6fe6c2e). Cost (`tests/benchmark.gd`, desktop, mean ms a tick, before -> after;
the battles' trajectories differ): bench_4000_city 4.02 -> 4.10 (march
2.67 -> 2.93: the first generation builds then, about 0.4 ms a tick for
its first 18 s; engaged 5.05 -> 5.12; max 8.4 -> 10.6), bench_4000_hills
(landforms: no fields) 3.36 -> 3.41. The 8 sieges of the probe run alone,
seed 7: 10.83 -> 11.05 ms summed (+2 %; per siege -13 to +10 %; the first
cut of the separation, four neighbours every other tick, cost +8 %, up to
+19 %). Setup unchanged (the fields build in play); `restore()` +50-80 ms
a generation (two at most); snapshots one byte a man bigger (`s_wf`).
Open: phase B (clearance: men stand
inside the drawn houses 3.4 %; done, next paragraph), phase C (fights at obstacles 4-5 %, town
3 %); landform-only maps keep the unit flee vector (no fields); huddled
routers are drawn as routing (no own icon); a scaled-down campaign
battle counts men who gave up as remaining (`CBattle.outcome_from_result`
scales killed / routed / withdrawn only; unscaled battles lose them).

**Pathing pass 2, phase B (building clearance), as built 2026-10-15 (not
committed; DESIGN "Clearance off the houses").** A static 1 m clearance
field from the drawn house outlines (exact integer distance to the nearest
one or two buildings per cell, their rectangles / turned quads / round
houses measured exactly at a man's position; built at setup in 6-45 ms,
not in snapshots, nothing new hashed). Men in all four movement paths are
put out to 0.5 m off a drawn face after the nav test (exactly onto that
line: no bounce; a standing unit's man pushed back square on takes the
slide memory); places nearer than 0.5 m are cut and flowed, flow and
huddle spots nearer than 0.8 m stay empty, the rest are put out to 0.8 m;
units re-lay their places after the first tick on such maps and an anchor
dropped in a house moves to open ground; `_squeeze` measures streets to
0.5 m off the faces; street graph edges cost 4 m more per metre they pass
nearer than 3 m to a house. Walls, towers and rocks are not in the field.
Probe (`tests/pathing_probe.gd -- --phase=A`, seed 7, same 10 maps),
before -> after:

| metric | before (phase A) | after (phase B) | threshold |
|---|---|---|---|
| inside drawn footprint / < 0.3 m | 3.35 / 1.66 % | 0.00 / 0.07 % (punic 0.01 / 0.42 %) | <= 0.2 % / < 0.5 % |
| rout jitter, worst category | 0.3 % (town) | 0.3 % (town) | <= 5 % |
| routing time stationary | 0.0 % | 0.0 % | <= 5 % |
| stuck > 30 s (longest ready / router) | 0 (26 / 0 s) | 0 (25 / 0 s) | 0 |
| fight near obstacles / in town jitter | 4.8 / 2.8 % | 4.7 / 3.1 % | <= 3 % (phase C) |
| idle in town / on walls rev/step | 4.6 / 8.6 % | 4.8 / 6.8 % | |
| move in town jitter | 1.9 % | 2.1 % | |

Cost (desktop): setup +6-45 ms (bench_4000_city 205 -> 232 ms); the 8
sieges' tick means summed 11.09 -> 12.23 ms at seed 7 (+10 %; polis 1.65 ->
1.97, punic 1.67 -> 2.10) and +6 % over seeds 1-4 (3,000 ticks; village
+14 %, city -8 %): the battles differ (units settle and fight in other
places); the pushes themselves cost 0.03-0.09 ms a tick, `_squeeze`
0.01 ms. bench_4000_city 4.07 -> 3.89 ms a tick (march 2.91 -> 3.25,
engaged 5.09 -> 4.32; another battle); bench_4000_hills / battle_2000
unchanged (no buildings). Goldens: the four flat digests, the campaign_sim
hashes (cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e) and every
determinism pin unchanged (no re-pins). Open: walls, towers and rocks are
not in the field (men still touch a wall's foot); fights near obstacles
4.7 % and in town 3.1 % (phase C); punic 0.42 % of men within 0.3 m (a
push refused where the open ground ends); the tick cost of settlement
battles sits at the +10 % budget.

**Pathing pass 2, phase C0 (real cover: flat shots stop at walls, men take
cover), as built 2026-10-15 (not committed; DESIGN "Real cover: flat shots
stop at walls"; spec addendum 1).** On maps with an obstacle grid where
something stands up (`ft_on`: houses, walls, gates, rocks, cliffs; `los`
not 0) a flat soldier's missile (balls, javelins, sling stones; arrows and
artillery as before) about to strike a man is traced along the 2 m grid
(integer DDA, in order; a 16 m summed-area look first): a cell whose
obstacle stands above the line stops it (a dust puff in the view at that
point, `game/overlay.gd`). The line ends at a cover man's body (1 m,
crouched) or a line man's head (1.7 m, upright), so a 1.6 m boulder covers
a skirmisher and not a musketeer; the rock / house / wall `COVER_STOP`
rolls are gone for flat shots (woods and going to ground keep theirs). A
man who shot within 1 s is up over or round his cover (skipped near him
as near a shooter). Field maps' hand-placed `blocks` now stand 5 m for fire
(shots used to pass through them). Per-man cover: a cover unit standing
with a threat (its fire target, else the nearest enemy seen within 250 m;
bearing `u_cvb`, laid out again only past 40 degrees) puts its men on
spots in the lee of cover within 8 m of their places, 1.5 m behind a
covering 2 m cell: the cover's edges first (where a man leans out 1.2 m to
shoot, `_lean`), then the middles of faces (safe, no shot); nearest men
first, one a spot; line units never. Hashed with `ft_on`: `s_shot` (per
man, his last shot's tick), `u_cvb`. Scenarios `test_cover_town` (an open
Punic town, buccaneers at a street's mouth) and `test_cover_rocks`;
probe `tests/cover_probe.gd`. Balance (probe, 4 seeds, 100 musketeers 90 m
off a 60-man unit, 90 s; defenders lost / attackers lost, HEAD -> C0):

| defender, ground | buccaneers | line musketeers |
|---|---|---|
| open | 0.51 = 0.51 | 1.02 = 1.02 |
| scattered rocks 1.6-2.4 m | 0.26 -> 0.27 | 0.77 -> 0.67 |
| hamlet (field-map blocks) | 0.18 -> 0.09 | 0.82 -> 0.25 |
| Punic town, a street's mouth | 1.16 -> 0.96 | 1.48 -> 1.41 |

`--only=cover`: buccaneers behind the 1.6 m boulder line lose 16 over 4
seeds (2b: 34; open 87), 7 balls stopped by the rocks; the line there 32 =
32 in the open (no spots, none off its places); in the town 92 men to
spots, 8 shots leaning out, 12 of 36 behind cover at the end (a line in
their place 0 of 19), lost 24 / killed 32 (the line 41 / 23); identical on
repeat and across snapshot / restore. Re-pinned checks in `--only=cover`
(no golden hash moved): "cover stops > 0" became "balls stopped by the
rocks > 0" (the rock roll is gone for flat shots); "line musketeers lose
the same in rocks as in the open" became "no more in the rocks, no cover
taken, at most 5 % of them over 3 m off their places" (holds 32 = 32);
new: the town pieces. Rome battles: the sieges' and benches'
trajectories did not move (their javelins and slingers land no flat shot
on a man near obstacles in these runs, and stand under orders), so the
pathing probe's numbers are identical. Goldens: the four flat digests,
campaign_sim hashes (cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685
b6fe6c2e) and every determinism pin unchanged. Cost (desktop, two rounds
each, HEAD -> C0): bench_4000_city 3.88 / 3.86 -> 3.86 / 3.82 ms a tick,
bench_4000_hills 3.44 / 3.43 -> 3.38 / 3.35, battle_2000 1.48 / 1.45 ->
1.45 / 1.43, the 8 sieges (3,000 ticks, `probe_maps.gd`) summed 10.91 /
10.94 -> 10.90 / 10.90: noise (nothing new runs in them); a trace is 7-16
microseconds a 100 m line (town, rocky field), only for balls that reach a
man; the town duel 0.27 -> 0.31 ms a tick (160 men). Open: the dust puff
is small and brief (FX_DUST); palisades, mantlets and field works keep
their own % rules; cover spots are claimed within a unit only (two units
may share a rock); cover units take spots only with no order (an attack
order's shooters do not); a man in a face's middle has no shot (no rule
yet lets him move to an edge as men there fall, beyond the layout after a
death); Rome's sieges barely use it (C1-C3: cover points, `COV_HOUSE` in
towns, stances).

**Pathing pass 2, phases C1-C7 (street fighting), as built 2026-10-15
(not committed; DESIGN "Street fighting: stances, bounds, the press in a
lane").** Stances (ORDER_STANCE through the lockstep: Line / Take cover /
Hold street; a Stance button, key C, and a Bounds toggle, key B, in the
order panel); Take cover for any foot unit standing, shooting its attack
target from where it stands, or halted in a bound (the C0 leftovers: an
attack / halt order keeps the spots; spots claimed across units; spots
re-laid every 5 s so face men take freed edges); two rows of spots behind
each spot in the same lee for the men with none (40 buccaneers at a street
mouth lost 62 -> 34); a town's houses are cover (C3: going to ground,
arrows); bounding advance (move "bound": the even men go up to 25 m to
cover while the odd men hold and shoot, then the odd men come up; lines
hop and halt 4 s); street melee (a squeezed unit in a lane fights with
ranks 1-2, no lapping round; the shove: a unit holding a lane outnumbered
3 : 2 at the front gives 0.3 m a second); Hold street (lines take the
street's width, three ranks at least; cover troops its corners within
12 m); West street AI in open towns (defenders' strongpoints at the mouths
nearest the attackers, lines in Hold street behind; attacking skirmishers
by bounds, lines wait 70 m off a strongpoint until it is worn to 60 %);
the blocked-ball puff is now a flash, chips and a 1.6 s cloud. Not built
(reasons in DESIGN): C1's static cover-point table (C0's spot finder
already gives the corners and faces; claims are done on the hashed
places), per-point cover kinds, section 6 (street disorder, rank-limited
volleys, flank support: they would move Rome's fitted battles).
Hashed only once a stance or bound order was given (`stn_on`): flat
goldens untouched. Balance (`tests/cover_probe.gd`, 4 seeds, defenders
lost / attackers lost, C0 -> C1-C7):

| defender, ground | buccaneers | line musketeers |
|---|---|---|
| open | 0.51 = 0.51 | 1.02 = 1.02 |
| scattered rocks | 0.27 -> 0.16 | 0.67 = 0.67 |
| hamlet (field-map blocks) | 0.09 -> 0.00 | 0.25 = 0.25 |
| Punic town, a street's mouth | 0.96 -> 0.51 | 1.41 = 1.41 |

`--only=street`: street-cover 40 buccaneers lose 34 at the mouth vs 63 in
the open (53 %; the spec's < 50 % not quite: the line's first volley lands
before the men reach their spots; the check is <= 60 %); bounds arrive
after 8 bounds, the holders shot 221 times, nobody shot on the move,
nobody inside a house; hold fills the street in 14 files of 60 men; each
identical on repeat and across a snapshot (mid-bound). Lockstep street
test: each peer orders Hold street through the lockstep (stn_on, 1800
frames equal, a joiner by snapshot). Pathing probe (seed 7, before ->
after): fight in town 3.1 -> 2.3 %, near obstacles 4.7 -> 5.1 %; seeds
8-10 town 2.6 / 2.6 / 3.4 -> 2.8 / 3.9 / 3.6 %, near obstacles 4.3 / 3.8 /
4.1 -> 4.9 / 3.7 / 4.3 %: **the phase C jitter target (<= 3 %) is not
met**; the changes are within the seed-to-seed spread. Attribution
(scratchpad `jat.gd`, `plc.gd`): near obstacles the jitter is men with no
man of their own in units attacking or shooting (battle_2000: horse and
missile units' places swung by the unit turning to its target, 29 km of
place movement from turning in 6,000 ticks), in town the rear ranks of
squeezed units pressing (their flowed places re-laid every second).
Tried and dropped: a 20-degree facing hold in contact (stuck > 30 s
appeared), matching pressing men to their nearest flowed places (jitter
up to 8-11 %). Phase A / B metrics hold at seed 7 (rout jitter 0.2 %,
stationary 0 %, stuck > 30 s 0, inside footprints 0.00 %); seeds 8-10
show 2-4 stuck > 30 s runs (HEAD: 2 / 0 / 1). A pre-existing case found:
in some punic trajectories a wall missile unit's men left on the ground
beside the wall oscillate under their walk places (fight/wall 1.1 %).
Goldens: the four flat digests, campaign_sim hashes (cdc1d805 32b83031
23f9ed4f 3237d82d a42fc685 b6fe6c2e) and every determinism pin unchanged
(no re-pins; the C0 cover pieces still pass with the town's new
numbers). Cost (desktop, HEAD -> now, two HEAD rounds): bench_4000_hills
3.37 / 3.52 -> 3.43, battle_2000 1.43 / 1.52 -> 1.45, the 8 sieges
(3,000 ticks) 10.85 / 10.94 -> 11.03 ms summed (+1-2 %), bench_4000_city
3.83 / 3.82 -> 4.30 ms a tick (march 3.22 -> 3.28; engaged 4.24 -> 4.87
in a battle 600 s long instead of 545 with 43 % more blows: the city's
battle runs another way: not C5's, with it off the cost is the same; most
likely C3, the city's skirmishers going to ground among the houses; no
cover layout ran in it).
Open: fight jitter (above; met by phase J, below); phase W (built 2026-10-16, below); the AI's field
battles do not bound; balance phase T (street disorder, West morale).

**Pathing pass 2, phase W (West open towns), as built 2026-10-16 (not
committed; DESIGN "West open towns"; spec section 7 and addendum 2).** The
user: the town should cover a larger part of the map, mostly unwalled, its
buildings not symmetrical or perfectly placed, following the road and the
land. A West settlement (city key "west": the West pack's
`CBattle.city_dict`, a West custom battle, the `west_*` scenarios) with
walls 0-2 and a European founder is now an open town (`MapGen._city_west`):
a band along the shore (or the top of the field inland) 380-600 m wide and
150-255 m deep, covering 32 % of the map (villages) to 39-46 % (towns,
cities); a quay (or back street), a winding high street through a 36-56 m
plaza (church, governor's house, market), a lower street, cross streets
every 50-90 m (dog-legs at the high street) out past the landward edge
(the street mouths), lanes between them; roads traced 10 m a step round
rocks, cliffs, big trees and the fort, and along the contours. Buildings
on irregular lots along every road by kind and density (warehouses,
chandlers, taverns and stores on the quay; shops, taverns, stores on the
high street; houses; shacks thinning out at the edge): uneven setbacks
and gaps, turned with the road +-5 degrees (more at the edge) and toward
the contour on a slope, at most 3 m of slope across a lot, wings (L),
lean-tos, yard walls, goods at the doors and on the quay; 90 (village) to
340 (city) buildings; a height and stone / timber material each. Walls 1:
a bastioned harbour fort on the shore (inland: the high back corner),
solid; walls 2: plus a stake palisade along the landward edge with a gap
at every road. Natives keep the oppidum, walls 3 the walled plans. Sim
(West maps only, so Rome, Greek and Punic battles are untouched): flat
balls go through a timber wall 35 % of the time (stone stops them; one
roll of the sim's RNG), houses stand their own heights for the line of
fire, goods (1.0-1.4 m) and yard walls (1.3 m) are crouching cover;
defenders routing in a port take to the boats at the shore (exits of their
field); a router caught in the streets (a ready enemy within 15 m for
10 s, or still 8 s with one there) gives up (hashed there: `stat_rs_*`,
`u_gu`); the clearance field is built 2 m round each house and not inside
its cells (houses block every cell within 0.6 m of their drawing). View:
12 new Blender kit pieces (tavern, shop, store, warehouse, chandler,
shack, lean-to, governor's house, low wall, stakes, crates, pier; the
atlas stays 1024 x 1024, 61 of 64 rects; the 49 old pieces pixel-identical),
street fronts to the road, Spanish flat roofs or northern gables by
founder, three painted palettes, the fort's curtain and bastions, sandy
streets and a paved plaza, town ground only where built up, palms on West
maps in any pack. Scenarios `west_village`, `west_town`, `west_city`,
`west_inland`, `west_port`, `west_hill_village`, `bench_west_town` (1,680
men in 40 units), `bench_4000_west`; `tests/determinism_test.gd
--only=west` (each town built twice the same, coverage, kinds, props,
mouths joined to the plaza; turned round for the other side; AI vs AI
identical on repeat and across snapshot / restore); West towns in
`tests/pathing_probe.gd` (`--west` for them alone) and a West town case
in `tests/cover_probe.gd`.

Pathing probe (`--phase=A`, seed 7, all 16 maps: the 10 before and 6 West
towns): PASS. West towns: rout jitter <= 1.2 %, stationary routers 0 %,
stuck > 30 s 0 (longest ready 20 s), inside the drawn footprints 0.01-0.12 %
(within 0.3 m 0.01 %), tick means 1.45-1.86 ms (1,264 men); the Rome rows
are those of C1-C7 (their trajectories did not move). Seeds 8 and 9 (West
towns): rout and footprint thresholds pass; one ready unit each stuck 46 /
37 s (an attacking skirmisher keeping an attack order on a target it no
longer sees: C7's AI with line of sight; Rome's sieges show 2-4 such runs
at seeds 8-10). Fight jitter near obstacles / in town 5.1 % / 6.1 % (the
phase C target of 3 % is still not met). Fixes found by the probe on the way
(each in DESIGN): the defenders' routers of a port take to the boats; a
router caught in the streets gives up; 3 m between buildings and wings
overlapping their house (2 m slivers jammed routers between the clearance
pushes off both faces); houses block the cells within 0.6 m of their
drawing (men pinned at turned houses' corners); graph nodes in the open
ground between the lots (a unit in a back yard saw no node and walked into
a house); 36-56 m plazas (ten attacking units jammed on a 30 m one); the
church and the governor's house before the other roads (the high street
crossed the plaza's sides: no governor's house); attackers inside the town
no longer go back out to their street's mouth.

Cover probe (`tests/cover_probe.gd`, 4 seeds, defenders lost / attackers
lost; the new West case 40 m up a street from the mouth nearest the
attackers, houses of stone and timber, goods, yard walls): buccaneers 0.58
(39.8 % of the men behind cover, 26 balls stopped of 273 traced, 2 through
timber walls), line musketeers 1.56 (0 % behind cover: in a lane they stand
upright); the Punic town 0.51 / 1.41, the open 0.51 / 1.02 and the other
rows unchanged.

Cost (desktop). Set-up, cold (terrain + map + sim, map cache cleared):
village 170 ms, towns 313-322, the Dutch port city 371, bench_4000_west
402, the hill port city with palisade 491 (Rome: polis 322, bench_4000_city
223, siege_city 169). Of the hill city's: the map 269 (lots 55, roads 45,
graph 45 with the bucketed join, landforms 37), the clearance field 113 (was
260: 2 m round each house, not inside it), the vis grids 35. Ticks:
`bench_west_town` 1,680 men in 40 units 2.89 ms a tick (engaged 2.90; the
spec's budget 3 ms for 1,500); `bench_4000_west` 4,704 men in 67 units 8.25
ms (Rome's bench_4000_city 4.40 for 3,894 in 53: the West battle is engaged
from tick 114 to the end, its men move among obstacles all the way and its
many cover units check their cover per man each second). Rome benches
unchanged against HEAD (same trajectories): bench_2000 1.47 = 1.47,
bench_4000 3.16 -> 3.17, hills 3.51 -> 3.47, city 4.39 -> 4.40, polis 4.99
-> 5.00, castrum 4.59 -> 4.63 ms a tick (noise).

Goldens and pins: the four flat digests, every determinism pin and the
campaign_sim hashes unchanged: Rome cdc1d805 32b83031 23f9ed4f 3237d82d
a42fc685 b6fe6c2e, West b137875c edd82dee 0393b18d 2aa8578b deb00750
1d051164 (the campaign auto-resolves; battle maps are not in its state; the
city dictionary's "west" key is built for the battle only). No re-pins: no
West settlement pin existed (the new `--only=west` checks build each town
twice and compare). Rome, Greek and Punic maps are byte for byte as
before (their city dictionaries have no "west"; `_clr_exact` was unrolled
with identical results). Verify suite: check_scripts clean, determinism,
custom battle, campaign, pack, battle screen (its exit-time heap abort
after PASS predates this, seen since phase A) and lockstep tests PASS.

Open: the fort is solid (no garrison, batteries or gate: slice 2c); the
palisade does not burn or get hacked; piers are scenery and no ships are
moored on the battle map; native towns keep the oppidum and walls 3 the
walled plans; West towns' tick cost is about 1.5 x a Rome city's per
man (per-man movement among obstacles and the many cover units' cover
checks); the hill port city's set-up (491 ms) is over the 450 ms mark; cover in the sparser West streets is weaker than in the
Punic town (balance phase T); fight jitter near obstacles and in town is
still over the phase C target (met by phase J, next paragraph); villages cover about a third of the map
(the approach and the attackers' ground take the rest).

**Pathing pass 2, fight jitter and stuck units (phase J), as built
2026-10-16 (not committed; DESIGN "Fight jitter and stuck units").** Goal:
the phase C target (fight jitter near obstacles and in town <= 3 %) and 0
stuck runs over 30 s at seeds 7-10; both met. Causes found by attribution
(scratchpad `pathJ/jat3.gd`: each jittering man-window of a fighting unit
split by what moved the man) and per-tick traces: men swinging between a
face and their place every tick (a slid or pushed step undone by the
next: battle_2000's men behind a cliff 10 %, men 50 m from their places
in town); units turning in a fight (most foot turn at once, so every
wobble of the bearing threw the places round; a facing flipped for one
tick at a move's first step); flowed places re-laid every second or at
each death and shuffled; the street middle shift against the path at a
corner (facing swinging 86 degrees every 3 ticks); the lag regroup every
10 s for men slowly coming through a lane; an anchor sliding to and fro
under a house below its waypoint; and in the AI, skirmishers fallen back
by the sim sent back to their post the next second (an about-face each
way), storming units turning between a defender and the plaza at the
plaza's hunt radius. Stuck runs:
West skirmishers in range with no line of fire closing straight into a
house; an attacker closing on a target 54 m off while its men fought
another at a gate; stragglers 40-130 m off in pockets; men split by a
shut gate; lone routers pinned at a drawn corner the exit field ran
past; 36 of 38 routers shut in a court. Fixes (all on maps with
obstacles only): a per-man step guard (`s_ls`: a slid step that undoes
the last stands, at most 2 s), a 12-degree facing deadband in a fight
with turns finished once begun, at most 16 a tick for foot that turn at
once, a fall-back in contact keeps its ordered facing (no about-face),
flowed places re-laid only when the anchor's cell (two cells in a fight),
the facing or the squeeze changes, a squeeze hysteresis of one file and no middle
shift with an enemy near, the lag regroup only once the men stop, the
anchor's along-a-wall step not undoing the last, missile troops with no
line of fire going round by the streets, a stragglers' trail at the
stuck release and per-man routing on the street graph for men of a
standing unit 12 m+ off who stopped getting nearer (`s_via`), exit fields off cells under a
drawn house's clearance and a sidestep for pinned routers, a huddle when
fewer than a quarter of a router's men can get out; AI: take on the
enemy at hand, West skirmishers pick a target they can shoot and keep an
unseen one 6 s, no order over the sim's skirmish fall-back (10 m
hysteresis), a 20 s stuck watchdog that plans the order again, the plaza
hunt with a 30 m hysteresis. The stuck statistic counts a unit
only while none of its men is fighting (a unit whose men fight in turn
at a gate is in the fight). Pathing probe (all 16 maps, 6,000 ticks),
HEAD -> now:

| seed | fight near obstacles | fight in town | stuck > 30 s (longest ready / router) |
|---|---|---|---|
| 7 | 5.1 -> 1.7 % | 4.0 -> 1.6 % | 0 (25 / 0 s) -> 0 (24 / 0 s) |
| 8 | 4.8 -> 1.9 % | 3.7 -> 1.6 % | 5 (46 / 22 s) -> 0 (24 / 18 s) |
| 9 | 3.8 -> 1.9 % | 4.1 -> 2.0 % | 3 (41 / 42 s) -> 0 (24 / 0 s) |
| 10 | 4.4 -> 2.2 % | 3.8 -> 1.9 % | 3 (54 / 52 s) -> 0 (24 / 0 s) |

rev/step in fights 7.0-8.4 -> 4.3-5.9 %, walk / net 1.30-1.35 ->
1.20-1.24. Per map at seed 7: battle_2000 near obstacles 10.3 -> 0.9 %,
siege_oppidum 5.2 -> 2.5 %, siege_town 4.6 / 4.5 -> 1.9 / 1.7 %, West
towns in town 5.0-8.2 -> 1.5-4.3 % (port 4.3, village 3.0); fights on
walls 1.1 -> 0.0 % (the stranded wall missile men on the Punic walk:
2-cycles against the walk's edge, caught by the step guard; what is left
on walls is men walking to a new slot after a death). The West towns'
near-obstacle rows (8-12 % at the port and the hill village) are a few
hundred man-windows each (men at the town's edge). Phase A / B metrics
hold (HEAD -> now, seeds 7 / 8 / 9 / 10): rout jitter worst 0.2 / 0.3 /
0.3 / 1.9 -> 0.3 / 0.4 / 0.4 / 0.3 %, routing time stationary 0.0 / 0.2 /
0.3 / 0.8 -> 0.0 / 0.1 / 0.0 / 0.0 %, inside the drawn footprints 0.03-0.04
-> 0.04 % (within 0.3 m 0.00-0.12 -> 0.00 %); seed 7 move in town 2.3 ->
1.6 % (seed 9 2.1 -> 2.9 %, most likely the missile troops now going
round by the streets, laid out again as they go), move near obstacles 3.3 -> 1.0 %, idle in town 0.4 -> 0.1 %
(rev/step 9.4 -> 3.6 %), idle near obstacles 0.6 -> 0.3 % (rev/step 2.3
-> 2.9 %). Cover probe (4 seeds, defenders lost / attackers lost, HEAD ->
now): buccaneers open 0.51 = 0.51, rocks 0.16 -> 0.13, hamlet 0.00 =
0.00, Punic town 0.51 -> 0.50, West town 0.58 -> 0.53; musketeers 1.02 /
0.67 / 0.25 / 1.41 / 1.56 unchanged. `--only=street` street-cover:
buccaneers lose 34 -> 32 at the mouth against 63 in the open (an early
cut of the straggler routing sent them the long way round to their
cover: 38, over the 60 % check; fixed by routing only men who stopped
getting nearer). Cost (desktop, `tests/benchmark.gd` and the 8 sieges of
`tests/probe_maps.gd` at 3,000 ticks, two rounds each, HEAD -> now, mean
ms a tick): bench_4000_city 4.39 / 4.30 -> 4.36 / 4.32, bench_4000_hills
3.47 / 3.45 -> 3.54 / 3.61 (its march, the same trajectory for the first
440 ticks: 3.80 / 3.88 -> 4.25 / 4.26, the per-man bookkeeping of the step
guard and the stragglers' check, +0.15 ms of the soldier update;
engaged 3.44 / 3.40 -> 3.44 / 3.51), battle_2000 1.48 / 1.45 -> 1.48 /
1.50 (march 1.20 -> 1.35, engaged 1.63 -> 1.56), bench_4000_west 8.25 /
8.27 -> 8.03 / 8.10, the 8 sieges summed 11.01 / 11.02 -> 11.79 / 11.94
(+7-8 %; town 1.45 -> 1.64, punic 1.47 -> 1.63, oppidum 1.30 -> 1.59: other
battles; polis 1.77 -> 1.67). Set-up +8-10 ms on settlement maps (the
exit fields' clearance cells, built once). Screenshots (scratchpad
`pathJ/shots/`, the pathB harness at seed 7: the Punic gate fight at
ticks 3600 / 3800 and a West town fight at 2600, before / after; the
battles differ by then).

Goldens and pins: the four flat digests unchanged; every determinism pin
unchanged (no re-pins); campaign_sim 6 x 60 Rome cdc1d805 32b83031
23f9ed4f 3237d82d a42fc685 b6fe6c2e, West b137875c edd82dee 0393b18d
2aa8578b deb00750 1d051164 unchanged. New hashed state on maps with
obstacles (`s_ls`, `s_via`, `u_flx`, `u_flf`, `u_asl`, `u_gnode`), so
settlement and landform battles hash differently from HEAD (lockstep
peers agree; snapshot / restore checked). One test changed:
`tests/lockstep_test.gd` three peers compared the refused-order counts
at each peer's last frame, and the peers stop a frame apart: with the new
trajectory an order refused in frame 1201 counted on A and C only (230
vs 231; the states were equal every frame); the counts are now compared
at the last frame all three applied. Verify suite: check_scripts clean,
determinism, custom battle, campaign, pack, battle screen (its
exit-time heap abort after PASS as before) and lockstep PASS.

Open: men in a lane still walk to a new slot after each death (slot
filling, not touched); West towns' fights in town are 1.6-4.8 % per map
at seed 7 (the aggregate is under 3 %); the stragglers' routing takes the street
graph's 3 m lines, so a man in a yard no line reaches still stands; the
watchdog halts a stuck move and its mode may give the same move again
(it plans it from where it stands); a view log: `game/unit_icons.gd`
draws a degenerate pike glyph polygon at some marker sizes ("Invalid
polygon data" in the after screenshot's log; view only, untouched).

**Balance pass T, as built 2026-10-16 (not committed; DESIGN "Balance
pass T").** The change pass after the measurement pass (scratchpad
`balT/MEASURE.md`, harnesses in `balT/` and `balT/t/`). Rows changed: one
West field (buccaneers `m_spread2` 60 -> 100); no Rome row. Rules: the
battle AI's plan anchors on a musket line, or on the missile foot of an
army with no line, and once engaged musket lines (and all-missile armies)
close to their range on the nearest free enemy; per-man fire at will for
guns and bows in Take cover on maps with obstacles (owner's request, no
volleys there); cover troops start in their spots, gone to ground, on the
battle's first step; `CS_R` 8 -> 10 m; a unit at cover spots has a line of
fire if one of 4 of its men has; skirmishers fall back from a gun unit
closing on them; West street posts chosen by the cover round them, reached
at the run, lines at 40 % (open towns) or in depth at 80 % (fort,
palisade); defenders routing inside the walls do not rally while the
attackers stand in the streets (`RALLY_TRAPPED`); battlements walls 2-3
15 / 25 % (was 25 / 40); a battery standing by its engines no longer
counts as stuck.
Before / after (4 seeds unless noted; 8-seed figures in brackets):

| measure | target | before (HEAD 5422cd6) | after |
|---|---|---|---|
| open field, musketeers 100 vs buccaneers 86, both AI | musketeers >= 3 of 4 | 0 / 4 (30-min draws, 0 lost) | 3 / 4 (seeds 5-8: 4 / 4) |
| West open town (west_town's town, seed 12), buccaneers holding | buccaneers >= 3 of 4 | 0 / 4 (towns 11-14: 0 / 16) | 4 / 4 (towns 11-14: 16 / 16) |
| street mouth: buccaneers' losses / open ground's | < 50 % | 50 % (32 / 63) | 29 % (21 / 72; killed 79 / 83) |
| equal-force full kit, ring walls 1 / 2 / 3 | 45 / 35 / 25 % | 0 / 25 / 0 % | 50 / 25 / 0 % (75 / 38 / 0) |
| equal-force full kit, polis walls 1 / 2 / 3 | 45 / 35 / 25 % | 50 / 25 / 0 % | 50 / 50 / 25 % (38 / 38 / 25) |
| both plans together walls 1 / 2 / 3 (8 seeds) | 45 / 35 / 25 % | 6 / 6 / 6 % (with the AI and cover changes, none of the siege ones) | 56 / 38 / 12 % |
| West equal force, west_town + west_city, walls 0 / 1 / 2 | 55 / 45 / 35 % | 75 / 75 / 75 % (4 seeds each); 31 / 62 / 44 % (8 seeds, after the AI and cover changes, posts at 60 %) | 69 / 44 / 38 % (8 seeds each) |

The street-mouth check (`tests/determinism_test.gd --only=street`,
`STREET_PCT`) is tightened from 60 to 50 %. Cover probe (4 seeds, 900
ticks), buccaneers lost / attackers lost: open 0.51 -> 0.76 (the scatter),
rocks 0.13 -> 0.27, hamlet 0.00 -> 0.00, Punic town 0.50 -> 0.41, West town
0.53 -> 0.78 (they lose less, 17.8 -> 14.8, and kill less at 90 m, 33.5 ->
19.0); musketeers' rows unchanged. Other rows of the equal-force table
(4 seeds): ladders + ram ring 75 / 0 / 0 %, polis 50 / 25 / 0 %;
artillery only ring 50 / 0 / 0 %, polis 50 / 25 / 0 % (draws 0 / 0 /
50 %). The Rome ids at their own (unequal) force: village 4/4, town 4/4,
city 4/4 (was 3/4), hill 0/4, castrum 2/4 (0/4), polis 4/4, punic 3/4
(3/4), oppidum 3/4 (1/4). West ids at ratio 1.46: village, town, port 4/4;
city 2/4 (2 draws), inland 1/4, hill village 1/4 (all 4/4 before).

The AI with a West army (owner's playtest note; `balT/t/aib.gd`, a West
field battle WEST_ATT vs WEST_DEF at equal cost and west_town, AI vs AI and
AI vs a scripted player, 4 seeds): cover troops sit in Take cover by default
(their row's stance) and the town's defending lines take Hold street (C7);
the field AI sets no stances (Line in the open, as wanted); bounds only in
towns (attackers, 17-58 a battle before, 20-42 after); guns fire in every
battle the gun row lives (attacker's battery 27 -> 42 shots in the field;
the defenders' battery in the field AI vs AI is ridden down before it
fires, before and after: no guard picked for it, a known gap);
skirmishers fall back (unit-seconds 347 -> 466 field, 776 -> 1118 town for
the defenders) and stand in a melee little (5 -> 21 / 14 -> 4
unit-seconds). Against the scripted player (stand 60 s, then everything
charges) the field AI drew all four at 30 min before (its last missile
units stood off) and now loses all four in 8-11 min, at closer losses.
Perf (benchmark, alone, before -> after): bench_4000_city 4.68 -> 4.29 ms
(another trajectory), hills 3.57 -> 3.58, battle_2000 1.50 -> 1.50,
bench_4000_west 7.75 -> 8.01 ms (+3 %; the per-man fire is 0.65 ms of it);
the 160-man town duel 0.30 -> 0.33 ms; the 8 Rome sieges' tick means
(pathing probe) within 0.1 ms either way. Phase A probe: PASS (rout jitter
0.3 %, stationary routers 0 %, stuck > 30 s 0); fight jitter near
obstacles 1.7 -> 2.1 %, in town 1.6 -> 1.9 % (target 3 %).
Left: equal-force walls 3 at 12 % (25 wanted: the ring holds 0 of 8) and
walls 1 a little high (56 %); the West open towns at 69 % (55 wanted), the result swings with the
line posts (40 / 50 / 60 %: 69 / 12 / 31 %) and the two towns differ more
than the walls do; the field AI against a charging player; the
defenders' guns unguarded in the field; the fort's inside (phase 2c).
For the auto-resolve refit (campaign/, another agent): see the outcomes
listed in the balance pass T report (equal-force rows above, the Rome and
West ids at their force ratios 1.33-2.35 and 1.46).

**Slice 2c, forts and fighting from buildings, as built 2026-10-16 (not
committed; DESIGN "Forts and fighting from buildings", AI.md 29).** The
owner: "there were no castles": forts, and towns where men fight from
buildings and rooftops, built on the per-man fire at will. (1) **The
harbour fort with an inside** (West walls 1-2): a square trace with four
flanked bastions (20 vertices), low thick walls (10 m, walk 6 m up), a ditch
round the land faces with causeways, the knoll levelled for the parade
(the glacis round it), the main gate toward the town (open till attackers
come near or bring a ram or ladders), a sally port, stairs at every
stretch's ends, the barracks and a powder magazine (new kit piece) on the
parade; the sim's wall machinery as a citadel ring (`fort_on`, `n_outer`:
the open town's rules key on the outer gates now, Rome equivalent). Its
guns: a fixed fort gun (new last unit row, 260 m, a shot in 40 s) on each
landward bastion and on the seaward curtain, firing only within 60 degrees
of their embrasure's way out. Its garrison: the best musket company (one,
only when another is left for the streets) on its land stretches, firing
man by man from the parapet with the walk's height (wall units on West
maps use the per-man fire). **Result rule:** the town's plaza is still the
prize: taking it wins the battle; the fort's men do not rout with the town
and the result carries `fort` {held, men, gate, taken}; the fort falls when
the attackers hold its parade with none of its garrison on it for 30 s
(its men rout). **Campaign:** a town taken with its fort holding
(`fort_holds` in the outcome) does not change hands: the fort's men are the
garrison and the siege goes on (no sack, no capture); no state change (the
auto-resolve never sets it: campaign_sim unchanged). The attackers' AI
storms the fort as well only with a ram, ladders or guns and when the fort
holds 35 % of the defenders' strength (else it takes the town round it);
storming: the ram at the shut gate, ladders at its land faces, followers up
the planted sets, the party holds its parade. (2) **Fighting from
buildings:** ORDER_OCCUPY (lockstep input; Occupy / Leave button, key I):
foot go into a West town's house, tavern, store, warehouse, shop, church,
governor's house: two men hold the door (a two-man front: attackers at the
step are paired one to one), the next at firing places round every face
(windows; flat roofs behind the parapet; a tavern's gallery), the rest
wait inside and step up; per-man fire from the firing level (2.2 m below a
pitched roof's top, or on a flat roof), balls at them stopped 70 % (25 %
just after their own shot), men inside never hit; out by the door on a
move, withdrawal, rout or melee attack. A house beset at its door (8 enemy
men within 7 m of the step) loses 12 morale a second; men in a house do
not hold the square. AI: one musket line a side holds the building nearest
its street post; attacking foot clear a held house first (at its door),
shooters prefer men in the open. View: men drawn along the roof edge and
windows, the held building outlined in its side's colour with its door
marked, the fort's parade-capture arc. (3) **Walls 3 routing: measured, no
rule kept.** The suggested camp rule (attackers' routers stop and rally 50 m
behind their start) never triggered: the attackers' routers already rally
on the approach (5-9 rallies a battle, 0-84 men routed off); the ring and
polis results were identical with and without it (walls 3 stays 12 %:
ring 0 / 8, polis 2 / 8); they lose by attrition at the walls (490-585
killed against 210-450) and withdraw beaten. (4) **Field AI leftovers
(West rows, field maps):** a gun guard (a West army's musket lines count
toward GUARD_MIN_MELEE, pikes guard first); the musket line's reserve
(melee foot and horse do not charge a free, unshaken musket line for the
first 3 minutes of the engagement while the enemy has melee left) and a
counter-charge rule (on enemy foot or horse charging or fighting a unit of
theirs within 140 m).

Measured (before = HEAD 8ab0506, after = this; AI vs AI, both Average):

| measure | target | before | after |
|---|---|---|---|
| West equal force, west_town + west_city, 16 seeds each, walls 0 | 55 % | 66 % (21 / 32) | 47 % (15 / 32) |
| ... walls 1 (the fort) | 45 % | 41 % (13 / 32) | 59 % (19 / 32) |
| ... walls 2 (the fort and the palisade) | 35 % | 34 % (11 / 32) | 38 % (12 / 32) |
| walls 3 fair sieges, full kit, ring + polis, 8 seeds each | 25 % | 12 % | 12 % (no rule kept) |
| field AI against the scripted charger (4 seeds) | wins | lost 4 / 4 | lost 2, drew 2 (30 min), losses closer (454 / 477, 492 / 457) |
| field AI vs AI, WEST_ATT vs WEST_DEF at equal cost (4 seeds) | - | WEST_ATT 4 / 4 in 3.5-4.3 min, WEST_DEF's guns 0 shots | WEST_DEF 4 / 4 in 6.8-11 min, its guns 164 shots (guarded) |

West towns by kind (first tries, each measured on 16 seeds a wall level;
scratchpad `f2c/eq*`): all five fort guns at 380 m and all musket lines in
buildings gave walls 0 / 1 / 2 25 / 22 / 16 %; the guns cut to three, 260
m, their embrasure arc, and 70 % stops (from 80) left walls 0 at 25 %; no
buildings held gave walls 0 66 % (the HEAD figure: the buildings are what
moved it); one building a side and the attackers clearing it first gave 47
%. The fort guns killed 50-90 attackers a battle before the arc rule;
the garrison almost none (it sits out the street fight: the fort draws a
musket company out of the town, so walls 1 is now easier than walls 0).
Fort storm set piece (`west_fort_storm`, seed 53197): the attackers choose
to storm, the gate is shut at 24 s, 12 ram blows, 167 men up the ladders,
the garrison 909 shots, the guns 6.

Perf (desktop, alone, HEAD -> after): bench_4000_west 7.70 / 7.77 -> 8.83 /
8.94 ms a tick (+15 %), bench_west_town 3.26 / 3.30 -> 3.66 / 3.73 (+12 %;
profile: the battle has three times the men in contact, target searches 25k
-> 70k in its first 3,000 ticks; units 1.03 -> 1.32, soldiers 1.00 -> 1.33
ms); the West towns, first 3,000 ticks AI vs AI: village 1.65 -> 1.74, town
(fort) 1.79 -> 2.30, city (fort, palisade) 2.11 -> 2.62, inland 2.01 ->
2.03, port (fort) 2.34 -> 2.33, hill village (fort) 1.77 -> 2.11 ms.
Set-up, cold, best of 3: village 184 -> 186, town 341 -> 340, city 537 ->
500, inland 347 -> 353, port 406 -> 467, hill village 234 -> 255,
bench_west_town 344 -> 381, bench_4000_west 430 -> 486 ms.

Tests: determinism full PASS (new `--only=fort`: the fort's layout, the
storm identical on repeat and across snapshot / restore at 1,000 and 2,600,
west_city's result; `--only=occupy`: a musket company on a flat roof 5.5 m
up, its shots, the door fight, cleared, identical on repeat and across
snapshot / restore inside and at the door); one threshold moved: west_city
"at least 280 buildings" -> 260 (the fort and its esplanade take some lots;
274 now). Lockstep full PASS (new `--only=occupy`: ORDER_OCCUPY through the
lockstep, a third peer joining by snapshot while the house is held, every
frame equal). Custom battle, campaign, pack, battle screen PASS;
check_scripts clean. campaign_sim 6 x 60 unchanged: Rome cdc1d805 32b83031
23f9ed4f 3237d82d a42fc685 b6fe6c2e, West b137875c edd82dee 0393b18d 2aa8578b
deb00750 1d051164. Rome / Greek / Punic maps byte for byte as before (the 8
siege ids, the 3 city benches, battle_2000, bench_4000_hills: map hash,
cells and the state hash at tick 600 equal to HEAD's); the four flat golden
digests unchanged; no pin re-pinned. Pathing probe phase A PASS (all 16
maps, seed 7: rout jitter 0.3 %, stationary routers 0 %, stuck > 30 s 0
(longest 24 s), inside the drawn footprints 0.02 %, men in held houses left
out of it on purpose; fight jitter near obstacles 2.1 %, in town 1.9 %, as
balance T; West towns' tick means 1.66-2.64 ms); cover probe unchanged (buccaneers open
0.76, rocks 0.27, hamlet 0.00, Punic town 0.41, West town 0.78; musketeers
1.02 / 0.67 / 0.25 / 1.41 / 1.56). Screenshots in scratchpad `forts/`:
`overview_fort_town.png`, `fort_close.png`, `men_on_roof.png`,
`storm_ladders.png`, `storm_gate.png`.

Left: walls 1 is too easy (59 %, 45 wanted: the garrison takes a musket
company out of the street fight; a sally, or the garrison coming down to
the inner streets, would put it back); the field AI against the charger
draws or loses narrowly (no win yet); walls 3 at 12 % (the attrition at
the walls, not the routing); no ships for the sea guns; no sally from the
fort; men in a house do not fight room to room; timber houses do not burn
with men inside; galleries only on taverns' fronts; the West benches cost
12-15 % more.

**Forts leftovers (2026-10-16, not committed; DESIGN "Forts and fighting
from buildings", AI.md 29).** Three leftovers of the slice, measured before
(HEAD 0812fba) and after with the slice's commands and seeds (scratchpad
`fl/`). (1) **Walls 1 too easy.** Probe (`fl/w1probe.gd`): the garrison
company did nothing (0 kills in every seed probed) and in west_town bled on
the parapet: the attackers' light gun, firing at will, killed 67-68 of its
117 men from 265 m (out of their reach) while the street defenders stood in
cover. Built: **the
sally** as designed: the garrison company stands as two units (`Scenarios
.settlement`: the guard, a quarter rounded up, 10 men or more, on the land
stretch farthest from the attackers, `order` [1, i, 1] a part of the same
army entry, `CBattle.outcome_from_result` adds its fates to the company's
row); the sally company (`A_FSALLY`) stays on the parapets while the streets
hold, and when the attackers hold the plaza or its approach (a unit of 10
men within the plaza's capture box + 12 + 30 m) or half the West line units
in the streets are gone, it goes down and out by the main gate (opened for
it) in Line stance to the street post nearest the gate, holds and shoots
there; attackers bringing a ram or ladders within 60 m of the gate send it
back up (for good). The player has the same with the existing orders (two
units, the gate order). Two fort bugs found on the way and fixed (West forts
only, `fort_on`): a bastion's stair foot in a pocket the way does not reach
(the descent / ascent take the other end, `FORT_STAIR_OFF`), and the street
graph's foot-of-stair nodes with no edges (`_near_nodes` skips them in a
fort: the sally walked into the bastion's gorge and stood there). Sally
alone: walls 1 56 % (18 / 32). Then **the attackers' guns spare the fort**
when they take the town round it (`_town_gun`, ai_fort 1, as AI.md 29 always
said: the nearest town defender in reach, else they hold fire): 41 %. The
fort guns' arcs, measured as a separate step (`fl/gunprobe.gd`, 4 seeds a
town): the landward bastion toward the town covers the approach and the
streets and fires at its reload limit (4-11 shots a battle, 10-36 kills);
the other landward bastion's arc never holds the town (0 shots, 460-1860
attacker unit-seconds in its range but out of its arc), the sea gun 0; no
change (walls 1 is already under its target). (2) **Walls 3 at 12 %.**
Probe (`fl/wallprobe.gd`, 8 seeds, ring / polis walls 2 vs 3): the attrition
is not at the ladders (up in 2 of 8 battles; 94 ladder deaths in 8) but at
the gate: the batteries need 250-310 s for the walls-3 gate (175-200 s at
walls 2), the stone towers shoot the batteries, the ram (crews lost 653
against 384 at walls 2 in the ring) and the crowd before the gate, and the
attackers storm the mouth stack with 665 men against 1075 (735 against 1055
at walls 2). Levers measured (walls 3, ring + polis): battlements 25 -> 15
%: 2 / 16; walls-3 gate 75 % hp: 2 / 16, 60 %: 3 / 16; four bolt towers ->
three: 2 / 16; gate 60 % and battlements 15 %: 4 / 16; the ram waiting on the
waiting line while the batteries batter (till 50 %): walls 3 0 / 16, walls 1
+6 points and each plan's walls 1-2 moved 25-37 points (dropped); no stone towers: 4 / 16 (ram crews lost 486 /
168 against 653 / 329, the gate down ~30 s sooner); **one stone tower**
(`TOWERS_STONE` [0, 0, 0, 1], was 2): 4 / 16, built (walls-3 only: walls 0-2
and the open field cannot move; Rome walls 1-2 full kit re-run: identical).
(3) **The field AI against the charger.** The two losses: the AI's horse
rode at the charger's unguarded gun through its musket lines' fire (lancers
and pistoleers, 110-120 men, 0-44 kills), the gun killed 94-124; the AI's
musket lines ran dry and, by the 2026-10-09 rule, left the field (46-65 men
each) while the charger's empty lines stayed; the army then fell under its
withdraw threshold though it had killed as many. Built (`sim/battle_ai.gd`):
a West army's shooters out of ammunition stay on the field (behind the line,
as a player's do), and West horse do not ride at a target within a free
musket line's reach + 30 m (`_gun_covered`). Variants, 8 seeds (wins / draws
/ losses): HEAD 0 / 3 / 5; shooters stay (musket lines only) 0 / 4 / 4;
shooters stay 0 / 5 / 3; **both 2 / 5 / 1 (built)**; with also the musket
line standing when an enemy is in its reach instead of walking past a fight
to a far target 1 / 7 / 0 (three rules; that third alone 1 / 2 / 5).

| measure | target | before | after |
|---|---|---|---|
| West equal force, west_town + west_city, 16 seeds each, walls 0 | 55 % | 47 % (15 / 32) | 47 % (15 / 32) |
| ... walls 1 (the fort) | 45 % | 59 % (19 / 32) | 41 % (13 / 32: town 11, city 2) |
| ... walls 2 (the fort and the palisade) | 35 % | 38 % (12 / 32) | 41 % (13 / 32: town 5, city 8) |
| walls 3 fair sieges, full kit, ring + polis, 8 seeds each | 25 % | 12 % (ring 0, polis 2) | 25 % (ring 1, polis 3) |
| Rome walls 1 / 2 fair sieges, full kit, ring + polis, 8 seeds each | as before | 56 % / 38 % | 56 % / 38 % (identical) |
| field AI against the scripted charger, seeds 1-4 | wins or draws | lost 2, drew 2 | drew 4 (30 min; killed 620-681, lost 533-590) |
| ... seeds 5-8 | - | drew 1, lost 3 | won 2, drew 1, lost 1 |
| field AI vs AI, WEST_ATT vs WEST_DEF (4 seeds) | - | WEST_DEF 4 / 4, 6.8-11.2 min | WEST_DEF 3 / 4, WEST_ATT 1, 8.9-12.3 min |

Perf (desktop, alone, two runs, HEAD -> after): bench_4000_west 9.27 / 9.34
-> 8.94 / 8.70 ms a tick, bench_west_town 3.86 / 3.76 -> 3.70 / 3.59 (its
battle ends sooner: 5,271 -> 4,451 ticks; the garrison is one unit more).
Tests: check_scripts clean; determinism full PASS (fort, occupy included),
lockstep full PASS, custom battle, campaign, pack PASS; campaign_sim 6 x 60
unchanged (auto-resolve): Rome cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685
b6fe6c2e, West b137875c edd82dee 0393b18d 2aa8578b deb00750 1d051164. The
rules hash changes (sim and `campaign/cbattle.gd`); no state change, no
`CState.VERSION` bump.

**Distribution (D): standalone game server, itch.io, player hosting (as built 2026-10-16 / 17, not committed; DESIGN "Distribution", SERVER.md 2 / 10 / 13 / 15, `docs/PLAYING_ONLINE.md`, `server/README.md`).** The goal: the game on itch.io (web + desktop), the game server a Docker image anyone can run, a "Host a server" button in the desktop build. **Server half (D-server, 2026-10-16):** the Go server can be called from another site. `SC_ALLOWED_ORIGINS` / `-allowed-origins` (comma list, `*`, or suffix wildcards such as `https://*.itch.zone`) adds real CORS (preflight 204, echoed origin, `Vary: Origin`) for `/api/*`, `/healthz` and `/telemetry`, and lets listed origins open the WebSockets; unset is byte-for-byte the old behaviour (own origin only). No web dir (`-web ""` or missing): `/` answers a one-line text page (`SC_GAME_URL` shown), `/api/info` works. `/api/info` has `state_version` (Go constant `StateVersion` = 7, bumped with `CState.VERSION`). `server/Dockerfile` has targets `server` (API only, the public image) and `full` (default, with `build/web`); `server/deploy/selfhost/` (compose profiles `scserver` and `caddy`, Caddyfile, `.env.example`); `.github/workflows/server-image.yml` (tag `v*` + manual: multi-arch push to `ghcr.io/ggiordano32/strategic-command-server`) and `server-test.yml`; `server/README.md` for self-hosters. Test: `server/internal/server/origins_test.go`. **Client half (D-client, 2026-10-17):** the client picks its game server. `Api.pick_base_url` order: `--server=`, the address saved in `accounts.json` (`server`), the page origin on the web only when it answers `/api/info` with `server: "strategic-command"` (probed by the first `Net.check_server`), else `Api.DEFAULT_SERVER` (https://strategiccommand.ggior32.dev). `Net.server_url()`, `set_server(url)` (normalises to scheme://host[:port]; http for bare IPs / ports, https for domains; refuses an http address from an https page with "A browser can only join servers with HTTPS..."), `test_server(url)` (GET `/api/info` on any address; reports version, invite needed, and "this server is for another version of the game" when `state_version` differs from `CState.VERSION`; a server without the field is accepted). Seats are kept per server (`accounts` entries carry `server`; entries without one belong to the default server; a seat token is only ever sent to its own server). Join and device links on a non-default server carry `&server=<url>`; `?server=` / pasted links on the Join page switch the server. The "newer build on the server" banner only fires when the server is also the page origin (itch.io pages never see it). New menu page "Game server" (`game/net/server_page.gd`; home button, and a Change button beside the Server row on the Online co-op screen): address, Change (field + Paste, Test, Use this server, Use default), and on desktop "Host a server" (`game/net/host.gd`: starts the bundled `scserver` beside the executable with `-web= -allowed-origins=*`, data in `user://host/`, optional invite key, polls `/healthz`, lists LAN addresses and the public address from api.ipify.org, stops it when the game closes; a pid file stops one left by a crash). Desktop exports: presets Windows Desktop / Linux / macOS in `export_presets.cfg`, `tools/export_desktop.sh [windows linux macos]` -> `build/desktop/<platform>/` + `strategic-command-<platform>-<stamp>.zip` (scserver cross-built beside the game; inside the .app for macOS, one binary per CPU), `tools/itch_push.sh` (butler, channels web / windows / linux / mac; not run). Test: `tests/net_test.gd`; testing aid `--host-start=PORT` (starts the hosted server at launch). Verified: server `go vet` / `go test ./...` including `origins_test.go`; the web export served from a foreign origin (python on 8073) with a scratch scserver on 8074 (`-web= -allowed-origins http://127.0.0.1:8073`) passes `server/cmd/webcheck` (create, join, resolve, WebSocket, soldiers); the Linux export starts the bundled scserver from the Host page. **Client batch (2026-10-17):** (1) UPnP in Host a server: once `/healthz` answers, `Host.open_upnp()` runs Godot's `UPNP` (discover, `add_port_mapping(port, port, "Strategic Command", "TCP", 0)`, `query_external_address`) in a worker `Thread`, never on the main thread; Start does not wait for it. The panel shows "Asking your router to open the port...", "Port opened on your router (UPnP). Friends on the desktop version join with <external>:<port>." (the public address then comes from UPnP, ipify is only the fallback) or "Your router did not open the port. Forward TCP <port> to <lan ip> on your router, or use a tunnel such as Tailscale, and give friends <public>:<port>." with a Try again button (`Host.upnp_text` is the pure builder, tested in `tests/net_test.gd`). Stop and quitting delete the mapping (also in a thread). Checkbox "Open port with UPnP", on by default, kept in `settings.cfg` `[host] upnp`. `--host-start=PORT` now also waits for the UPnP attempt and prints `HOST_UPNP state=... text=...` after `HOST_RESULT`. (2) No special official server: `Api.OFFICIAL_SERVER` -> `Api.DEFAULT_SERVER` (same value), `is_official()` -> `is_default()`, UI "Use default" and "the default server"; the Game server page on desktop reads Host a server, Join a friend's server (Change / Paste / Test), The default server; seats without a server still belong to the default server. The owner's server is one self-host among many, not a public relay. (3) Test saves out of Continue: `Saves.subdir` / `Saves.dir()` (game/campaign/saves.gd); runs of `tests/*.gd` and `tools/*.gd` (`--script` path) and the aids `--details`, `--popup=`, `--host-start=`, `--scenario=`, `--campaign=`, `--story=` save to `user://campaigns/tests/`, which `Saves.list()` (top folder only) never shows; reads fall back to the top folder (so `--campaign-slot=` can open a real save, and its autosaves go to tests/ copies); format unchanged, old files left in place.

**Open (distribution D):** the GitHub workflows have never run, and the ghcr package must be made public after the first push; the itch.io origin `https://html-classic.itch.zone` (itch staff say stable) is to be confirmed on the first real upload, the sandboxed iframe may send `Origin: null` in some browsers, then `*` is the fallback; the telemetry autoload on itch posts to the page origin, fails and switches itself off; the live playtest server keeps its same-origin-only behaviour (`SC_ALLOWED_ORIGINS` unset); no code signing (SmartScreen / Gatekeeper warn; macOS: right-click > Open); no game icon on the desktop exes (default Godot icon; Windows resource editing needs rcedit); the macOS app version in the preset is static; a game killed by SIGTERM leaves its hosted server running until the next Host > Start (the pid file stops it); Windows and macOS builds are exported but not run here; `tools/itch_push.sh` not run.

**Caribbean plan agreed 2026-10-14 (DESIGN "The Caribbean pack: ships,
pirates, cover, asymmetry"):** sea battles real time with the wind;
pirates as raiders with havens; armies embark on fleets (West only). Do
not tune battle balance yet. Two tracks: **campaign** N1 fleets (ship
rows, fleet pieces on sea cells, wind-dependent reach, embark / land,
interception, sea battles auto-resolved until N3), N2 trade, blockade,
the flota and the pirate loop (havens, plunder, sacking, infamy, letters
of marque); **battle** 2a firearms (running) -> 2d landforms -> N3 real
time sea battles -> 2b cover and line of sight -> 2c forts and fighting
from buildings; faction asymmetry threads through all of them.

**N1 fleets, as built 2026-10-14 (not committed; CAMPAIGN.md "Fleets (N1,
the West pack)").** West only (Rome byte-identical: campaign_sim hashes
cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e, pack_test golden,
no new keys). Ship rows `campaign/data/west_ships.gd` (sloop, brigantine,
frigate, galleon, ship of the line, war canoe; the wind from 90, the reach
table 125 / 115 / 100 / 75 / 60 %), Shipyard chain (West: `CData.CHAINS`
gets index 7), fleets in the state on sea cells, voyages by wind, embark /
land, armies without sea lanes, interception and auto-resolved sea battles
(never pending), ship upkeep, repairs in port, scurvy at sea; fleet AI
`campaign/cai_fleet.gd`; view: ship markers bobbing on the waves, the
fleet card, voyages and reach, Shipyard in the city panel. **N1 fleets
measured** (`campaign_sim --pack=west --seeds=6 --turns=60 --twice`,
deterministic): ships launched 52-78 a seed, sea battles 14-32, armies
embarked 38-53 / landed 31-44, sea crossings 29-44 (the lanes gave 53-69),
armies sunk 0-3, voyages refused 2-43; largest faction 14-20 regions at 60;
eliminated: Brethren 5 of 6 (turns 10-49; pirates surviving on ships is
N2), Miskito 5 of 6 (20-46), Itza 1, Dutch 1; 41-68 ms a turn mean (two
runs in parallel; 38-52 alone, was 19-22). Tests: pack_test fleets block
(Rome has no fleets, the West start, no lanes, a Shipyard only in a port,
downwind 30 cells against upwind 21, embark + voyage + landing at Belize
by turn 2, a ship launched, JSON round trip, interception is a sea battle,
the same twice, a sunk transport drowns its troops), campaign_test,
online_e2e (Rome and `--pack west`), go test, check_scripts. Open: N2,
N3, fleet split, fleet steps in the replay, march-and-board in one order,
AI escorts; turn time doubled in the West.

**N2 trade, blockades, the flota and the pirate loop, as built 2026-10-14
(not committed; CAMPAIGN.md "Trade, blockades, the flota and pirates
(N2)").** West only (Rome byte-identical: campaign_sim hashes cdc1d805
32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e; `CState.VERSION` 7, every
new key optional). `campaign/csea.gd` (new): ports' sea trade and
blockades (an enemy fleet within 3 of the harbour, stronger than the
owner's side there: -75 % of the port's trade, 40 % of it to the
blockader, 80 % to pirates), prize money (25 % of a taken ship's cost,
pirates 50 %, plus treasure), the flota (every 8 turns from turn 4: 2
galleons at Veracruz for New Spain and 2 at Portobelo for Tierra Firme,
900 gold each, sail by the rules to Havana and off the north edge; taken
galleons pay the captor), pirates (the Brethren, `"pirate": 1`: land
income 75 %, upkeep 50 %, beaten ships scatter, alive while afloat;
sacking a stormed port by policy Auto / Sack / Hold: 3 turns' income + 15 %
of the owner's treasury, buildings down a level, the owner keeps it;
havens: cheaper buccaneers and cutlass men, more recruits by infamy,
repairs; infamy 0-100; letters of marque, a `marque` proposal, 12 turns of
peace and +50 % plunder from the patron's enemies, none from the Spains).
AI: fleets hunt the flota across its course, blockade rich weak ports,
pirates pick weak rich prey, shun navies, wage war on the richest nation
at sea, refuse peace (a letter buys it); nations hunt pirates by infamy and
offer letters. View: blockade ring, flota coin / course / "to Spain" arrow,
flota card, region notes (blockade, sea trade, haven, sack), Realm (plunder,
infamy, sack policy, letters, next flota), Diplomacy "Marque", chronicle
texts, map key rows. **Performance:** fleet A* with a wind-aware estimate,
bucket queue, fast fail and the route kept between turns; enemy fleets
penned in each other's zones fight at the end of the turn (most of N1's
"no way" refusals: they were real, not the node limit); one AI context
pass shared by fleet and land plans; memos in the fleet AI; ship rows read
once a pack. Fleet voyages 20.5 -> 7.8 ms a turn, a West turn 53 -> 43 ms
(3 seeds x 60, same machine, load about 9; HEAD and N2 back to back:
40-66 -> 38-49 ms a turn mean, 6 x 60). **N2 measured**
(`campaign_sim --pack=west --seeds=6 --turns=60 --twice`, deterministic):
plunder 1600-9800 a seed (the Brethren 900-7300), blockade turns 101-144,
flotas 8 sailed / 7-8 arrived (17100-25200 gold), treasure galleons taken
0-4, sacks 0-5, letters of marque 2-5, voyages refused 4-19; the Brethren
eliminated in 1 of 6 (turn 21; N1: 5 of 6), alive mostly afloat (0-1
regions, 6-19 ships, infamy 0-79); Miskito 4 of 6, Itza 2. Tests:
pack_test N2 block (Rome off; blockade cuts and pays; the flota schedule,
gathering twice the same, no orders, arrival pays; prize money for a
treasure galleon; a sack takes gold and keeps the owner; hold policy; a
pirate afloat lives, dies with its last ship; a letter round-trips JSON,
lapses and breaks), campaign_test, online_e2e (Rome, `--pack west`), go
test, check_scripts. Open: the AI sacks rarely (its pirate armies are few
and the fleets hunt first); pirates seldom hold a haven late; flota
interceptions are rare (0-4 galleons a seed); West turn still above the
pre-N1 20 ms (the land AI and the fleet plans).

**Style and flavour direction (user, 2026-10-14): "fun and the rule of
cool mixed in with reality ... slightly over-exaggerated characters of
something based in reality".** Agreed: (1) overworld structures as
pre-rendered Blender models in the **painted tabletop miniature** style
(style D: painted minis on bevelled bases on a map table; style board
running, `tools/structures/`), shown as icons zoomed out and models zoomed
in, appearing as the campaign builds them (ports, shipyards, forts);
(2) the **overworld restyled to match** (map-table / diorama terrain:
stepped relief, richer palette, perhaps parchment edges) and **exaggerated
scale** (ships and forts 20-50x real size, a galleon about a town marker);
(3) **faction exaggeration**: one signature look and one signature rule
each (Spain treasure galleons and morions, England redcoats and volleys,
France plumed buccaneers, the Brethren named captains and flags of fear,
Itza jade and feather standards, Miskito eyed war canoes); (4) **dramatic
real mechanics**: hurricanes (a seasonal storm track sinking fleets and
wrecking ports), powder-magazine explosions and fire ships in sea
battles, named treasure galleons as boss prizes, notorious pirate
captains as heroes who build fame; (5) **chunkier unit sprites** (about
1:5, bigger heads, hats and weapons) when the West units get their art.
Order: N2 (running) -> hurricanes + notorious captains + named galleons
(N2b, campaign) ; structures style D -> overworld restyle + structure
integration ; magazines / fire ships with N3 sea battles ; chunky
sprites with the West art pass.

**N2b hurricanes, notorious captains and named treasure galleons, as built
2026-10-14 (not committed; CAMPAIGN.md "Hurricanes, captains and named
galleons (N2b)").** West only (Rome byte-identical: campaign_sim hashes
cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e; `CState.VERSION` 7,
every new key optional). New `campaign/cstorm.gd` (hurricanes) and
`campaign/ccaptain.gd` (captains); named galleons, wrecks, escorts and the
flota waiting out a storm in `csea.gd`; fear, striking colours, a beaten
captain's fate, wrecks in `cfleet.gd`; storm avoidance in `cai_fleet.gd`;
numbers in `west_ships.gd` (N2b block, ship rows gain `storm`).
**Hurricanes:** the season is the summer turn; 0-2 storms form east of
the Lesser Antilles (65 % / 15 %), named for a saint ("the San Mateo
hurricane of 1653"), radius 4-6 cells, 30-42 cells a move WNW, 2-3 moves,
recurving a point clockwise at 35 % (60 % in the north), swerving out of
the forecast cone at 12 %; a move sweeps its band: ships at sea in the core
founder at their row's % (galleon 35, canoe 45, frigate 16, sloop 8) scaled
by damage, the rest lose hull and crew, all of it at 20 % in a friendly
port; ports lose a turn's sea trade and a building level at 20 %; armies
ashore lose 6 % of their men. The forecast cone (exact unless it swerves)
is drawn on the map; the AI runs out of it or rides it out in port, starts
no blockade from port while storms are about, and aims no voyage into a
cone; the flota waits at Havana while a cone threatens its course home.
**Captains:** every pirate fleet sails under a named captain (36 names:
"Calico" Jack Rackham, Jacquotte "Back from the Dead" Delahaye, "Powder"
Polly Pruett ...); fame from wins (+2), prizes (+3), treasure galleons
(+10) and sacks (+10); tiers Known 20 / Feared 45 / Legend 75: haven crews
5 % cheaper a tier, fear +5 / 10 / 20 % power in a sea battle, a Feared
captain's foes strike sooner (+10 % lost, +20 % taken), a Legend draws a
recruit more to the havens; his fleet destroyed: killed 40 %, captured 45 %
(hanged at Port Royal or the captor's capital, or ransomed on a coin toss
under fame 40 when his faction can pay), else escapes ashore to take the
next fleet; a bounty of 12 x fame (fame 25+) to the nation that kills or
hangs him; a new captain rises on a captainless fleet at 35 % a turn.
**Galleons:** each flota galleon has a name (the Atocha, Santa Margarita,
San José, the Maravillas ... and inventions like La Bruja de Plata); the
capitana carries 1800, the rest 600 (the flota's total unchanged, 3600);
taking one is a headline, a sunk one leaves a wreck on the map; the Crown
adds an escort frigate to each part at the pirates' infamy 30 and 60.
View: storm swirls with the dotted track and the orange cone ("next
turn"), wrecks, captain names under pirate fleets ("(Feared)" in red), the
captain and the named galleons with their treasure on the fleet card,
Captains / bounties / hurricane season in the Realm panel, chronicle texts,
map key rows. **Measured** (`campaign_sim --pack=west --seeds=6 --turns=60
--twice`, deterministic): hurricanes 20-31 a seed, ships sunk by storms
0-2 (the AI dodges the cones; most ships hit ride it out in port), ports
battered 27-76, men lost ashore 195-581; captains born 3-7, killed 0-2,
hanged 0-1, ransomed 0-1, drowned 0-1, max fame 10-85, bounties paid
0-648; galleons named 30-32, taken 0-6, sunk 0-3 (up to 3600 in silver
lost); flotas arrived 6-8 of 8; the Brethren eliminated in 2 of 6 (turns
30, 30; N2: 1 of 6; on seeds 2000-2011: 6 of 12, HEAD 5 of 12); the Dutch
fell in 3 of 6 of these seeds (0 of 12 on seeds 2000-2011 in both trees:
seed noise); 39.5-44.3 ms a turn mean (HEAD 38.3-50.0, load 9-12).
Tests: pack_test N2b blocks (Rome has none; storms form only before a
summer turn and the same twice; a move is deterministic, westward, in its
cone or a point out; twelve galleons at sea in the core against twelve in
Havana; Havana pays; the flota waits at Havana; an AI fleet runs out of a
cone; captains at the start, fame from a win, a destroyed captain's fate
with the bounty, a new one rises, merged fleets, fear; named galleons, one
capitana, escorts at infamy 70, the headline, a wreck; JSON round trips),
campaign_test, online_e2e (Rome, `--pack=west`), go test, check_scripts
(mine clean). Screenshots `scratchpad/n2b/shot_storm.png`,
`shot_captain.png`, `shot_captain_realm.png`, `shot_flota.png`. Open:
storms rarely sink AI ships (by design the AI dodges; a player who
ignores the cone pays); storm port damage lands mostly on Puerto Rico and
Hispaniola (where they form); salvage of wrecks; privateer captains for
the nations; captains in the AI's power estimates; fame does not fade.

**Map table and miniatures (2026-10-14, view only):** style D miniatures redone (tight bases,
52 deg camera, tall towers, chunky ships, proper lighthouse) as layers + 8-heading ships, packed
to `assets/minis/` (atlas big 2048x1024 + small 2048x256, ~20 MB video memory, small only on
Low); overworld table style (West default, Rome selectable, Rome relief pixel-identical) with
banded sea, posterised hillshade and ink contours, parchment frame and tilt-shift. Frame time
(desktop 1280x800, Port Royal, uncapped): relief 155 / 152 fps, table 145 (zoom 0.5) / 185 (zoom 2).
Open: hand-checking on the Tab S7 and phones; Rome miniatures have only the generic roman look.

**Settlements in the countryside (2026-10-14, view only):** miniatures re-rendered without bases (tools/structures/build.py), diorama finish in minis.gdshader, ground painted into the land by game/campaign/footprint.gd (clearing, fields, orchards, tracks, quay, contact shadow / AO; only around the view), ships get a shadow and wake. Checked: campaign_input_test, deploy_view_test, check_scripts, check_mine pass; full-map footprint draw 56 ms headless (culled to the view in play; redrawn only on zoom, view leaving the area or a selection); no frame-time bench run; to look at on a phone: field density, shadow strength.

**Battle-map look (user, 2026-10-14): "looks a bit like a flash game";
the user likes the tabletop diorama / miniatures direction for battles
and would accept PC-only for it.** Agreed order: (1) style test (running:
Blender battle kit + ground textures composited on battle shots, variants
grounded painterly vs tabletop diorama); (2) **Level 1, all platforms**:
Blender kit walls / towers / gates / houses / trees / rocks with baked
light and cast shadows, painterly splatted ground, a sculpted-board look
with a bevelled board edge, units re-rendered as painted minis on bases,
light depth of field (off on Low); (3) **Level 2 prototype, PC "Ultra"
view only**: a 3D battle view (heightmap terrain mesh, the kit as glTF,
real light and shadows, a tiltable / rotatable camera = the iso view),
soldiers as billboards or instanced minis; view-only, same sim, so a PC
3D player and a phone 2D player can share a co-op battle; needs a desktop
export. The game itself stays web-first (phones and tablets).
Style test done 2026-10-14 (`tools/battlekit/`, 1d878c1): the user chose
**B "tabletop diorama" as the default and A "grounded painterly" as an
option** (changed on 2026-10-14 from A default; phase 1's shader keeps
both as uniforms, B's values in its header) (a `[video] battle_look = painterly | diorama` setting: B adds
rim light, outline and saturation). Level 1 phases: 1 kit walls / towers
/ gates + their baked shadows (running), 2 houses and props on the real
streets with culture palettes, 3 trees / rocks / cliffs, 4 the full
shadow and AO layer, 5 splatted ground, 6 the look setting (diorama default, painterly option).

**Towns follow-up (2026-10-15, view only, not committed):** whole town footprint is a tap target (test `tests/town_tap_test.gd`); army banners at towns stand on land (Rome too); coast sand band bug fixed and land greener; crowded towns pushed apart and labels stacked; richer native / Maya villages (4 new kit pieces, atlas repacked). DESIGN "Follow-up". Not yet seen on the Tab S7.

**Overworld towns modelled into the landscape: step 1 built 2026-10-15 (view only, not committed).** Towns are
assembled from kit pieces on the real terrain (`town_plan.gd`, `town_layer.gd`, `town_paint.gd`; DESIGN "Overworld
towns modelled into the landscape (as built)"): pieces at 8 yaws, per-town plan from elevation / slope / coast (hill
streets along the contour, harbour only for ports on the real shoreline, Tayasal on its lake without a harbour,
Port Royal fits its spit), ground and cast shadows painted once into a texture the land shader mixes in (no patch
edges, no redraw on zoom), forest cleared, ring trees y-sorted with the pieces, Low = small atlas, fewer pieces.
Also (user additions): the landscape's trees and rocks are models in one MultiMesh (`landtrees.gd`, not Low), and
one shared "map look" (`map_look.gdshaderinc`: NW light bands, gradient-map LUT, ink, grain) for terrain, pieces,
ships and trees. Checked: check_scripts clean, deploy_view_test and windowed campaign_input_test PASS, Rome relief
untouched and Rome table style draws; gallery of all 49 towns at zoom 0.6 / 1.2 / 2.4 in the session scratchpad
`towns1/`; zoom sweep worst frame 28 ms (HEAD 54), frames over 16 ms 7 of 400 (HEAD 399), steady frame 7.8 ms High (HEAD 10.1) /
8.4 ms Low (HEAD 8.0). Open (step 2): landmarks (El Morro, Cartagena's walls, Tayasal's temple), growth polish, ships' baked
shadow (ships keep their per-frame contact shadow), a look on the Tab S7 and phones (field density, saturation,
grain), the atlas must be re-imported (`godot --headless --import`) after repacking.
**Overworld towns step 2 built 2026-10-15 (view only, not committed): landmarks and visible growth.** 25 new kit pieces (El Morro,
La Fuerza, San Felipe, San Juan's Morro, harbour fort, San Marcos, Alcazar, Ulua on its rock, Itza temple, Fort Charles, taverns,
gallows, rock fort, careened hull, baluarte, twin cathedral; Rome: Capitol, Byrsa, Cothon, Euryalus, Acropolis, Greek temple;
burnt house, camp tent / flag), placed by `town_plan.LM` / `_landmarks` (DESIGN "Step 2"); growth from the state: houses and a
second street ring by level, West walls history (harbour fort, then landward stone curtain, then bastions; Campeche bastioned
with baluartes), shipyard levels (second slipway, cranes, shed), moored ships by level / market, sack (burnt houses with
smoke, fading over 8 turns), siege (camp in the besieger's colour). Checked: check_mine clean on town_plan / town_layer,
campaign_input_test, deploy_view_test, town_tap_test PASS; galleries `towns3/` (49 West towns at zoom 1.2 / 2.4, Rome
landmark towns, growth strips level x walls, shipyard / market, sack, siege); big atlas 2048 x 1152 (16.5 MB, was 14.7),
small 2048 x 320 (about 3.9 MB, was 3.1); plans for all 49 towns at max state 417 ms once (no per-frame cost, ground repaints
only when a plan changes). `tools/check_scripts.sh` is clean again (2026-10-15). Open: a look on phones (landmark scale, tower heights), Rome's Alexandria is not a region, ships'
baked contact shadow, atlas must be re-imported after repacking.
**The city on the map is the city you fight in, phase A: the shared town plan (built 2026-10-20, not committed; the plan is not state, no
VERSION bump, no hash moves).** The overworld towns' static layout is now baked data both the overworld and (phase C) the battle map read:
`tools/town_bake.gd` (`--pack=rome|west`) calls the generator (`TownPlan.generate`, grid mode) and writes `campaign/data/town_sites_<pack>.gd`
(Rome 36 towns 138 KB, West 49 towns 187 KB, integers in centimetres in the town's local frame); `campaign/ctown.gd` (`CTown`, rules side,
integers only) gives `site(r)` (foot, shore, mouth0 / 1, high, sea_dir, streets, plaza, lots, steep, coast 48 x 48 at 25 m, in dm) and
`plan(st, r)` (kind, level, walls, harbour, shipyard, owner, scale, scaled foot, wall trace, gates, landmarks as real pieces with size,
civic piece), plus the piece size table `PD` (dm) and the landmark table `LM`, moved out of `town_plan.gd`. `TownPlan` reads the baked site
(grid mode; the legacy region-hop mode keeps the generator) and CTown's tables / facts and still does all the painting. Before / after
screenshots of 6 towns a pack at zoom 1.2 and 2.4 (default and level 2 / walls 3): visually identical, a handful of pixels differ
(sub-pixel edge shifts from the centimetre rounding, one palm at Puerto Principe walls 1+, draw-order ties). Checked: campaign_test
(new `_town_plan`: both packs), town_plan_test, check_scripts. Left for phase C: `TownPlan._build` still places landmarks by the live
coast field (CTown.plan has its own integer placement for the battle map); the generic city fort and the harbour furniture are not in
`plan` yet.
**The city on the map is the city you fight in, phase C: the battle map from the plan (built 2026-10-20, not committed; DESIGN "The town
plan (shared), phase C").** A campaign settlement battle carries `CTown.battle_plan(st, r)` (the plan turned to the battle frame, integers
only) as the city's `tp`; `sim/mapgen.gd` builds the West open town (outline, plan shore refined by the seed's waves, plan streets plus the
generated filler, plan house slots first) or the walled plan (trace from the footprint, citadel at the landmark fort) from it; landmarks
are real buildings (the town's fort with an inside on the 2c machinery: Havana's Morro, Cartagena's San Felipe, the Ulua offshore with a
causeway; other forts, civic pieces, taverns as stone bodies; Cartagena's sea wall; Rome's citadel at the Byrsa / acropolis / Euryalus);
the view draws the kit's block 2 pieces under the walls (`city_draw.gd draw_pieces`, a node of the kit). `CTown.plan` gained the generic
level 2 fort / tower / skull rock and the overworld's church rule. Scenario keys and custom battles are byte for byte as before (10 ids:
map and tick-600 state hash equal to HEAD's); no golden moved; campaign_sim unchanged (Rome cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685
b6fe6c2e, West b137875c edd82dee 0393b18d 2aa8578b deb00750 1d051164). Acceptance (`tests/town_plan_test.gd`): 1020 town / level / walls
cases, landmark sets, turn order and civic piece equal to the overworld's, 15 known (Port Royal's gallows and waterfront taverns: the
overworld's `_put` finds water there; fix in `TownPlan._build`: place landmarks at `CTown.plan`'s points). New `determinism_test
--only=town` (Havana walls 1: Morro at mouth0, the fort's inside, Fuerza at mouth1, no town wall, a shot stopped by the cathedral, the
storm identical on repeat and across snapshot / restore; Carthage's Byrsa citadel). Balance (`tests/town_balance.gd`, the same armies,
seeds and city on the generated map and on the plan; attacker wins):

| set | walls 0 | walls 1 | walls 2 | walls 3 |
|---|---|---|---|---|
| West town (Cartagena plan, lvl 1), 16 seeds, generated -> plan | 68 -> 62 % | 87 -> 37 % | 62 -> 25 % | - |
| West city (Havana plan, lvl 2), 16 seeds | 93 -> 56 % | 37 -> 31 % | 18 -> 31 % | - |
| polis (Athens plan), full kit, 8 seeds | - | 37 -> 62 % | 37 -> 25 % | 37 -> 25 % |
| castrum (Rome plan), full kit, 8 seeds | - | 62 -> 25 % | 25 -> 25 % | 0 -> 62 % |

Not within 5 points: Cartagena's San Felipe stands on the high ground in the attackers' road (walls 1-2 harder), the plan towns have
fewer street mouths (5-7 against 8-10) and 60-70 % of the buildings; the Rome rows move both ways at 8 seeds (castrum's 12-sided
trace). Pooled West walls 0 / 1 / 2: 81 / 62 / 40 % -> 59 / 34 / 28 % (targets 55 / 45 / 35); Rome walls 1 / 2 / 3: 50 / 31 / 19 % -> 44 /
25 / 44 % (25 % wanted at walls 3). Perf: bench_4000_west 8.53 -> 8.51 ms, bench_west_town 3.51 -> 3.50, bench_4000_city 4.37 -> 4.37
(identical maps); plan towns' first 3,000 ticks within 0.2 ms of the generated (oppidum 1.35 -> 1.90); set-up 230-450 ms (generated 205-
480). Left: the walls rows to retune on plan maps (a balance pass), the overworld placing landmarks at `CTown.plan`'s points, a fort trace
of the piece's own shape (done: next paragraph), the shaded kit path for block 2 pieces, Rome's street
lattice from the plan's streets, ring-plan towns.
**Fort traces from the piece (built 2026-10-20, not committed; DESIGN "Fort traces from the piece").** Owner: Havana's Morro had the 2c
square laid over its triangle. `tools/battlekit/fort_trace.py` derives each fort piece's rampart outline from the minis' geometry
(`tools/structures/spec.json`) into the piece `.json` (`trace`; `build.py` `_add_trace`) and the generated `sim/fort_traces.gd`;
`BattleKit.piece_trace(name)` for the view. Traces: Morro triangle 3 vertices / 3 salients (corner towers), Morro of San Juan 4 / 4,
Fuerza 16 / 4 flat-nosed bastions, San Felipe 3 / 3, harbour fort 4 / 4 (towers), San Marcos 24 / 4 (16 in the sim: flanks under 12 m
dropped), Ulua 16 / 4, Fort Charles 4 / 4, rock fort 4 / 4, generic fort 4 / 4 (towers). Plan towns' forts (West walls 1-2) are built on
them (`_tp_fort_tr`, `_w_fort_tr`): scaled to the 2c square's area, the piece drawn at the same scale and turn, gate edge to the plaza
(Ulua: to the causeway), seaward line on the waterline; walls, corner towers, acute tips filled, gate / sally port, cuts and stairs,
bastion terreplein at walk level (no parade pockets), ditch, barracks / magazine, guns on landward salients and the seaward edge.
Checked on 17 town / level / walls cases: no parade pockets, only the gates' stretch ends unjoined. Generated maps' forts and walled
plans unchanged (walls 3 citadels stay the six-sided ring: a triangle of the ring's reach has too little inside; left). Pathing probe
(`plan:west:havana:2:1`, phase A): PASS, stuck > 30 s 0 (longest ready 10 -> 20 s), fight jitter town 1.6 -> 2.0 %, near obstacles 0.1 ->
1.7 %, move/nearobs 1.5 -> 5.5 % (not gated), footprint 0.18 -> 0.20 % (phase B line, now just over). Balance (`tests/town_balance.gd`,
HEAD -> traces, attacker wins): West city (Havana, Morro) walls 1 31 -> 12 %, walls 2 31 -> 12 % (16 seeds); West town (Cartagena, San
Felipe) walls 1 37 -> 56 %, walls 2 25 -> 68 %; Rome polis 1/2/3 62/25/25 and castrum 25/25/62 unchanged (8 seeds). The balance pass
follows. Tests: check_scripts clean; determinism full PASS, `--only=town` (new: Morro 3 salients, gate within 45 degrees of the plaza; San Marcos 4,
no pockets; its storm identical on repeat and across snapshot / restore), `--only=fort`, `--only=occupy`; lockstep full; custom_battle,
campaign, pack, battle_screen, town_plan PASS; campaign_sim both packs unchanged. Left: walls 3 citadels on the trace (sized for an
inside), the pieces' inner keeps / lighthouses drawn over the parade (view), bastion terrepleins drawn as ground, the balance pass (done: next paragraph).
**Balance pass on plan maps (built 2026-10-20, not committed; DESIGN "Balance pass on plan maps", AI.md 29).** The walls rows retuned on
the campaign towns' plan maps. Harness: `tests/town_balance.gd` gained `--town=<pack>:<key>[:level]` (any campaign town on its own plan:
West with the region's terrain, culture and coast, the West sets' armies, the campaign start level at least 1; Rome `fair_siege` with the
region's culture plan at level 2); measured AI vs AI, equal force, 16 seeds a town and wall level (scratchpad `bp/`). **Widened before
(HEAD 106fdb3), attacker wins:**

| set | walls 0 | walls 1 | walls 2 | walls 3 |
|---|---|---|---|---|
| the brief's West set: Havana (west_city), Cartagena (west_town), Port Royal, Veracruz, Santo Domingo, Natchez, Tayasal | 47 % | 22 % | 20 % | - |
| ... by town (same order) | 56 / 62 / 12 / 81 / 12 / 100 / 6 | 12 / 56 / 18 / 31 / 12 / 0 / 25 | 12 / 68 / 0 / 31 / 31 / 0 / 0 | - |
| 16 Spanish towns (Havana, Cartagena, Port Royal, Veracruz, Santo Domingo, Campeche, Portobelo, St Augustine, Cumana, San Juan, Maracaibo, Merida, Granada, Santiago de Cuba, New Orleans, Puerto Principe) | 35 % | 32 % | 32 % | - |
| ... the same towns' generated maps (`--old`, the 5 of the brief) | 41 % | 42 % | 22 % | - |
| Rome: Athens, Carthage, Syracuse, Rome, Massalia, Arverni (oppidum) | - | 29 % | 19 % | 17 % |
| ... by town (same order) | - | 68 / 6 / 31 / 31 / 37 / 0 | 18 / 0 / 37 / 50 / 12 / 0 | 25 / 0 / 25 / 43 / 12 / 0 |
| ... their generated maps | - | 48 % | 26 % | 23 % |

**Diagnosis.** *Havana at 12 %* (probes: `bp/` `_bp_probe.gd`, `_bp_map.gd`, now in the scratchpad): at walls 1-2 the Morro's trace
(reach 100 m) and the town's landmarks stopped the generated cross streets traced from the high street (`_w_trace` found nothing free
ahead): 2 street mouths against 7 at walls 0, 108 buildings against 146, the west half of the town empty; the attackers funnelled into two
streets and withdrew at about 55 % losses (the withdrawal rule's "below 35 % of the start and weaker than the foe", the untouched fort
counted in the foe). Not the Morro's guns (11-27 kills a battle), not the sally (late or never), not the storm choice (always "take the
town round it"). *Cartagena at 56-68 %* (the west_town set, level 1): San Felipe stands on the high ground in the middle of the town's
landward band, right in the attackers' lane; the attackers bypass it, it takes houses and posts off the street fight and its garrison
sallies at 1.3-2 min (the street line thins at once); at level 2 (the `--town` harness) the same fort was the opposite outlier (0-6 %).
*Spread*: the West street fight is decided as an attrition race (the attackers withdraw near even losses), so one town's 16 seeds swing
widely (generated maps too: 6-93 % at walls 0); per-town results at 16 seeds carry about +-12 points of binomial noise. Measured
non-levers (16 towns, 8 seeds, walls 0): plaza depth `TP_WEST_DOWN` 66 -> 55 % (41 %), town area `TP_WEST_AREA` 85 -> 55 / 65 / 75 %
(44 / 51 / 44 %), filler house density -35 (42 %): within the noise of 40 %. The fort's men left out of the withdrawal's foe strength:
+2-3 points (dropped). *Natives / Maya at walls 1-2* (the oppidum machinery, `is_west` false): the plan's walled oppidum had **no gate**
(the funnel gate is the generated outline's; plan mode has none): 15-16 draws of 16; the Gallic oppidum the same (Arverni 0 / 0 / 0).
*Rome*: on the generated maps the six towns give 48 / 26 / 23 % at 16 seeds (the 56 / 38 / 25 targets came from 8 seeds of two plans);
on the plans the Punic town loses the street fight behind its gate (Carthage: gate down at 1.5 min, the attackers lose 550-670 against
270-500 and never reach the citadel; generated 25 / 12 / 6 %); the Rome withdrawal threshold (35 -> 25 % for walled plans) moved nothing
(+1-2 points: Rome sieges are lost by attrition and time, not by quitting; dropped).

**Levers built** (plan maps only; scenario keys and custom battles byte for byte as HEAD: 22 ids' map hash, terrain hash and tick-600
state hash equal):
1. *Street mouths* (`_city_west`, plan mode): a generated cross street that stops short of the landward edge is traced from the edge
   inward (reversed), so it keeps its mouth. Havana walls 1: 2 -> 6 mouths, 108 -> 120 buildings, attacker wins 12 -> 25 % (16 seeds).
2. *The approach round a fort in the road* (`W_LANE_CLEAR` 60 m): a plan's fort landward of the plaza within its reach + 60 m of the
   attackers' road moves the road (`att_x`: the deployment, the mouths' order) to its far side, clear of it. Only Cartagena's San Felipe
   (att_x 366 -> 435).
3. *The walls-2 palisade* (`_tp_palisade`, `W_PAL_GAP` 2 cells): 9 m outside the plan's whole landward side, up its flanks (a 4-connected
   line), gaps where roads cross narrowed to 4 m. Walls 2: 42 -> 33 % (the generated palisade's run broke on a round plan's flanks and left
   every road's full width open: walls 2 was no harder than walls 1).
4. *The plan oppidum's main gate* (`plan_outline`): a plan oppidum (natives, Maya, Gauls) gets its main gate facing the attackers as the
   other plans do. Natchez walls 1 0 -> 31 %, Tayasal 25 -> 68 %, Arverni 0 / 0 / 0 -> 56 / 56 / 31 %.
5. *Rule, open campaign towns* (`SiegeAI.S_BEATEN_TOWN_PCT` 25, `_army`): attackers in an open town on a plan map (no outer gates: West
   walls 0-2) withdraw below 25 % of their start strength (and weaker than the foe) instead of 35 % (Easy 20 % stays). The map levers
   could not move walls 0 (above); 16 towns walls 0 40 -> 52 %, walls 1 26 -> 41 %. Gated to plan maps so the scenario keys' rows
   (generated maps) do not move; to be unified with `AP.S_BEATEN_PCT` when those rows are re-measured.

**After** (16 seeds; Rome unchanged by levers 1-3 and 5):

| set | walls 0 | walls 1 | walls 2 | walls 3 | target |
|---|---|---|---|---|---|
| 16 Spanish towns, pooled | 55 % | 41 % | 33 % | - | 55 / 45 / 35 |
| ... by town (order above) | 50 / 50 / 75 / 93 / 12 / 62 / 93 / 43 / 43 / 87 / 68 / 12 / 37 / 50 / 87 / 12 | 31 / 25 / 37 / 37 / 12 / 31 / 56 / 75 / 81 / 25 / 43 / 56 / 43 / 6 / 43 / 50 | 25 / 0 / 18 / 18 / 68 / 0 / 43 / 56 / 75 / 31 / 18 / 43 / 6 / 50 / 31 / 50 | - | |
| the brief's West set, pooled | 60 % | 45 % | 25 % | - | |
| ... by town (Havana, Cartagena sets; Port Royal, Veracruz, Santo Domingo, Natchez, Tayasal) | 75 / 56 / 75 / 93 / 12 / 100 / 12 | 50 / 81 / 37 / 37 / 12 / 31 / 68 | 18 / 50 / 18 / 18 / 68 / 0 / 0 | - | |
| Rome, pooled | - | 38 % | 29 % | 22 % | 56 / 38 / 25 |
| ... by town (Athens, Carthage, Syracuse, Rome, Massalia, Arverni) | - | 68 / 6 / 31 / 31 / 37 / 56 | 18 / 0 / 37 / 50 / 12 / 56 | 25 / 0 / 25 / 43 / 12 / 31 | |

West pooled within 5 points of every target. Not met: single towns outside 15 points (at 16 seeds the noise alone is +-12; several
towns sit 30-40 points off in both directions, e.g. Santo Domingo 12 / 12 / 68, Veracruz 93 % at walls 0); Rome walls 1 (38 against 56)
and 2 (29 against 38), walls 3 within 3. Natives at walls 2 0 / 16 (Natchez, Tayasal: 3 draws; the walled oppidum with the West
army's three ladder sets and one ram). Tests: check_scripts clean; determinism full PASS (no golden moved, none re-pinned); lockstep full
PASS; custom_battle, campaign, pack, town_plan PASS; battle_screen PASS (then a "double free" crash at exit, the same at HEAD); pathing
probe phase A `plan:west:havana:2:1` PASS (stuck > 30 s 0, longest ready 20 s; fight jitter town 1.7 %, near obstacles 2.5 %; footprint
0.19 %); campaign_sim both packs unchanged (Rome cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e, West b137875c edd82dee 0393b18d
2aa8578b deb00750 1d051164); 22 scenario ids (skirmish, battle_2000, bench_4000_hills, test_woods, the 8 sieges, bench_4000_city, the 6
West towns, bench_west_town, bench_4000_west, west_fort_storm): map hash, terrain hash and tick-600 state hash equal to HEAD's. Left:
Rome walls 1-2 (the Punic plan's street fight behind the gate; Greek and Punic plans harder than generated at walls 1), the natives'
walls 2, per-town spread (a 32-seed look at the extreme towns before any town-specific lever), unifying `S_BEATEN_TOWN_PCT` with the
generated maps' 35 % when the scenario-key rows are re-measured.
**The pirate story campaign** (DESIGN "Story campaign: The Brethren's Due",
agreed 2026-10-14: swashbuckling with a dark edge, ~45 turns, three endings,
co-op optional; about 4 builds). **Step 1 (4808ccc): the story engine, the
Prologue and Act 1** (DESIGN "As built, step 1"). **Step 2 built 2026-10-15
(not committed): Act 2 "The Commission", Act 3 "The Free Port" and the three
endings, solo** (DESIGN "As built, step 2"): `campaign/data/story_brethren.gd`
(about 60 new events: Ashby's letter of marque, the flota at Havana and three
ways to a fleet (Lindo's brigantine, the Isla de Pinos frigate that may be
bait, King Jeremy's canoes, Hesketh's Ranger), the Armada's blockade of
Tortuga, the Treaty of Madrid at turn 22 (the letter revoked, war with
England, the gauntlet out of Port Royal, HMS Oxford's chase, Lindo's
loyalty), Le Boucher as ally (his cruelty, his betrayal) or rival; Vane's
last pages reveal the free port (walls 2 held 5 turns, a fleet at 80 % of the
Armada's power, 1500 gold in the chest), the Brethren council (speech, votes
or a sea duel with Le Boucher), the great raid on Cartagena or Portobelo (a
land battle; surprise or a bribed gate), the King's pardon, recognition, the
finale at turn 41 (the Armada attacks the fleet in Tortuga road, then lands);
the Republic, the Pardon, the Legend, each with an epilogue of seven fates);
`campaign/cstory.gd` (new conditions and effects, `bt_` flags, a raid waits for
a pending battle, actors rest after a battle, the goal's parts, endings that
release the story's fleets and leave the sandbox); `cturn.gd` (the story's
end_turn also when the game is over: the Legend), `cfleet.gd` (no launched
ship joins a story fleet); `game/campaign/story_view.gd` (Free port gauge, the
ending screen with "Continue in the sandbox", captions, raid target ring),
`campaign_screen.gd` (news before pending battles, the ending before game
over: 4 lines), `game/campaign/story_autoplay.gd` (headless player: paths
first / random / republic / pardon / legend; `--story-path=`,
`--story-show=ID|ending`). Checked: story_test PASS (step 2's effects; the
three scripted 45-turn paths reach their endings, twice the same and through
JSON each turn; 8 seeds x 45 turns of random choices each end in one of the
three), campaign_test, pack_test, campaign_sim hashes unchanged (Rome
cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685 b6fe6c2e, West b137875c edd82dee
0393b18d 2aa8578b deb00750 1d051164), online_e2e (Rome 8072, West 8073), go
test, check_scripts clean. Balance (formula) in DESIGN step 2: the finale
holds 83 % with 4 companies of ours behind walls 2, the finale Armada needs
the fleet goal or recognition, the great raid wants the bribe (Portobelo
37-74 %, Cartagena 23-60 %). Screenshots: session scratchpad `story2/`
(the treaty, the goal reveal, the goal in the log, each ending). Open: a
real-time playtest of the finale and the raid; a sloop of the story's fleets
shows the generic ship art.
**Story step 3 built 2026-10-16 (not committed): co-op crew vote, the story
online, portraits** (DESIGN "As built, step 3"). Two captains (the Brethren
and a Miskito partner, "Captain Rook"): every choice is a vote
(`CStory.answer` records each captain's vote, still pure; agree passes,
disagree: Mercy calls it by weight = 10 x fame + crew / 10 + men / 10, tie to
the lead, the loser's crew -6 %; effects go to the lead, crew / hull / fame /
infamy to both; `v` / `w` in the log). Online: server kind `"story"` (CAS, the
seat's `{f, pid, k}` stored, `story.pending` read for the "crew is voting"
notification), `OnlineCampaign.answer_story`, `verify` re-runs votes; new
campaign screen buttons (hot seat, online); story view works online (read
markers in the session, "Waiting for ..."). Portraits for the whole cast and
both captains (`game/story_portrait.gd`, `tests/portrait_gallery.gd`).
`CState.VERSION` not bumped (new keys only in co-op stories). Checked:
story_test PASS (vote cases, 45-turn co-op runs), `tests/story_online_e2e.py`
PASS (scratch server port 8074: 14 votes, one CAS conflict re-applied, split
vote settled, 23 steps re-run with no mismatch), `go test ./...`, campaign_test,
pack_test, campaign_sim hashes unchanged (West b137875c edd82dee 0393b18d
2aa8578b deb00750 1d051164, Rome cdc1d805 32b83031 23f9ed4f 3237d82d a42fc685
b6fe6c2e); `tools/check_scripts.sh` could not be judged: another agent's
`sim/battle_sim.gd` (line 2739, shadowed `n`) fails it and cascades. Screenshots
`scratchpad/story3/` (vote in progress, portraits). **Tortuga on random paths** fixed by the **haven shield** (2026-10-16,
DESIGN step 3): unprovoked nations' AI leaves a captain's haven alone
(`CStory.shielded`; Spain provoked by attention 35+, any nation by a sacked or
blockaded port for 8 turns, England by the Treaty, lifted by the Legend);
reprisal data 3 companies ignored / 2 heeded. 30 random seeds: lost by turn 20
21 -> 4, by turn 45 27 -> 9 (losses are ignored warnings, the finale, the
Treaty); story_test shield cases, campaign_test, pack_test, campaign_sim
hashes unchanged (both packs), check_scripts clean for the files touched.
**Provocation taught (2026-10-16, not committed)**: Mercy's lines (attention 20 / 35,
sack tip on a port card, first sack or blockade per nation, cooling, the Treaty),
the Grudges block in the story log and the haven card's shield line, and a
once-per-nation punitive landing (2 companies, 3-5 turns after the first sack, a turn's
warning, clear of the turn-10 reprisal). story_test (lessons, grudges, expiry,
landing, reprisal clash), campaign_test, pack_test, campaign_sim hashes unchanged.
Screenshots `scratchpad/story4/`. Open: the landing sends no ship; random bots never sack, so
the landing is measured with a forced sack (DESIGN).
Open: effects other than crew / hull / fame / infamy go to the lead only; a
split ending; the partner is the Miskito (no story faction in the pack); the
vote dialogs on a phone; the shield lets a story haven sit untouchable until provoked (a sandbox look after an ending).
**Done 2026-10-14 (00fc498): better firearm smoke** (volley smoke today is flat
puffs in game/overlay.gd: wanted thick billowing banks that roll and drift
with the wind, lit from the NW, darker cores, muzzle flash with a short
flame tongue, lingering haze over a long firefight; cheap on Low).

**PAUSE 2026-10-14 (token budget at 82 %, back in a couple of days).**
Running at the pause: N3a real-time sea battles (Opus) and battle look
Level 1 phase 1, kit walls / towers / gates (Sonnet); they finish, are
committed and exported (phase 1 landed as b9e0380). Nothing new starts until the
user is back. Next when resumed: battle look phases 2-6 with **diorama as
the default**, then ONE screenshot gallery (Caribbean town battle maps,
both looks, and sea battles; the user wants it only after all the
updates), then cover and line of
sight (2b), forts and fighting from buildings (2c, with the West walls
history), the 3D PC view prototype, N3b boarding as a deck melee,
magazines and fire ships.

**Level 1 phase 1 built 2026-10-14 (view only, not committed): walls, towers and gates from the battle kit,
look A (painterly) by the user's choice, B kept as shader uniforms for a later `battle_look` setting.**
`tools/battlekit/pack.py` + `game/battlekit.gd` / `battlekit.gdshader` / `battlekit_shadow.gd`,
`assets/battlekit/`; MultiMesh + normal-lit shader on High, pre-lit 4 px/m atlas without shader or shadows
on Low / the CPU path; baked shadow + AO layer, re-baked round a broken gate. Frame time on bench_4000_city
5.7 ms vs 6.2 ms before and a siege 3.6 vs 4.1 ms (the kit draws fewer items than the polygon strokes);
texture memory about 4.5 MB plus the shadow texture. Details: DESIGN "Battle kit walls, towers and gates".
Open: houses, trees, ground (later phases); the roofed round tower is unused; no star-fort trace exists in
the map generator, so the bastion piece is packed but not drawn; the Low path's light is baked for the unrotated
piece (rotated walls keep their baked side); shots in scratchpad/battle1.

**Battle look Level 1 phases 2-6 built 2026-10-14 (view only, not committed): diorama is the default look, painterly
the option** (`[video] battle_look`, `--battle-look=`, "Battle look" button on the settings row). Kit houses (tile
roofs by culture, huts, church / temple, stalls, well) on the sim's footprints, kit trees (palms for the West pack),
rocks and cliffs, baked shadow + AO for houses / rocks / cliffs (trees cast their own in the shader), splatted ground
tiles (grass / dry, dirt streets, plough, rock, sand; High only), a bevelled board edge on a wooden table, light depth of
field at the screen edges (High only). Details and switches (`--no-kit`, `--no-splat`, `--no-board`, `--no-dof`,
`--tropic`, `--kit-culture=N`): DESIGN "Battle look: diorama default". Streets inside the city (paving / dirt by culture) and the house fit fixed (see DESIGN). Open: the cliff pieces are straight
**Second pass 2026-10-14 (not committed; DESIGN "Battle look: relief, cliff faces, fields, Punic roofs, board")**: hill shade
rebuilt (the dark ring was the valley darkening), stepped contour bands and slope tone (diorama), cliffs as one continuous
textured face along the polyline, fields with furrows / rows / stubble along the long axis and hedge or fence edges,
flat-roof Punic houses (`house_flat_s/m`), a better board edge and table; bench_4000_city 4.76 -> 4.8 ms. A real West-pack
battle (Portobelo) checked: palms and colonial houses show. Left: Caribbean adobe flat roofs (only Punic uses them),
hedges / fences are drawn not kit pieces, the cliff texture shows the rock tile's crack grid; not yet seen on the Tab S7.

**N3a real-time sea battles, as built 2026-10-14 (not committed; DESIGN "Sea
battles (as built, N3a)", CAMPAIGN.md "Sea battles fought (N3a)").** A sea
battle with a player's fleet in it is now a pending battle: Fight it in real
time or Auto-resolve it (the N1 formula); AI-only ones resolve at once as
before. **Sim:** `sim/sea_sim.gd` + `sim/sea_types.gd`, a sibling of
BattleSim (no soldiers to share; every land battle byte-identical) with the
same discipline and the lockstep interface (`sim/lockstep.gd` runs it for a
scenario with `"sea"`): ships with fixed-point position, heading, speed,
sails (stop / battle / full), hull, rig, crew, troops; the campaign's wind
(east) shifted by a seed, shifting every 30 s; points of sail with a no-go
zone per rig (sloop 42 deg ... galleon 70), tacking with way / wearing
without, caught in irons; a navigator beating in two tacks and avoiding
land, shoals (deep ships ground) and the edge; port / starboard broadsides
(42 deg arcs, reload 10-17 s slowed by thin gun crews) with round (hull),
chain (rig) and grape (crew), raking 1.5-2 x, fires and magazine blasts,
sinking; grappling and boarding resolved by crew x quality + troops over a
few seconds (N3b hook: scenario `deck`, `deck_request()`, order `O_DECK`);
morale and striking colours, struck ships taken by the winner, fleeing off
the edge; battle AI (weather gauge, broadside on, presents the loaded side,
boards from astern when much stronger with friends, grape close, chain to
cripple, flees when beaten or hopelessly outgunned). **Campaign:** pending
sea battle records (`sea`, `af` / `df`, `sf`, x / y, the nearest region),
busy fleets, `CSeaBattle.build` (crews by faction: England 115 gunnery,
the Brethren 130 boarding ...; troops aboard; a captain's fear in morale;
the water from the battle cell: coast sides / island / open sea), outcome
per ship (afloat / sunk / taken / escaped, hull, crew) written back by
`CFleet.apply_sea` (prizes and prize money, treasure, wrecks, troops lost
and drowned, fall back, captains' fame and fate); server `statemeta.go`
reads `sf` for the humans of a sea battle. **View:** `game/sea_battle.gd`
(touch first: tap / double-tap / box select, tap the sea to sail with the
tacking course drawn, tap an enemy to engage, Board, the orders bar, ship
cards, wind rose, speeds, Leave; hulls with braced sails, flags, wakes,
broadside smoke drifting with the wind, splashes, fires, blasts, sinking,
grapples), `game/campaign/sea_screen.gd` (the pending card with the water
preview and both fleets, the result card), custom battle "Sea battle" (West
setting, solo: ships per side, wind, water, start). **Measured**
(`determinism_test --only=sea`, seed 4242, AI both sides): frigate duel
decided 3:01 (side 0, the enemy taken); 3 sloops against a galleon 3:43 (the
galleon: one sloop boarded, all three taken); 2 pirate brigantines against
a weak frigate 4:16 (boarded from astern and taken); frigate duels starting
upwind 6:42 / downwind 5:19; a coast with an island 5:48 (two ships escape
off the edge); coverage over the six: 137 broadsides, 23 rakes, 5 chain and
2 grape broadsides, 2 boardings and captures, 6 struck, 7-9 tacks and wears,
2 escaped. Identical on repeat and across snapshots (400 / 1200 / 2500),
different seeds diverge. **Tests:** determinism_test `--only=sea` (and in
the full run), lockstep_test `--only=sea` (two peers + an observer from a
snapshot, foreign orders refused, solo through Lockstep = plain sim),
pack_test (a player's voyage -> pending -> fought in the sea sim -> applied,
the same twice, JSON, the formula, AI-only still at once), new
`tests/sea_screen_test.gd` (the card, Fight -> the sea screen -> a tap sails
-> Continue applies -> the result card; Auto-resolve), custom_battle_test
(the sea setup), go test (`TestParseStateSeaBattle`), online_e2e Rome and
`--pack=west` (5 sea battles fought by the clients and verified by the
other). Rome byte-identical (goldens, campaign_sim cdc1d805 32b83031 23f9ed4f
3237d82d a42fc685 b6fe6c2e); West AI-only campaign_sim unchanged (b137875c
edd82dee 0393b18d 2aa8578b deb00750 1d051164). Screenshots in the session
scratchpad `sea/`. **Open:** live co-op at sea (sim and lockstep ready; the
room, HUD co-op parts and ship gifts are not; "Fight together" is hidden for
sea battles), N3b deck melees, fleets joining a pending battle, smoke that
blocks aim, shore batteries, fire ships, fitting the auto-resolve formula to
these results, real ship art (the miniatures), balance (the AI often wins by
striking colours and flight rather than sinking; the galleon is hard for
small ships to take), playtesting on phones.

**Raids on a player's city (2026-10-16, owner's report, West as New Spain:
"buccaneers raided my city, my 7-stack next to it did not help").**
Diagnosed in the harness: it was the raiding stance, not an assault. A
Brethren army marches onto the camp cell of a city whose army stands
inside the walls (the AI's `_raid6` only avoids regions with an enemy
field army, `foe`, and a larger threat) and takes 50 % of the income with
no battle; nothing told the player (no event, no warning). Assault path
checked and sound: `_support6` brings the player's army in from 2-4 cells
(also after it marched that turn; ring armies defend; forced march and
inside other walls are the documented exclusions), the owner is always a
battle human (garrison-only defences are offered). Fix, view only (no
rules or hash change): summary line + toast "Raiders beside <city>: tap
them to attack", End turn warning, **Attack** on an enemy army's command
bar (`campaign_panels.raids_on / attacker_for / attack_with`). Test:
`campaign_test` `_west_raid_defence`. Open: the AI raiding beside a
garrisoned stack is legal but maybe too bold (an AI odds question); a
forced-march army does not support (by design, worth a hint).

**Sea follow-ons built 2026-10-16 (Opus, not committed; DESIGN "Sea
battles: live co-op, deck melee, fire ships (as built, N3b / N3c)",
CAMPAIGN.md "Sea battles fought").** (1) **Live co-op at sea**:
`CSeaBattle.build` gives `controller` / `battle` / `sim_side` like
`CBattle.build`; `CoopSession` takes a sea battle (sea AI flags in
`live_ai_sides`, no soldier count read from a SeaSim);
`CampaignScreen.fight_live` -> `_fight_sea_live` (room, guests, the host's
single upload, the last player's forfeit of their own side);
`game/sea_battle.gd` co-op mode (follows the lockstep's sim and rebinds on a
snapshot, orders through `coop.issue()` for own ships only, whose-ship hints,
II / speeds as votes, Gift in the bar with the picker, commander bands on the
cards, the co-op HUD through a shim, Leave / Continue as on land, test aids).
**Still hidden**: `game/campaign/online_ui.gd` gates "Fight together" off for
sea battles (`and not b.has("sea")` in `live_ok` and `with_ally`); another
agent was editing that file, so the two conditions are left to drop. (2)
**N3b deck melee**, an integer crew-against-crew melee inside the sea sim (2
m deck grid, up to 24 figures a side, crew kits by faction, troops by their
unit rows, captains, volleys, morale, strike / thrown back / both spent into
the existing capture rules; the `deck` hook kept for an outside melee),
with the deck inset view and clash / volley sounds. (3) **N3c fire**: fire
intensity fought by the crew, magazines only past `MAG_LV`; **fire ships**
(sea row and campaign row `fire_ship`: lit, abandoned, grapple and burn what
they touch; battle AI sends them at the biggest enemy when the wind serves;
the campaign AI does not build them; formula worth `power` 120; custom
battle ship list). **Tests**: determinism `--only=sea` (new set pieces
`melee`, `fireship`; coverage adds deck fights / taken / volleys / fire
ships; fire ships over 8 seeds: lit 8, reached 6, magazines 5), lockstep
`--only=sea` (+ `SeaChecks.lockstep_coop`: two players and a joiner, deck
melee, fire ship, a ship gift, pause / speed votes, drop and re-admission,
every frame equal), `tests/live_e2e.py --only-sea` (new
`tests/live_sea_client.gd`: two real clients over the Go server, a battle
joined in the lobby with gifts both ways and both votes, one joined
mid-battle by snapshot, hashes equal on every frame, one upload, both end
on the server's state; `--bin` / `--no-sea` added, `online_e2e.py --bin`),
pack_test, sea_screen_test, custom_battle_test, campaign_test, go test.
Rome byte-identical (campaign_sim cdc1d805 32b83031 23f9ed4f 3237d82d
a42fc685 b6fe6c2e) and West AI-only unchanged (b137875c edd82dee 0393b18d
2aa8578b deb00750 1d051164): sea battles with no human resolve by the
formula and the AI builds no fire ships. `CState.VERSION` stays 7. Sea sim
cost (desktop): 60-70 us a tick, 160 us in a deck melee (worst 300 us),
state_hash 26-30 us, snapshot 1.6-1.9 KB. Screenshots in the session
scratchpad `sea3/` (deck melee, fire ships into a line, a magazine, a
two-peer room). **Open**: drop the two `online_ui.gd` gates; head-to-head
humans at sea (lockstep ready, untested), smoke blocking aim, shore
batteries, the formula fitted to fought results (deck melees and fire ships
included), balance of the melee (fights run 2-30 s; the AI boards only
when 1.6 x stronger, so most end in a few seconds), phones. Known, not from
this work: `tests/sea_screen_test.gd` passes but Godot aborts at exit
("double free or corruption"), also with every file of this work reverted.

**Sea screen help (2026-10-16, view only, no rules or hashes touched).** The
owner's tablet report: the sail names and the shot kinds did not say what
they do. Every order button now has a tooltip (`SeaBook.order_help` in
`game/sea_book.gd`, one line, the numbers from the sim's constants and the
selected ship's row: `SAIL_PCT` 0 / 75 / 100, `RANGE_PREF` 165 / 140 / 70,
chain 80 % and grape 40 % of the round range); a long press (0.5 s) on a
button opens a help card with the same line plus one more (a tap anywhere
closes it; the release does not give the order); changing a sail or shot
setting shows a 3 s hint line under the row; the status line says "battle
sail (75 %)" the first 6 s a setting shows. New "Ships" button (the land
book's icon, top bar) opens the Ship book: points of sail (a polar diagram
drawn from `drive()` for the selected ship, no-go wedge, drive % by
heading), sails (speed only: aim and reload do not change), shot kinds with
ranges, hit and raking numbers, fire at will, engaging, boarding (reach,
75 % of the crew, strike thresholds), striking, ending, fire and fire
ships, and every ship row; it pauses a solo battle and does not in co-op.
Tests: `tests/sea_help_test.gd` (tooltips, card, hint, status %, book pages,
pause / resume; `-- --out=DIR` saves screenshots), tooltip and book checks
in `sea_screen_test`. The bar rebuild now removes the old buttons first so
the new ones keep their names.

**Sea pass 4: the leeward fleet (2026-10-17, Opus, built, not committed;
DESIGN "Sea battles: the leeward fleet (sea pass 4)", AI.md 30).** Owner:
"tacking is fun but a bit too extreme; the downwind ships keep running
aground and never really engage". **Probe** (new `tests/sea_probe.gd`:
mirrored fleets by seed, open / island / coast water, wind 60-120 deg as
the campaign rolls it; layouts ns, we, gauge0, gauge1 and `camp` (the
campaign's coasts and its we / ns rule); modes `ai` (AI both sides),
`hold` (side 0 hove to, the AI must come) and `order` (side 0 sends each
ship at the nearest enemy every 10 s); 24 seeds; `--rows` points of sail
by row, `--seeds=96`, `--swap` side order). Found: (1) every frigate /
galleon tack failed: head to wind the speed decayed in about a second
while the turn through the no-go zone takes 20-40 s, so each tack ended in
irons and a wear (a frigate made ~350 m to windward in 7 min); (2) the
groundings were ships driven onto shoals to leeward (an island's lee
shoal, a lee coast): the probes looked down a single line, ships swung
either side of an island, and a ship aground amidships never got off
(two frigate duels with no shot in 15 min); (3) the gauge rule sent the
AI's leeward fleet beating 500-800 m past fighting range (against a
hove-to enemy: first broadside 6:00, 6 of 24 never); (4) in `we` and on
campaign coasts the leeward fleet started against a lee shore. AI vs AI
the leeward fleet's first broadside was already about the windward's
(both fire when they meet); side 1 won 56 of 96 across the wind (the N3
15/24). **Changes** (`sim/sea_sim.gd`, no new state): (A) a ship turning
through the wind carries her way (`TACK_WAY` 300 ticks; 12 head to wind
and not turning): a frigate tacks in ~29 s, out at ~30 % speed; (B) the
engagement rule `_closing`: the weather gauge only for a ship that has it
(she bears down to her range on the target's windward side) or can fetch
the gauge point on one board; a leeward ship makes for the target's lee
bow, on a reach when she can, never beating past it; the AI's leeward
ship whose target lies beyond its fleet's two boards to windward
(`BOARD_M` 400 x 2 close-hauled, worst sailer) heaves to in line,
close-hauled toward the enemy, for at most `HOLD_TICKS` 3 min (then beats
up, so a player keeping the gauge cannot win on the clock); (C) sea room:
probes down a lane her beam + 12 m either side, a new board with
`SEA_ROOM_M` 400 m clear, tack `LAYLINE_M` 200 m short of land or the
edge, within `LEE_SHORE_M` 250 m of a lee shore sail along it (never in
toward it), `_avoid` tries the side she is turning to first, a ship
aground amidships works off once her bow points at open water; (D)
deployment: each line shifted (up to 800 m in / 300 m along, smallest
first, sign by seed, fleets 600 m apart) so no shoal or land lies within
`START_CLEAR_M` 300 m and the leeward fleet has `LEE_ROOM_M` 500 m clear
to leeward and both beams; leftover shoals within 300 m cleared
(`ter_hash` covers it); (E) the AI boards at `BOARD_PCT` 130 % (was 160).
Points of sail table left alone: irons + 16 / 55 % measured no gain on the
slow beat (7:05 -> 7:13 / 7:21), nor did tacking on headers. **Measured**
(24 seeds, AI both sides, ns / we / gauge0 / gauge1 / camp, before ->
after): side 1 wins 15 / 9 / 14 / 16 / 8 -> 14 / 14 / 10 / 12 / 9 (96
seeds 56 / 43 / 48 / 49 / 34 -> 49 / 37 / 50 / 55 / 49, side order
swapped 46 / 49 / 44 / 45 / 50: noise of about +-6 on 96); groundings
43 / 32 / 60 / 37 / 66 -> 4 / 4 / 3 / 6 / 20, ships stuck (4+) 2 / 2 / 3 /
2 / 9 -> 0 / 0 / 0 / 0 / 1, battles with the leeward fleet aground 4 / 1 /
5 / 5 / 7 -> 0 / 0 / 1 / 1 / 3 (median 0 before and after); leeward vs
windward first broadside 1:06 / 1:05, 3:03 / 3:00, 2:09 / 2:11, 1:50 /
1:47, 1:59 / 1:59 -> 1:15 / 1:09, 3:42 / 3:37, 1:56 / 1:56, 2:05 / 2:04,
2:03 / 2:03 (0.99-1.08 x); the leeward fleet's ground to windward before
it fires 78-272 m -> 10-57 m; boardings 7 / 8 / 22 / 5 / 7 -> 12 / 16 /
26 / 14 / 13 (three quarters take the prize). Player hove to: the AI's
first broadside ns 2:10 -> 2:03, we 3:49 -> 3:53, AI windward 2:09 ->
2:14, camp 2:45 -> 2:28, AI leeward 5:59 (6 never) -> 7:47 (3 never: 3
min hold, then the slow beat); the AI's groundings 23 / 23 / 13 / 27 /
65 -> 3 / 3 / 4 / 6 / 6. Player engaging: groundings 36 / 21 / 43 / 56 /
64 -> 6 / 4 / 5 / 10 / 1. Cost (desktop, 12 campaign-like battles, 3000 ticks each): 74 -> 100 us a tick (the lane probes and the lee-shore scan), setup 6 -> 9 ms (the start-line search). **Ship book**: the Points of sail
page (tacks carry their way; sea room; the engagement rule replacing
"beats up to windward of the enemy first") and the Engaging paragraph.
**Tests**: determinism `--only=sea` + `SeaChecks.sea_room` (a frigate
tack without a wear; six lee-coast starts clear with the leeward fleet's
sea room, aground at most once, firing within 4 min; chain / grape
coverage also over seeds 1-4 of three set pieces); lockstep `--only=sea`
(the co-op melee's target now starts with her rigging shot through: a
sound ship turning off the wind now sails out of irons); sea_screen,
sea_help, custom_battle; full determinism and full lockstep PASS; `check_scripts` clean.
campaign_sim not run (fog-of-war work in `campaign/` by another agent;
AI-only campaign sea battles are auto-resolved, the sea sim is not in
those hashes). **Open**: a scripted player who never flees wins 15-19 of
24 against the AI in `order` mode (11-15 before; the AI's flight rule is
the suspect); the AI's beat up to a hove-to fleet stays slow (a frigate
makes ~1.5 m/s to windward); phones.

## West sprites (2026-10-15)

Sprite sets 16-26 (`tools/sprites/spec.json`, atlas `sets` order): musketeers,
w_pikemen, buccaneers, rodeleros, cutlass, lancers, pistoleers,
native_warriors, native_bowmen, w_crew (gun crews), cannon (engine set); new
poses `musket`, `pistol`, engine kind `cannon` in `build.py`; palettes
new_spain, tierra_firme, england, france, dutch, brethren, itza, miskito
(rows 9-16; the West FACTIONS rows' view-only "palette" strings now name
their own). Atlas about 910 KB (shade 612 KB + mask 301 KB, was 613 KB).
Wired (2026-10-16): the look is widened to 5-bit sets (set + 32 x palette in
the CPU-fed instance data; texture path: flags bits 12-16 set, 17-20 palette,
the engine set in its own block 8, so nothing past bit 23), and the 11 West
rows carry sprite_set 16-24 (guns 25, engine_set 26). Rome frames are
pixel-identical before / after (battle_2000 and a siege with engines, GPU and
CPU paths).

## Next session (week of 2026-10-13; paused 2026-10-10 midday)

- **Update, 2026-10-10 evening (hold here):** the user resumed; landed
  and EXPORTED as version 7 (the client migrates older online campaigns
  on load; both machines reload before an online turn): the team rules,
  heroes and agents (both halves), the finer coast and water shader, the
  deployment / battle-time dropdowns (Unlimited), kills by enemy type on
  the result screens, the campaign loading panel, two-finger tap to
  deselect, speeds 0.5 / 1 / 2 / 4x, the wall / street column fight fix.
  The N-player UI, server seats and multi-human battles are still the
  next pieces; the new-campaign screen still picks two factions (one
  team). Open from this evening: the walk exchange 1.7 : 1 vs 3.8 : 1
  open (siege pass); yardsticks 5-6 (two wall lines) never make contact;
  the enemy's hidden assassin is still drawn by soldier_layer head to
  head; no HUD keys for Sabotage / Attempt / Parley; the AI seldom
  builds Barracks 2 so its heroes are rare (these three **done
  2026-10-13**, see the "Heroes and agents fix batch" row); audio levels
  untuned.
- **Live build 20261010T105314Z (commit 4b0c40d), version 6.** Everything
  through the battlefield visual upgrade and audio is live. The Friday
  game did not happen; the online campaign on the server is still
  version 6 and playable on that build.
- **Committed, NOT exported:** the team rules (5ed4a0c, VERSION 7 with a
  6 -> 7 migration; a default-shaped state hashes as its format-6 equal
  so goldens and campaign_sim are unchanged: a deliberate trick, noted
  here in case it surprises later). The next export carries version 7:
  online campaigns of version 6 are refused by the client, so export
  only once the UI below is in and start a fresh online campaign.
- **N-player UI built 2026-10-13 (not committed; Sonnet):** the new-campaign
  screen (Human / AI toggle and team dropdown per faction, "All humans one
  team" / "Everyone on their own", any 1..8 humans, online needs 2), the
  diplomacy screen (team rows, "Join our team" with the `CAI.why` stance line
  or "they answer next turn", incoming team proposals with Accept / Refuse,
  Leave team with confirm and the "Leaving in N turns" notice), chronicle
  rows for team_notice / team_left / team_joined, the Realm / Goals / game
  over text per team. Findings: (a) the server already had it: one join code
  gives every free human seat (`seats` rows; the join screen lists the free
  seats; the code retires when the last is taken); no server change for
  seats; texts say "players" instead of "ally". (b) Hot seat already cycles
  every alive human in index order (`_next_step`), no change. (c) **Server fix:** the Go
  `StateHash` now hashes a default-shaped version 7 state as its format 6
  view like `CState.state_hash` (before, an online create of a default-teams
  state, as the old e2e makes, was refused with bad_hash). Tests:
  `python3 tests/online_e2e.py --teams` (3 humans, one code, three seats, a
  resolved turn; client `tests/online_team_client.gd`), campaign_input_test
  team steps, `go test` (TestStateHashTeams). Still open: part (3) below
  (battles with several humans), the server's per-seat Discord text still
  says "ally" in places, the share screen in main.gd says "your ally".
- **N-player, remaining parts, in order:** (1) server: N seats per
  campaign (one per human faction), invites per seat, the turn deadline
  when every human seat has submitted, notifications to all seats
  (`server/`, `game/net/`; Sonnet, Go tests + online_e2e); (2) UI: the
  new-campaign screen with Human / AI per faction, a team dropdown per
  faction, "all humans one team" / "everyone on their own" buttons; the
  diplomacy screen's "join our team" proposal with the stance, and Leave
  team with its notice; the chronicle names for team rows; the Realm /
  victory text per team (Sonnet); (3) battles with several humans: any
  human on a side joins a fought battle as a lockstep guest (the lockstep
  already has host / guests / present), units gifted across a team; a
  3-peer lockstep_test case (Opus). Then heroes and agents (item 8a).
- **Part (3) built 2026-10-13 (not committed; Opus): battles with several
  humans.** Who may join: every human with an army in the battle (either
  side) and the alive humans on the team of a side's lead faction without
  one (`CRules.battle_guests`, `battle_side_of`); the server keeps them per
  battle (`Battle.Guests` from the state's `teams`; summary `guests`),
  refuses anyone else (`not_in_battle` for the room, `ask`, `wait`,
  `command`), admits up to 8 (`room_full`) and pings exactly them. Control:
  `CBattle.controllers` gives each human faction's units to that player
  (two humans on a side each command their own), AI factions' units on a
  side with players the side's lowest player friendly to them (the sim's
  battle AI commands whole sides only: per-army AI allies not built), -1
  on a side without players; a live battle trims `ai_sides` to the sides
  without a player (`CoopSession.live_ai_sides`; solo play unchanged);
  absent players' units held by the keeper as before; each player's side
  hashed in the lockstep (`p_side`; guests' sides passed in). Votes: a
  majority of the players taking part (hashed yes / no masks; a tie or a
  lost majority clears it and keeps the state; a drop re-counts; two
  players exactly as before). Gifts: in battle to any team-mate taking
  part on the same side ("Gift to..." picker when there are several);
  on the map (unit / army / city / money) between any two human
  team-mates, refused across teams even when allied by treaty and to the
  AI (`gift_partner_check` / `exchange_check` use `same_team`; not a
  `CState.VERSION` change, the rules hash changes). UI: HUD strip with
  "(enemy)" for the other side, unit cards with a band in the
  commander's colour when a side has several players, lobby rows for every
  eligible human with "the other side", vote chips "n of m agree", the
  battle screen's "Players: ... May join without an army: ..." line, the
  view fights from the player's own side (`player_side`). Tests: lockstep_test
  (three peers: 1,200 frames equal on A / B / C and an observer restored
  from B's snapshot at frame 600, a keeper holding absent player 3's
  units, each commanding only their own, A -> B gift and A -> enemy
  refused, pause carried 2-1 and resumed; majority votes of 4 and 3) PASS;
  campaign_test `_team_battles` PASS; Go `TestRoomManyPeers` (five
  humans, three teams: humans, guests, outsiders refused, four peers' one
  stream, the cap) and `go test ./...` PASS; `python3 tests/live_team_e2e.py`
  (three headless clients, Rome + Carthage against Macedon at its capital:
  3,617 frames equal on all three, own units only, the gift, one upload)
  PASS. Open: per-army AI for AI allies on a player side; custom battles
  still two seats; the server's Discord texts still say "ally" in places.
- **From the user's next listen / look:** audio levels (`tools/make_sounds.py`
  gains, `AU_MELEE_MIN`, the 90 m volley / whoosh split), the Tab S7's
  cost of the battlefield shader and the overworld relief.
- **Tuning list (unchanged):** Skilled vs Average ~47 % (AI-competency
  pass); walls 2-3 attackers lose 300 men outside before the gate falls;
  Epirus's start (two shores, at war with Rome, idle AI armies).

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
  touch_scroll_test passes again (2026-10-10).

## Where we are headed

**The goal (agreed 2026-10-16).** The real game is the Caribbean and the
Americas. Rome was the framework for getting the control system right and
stays in as a nod to Rome 2 and familiar content to play with friends;
Creative Assembly already did Rome well, so depth goes into the Caribbean
campaign first, and Rome gets its own polish / detail pass only after the
Caribbean details are worked out. Engine fixes (pathing, jitter, city map
generation, cover) flow back to the Mediterranean campaign for free.

1. **The Caribbean pack, playable:** the 45-turn Brethren story to its
   three-way ending, co-op optional, sea battles with live co-op, forts
   with an inside. Done when the owner finishes the story once as the
   Brethren.
2. **Rome, finished, as the control check:** a full co-op campaign on
   phones to a decisive end without a bug that needs the developer; the
   device pass and the balance numbers serve this.
3. **Someone outside plays it:** a named public build, guided first turns,
   a settings pass. Done when a stranger reaches turn 10 unaided.
4. **Distribution D (built 2026-10-17):** the game on itch.io (web +
   desktop), the game server as a Docker image players can run, "Host a
   server" in the desktop build; browser players need HTTPS servers (see
   "Distribution (D)" below).

Immediate order (2026-10-17, evening; everything marked done is committed and in the evening export of 2026-10-17): shaking / stuck pass (done) -> balance pass T (done, 8ab0506) ->
forts with an inside (2c; done, 0812fba) and its leftovers (done: sally,
walls-3 one stone tower, charger rules; see the Slice 2c "Forts leftovers"
paragraph) -> distribution D (done, c81fd75 / 8c00e06 / 1a6f792: itch.io
model, standalone game server image, Host a server with UPnP; the first
itch.io upload and the first image push are the user's) -> story step 3 and
sea follow-ons (done) -> overworld tap latency (done, 185895f) -> sea help
(done, b6a5f94) -> bathymetry (done, 185895f).
-> fog of war on the overworld (done 2026-10-17: last-known state in
unseen regions, Rome 2 style sight with team union, AI all-seeing, same at
sea, VERSION 8 + migration; see the "Fog of war" rows).
-> sea pass 4, the leeward fleet (done 2026-10-17, da1bb36: tacks carry
their way, the engagement rule, sea room, clear starts, AI boards at
1.3x; see "Sea pass 4").
**Next, in order:** (1) device checks on the Tab S7 / phone of today's
work (the fog look and markers, the sea top bar at phone width, the Game
server page, `?prof-tap=3`) -> (2) Hunyuan characters (done 2026-10-20, 44821ee: captain, Mercy, Rook
meshes and textures; wiring them in is open) -> (3) sea balance
follow-ons (the AI against a player who never flees; AI boards at 1.3x
now) -> (4) auto-resolve refit to pass T's siege
outcomes. Open from the leftovers: walls 1 and 2 both at 41 % (walls 2 no
longer harder than walls 1); the charger results are 30-minute draws; two
bastion guns never bear on the town. Smaller: drag-to-exchange on the bar,
divided story ending, punitive landing ship, West villages' map coverage,
hill-city setup time, Windows / macOS builds never run, the 23 old test
saves in this machine's user folder.

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
- **Moved by balance pass T (2026-10-16, see "Balance pass T, as built" above):** the walls 1-3 rows,
  the open-field firearm AI, the street mouth and the West sieges; the
  levers archers' pull-back and escalade lanes tried (neither kept;
  see there); what is left: equal-force
  walls 3 at 12 % (target 25) and the AI follow-ups listed there.
- Walls 2-3 equal-force sieges after the 2026-10-10 siege pass: full kit
  ring / polis walls 2 20 / 10 %, walls 3 0 / 50 % (targets 35 / 25):
  the attackers lose 290-350 men outside the walls (their archers die to
  the last man in the duel with the walls; the kit's carriers under fire)
  and the walls-2 gate falls at about 200 s against 125 s at walls 1
  (the batteries' set-up and counter-battery, not the gate's hit points).
  Levers not tried: archers pulling back from a lost duel, the
  carriers' pace, more escalade lanes at once. Easy defenders weaker than
  Average only in the ring at walls 1. A fortified holder at a crossing
  does worse than an open one (stays in its camp at the mouth).
- Ammunition kinds: fear values (fire against gates: `GATE_FIRE_CHIP`
  15 / 8 / 6 per mille a second by walls since 2026-10-10, not measured on
  its own); the explosive's price (late and
  rare only by building / faction). Explosive blast (2026-10-09): 4 m
  round, damage to a third at the edge, 30 men knocked at most, thrown
  1-2 m, down 2-3 s (riders half, elephants 1 s); its load kills 58 of
  120 pikes against 8 by as many ordinary stones.
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
- Known AI gaps (not tuning): no AI recaptures enemy engines (the
  settlement AI takes up its own since 2026-10-10); the wagon AI has no dedicated guard
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
3. **Roads, rivers, hills and crossings** as grid-cell overrides (historic
   roads, rivers as barriers with fords and bridges; ford battles on the
   battle map; **hills** (user, 2026-10-09): hill cells that cost movement
   and give the battle map its ground, so holding high ground on the
   overworld is a real position). **Design (user, 2026-10-09):** a river crossing gets its **own
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
      re-run the AI tables. **Done 2026-10-10** (parts 1-3; "Siege pass
      (2026-10-10)" in "Where we are"): equal-force full kit ring / polis
      walls 1 40 / 40 %, walls 2 20 / 10 %, walls 3 0 / 50 % (targets 45 /
      35 / 25: walls 2 and ring walls 3 still low, the attackers lose the
      approach); `WALLS_PCT` walls 1 115 / 115 / 114, walls 2 162 / 162 /
      158, walls 3 262 / 178 / 158 %, `FORTIFY_DEF_PCT` 119; calibration
      78 -> 87 % favourite agreement; Skilled `SHELTER_PCT` 70.
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
   plausible mistakes. Decided 2026-10-06: AI obeys fog of war (superseded 2026-10-17: the AI sees everything; fog is the player's) if it ever
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
7. **Mid-battle reinforcements** from the map edge: **built 2026-10-13**
   (no bounce past 24 field units; reserves arrive as slots free or after
   2 minutes; see the row above and DESIGN.md "Reinforcements"). Still
   open: the ambush stance once hidden information in an async game is
   designed.
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
8a. **Heroes and agents** (**built 2026-10-10**, both halves: see the "Heroes and agents" rows; not exported until the N-player UI; asked 2026-10-09, after the N-player campaign; **campaign and UI side built 2026-10-10**, see the row;
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
8b. **Audio** (asked 2026-10-07; **built 2026-10-10**, see the "Audio" row; levels untuned).
   Audit 2026-10-13 ("no audio" report): desktop and the web export (headless Chromium, context suspended until the first click) both pass every gate and play; if it is silent on a device, suspect a stale build/web or the device volume.
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
godot --headless --script res://tests/story_test.gd         # the story campaign (-- --turns=45 --seeds=8 --quick)
# Story testing aids: -- --story=seed[:turns] (turns autoplayed) --story-path=first|random|republic|pardon|legend
#   --story-show=EVENT|ending --story-seen=N --story-choices --story-log
godot --headless --script res://tests/campaign_battles.gd   # auto-resolve timing, formula calibration
godot --script res://tests/campaign_input_test.gd           # needs a window
godot --headless --script res://tests/battle_screen_test.gd  # battle screen: pre-battle, auto / fought result, field battle
godot --headless --script res://tests/matchups.gd -- --only=tiers   # tier balance
# Campaign testing aids: -- --campaign=rome[,greeks][:seed] --sim-turns=N
#   --camp-attack=N:region --camp-siege=N:region:turns --camp-assault=region --camp-auto --camp-fight --select-army=N --select-region=key
#   --cam-zoom=Z --dialog=battles|summary|diplomacy|realm|goals --new-campaign
#   --controls --ios-tab; battle: --demo-ghost=deg
#   --popup=... (command bar popups, see the Command bar row); --host-start=PORT (desktop: start the hosted game server at launch)

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
godot --headless --script res://tests/lockstep_test.gd   # snapshots, two peers, mid-battle join (-- --quick; -- --only=three: three peers)
python3 tests/live_team_e2e.py --port 8073       # three headless clients, a campaign battle with humans on both sides (~2 min)
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
godot --headless --script res://tests/net_test.gd  # client server choice: address normalising, per-server seats, state_version check
tools/export_desktop.sh [windows linux macos]    # build/desktop/<platform>/ + zip, scserver bundled beside the game
tools/itch_push.sh                               # butler push, channels web / windows / linux / mac (not run yet)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8070)
                                                 # the web export in two headless Chromiums

# Web build and playtest server
tools/export_web.sh                              # writes build/web
python3 tools/serve_web.py 8060                  # plain HTTP, behind Caddy
python3 tools/serve_web.py 8443 --cert .certs/dev.crt --key .certs/dev.key
                                                 # self-signed, direct on the LAN
python3 tools/playtest_report.py                 # summarise playtest_logs/
```

- Playing online as a player, hosting a server and the HTTPS rule for browsers:
  `docs/PLAYING_ONLINE.md`; self-hosting the server image: `server/README.md`.
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
- **Overworld zoom / pan hitch (2026-10-16, view only, built, not committed).** `tests/zoom_sweep.gd` (windowed, vsync off, `-- --pack=west|rome --style=table|relief [--select] [--off=layer,..] [--dump=step] [--shots=dir]`) scripts wheel / pinch / pan / refocus phases and prints the worst frames with per-layer ms (`game/campaign/zprof.gd`, off unless a test sets it). Found at HEAD: the overlay redrew everything on every pan or zoom frame (army-banner spots recomputed per pixel, emblems and labels reshaped each time), 8 towns redrawn per frame resolved ~300 sprite keys each (50 ms), the map's polylines redrew in one 7 ms frame, and a selected army redrew map + overlay every frame (31 ms mean). Fixes: overlay = six child canvas items that **slide** (pan = translation, small zoom step = scale, markers a few % off for a frame) and redraw one per frame, state changes still redraw all at once; `_side_spot` cached per town per 5 % zoom band as an offset; `TextLine` cache for labels; town draw lists cached per atlas variant; `Geo.region_at` bbox pre-test; map edges / coast staged on later frames (never in an overlay redraw frame); target tints and the army halo are their own cheap nodes. Worst frame west table (1600x900, ms, HEAD -> now): wheel 70 -> 19, pinch 70 -> 19, pan 20 -> 17, a refocus jump 78 -> 30; with an army selected steady 31 -> 14 mean; Rome table wheel 46 -> 11. Screenshots at three zooms differ by under 0.05 % of pixels (sea animation, text). **Open:** with an army selected a few % of frames are still 17-20 ms (AA polylines of the map cost ~7 ms a frame to render: edges 4.6, coast 2.5; LOD-simplify or cull them next), a jump of zoom (focus a region) is one 30 ms frame, `tests/zoom_sweep.gd --off=` shows the rest; not measured on the Tab S7 or a phone. Exit of the windowed tests aborts with a double free (pre-existing, also at HEAD).
- **Overworld tap latency (2026-10-16, view only, built, not committed; owner's Tab S7 on build 20261017T020027Z: "almost any selection has a visible delay").** Measured, not guessed: `game/campaign/tap_prof.gd` (testing aid `--prof-tap[=N]`, also `?campaign=rome&prof-tap=3` in the web build's URL) drives real touch / click events through the viewport and prints per action the handler time, the wall time of the tap's frame and the worst of the 3 frames after, with `zprof.gd` layers; `tests/tap_latency.gd -- --pack=west|rome --turns=10` runs it on a desktop (AI turns first). The web build was exported to the session scratchpad, served on 8077 / 8078 and driven in Chromium (desktop GPU, 1280x800 at DPR 2 like the tablet) with the DevTools CPU throttle. The telemetry has no overworld perf event (the tablet's `perf` rows are all battle frames), and nothing on a tap posts or syncs (orders only touch `OnlineCampaign.set_plan`, a local cache write and a debounced push). **Causes, ranked (desktop West turn 10; web Rome 6x throttle in brackets):** (1) the map and overlay drawn again for every selection: `_refresh_map6` queued the whole map (territories, then the AA edges a frame later) and all six overlay parts, ~6 + 6 + 7 ms over two frames (the select frame's map/overlay layers ~25 ms); (2) the command bar's vector icons, ~50 icons recorded as AA strokes in GDScript on every rebuild, 4-6 ms (25-40 ms), and the bar built twice per tap (show_side, then _refresh_map), 2 x 2 ms; (3) the army's reach: rules `reach6` 0.5-3 ms and the outline / triangulation 1.7-5 ms (12 + 15 ms); (4) a plan edit: a full JSON save of the campaign in the tap's frame 3-6 ms (5-20 ms) and the plan previewed twice; (5) End turn's confirm: the turn resolves inside the tap's frame, 30-50 ms (1.2-1.3 s with no feedback). **Fixes (DESIGN "The command bar", "Tap latency"):** reach and selected-region outline as own map nodes, the map redrawn only when an owner changes (`map_view.refresh_state`), `overlay.redraw_parts` for a selection on the same state (settlements never), the drag preview redraws only the paths; the army's reach / zones / links in the frame after the tap's (a process-frame count, so headless runs get it too); the bar built once per frame (signature); icons from a raster atlas (`game/campaign/icon_raster.gd`, SubViewport rendered only when an icon is added, warmed with the bar's icons at open; greyed icons no longer show overlapping strokes); `save_plan` (saved 1.5 s after the last plan edit, flushed by End turn, exit, focus loss, close, hand-over) and the preview handed from `add_order` to `_replan`; the turn resolves two frames after the tap under a "Resolving the turn" dialog. **Tap frame, before -> after (ms):** desktop West t10 (1600x900, vsync off; idle frame 13.9 / 11.2): select army 42 -> 17, select city 36 -> 16, stance (an order) 59 -> 37, Details 33 -> 20, Hide panel 28 -> 16, deselect 26 -> 13, End turn 16 -> 13, End turn confirm 81 -> 15 (resolve follows); desktop Rome t10 (idle 7.8): army 28 -> 15, city 27 -> 11, stance 45 -> 34, Details 27 -> 21, Hide 20 -> 14, confirm 44 -> 15. Web Rome t0, 4x throttle (idle 25 -> 20): army 125 -> 48 (reach next frame 57), city 85 -> 40, stance 205 -> 118, Details 111 -> 72, Hide 73 -> 50, deselect 47 -> 33, confirm 836 -> 40 (then 830 behind the dialog); 6x (idle 42 -> 31): army 203 -> 67 (87), city 135 -> 65, stance 338 -> 178, Details 177 -> 108, Hide 114 -> 76, deselect 78 -> 41, End turn 55 -> 46, confirm 1299 -> 55 (1254). zoom_sweep West table with an army selected: mean 16.1 -> 13.0 ms, frames over 16 ms 358 -> 138; unselected unchanged. Tests: check_scripts clean, campaign_input_test (307 PASS, as before), touch_scroll_test, town_tap_test, battle_screen_test, campaign_test PASS; screenshots of the bar before / after match (icons the same, greyed ones without the darker stroke joints). **Open:** an order still redraws the whole overlay and recomputes the reach in the tap's frame (stance 178 ms at 6x: reach6 21 + outline 21 + bar 32 + settlements 11); the bar is rebuilt from new Controls on each selection (15-17 ms at 6x: keep its Controls and update them); the first frame an icon size is asked for still draws vectors; West's fleets redraw every 70 ms for the wave bob (2.8 ms on a desktop); the turn's resolution itself (1.2 s at 6x) is rules time; not yet felt on the Tab S7 (the throttle is an estimate: compare `?prof-tap=3` on the tablet). The 36 `_draw_edges` errors at the start of campaign_input_test are pre-existing (the edges node draws once with an empty state).
