# Strategic Command

2D co-op grand strategy game in Godot 4 (GDScript), web-first. The design and
milestones live in `docs/DESIGN.md`; read it before making changes.

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
