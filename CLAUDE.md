# Strategic Command

2D co-op grand strategy game in Godot 4 (GDScript), web-first. The design and
milestones live in `docs/DESIGN.md`; current progress, open items and how to
run things are in `docs/STATUS.md`. Read both before making changes, and keep
`docs/STATUS.md` up to date when a milestone lands or the plan changes.

## Working model

- The main session is for design, architecture and review with the user.
- Delegate code generation and any other subagent or workflow work to the
  latest Opus model (`model: "opus"`), not the main session's model, to save
  tokens. `.claude/settings.json` sets this as the subagent default.

## Rules for battle simulation code

- The battle sim must stay deterministic (lockstep networking): integer or
  fixed-point maths only, the sim's own seeded RNG, fixed iteration order, no
  engine physics, no floats in sim state.
- No node per soldier; soldier state lives in packed arrays.

## Rules for campaign code (`campaign/`)

- Same discipline as the battle sim: the turn resolution
  (`cturn.resolve_turn`) and battle application (`cturn.apply_battle`) are
  pure functions of (state, submissions / outcome); two clients with the same
  inputs must produce the same `CState.state_hash`.
- Integers only, the state's own RNG (`CState.rand`), arrays in index order;
  never iterate a Dictionary in rules code (JSON load does not keep key
  order). The whole state is one JSON-serialisable Dictionary (no floats, no
  bools, string keys); bump `CState.VERSION` when its meaning changes.
- No Nodes or engine time in `campaign/`; the view (`game/campaign/`) only
  reads the state and emits orders.
