# Strategic Command — Design Doc (draft 1)

A 2D, sprite-based, co-op grand strategy game inspired by Rome 2: Total War,
built in Godot 4 for web and mobile. Campaign turns are played asynchronously
in short sessions; battles are real time and can be fought solo or together.

Status: draft for discussion. Items marked **OPEN** are undecided, items marked
**VERIFY** are technical assumptions to test before relying on them.

## Where things are

This file is the index. The design and the "as built" records of each pass live in `docs/design/<area>.md`, moved verbatim from the old single file (2026-10-22); every section keeps its exact title, so a reference such as `DESIGN.md "Controls additions"` is found in the table below. Inside each area file the design sections come first, then the "as built" sections in date order. `python3 tools/docs_check.py` proves nothing was lost in the split.

- `docs/design/battle_sim.md`: the battle layer: scale, per-soldier combat, performance, the AI, mechanics as built, terrain height, ammunition, beasts, firearms, cover, the general, river crossings, heroes, reinforcements, pathing flow and jitter. Sections: 4. Battle layer; Scale targets; Control in co-op; Per-soldier combat model; Performance design; Battle AI; Milestone 2: mechanics as built; Terrain height: as built; Deployment phase (as built, October 2026); Units flow into the space (as built, 2026-10-09); Ammunition kinds and fire (as built, 2026-10-09); Explosive stones: blast and knockback (as built, 2026-10-09); Resupply: foraging and the ammunition wagon (as built, 2026-10-09); Camels and elephants (as built, 2026-10-09); Missile cavalry and slingers (as built, 2026-10-09); The general (as built, 2026-10-09); War dogs (as built, 2026-10-09); River crossings (as built, 2026-10-10); Heroes and agents (as built, battle side, 2026-10-10); Reinforcements (as built, 2026-10-13); Firearms (as built, West slice 2a, 2026-10-14); Cover and line of sight (as built, West slice 2b, 2026-10-15); Fight jitter and stuck units (as built, pathing phase J, 2026-10-16).
- `docs/design/siege_and_towns.md`: settlement battles: battle maps, plans and landforms, siege equipment and wall towers, street fighting and the pathing phases in towns, forts, the shared town plan, the siege and town balance passes. Sections: Battle maps: woods and settlements (as built, October 2026); Settlement plans, sites and owners (as built, October 2026); Siege equipment and wall towers (as built, 2026-10-07); Unit blocking and street fights (as built, 2026-10-07); Field works and the fortified camp (as built, 2026-10-09); Mantlets (as built, 2026-10-09); Siege equipment usability (as built, 2026-10-10); Battle-map landforms and shaped settlements (as built, slice 2d, 2026-10-14); Routs among walls and houses (as built, pathing phase A, 2026-10-15); Clearance off the houses (as built, pathing phase B, 2026-10-15); Real cover: flat shots stop at walls (as built, pathing phase C0, 2026-10-15); Street fighting: stances, bounds, the press in a lane (as built, pathing phases C1-C7, 2026-10-15); West open towns (as built, pathing phase W, 2026-10-16); Balance pass T (as built, 2026-10-16); Forts and fighting from buildings (as built, West slice 2c, 2026-10-16); The town plan (shared), phase A, 2026-10-20; The town plan (shared), phase C: the battle map from the plan, 2026-10-20; Fort traces from the piece (as built, 2026-10-20); Balance pass on plan maps (as built, 2026-10-20).
- `docs/design/sea.md`: the Caribbean pack design and every sea battle section. Sections: The Caribbean pack: ships, pirates, cover, asymmetry (agreed 2026-10-14); Sea battles (as built, N3a, 2026-10-14); Sea battles: live co-op, deck melee, fire ships (as built, N3b / N3c, 2026-10-16); Sea battles: the leeward fleet (sea pass 4, as built 2026-10-17); Sea battles: the flight rule (sea balance, as built 2026-10-21); Sea battles: Douse (as built 2026-10-22); Sea battles: the look (as built 2026-10-22).
- `docs/design/campaign_rules.md`: section 1 goals, the campaign layer (turns, map, movement, diplomacy, fog), pending battles, the story campaign, milestones, risks and future themes. Sections: 1. Goals and non-goals; 2. Campaign layer; Turn structure; Map and economy; Diplomacy; Settlement attacks; 3. Pending battles; 9. Milestones; 10. Main risks; 11. Future themes: the American West (not started); Story campaign: "The Brethren's Due" (agreed 2026-10-14; steps 1-2 built 2026-10-15, see "as built" below); Movement (continuous overworld, as built October 2026, state format 6); Fog of war on the overworld (as built 2026-10-17, state format 8).
- `docs/design/overworld_view.md`: the overworld map view: real geography and the landscape layer, settlement markers, fleets join by tapping, view layers following the pan. Sections: Overworld: real geography and the landscape layer (as built, 2026-10-10); Fleets join by tapping (as built, 2026-10-20); Overworld settlement markers and banners at towns (2026-10-22); Overworld view layers follow the pan every frame (2026-10-22).
- `docs/design/ui.md`: touch controls, controls additions, the command bar, compact unit cards, the main menu, the UI theme. Sections: 7. Touch controls (to prototype first); Controls additions (2026-10-05, as built); Compact unit cards (as built, 2026-10-09); The command bar (overworld selection, as built 2026-10-15); Main menu (as built, 2026-10-21); UI theme (as built, 2026-10-21, pass 1: the kit and the campaign screen).
- `docs/design/art_pipeline.md`: section 8 art, the sprite pipeline, characters, the battle kit and the battle look. Sections: 8. Art; Characters (as built); Sprite pipeline (step 1a, 2026-10-13); Sprite pipeline (step 1b, 2026-10-13); Battle kit walls, towers and gates (as built, Level 1 phase 1, 2026-10-14); Battle look: diorama default, kit houses / trees / rocks, splatted ground (as built, Level 1 phases 2-6, 2026-10-14); Battle look: relief, cliff faces, fields, Punic roofs, board (as built, 2026-10-14, second pass).
- `docs/design/distribution.md`: networking (live lockstep, custom battles, the campaign server), platforms and tooling, distribution (itch.io, standalone server). Sections: 5. Networking; Live battles: deterministic lockstep; Campaign: save-store server; 6. Platforms and tooling; Live battles: as built (milestone 5, 2026-10-05); Campaign server: as built (milestone 4, 2026-10-05); Custom battles and head-to-head (as built, October 2026); Distribution (agreed and built 2026-10-17).
- `docs/design/audio.md`: sound. Sections: Audio (as built, 2026-10-10).

