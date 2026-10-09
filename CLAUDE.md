# Strategic Command

2D co-op grand strategy game in Godot 4 (GDScript), web-first. The design and
milestones live in `docs/DESIGN.md`; current progress, open items and how to
run things are in `docs/STATUS.md`. Read both before making changes, and keep
`docs/STATUS.md` up to date when a milestone lands or the plan changes.

## Working model

- The main session is for design, architecture and review with the user.
- Delegate code generation and any other subagent or workflow work to a
  subagent, never the main session's model. Model by task (agreed
  2026-10-09, to save budget): **Sonnet** (`model: "sonnet"`, the
  subagent default in `.claude/settings.json`) for builds with a fixed
  brief: data rows, UI and icons, tests, scenario keys, campaign rules
  with a clear spec, doc merges; **Opus** (`model: "opus"`) only for
  changes inside the deterministic sim core (hashed state, snapshots,
  lockstep), AI behaviour work and diagnosis (bisects, probes); **Haiku**
  (`model: "haiku"`) for mechanical runs: harness re-runs tabulated
  before / after, the verify suite, gallery regeneration, STATUS row
  merges from a draft. Balance passes split into a measure-and-report
  task (Haiku) and a change task (Sonnet or Opus); briefs fix the design
  and the numbers so the builder decides little.

## Rules for battle simulation code

- The battle sim must stay deterministic (lockstep networking): integer or
  fixed-point maths only, the sim's own seeded RNG, fixed iteration order, no
  engine physics, no floats in sim state.
- No node per soldier; soldier state lives in packed arrays.
- Live co-op (milestone 5): everything that affects a co-op battle and must
  be equal on both peers lives in the sim or in `sim/lockstep.gd` and is in
  `state_hash()` (sim) or `Lockstep.state_hash()`; it changes only by
  lockstep inputs applied at their frame. Never let the view, the network
  layer or wall-clock time write it. New sim state must also survive
  `BattleSim.snapshot()` / `restore()` (script variables are captured
  automatically; check `tests/lockstep_test.gd` passes).

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

## Server (`server/`, milestone 4)

- One Go binary (`server/cmd/scserver`) with SQLite (`modernc.org/sqlite`,
  pure Go, no cgo): serves `build/web`, the playtest telemetry endpoint and
  the campaign API. Reference, deployment and operations: `docs/SERVER.md`.
  Go is installed at user level in `~/.local/go` (`tools/build_server.sh`
  finds it); `tools/run_server.sh [port]` runs it.
- **The server never runs game rules.** Clients resolve turns and apply
  battle results with `campaign/` and upload the new state with the version
  it was computed from (compare-and-swap). The server only reads a few
  top-level facts from the state (turn, phase, alive humans, humans in each
  pending battle) for bookkeeping, deadlines and notifications.
- Client side: `game/net/` (API client, seat tokens, one campaign's sync /
  submit / resolve / battle outbox / determinism check, autoload `Net`) and
  `game/campaign/online_ui.gd`. Changing `campaign/` or `sim/` changes the
  rules hash online clients compare; changing the state's meaning needs
  `CState.VERSION` bumped (online campaigns of another version are refused).
- Tests: `cd server && go test ./...`, `python3 tests/online_e2e.py`,
  `server/cmd/webcheck` (headless Chromium against the web export).
