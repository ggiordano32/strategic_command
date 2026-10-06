# Sprite animation pipeline (later milestone)

Status: **not started**. Written 2026-10-06 so the plan is not held in a
conversation. Last item on the roadmap in `docs/STATUS.md`; nothing in the
game depends on it. The symbolic soldiers in `game/soldiers.gdshader` stay
until the game itself is in a good state.

## The problem

Image models produce one good frame; they do not keep the same character,
proportions and lighting across the eight frames and eight facings a walk
cycle needs, and attack / block / fall cycles multiply that. Hand animation
for ~40 unit types across four cultures (plus horses, elephants, engines)
is the single biggest art cost in a game like this. We want a workflow where
motion is made once, in code, and only static parts are drawn or generated.

## Why our case is easier than most

- **Top-down at 20–40 px per man.** Faces, feet and cloth are below the
  resolution floor. A readable walk is 4–6 frames; what the eye tracks is
  the shield, the weapon arm, the helmet and the overall silhouette.
- **One renderer already.** Soldiers are one MultiMesh fed from a data
  texture (`game/soldier_layer.gd`, `game/soldiers.gdshader`), with per-man
  position, facing, state and unit type. A per-man *part set* and *phase*
  fit the same channel layout; no node per soldier, no sprite sheet per
  unit type.
- **The sim already emits the states** an animation needs: idle, walking,
  running / charging, in melee (swing, thrust), blocking, hit, knocked
  down, routing, dead, plus missile release and reload for shooters and
  engine crews (`sim/battle_sim.gd` state and event arrays used by the
  view). No sim change is required; the view only reads.

## The approach: parts + procedural motion

Split the work so that **consistency problems live where code is good and
style problems live where image tools are good**.

1. **Style sheet first.** One reference sheet per culture (Roman, Greek,
   Punic, Celtic) at the final pixel scale, top-down lighting fixed (light
   from the top-left as in the current shaders), palette constrained. Made
   by hand or generated, then cleaned; this is the one place taste is spent.
2. **Parts, not poses.** Each soldier is a small cutout rig: torso/cloak,
   head/helmet, shield arm (+ shield), weapon arm (+ weapon), two leg
   blobs; horses add body, head, four leg blobs; elephants and engines have
   their own small rigs. Each *part* is a static sprite with a pivot. A
   unit type is a list of part choices and tints, so Roman vs Gallic
   swordsmen differ in parts, not in animation work.
3. **Cycles in code.** Walk, run, charge, swing, thrust, block, hit, fall,
   rout and idle breathing are parametric curves on the rig's pivots
   (angle/offset per part vs phase 0..1), tuned once and shared by every
   type that uses the rig. Weapon length and shield size are parameters, so
   pikes and spears reuse the sword swing with a thrust variant.
4. **Bake.** A tool renders each (rig, part set, cycle, frame, facing) to an
   atlas, so the runtime stays a single textured MultiMesh draw with a
   frame index per man (cheap on phones, where skeletal 2D for 4,000 men
   would not be). Eight facings × ~6 frames × ~10 cycles per part set is
   large but mostly shared; bake per *rig* with part swaps done in the
   shader (part atlas + rig frame) if atlas size becomes a problem.
5. **Hook up.** Map sim state + event timing to cycle + phase in the view;
   melee blows, blocks and hits already have ticks the view can key on.
   Keep the data-texture channels the same so the deterministic sim and the
   lockstep layer are untouched.

## Tooling to build (its own project, not inside the game)

- **Part editor / importer:** load a style sheet, cut parts, set pivots,
  assign to a rig slot, preview on the rig.
- **Cycle preview:** play every cycle on any part set at game scale, eight
  facings side by side, on the real ground palettes; adjust curve
  parameters live.
- **Generation helpers (optional):** prompts and masks that ask an image
  model for *one part* at a time (a shield face, a helmet from above, a
  cloak) against a fixed template and lighting, so the model is never
  asked for consistency across frames. Accept/reject per part.
- **Bake and export:** atlas + JSON (part sets per unit type, frame table)
  consumed by `game/soldier_layer.gd`.
- **Phone check:** a benchmark scene (reuse `tests/benchmark.gd` scenario
  sizes) measuring frame time with the textured atlas at 4,000 men on the
  Android and iPhone test devices before committing to the look.

## Acceptance

- Every unit type in `sim/unit_types.gd` has a part set; horses, elephants
  (when they exist), bolt and stone throwers and crews covered.
- Walk/run/charge/melee/block/hit/fall/rout read at phone zoom levels and
  at the desktop's closest zoom without a visible "swim" between frames.
- Frame cost at 4,000 men within the current budgets on the test phones.
- Determinism and lockstep tests unchanged (the view-only rule holds).

## Risks and fallbacks

- Atlas size on WebGL2 / iOS: fall back to baking per rig with shader part
  swaps, or fewer facings (four plus mirroring) at phone scale.
- Generated parts not matching across a culture: the style sheet and the
  one-part-at-a-time masks are the mitigation; hand-drawn parts are the
  fallback and remain small in number because motion is shared.
- If the game ever moves to a 3D client, the same split applies (static
  meshes + procedural or shared animation), and the sim/campaign layers are
  unaffected; see the note in `docs/DESIGN.md`.