## Section index (title, file)

| Section | File |
|---|---|
| 1. Goals and non-goals | docs/design/campaign_rules.md |
| 2. Campaign layer | docs/design/campaign_rules.md |
| Turn structure | docs/design/campaign_rules.md |
| Map and economy | docs/design/campaign_rules.md |
| Movement (continuous overworld, as built October 2026, state format 6) | docs/design/campaign_rules.md |
| Diplomacy | docs/design/campaign_rules.md |
| Settlement attacks | docs/design/campaign_rules.md |
| Fog of war on the overworld (as built 2026-10-17, state format 8) | docs/design/campaign_rules.md |
| 3. Pending battles | docs/design/campaign_rules.md |
| 4. Battle layer | docs/design/battle_sim.md |
| Scale targets | docs/design/battle_sim.md |
| Control in co-op | docs/design/battle_sim.md |
| Per-soldier combat model | docs/design/battle_sim.md |
| Performance design | docs/design/battle_sim.md |
| Battle AI | docs/design/battle_sim.md |
| Milestone 2: mechanics as built | docs/design/battle_sim.md |
| Terrain height: as built | docs/design/battle_sim.md |
| Battle maps: woods and settlements (as built, October 2026) | docs/design/siege_and_towns.md |
| Settlement plans, sites and owners (as built, October 2026) | docs/design/siege_and_towns.md |
| Battle-map landforms and shaped settlements (as built, slice 2d, 2026-10-14) | docs/design/siege_and_towns.md |
| Battle kit walls, towers and gates (as built, Level 1 phase 1, 2026-10-14) | docs/design/art_pipeline.md |
| Battle look: diorama default, kit houses / trees / rocks, splatted ground (as built, Level 1 phases 2-6, 2026-10-14) | docs/design/art_pipeline.md |
| Battle look: relief, cliff faces, fields, Punic roofs, board (as built, 2026-10-14, second pass) | docs/design/art_pipeline.md |
| Deployment phase (as built, October 2026) | docs/design/battle_sim.md |
| Siege equipment and wall towers (as built, 2026-10-07) | docs/design/siege_and_towns.md |
| Unit blocking and street fights (as built, 2026-10-07) | docs/design/siege_and_towns.md |
| Units flow into the space (as built, 2026-10-09) | docs/design/battle_sim.md |
| Routs among walls and houses (as built, pathing phase A, 2026-10-15) | docs/design/siege_and_towns.md |
| Clearance off the houses (as built, pathing phase B, 2026-10-15) | docs/design/siege_and_towns.md |
| Real cover: flat shots stop at walls (as built, pathing phase C0, 2026-10-15) | docs/design/siege_and_towns.md |
| Street fighting: stances, bounds, the press in a lane (as built, pathing phases C1-C7, 2026-10-15) | docs/design/siege_and_towns.md |
| West open towns (as built, pathing phase W, 2026-10-16) | docs/design/siege_and_towns.md |
| Fight jitter and stuck units (as built, pathing phase J, 2026-10-16) | docs/design/battle_sim.md |
| Balance pass T (as built, 2026-10-16) | docs/design/siege_and_towns.md |
| Forts and fighting from buildings (as built, West slice 2c, 2026-10-16) | docs/design/siege_and_towns.md |
| Compact unit cards (as built, 2026-10-09) | docs/design/ui.md |
| The command bar (overworld selection, as built 2026-10-15) | docs/design/ui.md |
| Ammunition kinds and fire (as built, 2026-10-09) | docs/design/battle_sim.md |
| Explosive stones: blast and knockback (as built, 2026-10-09) | docs/design/battle_sim.md |
| Resupply: foraging and the ammunition wagon (as built, 2026-10-09) | docs/design/battle_sim.md |
| Camels and elephants (as built, 2026-10-09) | docs/design/battle_sim.md |
| Missile cavalry and slingers (as built, 2026-10-09) | docs/design/battle_sim.md |
| Firearms (as built, West slice 2a, 2026-10-14) | docs/design/battle_sim.md |
| Cover and line of sight (as built, West slice 2b, 2026-10-15) | docs/design/battle_sim.md |
| The general (as built, 2026-10-09) | docs/design/battle_sim.md |
| War dogs (as built, 2026-10-09) | docs/design/battle_sim.md |
| Field works and the fortified camp (as built, 2026-10-09) | docs/design/siege_and_towns.md |
| Mantlets (as built, 2026-10-09) | docs/design/siege_and_towns.md |
| Siege equipment usability (as built, 2026-10-10) | docs/design/siege_and_towns.md |
| River crossings (as built, 2026-10-10) | docs/design/battle_sim.md |
| Heroes and agents (as built, battle side, 2026-10-10) | docs/design/battle_sim.md |
| Reinforcements (as built, 2026-10-13) | docs/design/battle_sim.md |
| 5. Networking | docs/design/distribution.md |
| Live battles: deterministic lockstep | docs/design/distribution.md |
| Live battles: as built (milestone 5, 2026-10-05) | docs/design/distribution.md |
| Custom battles and head-to-head (as built, October 2026) | docs/design/distribution.md |
| Campaign: save-store server | docs/design/distribution.md |
| Campaign server: as built (milestone 4, 2026-10-05) | docs/design/distribution.md |
| Distribution (agreed and built 2026-10-17) | docs/design/distribution.md |
| 6. Platforms and tooling | docs/design/distribution.md |
| 7. Touch controls (to prototype first) | docs/design/ui.md |
| Controls additions (2026-10-05, as built) | docs/design/ui.md |
| 8. Art | docs/design/art_pipeline.md |
| Sprite pipeline (step 1a, 2026-10-13) | docs/design/art_pipeline.md |
| Sprite pipeline (step 1b, 2026-10-13) | docs/design/art_pipeline.md |
| Characters (as built) | docs/design/art_pipeline.md |
| Overworld settlement markers and banners at towns (2026-10-22) | docs/design/overworld_view.md |
| 9. Milestones | docs/design/campaign_rules.md |
| 10. Main risks | docs/design/campaign_rules.md |
| 11. Future themes: the American West (not started) | docs/design/campaign_rules.md |
| The Caribbean pack: ships, pirates, cover, asymmetry (agreed 2026-10-14) | docs/design/sea.md |
| Sea battles (as built, N3a, 2026-10-14) | docs/design/sea.md |
| Sea battles: live co-op, deck melee, fire ships (as built, N3b / N3c, 2026-10-16) | docs/design/sea.md |
| Sea battles: the leeward fleet (sea pass 4, as built 2026-10-17) | docs/design/sea.md |
| Sea battles: the flight rule (sea balance, as built 2026-10-21) | docs/design/sea.md |
| Sea battles: Douse (as built 2026-10-22) | docs/design/sea.md |
| Sea battles: the look (as built 2026-10-22) | docs/design/sea.md |
| Story campaign: "The Brethren's Due" (agreed 2026-10-14; steps 1-2 built 2026-10-15, see "as built" below) | docs/design/campaign_rules.md |
| Overworld: real geography and the landscape layer (as built, 2026-10-10) | docs/design/overworld_view.md |
| The town plan (shared), phase A, 2026-10-20 | docs/design/siege_and_towns.md |
| The town plan (shared), phase C: the battle map from the plan, 2026-10-20 | docs/design/siege_and_towns.md |
| Fort traces from the piece (as built, 2026-10-20) | docs/design/siege_and_towns.md |
| Fleets join by tapping (as built, 2026-10-20) | docs/design/overworld_view.md |
| Balance pass on plan maps (as built, 2026-10-20) | docs/design/siege_and_towns.md |
| Audio (as built, 2026-10-10) | docs/design/audio.md |
| Main menu (as built, 2026-10-21) | docs/design/ui.md |
| UI theme (as built, 2026-10-21, pass 1: the kit and the campaign screen) | docs/design/ui.md |
| Overworld view layers follow the pan every frame (2026-10-22) | docs/design/overworld_view.md |
