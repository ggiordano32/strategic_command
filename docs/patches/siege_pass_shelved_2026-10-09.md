# SHELVED.patch (siege pass, paused 2026-10-09)

Apply on top of the kept tree (harness only: full-kit fair-sieges row,
fort variants, flank yardsticks) with `git apply SHELVED.patch`.
Measured tables: docs/STATUS.md row "Siege pass, paused (2026-10-09)";
raw: fair_base/ (HEAD), fair_fin/ (this patch), calib_base.txt / calib_after.txt,
csim_base.txt, ../../sg_sim.txt (campaign_sim of this patch), bis/ (bisect).

Hunks:
- sim/battle_sim.gd
  - TOWN_PLACE_LEAD 10 m (static var), `lead` argument of _cap_lead: on
    settlement maps a fighting man may get 10 m ahead of his place
    (field PLACE_LEAD 1.5 m). Cause found by bisect: melee commit 15ef028
    took walls-1 fair sieges from 40/50 % to 0/30 % (ring/polis).
    3 m: 0-30 %, 10 m: 40-60 %, no cap: 70-100 % at walls 1.
  - WALL_COVER 25/45/70 -> 25/25/40; TOWERS_MAX 6/8 -> 3/4;
    GATE_HP_PCT walls 2/3 130/130 -> 100/115 (walls 2-3 attrition; with
    these ring w2 full kit 0 -> 30 %, w3 0 -> 10 %).
  - GATE_FIRE_CHIP [6,15,8,6] per mille/s by walls (a burning walls-1
    gate in ~70 s; backlog: 780 fire arrows took it only 57 %). Not
    measured on its own.
- sim/ai_profile.gd: Skilled SK_STORM_STAGGER 1 -> 0 (ablation: Skilled
  attacker ring/polis walls 1 0/20 -> 70/40 %; others no effect).
- sim/siege_ai.gd: missile units out of ammunition take up their side's
  crewless engines (BattleAI._take_engines) on settlement maps. Not
  measured on its own.
- campaign/cbattle.gd: WALLS_PCT walls x kit (arrival / ladders+ram /
  full kit) on the whole defending side, kit_of(), walls_pct(),
  garrison_strength on the full-kit column, test switch old_walls.
  Fitted to fair_fin as (lost/won)^(1/3), smoothed. Calib n=60:
  favourite agreement 82 -> 90 %, formula att 34 -> 29 % (sim 30).
- campaign/cdata.gd: FORTIFY_DEF_PCT 125 -> 123 (camp won 13/20).
- campaign/cai_profile.gd: Skilled SHELTER_PCT 0 -> 70.
  campaign_sim 6x60 hashes -> 704eeec1 96b2efba 3fa67102 3e463360 4263d23c e202ac8c.
- tests/campaign_test.gd: odds loop to 50; CBattle.old_walls for the
  pre-step-4 golden campaigns.
- tests/determinism_test.gd: layout case on ladders + ram (artillery only
  no longer reaches the plaza); castrum coverage without gate_broken.
  Full determinism PASS with the patch (before the ladder work).
- tests/matchups.gd: --tune TOWN_PLACE_LEAD (dm) and GATE_FIRE_CHIP.
- docs DESIGN / AI / CAMPAIGN: the numbers above, AI.md section 25.

Not in the patch: a ladder rewrite (all ladders at once, stall end, move
cancels the climb) begun and dropped when the ladder work moved to the
movement build; it is in full_worktree_with_ladder.diff for reference,
untested. Probe: ladder.gd (walls, defenders 0/1).
