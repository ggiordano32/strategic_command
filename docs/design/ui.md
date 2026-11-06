# UI (touch controls, command bar, menus, theme)

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

## 7. Touch controls (to prototype first)

- Tap a unit or its banner card to select; unit cards along the bottom edge.
- Drag from a selected unit to draw the destination line: length sets width,
  direction sets facing.
- Tap an enemy to attack; double tap to run/charge.
- Two-finger pan and pinch zoom.
- Pause and speed controls. Solo: immediate. Co-op: by vote, as in Rome 2. A
  requested pause or speed change shows the requester's icon under that
  control and takes effect only when the other player agrees. Requests and
  agreements are lockstep orders, so the change lands on the same tick for both.
- Group buttons for "select all infantry / cavalry / missiles".

HUD as built (October 2026, after "the buttons are too large ... double
stack the cards"): the UI is laid out in logical pixels and
`game/ui_scale.gd` sets the window's logical size from the device: one
logical pixel is 0.88 CSS px on a touch screen (a 42 px button is ~37 CSS
px, ~7 mm on the user's phone) and 0.82 CSS px with a mouse (normal
desktop sizes on any monitor), times an S / M / L setting (0.72 / 1 / 1.4,
menu "UI size", saved in `user://settings.cfg`). CSS size and touch come
from `window.innerWidth` and `matchMedia("(pointer: coarse)")` on the web,
the screen scale and DisplayServer natively; stretch stays canvas_items, so
the battlefield is drawn at full window resolution. Never laid out smaller
than 800 x 400 logical (a 780 x 360 phone at DPR 3 is 1231 x 568 at S, 886 x 409 at M, 866 x 400 at L: the floor caps L). A 780 x 360 CSS phone is 886 x 409 logical; a
1920 x 1080 desktop 2341 x 1317; 3840 x 2160 at DPR 1 4682 x 2634.
Top bar (right): Withdraw army (tap twice), Units, Orders, Pause, speed,
Menu (the speed button shows the speed in force and opens a popover with a
labelled slider, 0.25x to 4x in quarter steps, ticks at 0.25 / 0.5 / 1 / 2 /
3 / 4 and the live value; solo it applies while dragging, + / - keys step
between the ticks); the readout (left) is one short line (fps, battle clock), tap for the
full readout below the bar (benchmarks open it). Bottom: one row with the
group buttons (left) and the selection's actions (right), then the unit
cards, wrapping into the fewest rows: 84-136 logical px wide, 34 tall;
from two rows on they become narrow (symbol and number only) if that saves
a row. 26 units: two rows on the phone, one on a desktop; 40 fit in three
rows on the phone. A card shows the symbol, short name and number, a
headcount bar with the count and a short state word (artillery: set-up /
refill state), ammunition at the bar's right (batteries: shots + reserve),
an orange edge under fire or charge, a white frame when selected, yellow
when routing, orange text wavering, grey when gone. Screenshots:
`docs/screenshots/hud_*.png`. Reordering the cards: drag a card (mouse: a plain
drag; touch: hold it still 0.35 s until it lifts, bigger and brighter with
a shadow and a gold rim, then drag; a quick touch drag does nothing) and
drop it between two cards (a ghost follows the pointer, a gold bar marks
the slot); a long press released without moving opens the unit book as
before (`game/drag_reorder.gd`, shared with the campaign army card). The
order is the strip's own view mapping (display position -> sim unit
index; the sim's unit indices never change, nothing reaches the sim or
lockstep: per player, per battle, co-op peers may differ), kept for the
whole battle (book, controls page, pause); All / Inf / Missile / Cav
select in that order, so the first card of the group becomes the primary
unit. Screenshot (phone, mid-drag): `docs/screenshots/reorder_phone.png`. Testing aids: `--ui-dpr=X --ui-touch=0/1
--ui-size=S|M|L` emulate a device, `--shot=file.png` saves the window,
`--menu-tests`, `--refill=U`.

Start menu: the three battles, then Terrain, Replay, Unit book, UI size,
Fullscreen and a folded "Tests and benchmarks" section with the other 16.

Built in milestone 2: group buttons All / Inf / Missile / Cav and a "+ Add"
toggle (taps on cards or units add to / remove from the selection; Shift on
desktop). A selected group moves together on a ground tap, keeping relative
positions and wheeling to face the direction of travel; a drawn line lines the
group up along it, left to right in their current order, each unit's frontage
in proportion to its soldiers, 2 m apart. Action buttons for the selection:
Run, Halt, Fire (at will / hold, missile troops), Skirmish (on / off), Withdraw;
"Withdraw army" asks for a second tap within 3 s. Tapping an enemy with
missile troops selected orders them to shoot it. Unit cards show ammunition.
The selected missile unit shows its range circle and current target line;
unit markers show a class sign, an orange ring under missile fire, a red
flash when charged, a chevron for charging cavalry, a bar when braced, and an
arrow when withdrawing. All orders, including the new ones, are predicted by
the view through the sim's own order-rule function while paused.

Artillery controls: batteries sit under the **Missile** group button (they
shoot, take Fire orders and stand behind the line; a sixth group button
would crowd the bar on a phone). A **Deploy: on / off** action button
appears when batteries are selected (set up to shoot / pack up and stay
packed); Run and Skirmish are hidden for a battery alone. Tapping an enemy
orders "shoot it"; tapping ground moves (it packs up first). The battery card
reads e.g. "Bolts 2 16/16 / eng 4/4 28 shots / Ready Steady" (Packed,
Moving, Set up 40%, Packing 40%). The selected battery shows its firing arc
as a sector from minimum to maximum range, both range circles faintly, and
its current target; its marker has a ring that fills while it sets up. The
Orders overlay adds "PACKED UP" and "HOLD FIRE" labels; the paused preview
covers the Deploy order like every other. Engines are extra instances of the
soldier MultiMesh (no extra draw call); bolts (long, flat) and stones (big,
round, swelling at the top of their arc) go through the projectile shader;
stone impacts leave a 1.5 s dust ring and furrow drawn by the overlay from a
small view-only ring buffer in the sim (not state). Unit book pages for both
types show an Artillery stat section and derived tags.

**Fire and blast effects (view only, 2026-10-09)**: nothing here is sim state
or in any hash; it is all read from arrays the view already has. A fire
missile in flight (its slot's `pr_ak` has `fire` > 0: fire arrows, javelins,
pots) draws a hot head and a flame tail fading to smoke: the projectile
shaders get the slot's kind (GPU: texture block 8 and a `fire_mask`
uniform; CPU: +16 on the missile's flag) and enlarge the quad behind the
head. `overlay.gd` walks the sim's landing buckets once per tick, follows the
fire, explosive and stone missiles, and a slot that is gone landed at its
aim point: a fire missile leaves 0.4 s of sparks and flame and 2 s of drifting
smoke, an explosive stone a flash, a ring out to its blast radius (`m_blast`
+ the kind's `blast`) in 0.5 s and 3 s of smoke, a plain stone a dust puff.
The effects are one capped list (64, blasts kept over sparks; a volley landing
in one 2 m cell gives one effect), advanced by the view clock so they fade
while the sim is paused, and drawn in the overlay's single `_draw` pass. A
unit with `u_burn` > 0 carries a flame on every 7th man (at most 12) with a
thread of smoke, and burning gates, engines and equipment send up a smoke
column. Cost on a 4-battery, 2-archer-unit fire test: about 0.8 ms of view
time per frame at the cap.

Terrain controls: the menu's "Terrain:" button cycles the ground for the
three playable battles (random from the seed, flat, rolling, ridge, valley,
hill, slope; tests keep their own), "Replay (seed N)" restarts the last
battle with the same seed and ground, and `?terrain=ridge&seed=N` /
`--terrain= --seed=` do the same from the URL / command line. The readout
shows the terrain kind and seed. The unit book's last page, "Terrain",
explains the rules with the sim's numbers; unit pages carry terrain tags
derived from the data (climb rate, range per height, flat weapons blocked
by crests, charge up / downhill, pike wall on steep ground). Testing aids:
`--force-terrain=K` (any scenario), `--attack=U:T`.

Unit symbols and unit book: every unit type has a symbol (drawn with canvas
primitives in `game/unit_icons.gd`) used for the field markers (disc in the
side colour, yellow when routing) and on the unit cards. The unit book
(`game/unit_book.gd`, from the menu and the "Units" button in battle, which
pauses solo play and restores the previous pause state on close) shows one
page per type via `game/unit_entry.gd`, a self-contained control taking a type
id, meant to be reused as the campaign recruitment card. Stats are read from
the sim's unit type data, shown as numbers in metres / m/s / seconds plus bars
scaled to the best value among all types; special-rule tags are derived from
the data; only the role, description and good / countered-by prose is
hand-written (display-only fields in `sim/unit_types.gd`, never read by the
sim). Long press (or right click) on a unit card opens its page without
selecting or ordering anything.

### Controls additions (2026-10-05, as built)

- All inputs are listed in one table, `game/controls.gd` (action, section,
  touch, mouse, default keys); the Controls page (main menu, battle "Keys",
  campaign Menu, F1) renders it, and the battle and campaign keyboard
  handling read their keys from it. No rebinding yet.
- Shift / Ctrl / Cmd + click adds to the selection on the field and on
  cards. It did not work before because cards ignored modifiers and the field
  read the key state; modifiers are now read from the mouse event itself.
- Symbol markers are hit targets first (radius 2.3x the marker on touch,
  1.7x with a mouse), so a marker floating over a neighbouring unit selects
  its own unit; long press (touch) or right click on a unit opens its book page.
- "None" button with the group buttons deselects; Esc too.
- A friendly marker always selects (2026-10-20, replacing the 2026-10-13
  "ordering into crowds" select rule that wrecked formations on a near miss):
  with or without a selection, a tap within the loose marker radius (2.3x the
  marker on touch, 1.7x with a mouse) of one of our units' markers selects
  that unit (nearest marker wins; Shift / Ctrl / Add toggles it). A tap on
  one of our units' footprint away from its marker, with a selection, is
  still a MOVE to that point (a "Move" flash: ordering into a crowd); a
  double tap on our unit selects it; with nothing selected a tap selects; a
  tap on an enemy attacks. Long press on any unit (selection or not) opens
  its book page; holding the only selected unit no longer deselects (two-finger
  tap and the None button do). Drag with a selection always draws the order
  line (box select only with an empty selection or Shift). Telemetry
  `tap_select_loose`: the loose radius, beyond the tight one, made the
  selection. Constants and rules: top of `game/battle.gd`.
- Campaign map, real mouse (2026-10-22, the Total War scheme as on the battle
  field; touch unchanged): a real left click is an emulated touch with
  `device == DEVICE_ID_EMULATION` (`_press_mouse`). Left click only selects
  (`_left_click`): our or another faction's army / fleet (viewing, never an
  attack), a settlement or region; a left click on our other
  army / fleet selects it, never merges or joins; empty map (sea,
  nothing pickable) deselects and never orders; Shift keeps the selection.
  Right click without a drag is the order (`_right_order`): exactly the tap
  for that target (march / attack / siege / merge or join our other army or
  fleet / board; sail / land /
  attack / join; the same spot again cancels), only with an army or fleet of
  ours selected, else nothing. A right drag past 14 px pans, middle drag
  pans, wheel zooms. Esc deselects (`deselect_all`). The hint line says
  "Right-click ..." after a mouse input and "Tap ..." after a touch
  (`last_mouse`). Touch: a two-finger tap (down within 120 ms, up within
  250 ms, each under 12 px) deselects, as on the field. The Deselect button
  shows for armies, fleets and regions on every input: it was missing with
  the command bar on because `show_side` returns early (the bar shows the
  selection) before `_update_deselect`; `_refresh_bar` now updates it, and
  `_refresh` drops a selection whose army / fleet is gone (after a battle).
- Undo (2026-10-20): `game/battle.gd` keeps a stack of the last `UNDO_DEPTH`
  (5) order batches. A batch is every order queued in one frame by the player
  from the field or the bar (tap move / attack, line drag, group move, run /
  halt / fire / skirmish / deploy / stance toggles, card orders); before the
  first order of a batch, each affected own unit's order is recorded as the
  view predicts it (order kind, destination, facing, frontage, run, attack
  target, mode flags). Undo pops one batch and re-issues the records as
  ordinary queued orders (`_queue`, so lockstep and hashes are untouched, the
  sim does not change): a move back to the old destination / facing /
  frontage, an attack on the old target, a hold at the unit's centre for a
  unit that stood without an order, flags only where they changed; broken or
  dead units are skipped. The command bar's **Undo** button shows for
  `UNDO_SHOW_SEC` (6 s) after each batch (the timer restarts on each batch and
  on each undo); Ctrl+Z works while the stack holds anything, paused too.
  Deployment placements, gates, field works and Drop are not undoable. Flash
  "Order undone". Telemetry `undo`, `undo_button`, `undo_shown`.
- Reading a town battle (owner 2026-10-22: "it is difficult to tell where
  the pathing is going to take units ... what is a street vs what is not
  walkable ... I would rather you press the button, and then it shows all of
  the buildings that can be occupied, and the sight lines of that building").
  View only; the sim, its inputs and its hash are untouched (read-only
  queries: `BattleSim.route_to`, `occupy_refusal`, the obstacle cells).
  - **Streets and alleys** (`game/city_streets.gd`, now given the sim): the
    painted ground is clipped to what the sim says is open (rock, cliff,
    wall and sea cells get no street paint), a house's own cells get a dark
    footing, streets are a pale packed earth (paving in the Rome pack) with a
    darker rim, the gaps between houses (within 3 m of a footprint) a warmer,
    darker alley earth; impassable blocks read as blocks, passable gaps as
    alleys.
  - **Paths** (HUD toggle on town maps, remembered in settings.cfg [ui]
    paths, on by default): a faint red diagonal hatch on every cell the sim
    bars to foot on the ground (houses, walls, rocks; the sea is left clear),
    one 2 m-cell mask texture and a world-space shader on `CityLayer`
    (`set_paths_alpha`), shown when the selection changes and fading out
    over 2 s; a route being drawn (a drag) keeps it. Telemetry
    `paths_toggle`.
  - **The move preview is the sim's path.** A drag preview (touch drag,
    right-button drag), the mouse hover with units selected, and the
    selected unit's order line draw `BattleSim.route_to` (the street search
    `_plan_path` uses, run read-only from the order rule's own end point:
    a tap on a house keeps to open ground beside it) from the unit's centre
    as a dotted line through the streets (`OrderPreview.move_route_for` /
    `order_route`, cached per unit and cell). A goal with no way (every
    way shut, or the order rule's snap 3) shows the ghost's men in red and
    "No way through". Once per (unit, cell, gates), not per frame.
  - **Occupy is a pick** (`game/occupy_view.gd`, `game/battle.gd`
    `_toggle_occupy` and the `_occupy_*` functions): the button arms the mode
    (lit); every building some selected foot unit may take
    (`occupy_refusal` clear, an inside of 4+ firing places, no holder) is
    outlined in gold with its door step and a chevron into the door; a mouse
    hover (a first touch tap) on one shows its sight fans and a tip
    ("House: 12 places, holds 14 men", "Click to send them in" / "Tap again
    ..."); the fans are one per face, 16 rays from the face's firing places
    out to the weapon range (25-80 m), each cut at the first obstacle cell
    (another house, wall, tower, gate, rock; its own cells, open ground,
    ditch and water let it through), built once per building and range
    (0.7 ms); a click (a second tap) sends the man nearest its door in with
    `ORDER_OCCUPY` and the others of the selection to the nearest free lit
    buildings within 60 m, none twice; a tap elsewhere, Esc, the button
    again or another selection cancels. A selected unit that holds a
    building shows that building's fans and places at once (the button says
    Leave, which goes out as before). Telemetry `occupy_arm`,
    `occupy_preview`, `occupy_pick`, `occupy_cancel`. Test:
    `tests/city_read_test.gd` (desktop and `--phone`).
- Waypoints (owner 2026-10-22: "Can we add a waypoint system for moving
  units on the battlefield? It makes a big difference for flanking
  manoeuvres"). **Sim** (`sim/battle_sim.gd`, hashed, snapshotted): each
  unit has a queue of up to `WP_MAX` (8) waypoints after its current move,
  `u_wpn` (count) and `wp_q` (`WP_K` 5 values a slot: x, y, facing, width,
  flags `WP_RUN` / `WP_BOUND`), hashed once `wp_on` is set (the first
  waypoint queued: a battle without one hashes as before, no golden moved).
  `ORDER_MOVE` takes `append`: 0 (default) replaces the current order and
  drops the queue as before; 1 appends a waypoint if the unit has a move
  under way (or waypoints queued), else it is an ordinary move. A full
  queue, a fixed engine and the deployment phase take no waypoint. The
  waypoint is stored raw (x, y clamped to the field) and goes through the
  order rules only when it becomes the move, from where the unit then is
  (reach snaps, walls, the short re-form, the width of the order). The
  pop (`_wp_pass`, each step after the AI's orders): a unit with
  waypoints and no order (its move arrived: the existing arrival test, the
  anchor on the destination) takes the next as its move, with its own
  facing, frontage and run flag; the last one's facing is the facing at
  rest. A unit on a stair or a ladder waits until it is up or down; a
  broken or gone unit, or one the sim itself gave another order (an attack
  after a climb), drops its queue. Any other order but Run, Fire,
  Skirmish, Ammo and Stance (an attack, Halt, Withdraw, Occupy, a pick-up,
  Deploy ...) drops the queue; the AI never appends. The rule lives in
  `apply_order_rule` (the queue is the order fields' `wp`), so OrderPreview
  predicts the queue of pending orders and Undo records it. **Inputs**: the
  same lockstep path as every order (an `ORDER_MOVE` with `append` 1); the
  view has no "remove": taking a stop out re-issues the chain without it
  (the current move, then the remaining waypoints appended). **Undo**
  records each unit's predicted queue with its order and re-issues it
  after the restored order (a queue the sim popped from meanwhile comes
  back as it was at the batch). **Mouse** (Total War): Shift + right click
  on the ground appends a waypoint (a group: per unit, keeping the shape
  from where each unit's chain ends), Shift + right drag appends a line
  waypoint (position, frontage, facing); Shift + left click on a numbered
  dot takes that stop out (dot 1, the current move's destination: the unit
  goes on to the next). **Touch**: a Waypoints toggle on the command bar
  (a lit plate, after Halt; hidden in the deployment and for tower
  engines): while on, each ground tap and line drag appends instead of
  replacing (a double tap: run to the stop the first tap added), a tap on
  a numbered dot takes that stop out; it goes off by itself when the
  selection changes and with the two-finger tap. **Preview**: a selected
  unit's chain stays up, faint: numbered dots at each stop (gold ring: a
  run to it) joined by the legs it will walk (on town maps the sim's
  street route of each leg, dotted, red with no way; straight elsewhere),
  the ghost footprint at the last stop; the drag / hover preview with
  Waypoints on (or Shift) starts at the end of the chain
  (`OrderPreview.chain` / `chain_end`, `move_route_for` with `append`).
  Hints: the flash "Waypoint N" / "Waypoint N removed" / "At most 8
  waypoints", the Kit tip on the toggle, the controls table row
  `waypoints`. Telemetry: counters `wp_on`, `wp_off`, `wp_off_selection`,
  `wp_append`, `wp_run`, `wp_remove`, `wp_full`, event `wp_toggle`. Tests:
  `determinism_test --only=wp`, `lockstep_test --only=wp`, `input_test`
  (the `_step_wp_*` section).
  - Attack as the final waypoint (2026-10-30; owner: "can we add attacking
    as a point? So we can have them take a path and finish in an
    attack"). **Sim**: an `ORDER_ATTACK` at a unit (no `gate`, `wall`,
    `bld`) with `append` 1 in the battle phase, on a unit with a move under
    way or waypoints queued, is queued as the final record: flags
    `WP_ATTACK` (4, with `WP_RUN` from the order's run), the target unit
    index in x, y / facing / width 0 (`BattleSim.wp_appends` is the test,
    shared by the sim and the preview). Nothing is queued after it: a later
    appended move or attack replaces the attack record (a full queue ending
    in an attack still takes the replacement). An appended attack on its
    own side, a destroyed or gone target, a fixed engine: refused, the
    queue as it was; with no move under way and no queue it is an ordinary
    attack (and drops nothing). Queuing it changes only the queue (none of
    an order's side effects: the bound, the caracole, the path plan). At
    its pop (`_wp_pass`) the unit is given `make_attack_order(tick, u,
    target, run)` through `_apply_unit`, so the order rules apply (a
    missile unit shoots, foot close, foot inside the walls climb at a unit
    on the wall); a target destroyed or gone by then: the record is
    dropped and the unit holds where it is. The order's `charge` /
    `butt` / `throw` flags are not kept in the record. `stat_wp_atk`
    counts the attacks given (checks). Hash: the record is in `wp_q`
    (hashed once `wp_on`), the target index included. **Lockstep**: the
    order travels as any order (`receive` keeps every key, `append`
    included). **Preview**: `OrderPreview.wp_of` returns the record;
    `chain` / `chain_from` add the key `"attack"` to every entry (-1 for a
    stop, the target for the final attack, whose `"at"` is the target's
    centre, `"face"` towards it, `"blocked"` if the target is gone or the
    order rule refuses it), predicted through `apply_order_rule`. Tests:
    `determinism_test --only=wp` (`_check_wp_atk`, Rome and West: two stops
    then the attack for foot and a missile unit, the hash, repeat,
    snapshot / restore with the attack queued, the replacement and refusal
    rules, a target gone by the pop), `lockstep_test --only=wp` (A's chain
    ends in an appended attack on an AI unit, given on all three peers).
- Campaign battles have no field result panel; they end with a choice
  (owner 2026-10-20, Rome 2's end of battle). **Battle end: End battle /
  Continue.** When a side is decided (the other has no ready unit; not a
  draw), an interactive campaign battle shows a modal over the field: the
  banner's title (Victory / Defeat), one line ("The enemy is broken and
  running." / "Your army is broken."), [End battle] [Continue]. End battle
  queues the sim input `ORDER_END` for the player's side: `ended` on its
  tick. Continue queues `ORDER_PURSUE`: the sim's `pursue` flag (hashed once
  set, in snapshots) moves the end from `END_AFTER` (60 s after the decision)
  to the loser's last unit off the field or the hard stop `END_PURSUIT_MAX`
  (3000 ticks, 5 min); the modal closes, the top-right button reads "End
  battle" (no Stay / Leave modal after the decision) and queues `ORDER_END`,
  and the banner shows small at the top ("Victory: pursuing", the time left
  under the hard stop). No answer: the sim ends it after 60 s as before. Both
  inputs count only from a human side (not one under the battle AI) and only
  after the decision (before it Leave / withdraw covers leaving); one from
  any side is enough (co-op: one Continue closes the modal on every peer,
  with the flash "<name> continues the pursuit"; one End ends it for all).
  At `ended` a campaign battle stops stepping (the result handed to the
  campaign is the state at `ended`) and returns after the 1.5 s Victory /
  Defeat banner (0.3 s after this player's own End; tap to skip). A draw
  (both gone or the time limit) and a non-interactive campaign battle end
  as before: the banner, then back. No input = the old end, so no
  determinism golden moved. The modal is one flag (`end_choice` in
  `game/battle.gd`, on for campaign battles); custom battles and the sandbox
  keep the field result panel and the 60 s end (in a head-to-head custom
  battle the loser's End would cut the winner's pursuit short). Telemetry:
  counters `end_choice_end`, `end_choice_continue`, `end_battle_button`,
  `end_pursuit_ended_<how>` (`end`, `last_unit`, `hard_stop`, `timeout`)
  and events `end_choice_shown`, `end_choice`, `end_pursuit_ended`.
  Sea battles are untouched.
- Keys: Space / P pause, + / - speed, 1-4 and Ctrl+A group selects, R run,
  H halt, F fire, K skirmish, Shift+D deploy, Y refill, O orders overlay,
  W A S D / arrows pan, Page Up / Down zoom, B book, F3 readout, F11 fullscreen.
- Mouse (Total War: Rome scheme, 2026-10-13; real mouse only, touch unchanged):
  left click a unit selects it (Shift / Ctrl adds or removes), left click on
  empty ground deselects, left drag draws a selection box (Shift adds);
  right click on the ground moves the whole selection there keeping its
  shape (`_group_move`: the group's centre goes to the point, each unit keeps
  its offset from it, turned with the group if the travel is a big turn;
  one unit: a plain move), right click on an enemy attacks, on one of ours
  moves to that point, double right click runs / charges; right drag lays
  the selection out along the dragged line (the drag-to-line rule of touch:
  left to right in current order, files fitted to the width, facing
  perpendicular toward the side dragged from; preview as for touch); in the
  deployment phase the same buttons place units. Middle drag pans (right
  drag pans when nothing is selected), also keys; wheel zooms. A unit's book
  page is on the card / B key. Gates, engines, equipment and the targeting
  modes (Release, Sabotage...) still take a left click.
- Walls (2026-10-23): there are no Man the wall / Come down buttons. With
  men selected that may man a wall (or stand on one), a left click (mouse)
  or a tap (touch) on a wall stretch (body, walkway, stair or tower:
  `BattleSim.wall_stretch_at`) sends them onto THAT stretch (the same move
  as before, to its point nearest the click, facing `ws_dir`; refusals
  flash their reason). The mouse hover lights the stretch beforehand; a tap
  lights it for 0.9 s (`Overlay.flash_stretch`). A click in a gate's
  doorway stays the gate's; a click or tap on the street or ground is an
  ordinary move and brings men down by a stair. M (nearest stretch to the
  enemy) and Shift+M (down) stay as keys (Keys panel). A selected unit near
  a wall shows "Click a wall to man it" / "Tap a wall to man it" in the
  carry-note line. The `man_wall` counter counts wall clicks too.
- Two-finger tap deselects all (touch, battle only): both fingers down within
  120 ms, both up within 250 ms of the first touch, each moved under 12 px;
  pinch / pan motion cancels it (`TWO_TAP_*` in `game/battle.gd`).
- Two-finger pan on the phone (2026-11-01; the owner: "2 finger panning does
  not work", pinch zoom did). Cause, reproduced in engine: `_update_pinch`
  moves `camera.position` by the midpoint's travel, then calls `_zoom_at`,
  which read its anchor (`before`) through the canvas transform, still the
  one from before the pan (Camera2D refreshes its scroll at its next update),
  and its forced `after`: `before - after` was the pan, reversed, so most of
  it was undone every event (measured 23-51 % of the finger travel, jittery).
  Not the browser: the default 4.7 shell already has `user-scalable=no` and
  `touch-action: none`. Fix: `_zoom_at` calls `camera.force_update_scroll()`
  before reading `before` (the pan now follows the midpoint 1:1). And a
  second finger landing over the HUD (a thumb on the chip rows) while one is
  on the field now joins the pinch / pan (counter
  `touch_on_ui_joins_gesture`); a lone finger over the HUD still starts
  nothing on the field. input_test checks both and the tap after a pan.
- Group move: three fingers on the screen with units selected; after 24 px
  of movement or 8 degrees of twist a ghost of every unit's destination
  (real frontage, depth and facing) follows the touches' centre and twist;
  lifting a finger places the group (move orders keeping each unit's
  frontage, relative position and facing), a fourth finger cancels, small
  movements issue nothing. Desktop: Alt + left drag (or hold G and drag, for
  systems where Alt-drag moves windows); wheel or Q / E turns 15 degrees;
  right click or Esc cancels. Works paused (the usual order preview).
  Telemetry counters three_finger_move, alt_drag_move, group_rotate,
  group_rotate_placed, group_move_cancelled.

### Compact unit cards (as built, 2026-10-09)

View only: `game/unit_traits.gd` derives everything from the unit rows, so a
new row gets it free. A unit card (`Kit.UnitRow`: recruit lists, army cards,
the raise picker, exchange, garrison) has three lines: the name with up to
three **trait** glyphs (siege, shock, anti-cavalry, fearsome, armour piercing,
long range, skirmish, fire for the viewer's faction, beast, fast; tap =
one-line toast), a green row (good against) and a red row (weak against) of
the six enemy **class** glyphs (foot, spear, horse, missile, beast, engine),
and five **pips** (attack, defence, armour, missile, speed, four segments,
scaled against the best of the unit's class; speed and missile against all
rows). The rule table is in the file's head comment; the unit book page and
the battle card tooltip show the same. Recruit lists and the raise picker sit
under collapsible class headers, every unlocked row listed flat under its
own role (best tier first; see the 2026-10-29 note below); an army card opens with a composition
strip (class glyphs with unit counts) that folds the unit rows (armies of up
to six units start open). Fold state is per session, never in the campaign
state.

### Recruit slots and flat tiers (as built, 2026-10-29)

Owner: "What determines how many units can be built from a location each turn?" and "The position of the
'1 tier' button is on top of the first unit ... super confusing". View only, `campaign_panels.gd`.
- **Slot chits.** The recruit headers (settlement Recruits, the raise dialog's "Recruit slots", the army card's
  Slots) show one rounded chit per recruit the settlement raises a turn (`CRules.recruits_per_turn`: level 1 / 2 / 3
  plus a haven's infamy recruits), numbered, filled in the faction colour when queued, an outline when free
  (`_slot_header`, row named `recruit_slots`, chits `slot_chit_n`). The tip says "A village raises 1 a turn, a town 2,
  a city 3; a pirate haven more with infamy (West only); one general a turn. Recruits arrive at the end of the
  turn." The settlement panel's level line reads "Town: 2 recruits a turn" and the growth line adds ", +1 recruit a
  turn" when the next level raises more.
- **Queue.** `_queue_list` lists the queued recruits by name with an x (`queue_cancel_n`; the cancel is removing the
  recruit order, as the army card's arriving rows do). New-army recruits stay on the "Raising a new army" line
  (one x cancels all).
- **No tier folding.** `_grouped` lists every unlocked row flat under its role group; the "+n tiers" chip and `_fold`
  of lines are gone (Canoe Raiders and Miskito Warriors share a roster line, not a role, and the chip hid one under the
  other). A lower tier is a touch dimmer and carries an upgrade arrow by its price (`UnitRow.upgrade_tip`), the tip
  naming the better row ("Upgrades to Canoe Raiders at War lodge 1"). Locked rows keep the one "needs ..." fold.
  "Trains here" already shows one row per line and is unchanged.
- **The army's list says the special arrow too (2026-11-02, view only).** Owner (West, phone): "When recruiting units
  through an army, the tier 2 Bowman don't show. The tier 2 Bowman can be recruited fine in the same town itself."
  Both dialogs are one listing: the settlement's "Raise new army" and the army's Recruit popup / card section both
  call `best_options(ps, f, r)` with `r` the settlement the army stands at (`CRules.recruit_region`), and
  a built-up state of every West and Rome settlement gives equal lists (`campaign_test _recruit_lists`). The West
  has no second bowmen tier row; what a Range 2 adds is the natives' special arrow (`AMMO_AVAIL`: the Miskito's
  poisoned arrows, the Itza's fire arrows), which the raise dialog's rows state ("Tier 1 - upkeep 48 - + poisoned
  arrows") and the army's rows left out, so the army's Bowmen looked like the plain tier 1 row. `_army_recruit`'s
  rows now add the same "+ <arrow>" text. No rules change (the recruit already carried the arrow, `new_unit`).
  Checked on a phone-sized window (windowed, 393 x 851 logical and dpr 3, New Spain, England and Rome at max
  buildings): the army's popup is the same `show_dialog` scroll as the raise dialog (page 560, content 1700-2100,
  scrolls to the last row), with the same number of rows (17 / 18 / 22); a full army of 12 or a treasury of 10
  greys the army's rows ("the army is full", "not enough money") and hides none; no West roster line has two bowmen
  tiers (Rome's archer lines list in both).
- **A unit's special arrow is marked (as built, 2026-11-02, view only).** Owner (the Miskito, phone): "I can't tell the
  difference between level 1 and level 2 bowmen on the bottom bar once an army is selected in the overworld, or in the
  battlefield." Cause: the arrow a unit carries is per unit (the entry's `ak`, set by `CRules.new_unit` from the
  `AMMO_AVAIL` row whose building stands where it was raised; the battle sim's `u_sk`), but only the raise dialog's text
  said it; the army bar's chit, the battle HUD's card, the unit page and the result cards drew a plain Bowmen. The
  campaign has no experience or veterancy (tier is the only rank, the three pips), so the arrow was the one per-unit
  difference hidden; in battle the other one was which kind it shoots and whether it is spent.
  The mark (`game/unit_traits.gd` `ammo_icon` / `ammo_adj` / `ammo_color` / `ammo_mark_text`; icons `am_poison`, `am_fire`,
  `am_heavy`, `am_lead`, `am_pots`, `am_blast` in `ui_icons.gd`, two-colour strokes like the trait glyphs: an arrow and a
  drop, an arrow with a flame, a thick bolt, three shot, a pot with a flame, a burst; poison green, flame orange, the rest
  brass): (1) the overworld army bar's chit (`command_bar.gd` `UnitCard.ak`): a dark badge ringed in the kind's colour on
  the symbol's lower right, and the card's title in the kind's colour; the hover row and the long-press unit page say
  "Miskito Bowmen - poisoned" and lead with "Carries poisoned arrows (33% of the load, 67% damage, ...): <what it does>"
  (`UnitEntry.set_unit_type(.., ak)`, `open_unit_page(.., ak)`); (2) every `Kit.UnitRow` that lists a raised unit (army
  panel rows, exchange rows) or a recruit row with a special arrow: the adjective after the name where it fits and the glyph
  with the trait glyphs (tap: the same words), the recruit rows keep their "+ poisoned arrows" text; (3) the battle HUD's
  `CardFace`: the glyph left of the shot count (lit with a bar under it while the unit shoots the special kind, dimmer
  while it is held back, struck through grey when it is all spent), the name tinted, the adjective after the name when the
  card is wide enough (not on a phone's narrow cards), the card's tip adds the words and the state; (4) the fought battle's
  result cards (`battle_screen.gd`): glyph and adjective in place of "+poison". The custom battle's army rows already say
  "Ammo: Poisoned arrows" on a tinted button and are unchanged. Not marked: the garrison cards (derived from the rules,
  no per-unit entry), the field tokens, the unit book (a reference by type: it already lists every special kind with who
  carries it). Tests: `hud_fit_test _ammo_mark_check` (every size: the glyph inside the card, none on a plain unit, lit
  state, icons exist); shots `tests/bows_shot.gd`.

### Per-faction unit names (as built, 2026-10-26)

The West pack's native and pirate rows are shared by two factions and carry a bare name, so a card did not say
whose unit it was. `campaign/data/west.gd` `UNIT_NAMES` ({faction key: {unit row key: [name, short]}}, view only; it
moves the rules hash as a pack constant, nothing reads it in the rules) renames them per faction: Itza: Warriors,
Bowmen, Slingers ("Itza ..."), the chieftain's guard "Batab's Guard" (short "Batab"; a batab was a Maya town lord),
shaman "Ah Kin"; Miskito: Warriors, Bowmen, Slingers, musketeers "Miskito Musketmen", chieftain "King's Guard" (the
Miskito king was crowned under English patronage from the 1680s), shaman "Sukia"; Brethren: general "Captain's Crew"
(short "Captain"), musketeers "Ship's Musketeers". The lookup is `CData.unit_name(key, f)` / `CData.unit_short(key, f)`
(a Dictionary lookup; f < 0, no entry or a pack without `UNIT_NAMES` such as Rome: the row's own name). Used by the
unit rows (`Kit.UnitRow.name_f`, apart from `faction` so the fire trait is unchanged), the command bar's cards and
tooltips, the unit page (`open_unit_page(..., fac)`, `UnitEntry.set_unit_type(..., faction)`), the recruit / raising
event texts, the pre-battle and result cards (`battle_screen.gd UnitCard.name_f`) and the battle HUD (`Hud.unit_faction`,
copied from the battle's `unit_faction`: card names, battery text, reinforcement note, result table). Left with the row
name: the Roles texts (they name roles, not units), the "killed by" lists (`Kit.kills_detail`, enemy types), the
engine-worker note ("on bolts") and the trait text of characters, and the custom battle's unit picker (it
adds rows, not a side's units).

Unit book and custom battle (2026-10-27): the main-menu book (`unit_book.gd`) has a faction picker above its list
(`book_faction`, only in a pack with `UNIT_NAMES`): "All factions" lists each row once under its own name with the
per-faction names in small text under it ("Itza Warriors, Miskito Warriors"; `variants_text`), and a faction pick
lists that faction's names (`unit_label`) and the unit page takes the faction (`open(ty, fac)`,
`UnitEntry.set_unit_type(..., faction)`). Rows the factions rename but the book did not list in the West (the
Rome-tagged chieftain and general guards) are listed for them. Rome has no table: unchanged. A custom battle side
is an army of any units, not a faction, so each side has a Names button (West: standard / Itza / Miskito / Brethren;
setup side key `names`, view only, erased by a pack change); `CustomSetup.unit_label` names the side's army list
(`game/unit_names.gd` reads the pack's table without making it active) and `Battle.side_name_fkeys` makes the HUD's
`unit_faction` per sim unit (the soldiers' palette `unit_faction` is untouched); `main.gd` makes the setup's pack
active for the battle and puts the old one back at its end.

### Diplomacy screen: trust, alliances and passage (as built, 2026-10-26)

The view half of the diplomacy rules (`campaign/cdip.gd`; `docs/design/campaign_rules.md`
"Diplomacy: trust, alliances and passage"). It reads the planned state (`ps`: a gift or a
planned war already shows) and emits orders; nothing here writes the state. Every number
in a hint or a confirmation is read from `cdip.gd`'s const table, never typed in.

- **Top of the dialog**: "Your repute: +N" (`own_repute`, coloured by its sign) with a
  dim note on what moves it; then the inbox, the team header, then one block per live
  faction but ours. Formats before 10 (no `regard` key) show no trust lines or trust actions.
- **A faction's block** (`dip_<key>`): a header (a `PanelContainer` holding crest, name in
  the faction colour, the relation and a +/- mark, with a `Kit.PressRow` laid over it: a tap
  opens or closes the block, kept in `_dip_open`; the faction asked about via
  `show_diplomacy(focus)` is open). The relation reads War / Peace / Trade / Allied (team
  mates "on your team (ally)") with ", passage until turn N", ", they cross our land until
  turn N" and ", marque until turn N" when held. Under it the strength line, and the trust
  line: "Regard of you +N" (their regard, `regard[g*n+f]`), a short bar (red below 0, green
  above, its width the magnitude of -100..100; `dip_bar_<key>`, meta `value`) and "Repute
  +N" (theirs). `CampaignPanels.dip_open_all` (static) opens every block (the test flag).
- **Open**: up to 4 lines from `regard_log[g*n+f]`, newest first, "turn 31: you took a
  city of theirs, -15". The rules store codes ("city_taken"); the screen words them from
  the row's side (`_regard_why`, unknown codes show as given with underscores spaced). Then
  the AI's stances (existing peace / trade / team / marque lines), the actions in a flow
  row, planned orders and the gift chips.
- **Actions** (the existing `_dip_button` path, so they are orders): Offer peace, Offer
  trade, Cancel trade, Marque, Join our team (as before); Propose passage and Propose
  alliance (shown at peace or trade; on when the rules allow and `CAI.why` says yes or the
  target is a human, who answers next turn; off with the refusal as its hint,
  `hint_<what>_<key>`, e.g. "they do not trust you (0, 10 needed)"; passage already held
  reads "Passage held until turn N"); Leave alliance for a non-team ally (confirm dialog
  with the 5-turn notice and the -20 regard when they are at war; a recorded notice reads
  "Leaving the alliance: N turns left"); Declare war, whose confirmation lists what it
  costs from the rules' table: "breaking a treaty: repute -20" on a trade partner or an
  ally, "an unprovoked war ...: repute -10" when none of their armies stands in our land,
  their regard -40, the alliance ending. Gift 100 / 250 / 500 gold chips (off above the
  treasury or at war, `CDip.gift_check` as the hint) with the line "Gifts: 100 gold = +2
  regard, 250 = +5, 500 = +10, capped at +25 from gifts (now +N); the gift share fades 2 a
  turn". A pending order of ours on the faction is a "Planned: ..." line with its own
  Cancel (propose / war, leave alliance, each gift separately). Team mates keep the
  gift-money / buy-a-city deals and gain no treaty buttons.
- **Inbox** (`proposal_<id>`, text `proposal_text_<id>`, `proposal_accept_<id>` /
  `proposal_refuse_<id>`): team (as before), alliance ("shared sight, each other's ports,
  reinforcing each other's battles and a defensive call to arms"), passage ("asks to march
  through your land for 10 turns") and a call to arms ("X calls you to arms against Y:
  accepting declares war; refusing costs regard -20 and repute -5"). All answer with the
  `answer` order; the end-turn warning lists an unanswered one.
- **Creation screen**: "AI alliances" On / Off (`ai_alliances`, default On; the rules store
  it only when 0), after "AI aggression".
- **Trespass** (the rule is `CDip.may_cross` without passage, the one `end_turn` charges;
  `MapOverlay.trespass_owner(st, f, region)` is the view's name for it): planning a march
  whose path ends a turn in such a region toasts "Trespass: -2 regard a turn per army;
  war at -40. <Faction>'s land: ask for passage in Diplomacy." with a Diplomacy action
  (`campaign_screen.trespass_toast`; a path only crossing the land in a turn costs nothing,
  so it is not warned), the path's end gets an orange warning triangle (`COL_TRESPASS`, the
  `trespass` intent kind), an army of ours standing in such a region wears the same
  triangle at its banner's corner and the command bar's status line reads "Trespassing in
  <faction>'s land" while it holds position. Passage held clears all three.
- **Raise dialog**: a unit row refused for a reason now draws it red on up to two lines
  (`UnitRow.sub_bad`), so "needs a trade agreement with a European nation" (the Miskito
  musketeers without a European trade partner) fits a phone at S.
- **Chronicle**: `event_text` words regard (only moves of 5 or more, and only a faction's
  regard of us), repute (ours), alliance, alliance_notice, alliance_left, passage,
  passage_end, gold_gift, trespass, call, call_answered, call_sat_out and the trespass /
  called wars. `_involves` also reads the keys `with`, `g`, `vs`.
- Tests: `campaign_input_test` step `_dp_run` (West, human Miskito): the rows, the closed /
  open block, the log line, Propose passage on / off, the gift, the inbox, the war
  confirmation, the fit at S / M phone sizes and 1280x720, the musket reason, the trespass
  toast, mark and bar line, and a chronicle line per event key.

### The command bar (overworld selection, as built 2026-10-15)

View only (`game/campaign/command_bar.gd`; no rules path, no `campaign/`
change): what is selected shows as cards along the bottom of the screen
instead of the side panel's long list (user: "just a big list on the right ...
like Rome"). **Army:** a leader card (faction emblem, the hero's name or
"X army", men, units of the cap, movement left, stance, upkeep, supply in a
siege, a status line: holding / marching and when it arrives / besieging),
a strip of **unit cards** (symbol, tier pips, up to three trait glyphs, a
strength bar with men / full; a tap picks it for Split / Disband, a long
press opens its page, hovering shows the full compact row; planned recruits
as dimmed "joins" cards) and a grid of **icon actions** with a label under
each (Stance cycles March / Forced / Fortify / Raid, Siege / Assault on
arrival, Cancel, Split, Merge, Exchange, Recruit, Disband, Board, Sally,
Details). **City:** city card, garrison cards, building chips (icon and
level; a tap says what it does), Recruit (the raise picker), Build, City map,
Assault / Continue / Withdraw for a besieger, Besiege and Raid at an enemy
city, Sally for the besieged. **Fleet:** a card per ship (hull and crew),
Cancel voyage, Board, Join. An action that cannot be done is greyed and says
why on hover and on a tap. Every button calls what the side panel's buttons
call (`add_order`, `set_move_mode`, `_set_stance6`, ...). **Details** opens
the old full panel in the side panel, which now opens only on demand (and
for Build / Recruit into an army, which scroll to their section there); its
Close hides it and keeps the selection. Layout: full width at the bottom,
132 px at least (96 on a phone: narrower than 700 or lower than 560 logical px, one
horizontally scrolling row); the reported height is the larger of that and the
built content's real minimum height (a level-3 city with seven buildings is
about 148), so the map key buttons, the End turn row, the hint and the toasts
rise above it by what it really takes while it shows; the hint wraps in the
room left between the key buttons and the End turn row. Versions before 6 keep the side
panel only. Testing aids: `--details` / `--no-bar` (the old behaviour).

**Map pan limits and the UI size steps (as built, 2026-10-25).** *Pan:* `_clamp_view()` counts the
command bar (`_bar_lift()`, also the lift of the bottom corners) as covered: the fit zoom and the
centring use the band above it, and when the map is larger the margin is a buffer (a third of the
uncovered height, a quarter of the width, 60 px at least), so the southern strip can be brought
above the bar. `_layout_bottom()` re-clamps when the bar shows or hides. *Sizes:* S / M / L are
0.72 / 1 / 1.4 (M unchanged; S was not small on a phone, L not large on a 1440p monitor). Logical
size of a 2560 x 1440 mouse screen at DPR 1: 4336 x 2439 (S), 3122 x 1756 (M), 2230 x 1254 (L).

**Round 2 (2026-10-16, owner's tablet playtest).** *Recruit popup tabs:* the
city's Recruit opens `show_raise` on **Army** or, with nothing to raise and a
yard to build in, **Shipyard** (tabs only in a pack with ships at a port of
ours; greyed "needs a Shipyard"); the Shipyard tab lists the ship rows (cost,
guns, hull, crew, carries, pace, upkeep, yard level, the reason when not
buildable), the queued ship with X and the fleets in the harbour; "Build ship"
adds the same `ship` order; a fleet in port gets a **Shipyard** action. *Drag
on the bar:* `DragReorder` over the unit cards (mouse: press and move; touch:
hold until it lifts; ghost and gold slot mark), drop = `_arrange(id, from,
to)`; a hold without a move opens the unit page; a short tap still picks the
card for Split. Dragging onto another army or the Exchange action is not
built (reorder only). *Build popup:* queue on top with Cancel, a row per
chain (icon, "Farms 1 -> 2", cost and turns, first clause of the description,
the reason greyed), a tap queues the `build` order. *Details thinned:* the
army panel keeps the count, characters, the march line and the movement
points; the city panel keeps income / growth, sea notes, armies here,
characters, what it trains, the siege section (odds and orders text) and
gifts; units, order, Split, Disband, Exchange, Merge, stance, recruits,
Board, Cancel, siege orders, the garrison, buildings, raise and the
shipyard are on the bar or in a popup, each order in one place. A planned new
army's X is in the Recruit popup; a planned recruit into an army is a dimmed
card (tap cancels). Testing aid `--popup=build:key|raise:key|ship:key|recruit:N`.

**Command bar round 3 (as built, 2026-10-31).** View only (`command_bar.gd`, `campaign_screen.gd`, `map_overlay.gd`,
`campaign_panels.gd` one word; nothing under `campaign/` or `sim/`). *Status:* the leader card's coloured status line now
says what the rules hold: an army "Besieging <town>: N turns of stores left" (the siege record's `supply`, `CState.siege_at`),
inside a besieged town "Besieged: N turns of stores left", a raiding army "Raiding <town>: +G a turn" (`CRules.raid_map` for
who raids, `CRules.income(...)["raid"]` is the rules' own total; G is its per-region term `_base_income * RAID_PCT / 100`), a town's "Besieged by X, turn T:
N turns of stores left"; a fleet "Raiding <lane>: +take a turn" (`CLanes.raiders`, `lane_state()["take"]`) or "Blockading <port>:
+take a turn" (`CSea.blockader`, `blockade_take`). Under it a dim summary line (`leader_line`: "610 men, 8 companies, March";
a fleet "2 ships, 3 units aboard"), on a phone only as the status line's tooltip (the 96 px card has no room). The campaign has no
army morale, so none is shown; an army aboard a fleet leaves `armies` and has no bar (the fleet's summary counts the units
aboard). *The "..." fold* (`_fold`, `_open_more`): the rule is the bar's width, not only the phone layout: the first three
actions stay when the actions plus the leader card would leave the strip less than four cards at their narrowest
(`FOLD_CARDS`), or always in the phone's single scrolling row (under 700 logical px); the rest are the same buttons under a
"..." button (name `act_more`) whose popover (`more_pop`, a flow above the bar, right edge on the button, inside the screen)
closes on a tap anywhere (`more_catcher`), on an action and on any rebuild. The battle HUD's `MoreBox` holds ability chips and
is not shared. The width rule folds an army with seven actions below about 870 logical px (800x450 and 844x390 with a
neighbour army to merge with); on the S size the logical screen is wider (800x450 at S is 1355 x 763) and the bar fits whole.
*Quick recruit* (`_quick_chips`): a "Quick recruit" caption over up to three chips (`quick_<key>`, short name and price)
beside Recruit and Build in an owned city: the first three rows the raise dialog lists (non-locked `best_options` in the
dialog's group order); a tap adds `{"t": "recruit", "r", "unit", "new": 1}` (the dialog's own order); greyed, with the refusal
on a tap, when `CRules.recruit_options` refuses (the turn's `recruits_per_turn` slots used, or the gold short). *Drag onto
another army:* a drag from one of our free armies (the screen's existing drag, `DRAG_THRESHOLD` 14 px, mouse and touch alike:
the map has no long-press) that is over another army of ours standing together (`_exchange_target`, `Panels._partners`
and `CRules.together`) rings it (`Overlay.set_drop`, gold, in the glow layer) and draws no march path; the drop selects the
dragged army and opens the existing Exchange dialog (`show_exchange`: two columns, a tap sends a unit across, either way,
one order, `exchange {from, to, units, back}`), whose button now reads "Exchange" (a gift stays "Gift N units"). A drop
anywhere else is what it was: the march plan. Tests in `campaign_input_test`: `_c3_drag`, `_c3_bar`, `_c3_fleet`.

**Shipyard rows and the dialog height (as built, 2026-10-26).** The Shipyard
tab's rows are `Kit.ShipRow`, a drawn row of the soldier row's shape and
height (200 x 72, both on the base `Kit.PressRow` that holds the press /
long-press / hint-zone code): the ship glyph in the side colour, name and
price, the row's `"role"` sentence (`west_ships.gd`; the `desc` when a row
has none), five pips G H C P L (Guns, Hull, Crew, Pace, Load; thresholds
2/10/25/45, 15/35/70/110, 30/80/180/300, 250/300/350/390, 1/2/3/5, each stat
in its colour; a tap on them hints the exact numbers), and the sub line
(upkeep, Shipyard level, coastal, rowed, or the reason in red; "not enough
money" stays dim and the row stays pickable). A long press shows the `desc`.
The dialog's height: `show_dialog` measured the content in `_center_dialog`
before the first layout, when the new content's wrapped labels are measured at
their 40 px minimum width (the Shipyard intro 564 px high, the content 1645
against 315 laid out); the scroll area took its cap and the dialog, which never
shrinks by itself, kept it, with empty space inside and the buttons pushed
down. `_center_dialog` now fits again after the next two layouts, and
`_fit_dialog` limits the scroll area to what is left of the screen after the
title, rule and buttons (`campaign_input_test` `_j_ship`: both tabs inside the
viewport with the buttons visible at 844x390 S / M and 1231x568 S).
2026-10-27: the dialogs were right; the test's fit checks failed (up to 28) only when
the test window's shape differed from the phone sizes (a window manager resizing the
`--resolution` window): with the project's stretch aspect `expand` the visible rect,
which `_fit_dialog` centres in (`_vp()`), was taller than the `content_scale_size` the
test checks against. The phone-size steps (`_d_select`, `_j_barfit`, `_j_ship`,
`_dp_run`) now set `content_scale_aspect` to `keep` (the visible rect is exactly the
phone size, letterboxed) and restore `expand` after; PASS at 2000x923 and 1600x1100.

2026-10-29, test hygiene (view and tests only). (1) `menu_test` headless: the root starts at 640x640, so the
Host / Join cards stacked and the phone layout measured the wrong size; `_run` and `_phone` now size the root
(`root.size` 1280x720, then 844x390 for the phone steps, back after) when the display server is headless, the
checks themselves unchanged: RESULT PASS. (2) The windowed tests (`campaign_input_test`, `battle_screen_test`)
aborted at exit ("corrupted size vs. prev_size in fastbins") after RESULT: PASS: found with
`LD_PRELOAD=libasan.so.8` (a double free at quit) and by bisecting `CampaignScreen._ready`: `Kit.hint_cb = func...`
set a static to a lambda capturing the screen and nothing cleared it. The screen now keeps the lambda in `_hint_cb`
and clears the static in `_exit_tree`. (3) The six "Signal already connected ... _grow" errors: `Kit.motion` ran twice
on a button (`Kit.button` wires it, `battle_theme` styles it again); `motion` now marks the button (`motion_on`) and
wires it once.

**Boarding indicator and the Shipyard queue (as built, 2026-10-26).** The
overlay's `set_landing` (called as before after a selection or an order; it
still returns "changed") also fills `board_cells` and `pickup_cells`
(`landing_cells` keeps its meaning, the sand-gold beaches), drawn in teal
(`COL_BOARD`) as a rounded cell outline with a small boat at the cell's centre.
With an army of ours selected (no fleet), the cells of `CFleet.boarding_cells`
of every fleet of ours with room for the whole army are lit. With a fleet of
ours that has room selected, the `CFleet.pickup_cells` of every army of ours
that is not busy, not in a siege and not already beside it are lit (a tap on
one sails there, as before). Tap order with an army selected and a fleet of
ours tapped: beside it (or `embark_check` clean) the army boards now; else, if
`CFleet.board_order_check` is clean, `set_board` sends a persisting move with
`"fleet"` to the boarding cell with the fewest march turns (ties: Chebyshev
distance, then cell index), toast "Marching to board the fleet: N turn(s),
boards on arriving."; the same fleet tapped again cancels it; a refusal flashes
"Cannot board: why." The planned path ends in the boat mark, the command bar's
status line reads "Boarding fleet on arriving" (`plan6` carries `"fleet"` from
the order or a stored `dest_fleet`), and Cancel clears the order, or sends
`cancel_move` for a stored march. The Shipyard tab's intro names the batch
kind from the data ("one ship a turn; war canoe: 4 a turn"); the queue is
grouped by kind with a count ("War canoe x3: launched at the end of the turn")
and each group's close button removes only that kind's orders for the port; the
rows show the rules' reason (red) when the batch rule blocks them.

**Tap latency (2026-10-16, owner's Tab S7: "almost any selection has a visible
delay").** A tap is answered in the frame it lands in, and that frame only does
what the tap changed; the rest follows in later frames. Rules of the view
(`game/campaign/`, nothing in `campaign/` or `sim/`):
- *The map is not drawn again for a selection.* The selected army's reach is
  its own child node of the map (`map_view._reach_node`, under the pulse
  tints) and the selected region's outline another (`_sel_node`, over the
  edges, under the coast); `set_reach` / `set_selected_region` redraw only
  those, and `set_reach` keeps the outlines when the reach is the same.
  `map_view.refresh_state()` redraws the territories and edges only when an
  owner changed (the only part of the state the map shows).
- *The overlay redraws only the parts a selection changed:* on the same state
  (`_refresh_map6` keeps the state, campaign and planner it last drew, plus a
  few counts) `overlay.redraw_parts(paths, fleets, armies)` redraws the paths
  (with zones, links, badges) when they differ, the fleets when the selected
  fleet, voyages or sea reach differ, the armies when the merge glyphs differ,
  the halo always; settlements never. A new state (an order, a resolved turn)
  still redraws all six parts. The drag preview redraws only the paths.
- *An army's reach comes one frame later:* `select_army` shows the bar, the
  halo and the hint in the tap's frame; its reach (the rules' `reach6` and
  the outlines), zones, links and merge glyphs are computed in the first
  frame after the tap's frame (a process-frame count, deterministic and
  headless-safe; on the web the page has shown the bar before the work
  starts).
- *The command bar is built once per frame* for the same selection, state,
  plan, panel and window (`_refresh_bar` signature; a tap used to build it
  twice: `show_side`, then `_refresh_map`).
- *Icons are textures:* `game/campaign/icon_raster.gd` draws each vector icon
  (`game/ui_icons.gd`) once, in white, into an atlas (a SubViewport rendered
  only when an icon is added; premultiplied blend so the atlas is straight
  alpha) at the screen's physical pixel size, and the bar's actions, unit
  card trait glyphs, `Kit.set_icon` buttons and `Kit.label_icon` labels draw
  one tinted quad (the first frame an icon size is asked for it is drawn as
  vectors). The bar's icons are asked for when the screen opens. Greyed icons
  no longer show darker overlaps where strokes cross.
- *A plan edit is saved 1.5 s later* (`save_plan`: one save for a burst of
  taps; flushed by `save()`, End turn, leaving the screen, the window losing
  focus or closing, a hot-seat hand-over); `add_order` hands its preview to
  `_replan` instead of computing it twice.
- *End turn answers at once:* the turn resolves two frames after the tap,
  under a "Resolving the turn" dialog drawn first.
Measure with `--prof-tap[=N]` (also `?prof-tap=N` in the web build's URL,
e.g. `?campaign=rome&prof-tap=3`; `game/campaign/tap_prof.gd`) or
`tests/tap_latency.gd` on a desktop; numbers in STATUS "Overworld tap latency".

### Main menu (as built, 2026-10-21)

Owner's call: "we need a proper main menu now. We just have a big group of buttons", the Grand Campaign (online
co-op) apart from the single-player Campaign, "make it look like a modern menu", "try both styles and then choose".
`game/main.gd` builds the pages; the new view code is in `game/menu/` (`menu_prefs.gd`, `menu_style.gd`,
`emblem.gd`, `menu_bg.gd`, `diorama.gd`). View only: nothing in `sim/` or `campaign/` changed.

**2026-10-27, the Campaign page is the story only (bug and reshape).** Owner: "I can no longer start a roman campaign. The
campaign shows Caribbean when i choose either option ... If the campaign is only the single player story we should remove
the Rome selection and not allow choosing of armies, that is reserved for the Grand Campaign." Cause: since the Story panel
went in, the offline new-campaign screen showed it above the faction rows for every setting and its buttons ("Play the story",
"Play with two") call `_start_story`, which forces `PackView.use_pack("west")` (`new_campaign.gd`, `_start_story`); the Rome
card led to a Rome-titled screen whose prominent Start buttons all started the West story. Now: the Campaign page has one
card (`card_story`, "The Brethren's Due") that opens the new-campaign screen with `story_only` (no Setting row, no faction
rows or team buttons; the name, seed and the settings the story reads: Battles, Battle AI, Campaign AI, Deployment, Battle
time; Start plays the one-captain story, "Two captains" is the card below). Rome and the faction pick live only in the Grand
Campaign's Host card (`host_pack_west` / `host_pack_rome` then Host: the faction page, one human at least (2026-10-27: a solo campaign can be hosted on the server, no join code; before it needed two); the
online story card shows on the West setting only). "Your campaigns" and Continue open saves of either setting as before.
`NewCampaign.build_state` is the one place a faction campaign's state is made (tests assert Host + Rome gives a Rome state).

**2026-10-27, offline play restored.** Owner: "The grand campaign should be playable single player without needing to be online or attached to a server." The Grand Campaign page has a third card, Play offline (`offline_card`, since merged into the Host panel 2026-10-30, `offline_pack_west` / `offline_pack_rome` sharing the Host card's pick, then `home_offline`), which opens the faction page with `online` false and `story_only` false: the full faction pick, teams and rules, and Start runs the offline `_start` (a local save, listed under "Your campaigns" and Continue). The cards sit three across from 900 px of page width, stacked below it and on a phone. View only. The offline faction screen shows no story cards (2026-10-27, owner: "why does the brethren story show as an option?"): the Campaign page is the story's home; the Host screen keeps "Host the story" (the two-captains online version).

**2026-10-29, the tutorial's entries.** The Campaign page has two cards: `card_tutorial` "Your first command" (the guided first campaign: a setup with a Name row and a Difficulty row only, `NewCampaign.tutorial_only`, fixed seed) and `card_story`; the title screen has a sixth entry `home_howto` "How to play" (page `howto`, Back to the title screen; eight sections of `howto.gd` as text in the trim panel, scrolling) and the in-game Menu of the campaign and the battle an entry `menu_howto` with the same sections in the column. Options gained "Show the tips again". The lesson cards and tips use the trim panel at the top left (`tutor_card.gd`); the pointer is a ring over the interface (`tutor_pointer.gd`). Built in docs/design/campaign_rules.md "The tutorial (as built, 2026-10-29)". View only.

**Title screen.** The wordmark top-left (the last-played setting's emblem, "STRATEGIC COMMAND" in Cinzel Bold from
`assets/ui/fonts/` when present, else the UI font, and the setting's subtitle), a left-aligned stack of five entries
over a full-bleed background with a dark gradient under the stack (phones, `UiScale.is_touch()` and a logical
height under 520: the stack centred, a flat dim over the picture):
1. **Continue: <name>, turn N** (hidden with no save) with the setting's emblem: the most recent save, local
   (`saved_at`) or online (an online seat has no play time, so `added_at` is the proxy; online reads "Continue:
   <name>, online"). Opens it as the old Continue list did.
2. **Campaign**: two art cards side by side ("The Caribbean, 1650" / "Rome, 280 BC": emblem, `PackView.subtitle`),
   a card opens the existing new-campaign faction page for that setting (`NewCampaign.pack_pick`; the Setting row is
   then hidden); below, **Your campaigns** (local saves of either setting, a row with its setting's emblem, Delete)
   and Import.
3. **Grand Campaign** (online co-op; pass 2, see "Menu pass 2" below): the Host card, the Join card, **Your grand
   campaigns** (rows with the live badges) and the Game server row.
4. **Battles**: Custom battle, Battle sandbox (the old sandbox page, its Back now the page's).
5. **Options**: rows, not cycle buttons (pass 2, below): Display, Looks, Audio, Help; Tests and benchmarks only with
   `--dev` (or `?dev` on the web; the sandbox page's own Tests button likewise; the old `--menu-tests` aid still opens it).
Entries slide in from the left on open (0.25 s each, 0.07 s stagger) and grow 3 % on hover / press with a brighter
label. Every sub-page has a **< Back** at the top-left (`go_back`, parent table `BACK`); Esc (`ui_cancel`) and the
Android back request do the same. The page dim is 0.66 on sub-pages so the centred content reads over any picture.

**The Back rule** (2026-10-23): every full-screen page outside a battle has **< Back** in the top-left corner and nothing
else sits there: the menu's button, at (14, 10), 110 x 40, font 16, `Kit.nav_style` (gold edge on a dark plate). Pages
that follow it: all the menu's sub-pages (the one `_back_btn`, `go_back`), the faction page (`new_campaign.gd`: its top
bar is padded so the button lands on the same spot and size) and the Custom battle page (`custom_battle.gd`, node
`custom_back`; in the online lobby it leaves the room first). Dialogs keep their bottom-row buttons, the battle screens
keep Leave in the battle menu, and Close on books, keys and the unit picker stays a Close.

**Custom battle page** (2026-10-23, house style): a fixed strip with Back and the Cinzel heading "Custom battle", then
one line of explanation and three `Kit.trim_panel` cards with gold `Kit.title` heads. **Battle**: Template, Setting, Sea
battle (a row), the map options as one wrapping flow with "Seed" as a label + field pair that never splits, and
Deployment / Battle time / Funds per side as one row of label + dropdown pairs (sea battles show the wind / water / fleets
here). **Side 1** and **Side 2**: the side cards, side by side from 900 px of width and stacked below it (`_fit` on
resize). **Play**: the check line ("Ready to play solo."), then Play solo, Play online and the friend's code with Join in
one wrapping row. 16 px side gutter on a phone; the page is at most 1100 wide. In the online lobby the room card sits
under the explanation. Node names are unchanged.
Button names are kept for the tests: `home_campaign`, `home_grand`, `home_battles`, `home_options`, `home_continue`
are new; `home_controls`, `home_sandbox`, `home_custom`, `home_server`, `home_soldiers`, `home_quality`,
`home_battle_look`, `home_map_style`, `home_Join`, `home_Import` live on their new pages. (After pass 2 the Options names are capsules: `home_<key>` with its segments `home_<key>_<value>`, e.g. `home_quality_low`; the in-game Menu's use `menu_<key>`; `home_Join` is the Join page's, the card's Join is `grand_join`.)

**Backgrounds** (`[menu] background = diorama_west | diorama_rome` in `user://settings.cfg`, set by
the selector at the bottom of the title screen, see "Background selector" below; `--menu-bg=` forces one for the session
and also takes the old values; a test run that asked for none builds no table, so it never switches the content pack and
the placeholder gradient shows):

(2026-10-30) The painted key art retired (the owner: the AI paintings no longer match the overworld and the battle
map). The backgrounds are the two dioramas only. `assets/ui/keyart/*.jpg` and their imports are deleted; the stored
`art_west` / `art_rome` (and the older `art`, `auto`, `diorama`) migrate to the diorama of their setting (or of the
last-played one). What stands in while a table builds, on the campaign pages' hovered setting card (while no table
shows) and behind the loading panel is the setting's placeholder gradient, `MenuPrefs.PLACEHOLDER`: a dark warm wood
brown for the West, a cooler stone grey for Rome, no picture file (no grain; a device that never gets the table
still has a background, never a missing texture). The selector stays, now the setting pick: Caribbean table or Rome
relief (it also sets the wordmark's emblem and subtitle). The camera is pulled back: the West's zoom 2.6 -> 2.1, Rome's
2.0 -> 1.65, `at` and `shift` unchanged (Port Royal and the Bay of Naples still sit right of the entries at 1280x720
and 844x390; neither view reaches the chart's edge). Testing aids `--menu-zoom=`, `--menu-at=x,y`, `--menu-shift=x,y`.
Build time and frame time are unchanged by the zoom (the West about 2.15 s cold, Rome about 0.92 s; about 27 ms a frame
in the windowed run, which is bound by something other than the table).
- *diorama*: the live overworld. `game/menu/diorama.gd` builds a non-interactive copy of the campaign screen's layer
  stack (MapView, LandTrees, TownLayer, MinisLayer, MapOverlay) inside a SubViewport (the layers use canvas layers)
  on `CState.new_campaign("Menu", 7, [0], {"fog": 0}, [], pack)`, never saved, fog off, at a fixed scene per setting
  (Port Royal from the sea at zoom 2.1; Campania / the Bay of Naples at 1.65), drifting 13 px each way over a 4
  minute sine (about 20 px a minute at its fastest). The map style is forced per scene while it shows (the Caribbean the
  table, Rome the relief map, whatever the campaign map's own setting; it and the stale bake are put back on release). The build is queued as steps that `_process`
  runs one a frame (map, relief, landscape, state, layers, refresh), so the menu is never blocked and freeing the
  node in between is harmless. It holds the content pack (`CData`, `Geo`) of its setting, so it is freed when the
  menu hides (`release()` puts Rome back) and built again when it shows. It is built for the selected
  setting only (one world at a time; the setting's placeholder gradient stands in until it is ready).
- There is no *auto* any more: Quality Low no longer forces the picture; a chosen diorama on Low uses the Low layers
  as the campaign does.
Measured on this PC (RTX 3070, relief cached): Caribbean about 1.0-1.3 s (the first world after a Rome menu also
rebuilds the map geometry), Rome about 0.65 s; the longest single frame is the landscape bake, about 250 ms.

**Background selector** (owner 2026-10-22, after Rome 2's menu): bottom centre of the title page only, a thin gold rule
over `[<]  The Caribbean, the map table  [>]` (`bg_selector`, built in `main.gd`): 44 px nav-style arrow buttons (36 px on
phones) with a chevron drawn in code (the kit has no chevron icon), the name in Cinzel 18 (16 on phones) in bone with a
dark outline. The choices, in order and wrapping: The Caribbean, the map table (`diorama_west`), Rome, the relief map (`diorama_rome`). The arrows, the Left / Right keys and
a 40 px swipe along the name step it; the switch cross-fades the pictures over 0.5 s (`MenuBg.switch_to`) and a diorama
builds as before. The choice is saved at once; old saved values migrate (`art_west` / `art_rome` to the diorama of their setting; `art`, `auto`, `diorama` to
the diorama of the last-played setting; first run: the table of the last-played setting). The wordmark's emblem and
subtitle follow the selected choice's setting; Continue keeps its own save's emblem. Options no longer has a Menu
picture row (the title screen's and the in-game Menu's).

**Emblems** (`[menu] emblems = drawn | painted`; `--menu-emblems=`): `game/menu/emblem.gd`. *Drawn*: code-drawn vector
marks (`Emblem.draw_mark`): the West's black flag on its staff with a compass rose over two crossed cutlasses, Rome's
eagle over a laurel wreath, crisp at any size. *Painted*: `assets/ui/emblems/<pack>.png` (512 px, alpha; a file not
yet imported is read straight from the project folder); a missing file falls back to the drawn mark. Used on the
cards, the Continue entry, the save rows (local and online) and beside the wordmark. Both styles are in the
screenshots; the choice is the owner's.

**Menu pass 2 (2026-10-22: "some of the options and buttons are hard to read. The tooltips should be in a box, not just
a long string").** View only.
- *Boxed tooltips, kit-wide* (`ui_kit.gd`). `Kit.tip(control, title, text)`: a trim panel (dark warm plate, gold rule,
  bracket corners), an optional title (Cinzel 16) over a wrapped body (UI face 14, bone), at most 320 px wide. How: the
  kit's controls are subclasses with `_make_custom_tooltip` (`TipButton` for `Kit.button` / `hero_button` / the menu
  buttons, `TipOption` for `Kit.dropdown`, `TipEdit` for `Kit.text_field`) returning `Kit.tip_box(title, body)`; any
  other control gets the same plate and the 14 / bone type from the default theme's `TooltipPanel` / `TooltipLabel`
  (`Kit.install_tips`, run by every kit control) with "title\nbody" as its text. Desktop delay 0.4 s
  (`gui/timers/tooltip_delay_sec` in project.godot). Touch: `Kit.TipHost` (one node under the root) watches the
  touches; a press that stays within 8 px for 0.45 s on a control with a tip shows the same box above the finger until
  release, and that release is swallowed (a button under it is off for two frames) so reading a tip never gives an order.
  A control with the meta `tip_host_skip` is left alone (the sea screen's order buttons have their own help card). The
  Options, Grand, faction-page and online-panel tips are converted to `Kit.tip` with a short title and two or three
  sentences; plain `tooltip_text` on a kit button is boxed too, without a title.
- *Kit controls*: `Kit.segmented(options, value, cb, name)` (a capsule of choices, the lit one gold; segments named
  `<name>_<value>`), `Kit.toggle` (Off / On), `Kit.slider` (0-100, gold fill, round grabber, 30 px tall), `Kit.dot`
  (status dot), `Kit.field_style` (text fields: dark inset, thin gold edge, gold while focused), dropdowns in the nav
  style.
- *Options* (`game/menu/options_rows.gd`, one builder for the title screen's page and the in-game Menu's): each setting is a
  row, the label (16, bone) with a one-line description (13, dim) left and a capsule right (under the label on phones and
  in the 440 px in-game column): UI size S / M / L, Graphics Auto / High / Low (the description says what Auto is now),
  Soldiers Auto / Compatible, Fullscreen, Battle look Diorama / Painterly, Map view Terrain / Political, Map style Auto / Table / Relief (see "Map view switch" below); the title
  page adds Emblems Drawn / Painted (the menu picture moved to the title screen's selector) and its Help section (Controls, Unit book,
  Tests with `--dev`). Audio: a Sound On / Off capsule and three sliders (master, effects, ambient) with their percent.
  The page sits in a trim panel so it reads over any picture; it scrolls (the Help buttons are at the bottom).
- *Table motion (tabletop pass 5, 2026-10-30)*: a third capsule **Motion / Still** (`home_battle_dive`, in-game `menu_battle_dive`,
  stored `[video] battle_dive = on | off`, default on, `game/table_motion.gd`) shares the Battle look row with Battle view (the same
  `_beside` pair, so the Options page does not grow and does not scroll at 1024 x 576). Motion is the camera's dive onto the table as a
  battle opens (`Battle.dive`, game/battle.gd) and the die that rolls on the campaign's Auto-resolve
  (game/campaign/die_roll.gd); Still turns both off; `--no-dive` does the same for one run. A tap or key skips either. Takes effect at the next battle /
  auto-resolve. Details: docs/design/art_pipeline.md "Pass 5, furniture and motion".
- *Crest ghost (tabletop pass 6, 2026-10-30)*: a fourth capsule **Crest off / Crest on** (`home_crest_ghost`, in-game `menu_crest_ghost`,
  stored `[video] crest_ghost = on | off`, default off, `BoardView.crest_ghost_pref`, `--crest-ghost=on|off`) joins the same Battle look row
  (the `_beside` pair, which wraps on the narrow layouts). On (oblique view only): a man hidden by a crest nearer the camera draws as the faction ghost,
  as men behind a wall do. It costs a pass over the ground, so it is off by default. Takes effect at the next battle. Details:
  docs/design/art_pipeline.md "Pass 6, the hills".

**Map view switch and the Looks rows (as built, 2026-10-25).** The campaign map's bottom-left button showed the
*current* view ("Political" or "Terrain"); on the owner's phone "Political" read as "switch to Political", so the map
looked stuck and he tried the Options "Campaign map" row, which does nothing in the Political view. Now
`map_key.gd` `view_button` (node `map_view_button`) is a two-segment capsule, Terrain | Political (`MapKey.VIEW_W`, two
button widths), the lit segment the current view; the hint clears the wider control. The key list's row reads "Map view:
Terrain". Options (`options_rows.gd`) gains a **Map view** row (same switch, `MapView.set_terrain_view`) and the old
Campaign map row is **Map style** (Auto / Table / Relief, for the Terrain view); picking Table or Relief while Political
switches the view to Terrain. The Looks descriptions and tips now say which setting costs more: Political lightest,
Table heaviest, Relief lighter; Diorama (splatted ground, full-strength shadows) the heavier battle look, Painterly the
lighter. View only; no hashes move.
- *Grand Campaign page* (`main.gd`): the heading and a line, then two trim cards side by side (stacked under 640
  logical wide or on a phone). **Host a grand campaign**: the two settings as mini-cards (emblem, name, year; the lit one
  gold), the **Host** hero button (opens the faction page in online mode for the picked setting), and under it the
  server line with a status dot, "Server: <host> - ready / invite key needed / not reachable / checking...", and a Change
  link. **Join a grand campaign**: the code field (uppercase as typed, 6 or 8 characters, a whole link works), Paste,
  Join; the error or result under the field (the 6 / 8 hint is checked before the server is, so it shows at once) and
  the seats to take ("Play as ...") inside the card; the separate join page stays for `?join=` / `?server=` links.
  **Your grand campaigns**: one row per seat (setting emblem, the campaign's name, your faction's flag and name, "- turn
  N" once the server has answered, the live badge from `Net.badge_for` ("Your turn", "Waiting for X", "N battles
  pending", "Offline"), Resume, and a small x that asks "Sure?" before forgetting); an empty line points at the Host
  card. The **Game server** row at the bottom: "Game server: <address>" with the same dot and Change (the server page's
  Back returns here). `_join_find_in(edit, info, box)` serves both the card and the page.
- *Faction page* (`new_campaign.gd`, both modes): a fixed top bar (Back, the setting's emblem, "New campaign" / "New grand
  campaign" in Cinzel, Start as the hero button, off with the reason as its tip until a human is picked), then the
  instruction line, the **Story** panel (West: cards with a two-line description and a button; online one card), the two
  team buttons, the faction rows (flag 36 px, name 16 bold, the blurb 13 dim wrapped so the row grows, an AI / Human
  capsule, the team dropdown; a human row has a gold left edge), the **Settings** panel of rows (Name, Seed with a
  dice, Victory as two steppers, Victory counts (your regions only / your team's, 2026-10-23), Turn timeout, Battles, AI aggression, Battle AI, Campaign AI, Fog of war, Deployment,
  Battle time; each with a line and a tip) and, online, the **Online** panel (server and Change, Discord webhook, user
  id, invite key). Under 700 logical wide (or a touch screen under 520 high) the rows stack and the Settings panel
  folds under a "Settings" header. Names kept for the tests: `faction_<key>` is now the Human segment of the capsule
  (`ai_<key>` the AI one), `team_<key>`, `start_campaign`, `all_one_team`, `everyone_alone`, `campaign_name`,
  `campaign_seed`, `deploy_time`, `time_limit`, `server_change`, `webhook`, `discord_user`, `invite`.

Tests: `tests/menu_test.gd` (windowed: every entry and Back, Esc and the back request, Continue hidden / shown /
opens, the cards open the right pack's faction page, the server line on Grand Campaign only, Options cycles each
setting and `settings.cfg` is restored, `--dev` entries, both backgrounds build and free, auto follows Graphics,
both emblem styles, the phone layout centred, script errors counted); `input_test` and `touch_scroll_test` now go
through the Options / Battles / Campaign pages.

#### Grand Campaign panel, Campaign Settings fold, server page (2026-10-30)

View only (owner's notes). Nothing under `sim/` or `campaign/` changes.

- **One Host panel.** The Grand Campaign page is two panels (Host a grand campaign, Join a grand campaign; side by side from 900 px of page width, stacked on a phone). The old third card, Play offline, is gone: the Host panel has the one West / Rome pick row (`host_pack_west` / `host_pack_rome`, `_gh_cards`), the Host hero button (`home_Online_co-op`), under it Play offline at the same width (`home_offline`) with a one-line caption, then the server status line. Both buttons read the one `_gh_pack`.
- **Story Campaign and Grand Campaign saves are separate.** The title entry and page are "Story Campaign" (page key `campaign` and `BACK` unchanged). `Saves.list()` adds `story` (1 when the state has a non-null `story`) to each meta; the Story page's "Your story campaigns" lists only those, the Grand page's "Your Grand Campaigns" (below the Host / Join panels, above the server row) lists the other local saves, then the online seats as before. Home Continue stays the most recent of either. Import stays on the Story page (it takes any save).
- **Campaign Settings fold.** On the setup screen Name and Seed stay above; the rest of the Settings block is a section "Campaign Settings" with a chevron header (`settings_fold`, body `settings_body`) that, folded, carries a one-line summary ("Average AI, 15 min battles, fog on"). Folded by default on the Grand setups (Host and Play offline), and on a phone for the story and tutorial; those two open expanded on a roomy screen. The state is remembered for the session only (a static dictionary, "grand" / "story"). Start is in the top bar, so it is reachable without opening. Testing aids: `--new-grand=rome|west` (the offline setup), `--settings-open`.
- **Game server page** (`game/net/server_page.gd`) is one trim panel: display-face titles, dim paragraphs with rules between sections, the current server as a field row (the address in a field-style box, a "default" capsule), the status as a `Kit.dot` (ready green, invite key gold, down red, unchecked dim) and its line, and one button row (Back at the left, Use default and Change at the right). The desktop-only note is a boxed tip. Names (`server_current`, `server_state`, `server_change`, `server_default`) kept.
- **Story cards.** The "Your first command" title overflowed its card (22 px display face in 250 px): cards are 280 x 236, the title 20 px and wrapping. menu_test checks that every child of both cards lies inside its card at both sizes.
- **Rome on the Grand page** (owner: "it still shows all of the Western armies, and then plays the Caribbean map"). Not reproduced as reported; a real leak was found and fixed: `Saves.parse` ran `CState.migrate`, which makes the save's pack the active one, so merely listing saves (home Continue, the Story and Grand lists) left `CData.pack` on the last save read (often West). `parse` now restores the pack. `NewCampaign.build_state` also asserts the screen's picked setting before creating the state, since the title's live table sets the global pack while it builds. menu_test covers Host and Play offline with Rome at 1280x720 and 844x390, with the live table background, and after a West save.


### UI theme (as built, 2026-10-21, pass 1: the kit and the campaign screen)

Owner's call: "the in game menu needs some work. trim, font, anything else". The title menu's dressing (Cinzel, gold
`b08a40` / ink `1a1410` / bone `e8dcb0`, the dark warm panel, the 3 % hover growth, the setting emblems and the placeholder gradients)
now runs through the shared widget kit, `game/campaign/ui_kit.gd` (its header documents the theme: colours, type, trim,
buttons, spacing). View only: nothing in `sim/` or `campaign/` changed. Pass 2 (the battle HUD, the sea screen) is
separate.

**The kit.** `Kit.title(text, size)` is a Label in Cinzel Bold (`Kit.title_font()`; the UI face when the file is
missing), used for titles only (dialog and panel titles, the faction name, the leader card, End turn, loading titles,
city names at the diorama zoom) and never under 18 px (it clamps); body text, buttons and numbers keep the UI face.
`Kit.trim_box()` / `Kit.trim_panel()`: the dark panel with a 1 px gold rule inset 4 px and four corner brackets, drawn by
a StyleBox (`Kit.TrimBox`, no textures); `Kit.draw_trim(canvas_item, rect)` draws the same on a custom control; used by
dialogs, the side panel, the loading panel and the selected unit card. `Kit.rule()` is the gold hairline between
sections. `Kit.button` / `icon_button` (so every kit button, battle HUD included) get the menu's motion: a tween
to scale 1.03 in 0.1 s on hover / press and a brighter hover label; the signals only start a tween (nothing at build
time), a disabled button stays put, and it is off on Quality Low and with `--no-anim` (`Kit.anim_on()`, read from the
settings at most every 2 s; tests force it with `Kit.anim_override`). `Kit.hero_button(text, icon, cb)`: gold-trimmed,
48 px, 18 pt Cinzel (End turn). `Kit.nav_style(button)`: the menu's dark plate with a thin gold edge for the top bar and
the Menu's option buttons, with the default button's margins so rows keep their width. `Kit.emblem(pack, px)`: the
setting's emblem control (painted or drawn by `[menu] emblems`).

**Campaign screen.** Top bar: the setting's emblem at the left, the faction name in Cinzel 18, date, gold, income,
the icon buttons as plates, a gold rule under the bar; below 820 logical px wide (phones) the emblem is hidden and the
name keeps the UI face, so the phone row is as before. End turn is the hero button. The command bar: only the selected
unit card carries the gold trim; the leader card title is Cinzel 18 on desktop (15 plain on phones). The side panel has
the trim, panel titles are Cinzel 18. `show_dialog` (so the "Resolving the turn" wait, confirms, diplomacy / build /
recruit popups and the story cards' frame) uses the trim panel with the title in Cinzel 22 and a rule under it; the
story cards' layout is unchanged. City names are Cinzel at 18-22 px from zoom 1.6 (`MapOverlay.DIORAMA_ZOOM`), the UI
face at smaller zooms.

**The Menu** (the top-right button; `game/campaign/game_menu.gd`): an overlay like the title screen: the map dimmed, a
dark column on the left (440 logical px at most) with the setting's emblem, the campaign's name in Cinzel and the date,
then Resume, Save, Options, Controls, Main menu (a confirm page: "Leave to the main menu?" with Main menu / Stay; the
campaign is saved first). Under a rule: Export save as text and Play online (a local campaign) or the Online page (an
online one), and the state hash. Options holds the title screen's settings with the same saved values (UI size,
Graphics, Soldiers, Fullscreen, Battle look, Map style, Sound and the three volumes) as plate buttons; the cycles are
duplicated from `game/main.gd`'s Options page (a later cleanup could move both into one helper). Esc, the Android back
request and a tap on the dimmed map close it (one step back from Options or the confirm); Controls closes it and opens
the controls page.

**Loading** (`loading_panel.gd`): the setting's placeholder gradient (`MenuPrefs.PLACEHOLDER`, darkened 40 %) behind a trim panel with the title in Cinzel, a one-line tip from `LoadingPanel.TIPS`
(view-side random choice), the progress bar and the step. Used by the campaign start, the battle build and the turn
resolve: "Resolving the turn" shows this panel when the last resolve took over 0.5 s (`last_resolve_ms`, measured in
`_resolve_turn`), else the small dialog as before (the first resolve of a session always the dialog).

Tests: `tests/theme_test.gd` (windowed; the kit, the campaign screen in both settings, the Menu overlay, the loading
panel and the slow resolve, the diorama-zoom labels, the phone layout; `--shots=DIR` saves screenshots).

**Pass 2 (2026-10-22: the battle HUD, the battle modals and Menu, the sea screen; view only).** Shared helper
`game/battle_theme.gd`: the kit's nav plate and a lit variant (a toggle that is on) built once and shared by every
button (no styles allocated per button, so the sea order bar, rebuilt on each selection, costs nothing), the kit's
hover / press motion, a capsule of momentary segments, the top-bar title block and gold rule.
- *Battle HUD* (`hud.gd`): the top bar has a gold rule and, on a desktop only (window 820 logical px or wider, no
  touch), the setting's emblem and the battle's name / terrain ("Battle: 2,000 soldiers - Ridge") in Cinzel 18 beside the
  readout; phones keep the row as before. Every command button is a kit button in the nav plate with the hover / press
  motion; the toggles (Orders, Add, Release, the character acts, the field works) show the lit plate when on. **All /
  Line / Skirm / Shock / Horse / Guns / None** (2026-10-23, roles step 1: was Inf / Missile / Cav) are one capsule (`group_capsule`): momentary, nothing stays lit, 50 x 42 touch
  segments; `group_buttons` keeps its keys and `deselect_button` is the None segment (name `deselect`). Only SELECTED
  unit cards carry the trim (gold rule, corner brackets), as the campaign's command bar. Every button has a boxed
  `Kit.tip` (title and one line; the old long strings trimmed; Run and Halt, which had none, got one). **No touch
  long-press tips in the battle:** HUD buttons carry the meta `tip_host_skip`, because a press held half a second and
  released must still give the order mid-fight; the tip shows on a desktop hover. The end banner (Victory / Defeat /
  Draw) is Cinzel 30 over a trim plate, green / red / gold (the pursuit line stays 20); the result panel of a custom
  battle, the bench panel, the speed popover (gold slider) and the deployment bars are trim panels with a Cinzel title
  and a rule.
- *Battle modals and Menu* (`battle.gd`, new `game/battle_menu.gd`): the End battle / Continue card and the Leave confirm
  (campaign battles) are the dialog frame (trim panel, Cinzel title, rule, plate buttons; the Leave text now sits under
  the title "Leave the battle?"). The top-right Menu of a non-campaign battle (the battles list, custom battles) opens the
  campaign Menu's overlay: emblem, the battle's name, Resume, Options (the title screen's rows, `bmenu_*`), Controls,
  Leave the battle with its confirm (Leave / Stay). Solo, the battle is paused while it is open and the pause put back
  on close (co-op cannot pause: it runs on, as with the unit book); Esc, Resume and a tap on the dimmed field close it.
  **Campaign battles keep the "Leave" button and its confirm** (the grace, the End battle button, the tests that tap
  them); the Back to menu buttons of the result panels still leave at once.
- *Sea screen* (`sea_battle.gd`, `sea_book.gd`): the top bar has the emblem and the title in Cinzel 18 on a desktop,
  a gold rule; the speeds (II 1x 2x 4x) are one capsule with the speed in force lit (a press acts even on the lit one:
  II toggles pause in co-op); Full sail / Battle sail / Heave to and Round / Chain / Grape are capsules with the same
  labels and names; the other orders, Ships, Key, Leave and Douse are plate buttons (lit when on); the boxed tip body is
  the long-press help card's text, and the card itself is a trim panel with a Cinzel title; the ship book's panel and
  page buttons are themed and its titles are Cinzel; the end panel and the Leave confirm are framed.
- *The sea Key* (owner 2026-10-22: "I'm not sure what the different coloured lines mean"): `game/sea_key.gd` holds the one
  list of drawn kinds (`KINDS`) and the one colour function (`col`) the drawing uses, so they cannot disagree. A **Key**
  button on the top bar opens a trim panel (a drawn sample on a strip of sea, a name and one line per kind), closable,
  open / closed remembered in settings.cfg `[ui] sea_key`; the first sea battle of a session shows a 3 s hint pointing at
  it (not when the Key is remembered open). One colour per meaning: the selected ship's ring, course and destination
  ring in her flag's colour (lightened); attack order red; boarding (the target and the grapple ring) gold; fire ship
  (target and lighting reach) orange; flee heading violet (was grey); broadside arcs and range teal (were white); wind
  white (the rose's arrow was pale blue); wake white foam; grapple lines dark brown. Before, the course was cream, the
  arcs, the selection ring and the rose white and the wind arrow blue.
- *Loading*: the battle build uses the themed panel (the placeholder gradient of the campaign's pack, tip, trim; `_enter_battle`) when the
  last build was slow; a sea battle is added directly (as before; its build is fast).
Tests: `tests/battle_theme_test.gd` (windowed; `-- --shots=DIR`, `--phone` for an 844x390 touch layout), `sea_help_test`
(the Key lists every kind, the drawing uses only those kinds, six distinct colours, remembered, the hint), `input_test`
(its Leave text check), `sea_screen_test`, `battle_screen_test`, `theme_test`. Frame time (RTX 3070, 1920x1080, vsync off,
mean ms over 8 s from tick 600, HEAD -> now, 2 runs): bench_2000 paused 3.06 / 2.99 -> 2.94 / 2.85, running 3.19 / 3.02 ->
2.98 / 2.86; bench_4000_city paused 4.89 / 5.43 -> 5.22 / 5.21, running 5.20 / 5.71 -> 5.54 / 5.46: within noise.

### Role badges, filters, the book's groups and the Roles page (as built, 2026-10-23, roles step 1)

View only: the data is the `role` key on every unit row (docs/design/battle_sim.md "Roles, step 1"); no sim change.
- **Badge.** `game/role_badge.gd` draws a tiny tile in the role's colour with its glyph (a rank of bars, a loose scatter,
  a bow, a sword, a horseshoe, a horseshoe with a dot, a gun on a wheel, a fatter gun with a ball, a pennant, a humped
  back), crisp at 14 px. The unit card (`CardFace.role`) shows it at the left of the count (the headcount bar and the
  count move over by 16 px) and a 2 px band of the role's colour along the card's foot; the card's tooltip is the role's
  name and "plays as" text. `game/role_tile.gd` is the same badge as a Control (34 px beside the icon on the unit book's
  page, 22 px at a book group head and on the Keys page), with the "plays as" as its tip. The entry's role line reads
  "Role name: what the row is". (The older display text key `role` of the rows, "Line infantry", is now `what`.)
- **Filters.** The selection bar: **All / Line / Skirm / Shock / Horse / Guns / None**, still one momentary capsule
  (`group_capsule`, 50 x 42 segments; `group_buttons` keys `all line skirmish shock horse guns`, `deselect_button` the
  None segment). A unit's group is `UT.filter_group(type)`: its role's group (`missile` goes with `skirmish`; `guns_field`
  and `guns_siege` with `guns`; `horse_shock`, `horse_skirmish` and `beast` with `horse`), except `command`: a mounted
  one (a general's guard, a mounted hero) is under Horse, a foot hero, an agent or a wagon under Line. Keys 1-6: all,
  line, skirmish, shock, horse, guns (the actions `select_line` ... `select_guns`; the old 2 / 3 / 4 were Inf / Missile / Cav).
- **Book.** The unit list is grouped by role in `UT.ROLE_ORDER` (a group head: badge, role name, the two-line "plays as"
  in small type, hidden when no row of the open setting has the role); Prev / Next and the arrows follow the list's order
  (`UnitBook.next_page`); the Terrain, Settlements and Heroes pages stay last. The entry keeps "Good against" / "Countered by".
- **Keys.** The Keys page ends with a Roles section: the ten roles, each a badge, the name and its two lines.
Tests: `tests/roles_test.gd` (every row has a role in the table, the roster by role, filter groups), `battle_theme_test`
and `input_test` (the capsule and the group steps).

### The battle HUD pass (plan, 2026-10-24; roles step 3 folded in)

The owner, 2026-10-23: "our combat UI is getting crowded"; the reorganisation is done once, now that the roles'
behaviours, the destruction AI and batch 2 have landed. One pass over the bottom bar, the filters, the order
buttons and the cards; the sim is untouched (abilities already take `ORDER_ABILITY` from roles step 2).

**The bottom bar, left to right.** (1) The selection capsule: All / the role groups / None, with **Add**. On a
compact width (phone) its segments show the role badge glyphs (`game/role_badge.gd`) instead of words, 34 px
each, with the tip naming the group; on a desktop width the words stay. (2) The fixed three, always visible with a
selection: **Halt**, **Run**, **Withdraw** (Run keeps its on / off state word). (3) The **ability chips** of the
selected units' roles, in a fixed order per role, only the chips every selected unit's role has (a mixed
selection shows the common chips, then the rest greyed with the tip "not all selected units"). Then (4) **More**:
a single chip at the end that opens a vertical popover with every chip that did not fit, so nothing is ever
clipped (the half-a-button overflow on phones goes away); the fit is measured from the laid-out widths one frame
after the selection changes and again on a resize (`_fit_actions` grows into this).

**Chips.** One widget (`game/ability_chip.gd`): an icon, a short name, a state word under or after it, 42 px
high, 56-96 px wide. Two kinds:
- **Toggles** (the orders that exist today, unchanged in the sim): Fire (at will / hold), Skirmish (on / off),
  Stance (Line / Cover / Hold street), Bounds, Deploy, Refill, Forage, Ammo (the kind), Occupy / Leave, Release
  (dogs), Drop, the heroes' acts, Gift, Waypoints. A tap cycles.
- **Abilities** (roles step 2's table: pistols, grenades, caracole, batter): three states **Auto / Hold / Use
  now**; a tap cycles Auto -> Hold -> Use now -> Auto; **Use now** arms a target pick on the field (the chip reads
  "Use now: tap a target", the cursor as Occupy's, the valid targets lit: units for grenades and pistols, a
  stretch or a building for batter, the enemy unit for caracole), and the pick sends `make_ability_order`; Esc or
  the chip again cancels back to Auto. The chip's state word shows the current state; a unit with no such
  ability shows no chip.
Chips per role (in order): `line` Fire, Stance, Occupy; `skirmish` Fire, Skirmish, Stance, Occupy, Grenades (if
the row has them), Pistols (if the row has them); `missile` Fire, Skirmish, Ammo; `shock` Occupy, Grenades,
Pistols (if the row has them); `horse_shock` Bounds; `horse_skirmish` Caracole, Fire, Pistols, Bounds;
`guns_field` Fire, Deploy, Ammo, Target (men / walls / buildings: Target is the batter ability's Use now with a
pick, plus "men" as Auto); `guns_siege` Target, Fire, Deploy, Ammo; `command` the acts, Gift; `beast` Release where
it applies. Wagons: Refill, Forage, Drop. Waypoints and the dogs' Release go to More on a compact width.

**Cards.** The unit card keeps the role badge and the colour band; it gains a thin state strip under the count:
one glyph per chip whose state is not the default (a hand for Hold fire, a crossed grenade for Grenades on Hold,
a target ring for an armed Use now, a cover glyph for the Cover stance); nothing when all is default, so the cards
stay quiet. The card tip lists the states in words.

**Keys and the book.** The Keys page gets a "Chips" section (what Auto / Hold / Use now mean, the three fixed
buttons, More, the compact capsule's glyphs); the Controls table gains the chip actions where they have keys
(the existing keys for fire / skirmish / stance / run / halt stay; no new key bindings in this pass).

**Fit rule and test.** A new `tests/hud_fit_test.gd` lays the HUD out at 844 x 390 (phone landscape), 1180 x 820
(tablet) and 1280 x 720 (desktop) with selections of each role, a mixed selection and a wagon, and asserts that
no visible child of the bottom bar extends past the viewport, that the fixed three are visible, and that every
chip is either visible or in More. `input_test` and `battle_screen_test` keep passing (the capsule's glyph
segments keep the same keys 1-6 and the same `group_buttons` names).

**Out of scope.** The sea battle HUD; the campaign bar; new abilities; the AI's use of Hold / Use now.

### The battle HUD pass (as built, 2026-10-24; roles step 3 folded in)

View only: nothing under `sim/` changed (the determinism hashes are as before). Code: `game/ability_chip.gd` (new, the chip),
`game/hud.gd` (the bar, the fit, the capsule, the cards' strip), `game/battle.gd` (the ability orders and the Use now pick),
`game/overlay.gd` (`target_lit`), `game/ui_icons.gd` (new icons `grenade`, `pistol`, `caracole`, `target`, `hand`),
`game/controls.gd` (the Keys "Chips" section), `tests/hud_fit_test.gd`. What differs from the plan, and why:
- **The bar.** Halt, Run (its state word), Withdraw are fixed in that order, then `chips_box`, then **More**. Run stays hidden
  when only guns are selected (they cannot run; `input_test` asserts it), so "the fixed three" is Halt and Withdraw always and
  Run unless guns only. The Withdraw army button of the top bar is unchanged.
- **Chips.** Every old toggle button (`fire_button`, `skirm_button`, ... `waypoints_button`, the act buttons, `gift_button`) is
  now an `AbilityChip` (a `Button`, so the names and tests hold); its text stays "Name: state" on one line (the plan's "state
  under or after the name": after), the state-only text on a tight bar. An ability chip is the same widget with `ab` set; its
  state word is Auto / Hold / Use now (Mixed when the selection differs). Chips are 42 px high and at least 56 wide.
- **Order and common chips.** One global order (Target, Caracole, Fire, Skirmish, Stance, Occupy, Grenades, Pistols, Bounds,
  Deploy, Ammo, Refill, Forage, Drop, Release, the acts, Gift, Waypoints) rather than a list per role: a role shows the chips
  that apply to it in that order, which gives the plan's per-role lists. A chip some selected units lack is dimmed (alpha 0.55,
  tip "Not all selected units have it") and sorted after the common ones; it still works for the units that have it.
- **Fit.** `Hud._fit_now` works from the texts' metrics (the same as before) at once and again one frame later (`_refit_later`,
  after the layout) and on a resize, not from the laid-out widths: the metrics need no layout and cannot disagree with it.
  Step 1: full texts; step 2: state-only texts; step 3: what still does not fit goes under More (in order: an armed ability
  first, the common chips, the rest). Waypoints and Release always go to More on a phone width. The popover is a grid
  (`more_box`): one column, more columns when the list is taller than the room between the top bar and the More chip, so it is
  never clipped even in the worst case (all 20 chips under More on a phone: 4 columns). A tap outside, a tap on a chip in it or a
  new selection closes it (`_input`).
- **Capsule.** `_apply_capsule` (at build and on every resize): on a compact width (`BTheme.desktop` false) the Line, Skirm,
  Shock, Horse, Guns segments show the role badge (24 px glyph in a 34 px segment, text empty) and All / None keep their words;
  on a desktop the words at 50 px. `group_buttons` keys, `deselect_button` and the keys 1-6 are as before. The glyph of Horse
  is the horse_shock badge, of Guns the guns_field badge.
- **Ability chips** (`battle.gd`, section "ability chips"). A tap cycles Auto -> Hold -> Use now -> Auto for the selected units that
  have the ability and are ours (`_ability_units`); orders are `make_ability_order` through `_queue` (so lockstep, co-op ownership
  and the deployment whitelist: Auto and Hold pass in the deployment, Use now is not offered there). A view-side prediction
  (`_ab_pred`) shows the new state before the sim applies it (the sim's own state once it equals it, or 40 ticks later). Use now arms
  `ability_armed` (cancelled by a selection change, Esc, the chip again; Esc or the chip sends Auto back to the units): grenades
  pick an enemy unit (a ring on every enemy unit, `overlay.target_lit`) or a shut gate (-2 - g); the caracole an enemy unit; the
  batter lights the standing buildings (the Occupy outline, `overlay.occ_lit`) and takes a building (-2 - b), a wall stretch (the
  stretch index) or a gate (-1: the stretch the destruction AI would batter beside it). A tap that hits no target keeps the pick
  armed and says so. **Pistols are Auto <-> Hold only**: the sim accepts Use now for pistols but nothing reads it, so a pick
  would do nothing. **Field guns have no Target chip** (the sim has the batter for `guns_siege` only, and for attackers at a
  walled town); the plan's list gave `guns_field` a Target.
- **Cards.** The state strip is at the top right of the card (the card is 34 px: no row under the count), up to three 11 px glyphs
  (one on a narrow card) left of the general / hero mark: hold fire (`hold_fire`), a stance that is not the unit's default (Cover
  for a unit whose default is Line, Line for a cover unit, Hold street), an ability on Hold (its icon struck through, red), a Use now
  (a gold target). Defaults show nothing, so a skirmisher in its default Cover stance is quiet. The card's tip lists the same in
  words under the role's "plays as" (`Hud._card_state_strip`, fed by `Battle._card_states`).
- **Keys.** The Keys page has a "Chips" section (the fixed three, the chips, Auto / Hold / Use now, More, the phone capsule, the card
  strip) before the Roles section. No new key binding.
- **Tests.** `tests/hud_fit_test.gd` (headless works, about 8 s; windowed about 4 min with the screenshots): 844x390 (touch,
  dpr 3), 1180x820, 1280x720; a selection of each role present in the test field, everything, line + skirmish + guns, a stress
  selection with every chip applicable, a siege field with the Target chip, the chips' states and the card strip, a resize
  with a selection standing. It asserts nothing past the viewport, Halt / Withdraw (Run unless guns) on the bar, every applicable
  chip on the bar xor under More, the popover inside the viewport, no capsule / actions overlap. `input_test` and `battle_screen_test`
  were not changed (the `Run`, `Halt` order on the bar and the popover are not asserted there).

### Chip options (as built, 2026-10-24)

The owner, 2026-10-24: "Instead of cycling when a button is pushed, show the options above the button as selections." View
only (nothing under `sim/` changed). A tap on a chip with more than one state no longer cycles it: it opens an **options
popover** (`Hud.opt_panel`, built in `game/hud.gd`, section "chip options") directly above the chip, one 42 px row per state
(`OptRow`: the state's word, an icon where the chip has one per state: Fire's `fire` / `hold_fire`, Stance's three, Ammo's
quiver), the current state pressed-lit with a check drawn at the right. Rows: Run, Skirmish, Bounds, Deploy, Refill, Forage
On / Off; Fire At will / Hold; Stance Line / Cover / Hold street; Ammo the two kinds of the selection (`Hud.ammo_kinds`, set
by `Battle._refresh_actions`); Release Ready / Tap an enemy; the abilities Auto / Hold / Use now (Pistols Auto / Hold). The
chip itself keeps its state word. Halt, Withdraw, Waypoints, Drop, Gift, the acts and Occupy / Leave (one word at a time, an
action rather than a state) act at once as before.
- **Choosing.** A row other than the current one sets that state through the old order path: a toggle chip emits its old
  signal once (`_toggle_emit`; the flip is exactly what a tap did), Stance emits `stance_set` (`Battle._set_stance`, shared with
  the key's `_cycle_stance`), an ability emits `ability_set` (`Battle._ability_set`, shared with `_ability_pressed`; Use now arms
  the pick as before, Pistols never Use now, Use now before the battle falls back to Auto). The current row closes it with no
  change. An armed ability chip tapped again still cancels the pick (no popover).
- **Closing.** A tap on the chip again, a press outside the popover (`Hud._input`; the More popover no longer closes when the
  press is on a row), Esc (handled in the HUD before the field's deselect), a selection change, the speed popover or More
  opening (and the other way round). One popover at a time.
- **Placement.** Centred above the chip, kept inside the viewport (shifted at the edges). A chip under More puts it beside the
  More popover (left, else right), else above it, else clamped inside the viewport; More stays open under it, and closes with it.
  `_fit_now` re-places it (or closes it if its chip is gone).
- **Keys** still cycle (`controls.gd` and the `_toggle_*` functions are unchanged).
- **Not built.** The drag from the chip up onto a row and release (it would cross the outside-press rule and the field's touch
  handling); a tap selects.
- **Tests.** `tests/hud_fit_test.gd`: at 844x390, 1180x820 and 1280x720 every multi-state chip's popover (on the bar and under
  More) lists the right states, stays inside the viewport, has 42 px rows, sits above its chip and closes on the chip again; Fire /
  Stance / Run rows send their orders; Esc, a selection change, the speed popover, More and an outside press close it with no
  change; the ability tests choose rows. `tests/input_test.gd`: Fire, Skirmish, Deploy, Ammo, Forage, Refill and Release now
  tap the chip, then the row that is not the current state (`_step_opt_row`); their expectations are unchanged.
- **The Countermarch chip (2026-10-27, docs/AI.md 44.2).** The ability chip of West musket lines (`UT.AB_ROLL`, glyph
  `countermarch`: three ranks and an arrow from the front one round to the rear), in the bar's order right after Fire.
  Auto / Hold / Use now as the others, but its Use now has no target: the row sets it at once (rolling fire at any range,
  no last volley), no pick is armed; before the battle starts it falls back to Auto with the usual flash. The Keys
  "Chips" section has a Countermarch line; the unit page lists "Countermarch: rolling fire by ranks".

### Withdraw at the right with a confirmation (as built, 2026-10-27)

Owner's phone playtest. Halt and Run stay at the left of the action row; the unit Withdraw button is now the row's last
element, after the chips and the More chip, flush with the bar's right edge (its width still counts as fixed in the
fit, and in compact mode it takes the compact width like the others). The More popover stays right-aligned to the More
chip. Pressing Withdraw no longer withdraws at once: a small popover (`confirm_panel`) opens above the button, same
style, placement and close rules as the options popover (kept on screen, Esc or a press outside closes it with no
action) with one line, "Withdraw N unit(s) by your map edge?", and two 42 px rows, Withdraw (emits `withdraw_pressed`,
closes) and Cancel. Withdraw army in the top bar uses the same popover ("Withdraw the whole army? Every unit leaves
the battle.", Withdraw army / Cancel) instead of the old tap-twice text swap (CONFIRM_SEC is gone). Only one popover is
open at a time (More, options, speed and this one close each other). Tests: `tests/hud_fit_test.gd`.

### Chip clusters and the long-press explanation (as built, 2026-10-27)

The owner's words: "I don't know what all of the chits do on the bottom bar in a battle ... maybe we can double stack them, or condense and explain them." First step, view only (nothing under `sim/` or `campaign/`): clusters with captions, and a long-press explanation. The double stack and a legend page are later steps.

**Clusters.** The chips of the bar sit in four groups, in this order, derived from the flat `_chip_order` (which stays the single list a new chip is appended to) by `Hud.CLUSTER_OF`, a chip key -> cluster map; a key not in the map lands in Fight, so a new chip is one map line (the Countermarch ability chip is already mapped, to Shoot, under the key `countermarch`):

| Cluster | Chips |
|---|---|
| Move | Bounds, Deploy, Waypoints, Release |
| Shoot | Target (batter), Caracole, Fire, Skirmish, Ammo, Refill, Forage, (Countermarch) |
| Fight | Stance, Occupy, Grenades, Pistols |
| Kit | Drop, Gift, Sabotage, Attempt, Parley |

- On the bar: a 1 px divider (the bar rule's gold at 50 %, in a 3 px slot, so a divider costs 8 px of the row) between neighbouring clusters, and a 9 px caption (bone at 60 %, drawn by one `ClusterCaptions` control, a top-level child of `chips_box`) centred under each cluster's chips. The caption row is 10 px: `chips_box` is 52 px high (chips 42, shrink-begin, the caption row under them); the other row items (Halt, Run, More, Withdraw, the capsule) keep 42 px at the top of the row, the two notes bottom-align in 42. The bar is 10 px taller while any chip is on it (`bottom_height()` adds `CAP_H` then). No caption at the left of the divider was needed.
- The order on the bar is now cluster order, then the fixed order; the old "an armed ability first" display order is gone (the armed ability still never goes under More, and still gets its room first). The fit counts the dividers' width per chip (a chip of a cluster not yet on the bar costs its 8 px too); a cluster with no chip on the bar has no divider and no caption.
- Under More: the grid lists the same clusters, each with a 10 px heading cell in its first column (padding cells fill the rest of the heading row and the cluster's last row, so a multi-column grid keeps one cluster per band); the column count is the least that fits the clusters' height above More. The headings exist only while More is open.

**Long-press explanation.** A press held 0.45 s on a chip (touch or mouse button, 8 px of slop) opens `explain_panel` above it (placed like the options popover; for a chip under More beside the More popover, `_popover_pos` is the shared placement): the chip's title (gold), "Now: <state>", the tip text (with the "not all selected units" note), one row per state with the options' own words and icons and "(now)" on the current one (Auto / Hold / Use now for abilities; none for a single-action chip), and a "Unit book" row that emits `chip_book_pressed`; battle.gd opens the selected unit's type page (`book_open_chip`). The hold swallows the release (the chip is switched off and on once, which cancels the press), so no tap, no options, no order. Closed by a press anywhere outside, Esc, a selection change, More closing (for a chip under it), or opening any options / More / confirmation; opening it closes those. The mouse hover tooltip is unchanged; the touch tip host (`Kit.TipHost`) skips the chips already (`tip_host_skip`).

**(2026-10-30) Chip options set, not toggle.** The owner: "selecting all 3 musketeers in the tutorial and changing to 'fire at will' does not change it for all musketeers". A row of a two-state chip's options (Run, Fire, Skirmish, Bounds, Deploy, Refill, Forage, Ammo) used to fire the chip's old one-flip signal, and `_choose_option` returned early when the row equalled the chip's value (the max over the selection), so with one company at will and two holding, "At will" sent nothing. Now a row emits `hud.toggle_set(key, value)` and `battle.gd _set_toggle` queues that value for every eligible selected unit (the toggle's own eligibility rule, `_toggle_units`), skipping the units already there; choosing the value everyone has sends nothing (no order, no Undo toast). The one-tap flips (`fire_pressed` and the others, the keys) are unchanged. When the eligible units disagree (`battle.gd _chip_mixed`, set as `hud.chip_mixed` before `set_selection`) the chip's state word is "mixed" (so the explanation says "Now: mixed"), no options row is marked "(now)", and the icon and the cards' glyphs stay as the max. `tests/chip_set_test.gd` (headless).

**Tests.** `tests/hud_fit_test.gd`: at every size and selection captions = the clusters on the bar, inside the chips box, the bar and the viewport, clear of every chip, dividers = clusters - 1 and clear of chips, the clusters in order; the More headings one per cluster present and inside the popover and viewport; every chip's explanation inside the viewport, above a bar chip, title right, state rows, Unit book row, options closed. `tests/input_test.gd`: `_long_press_control` (a 0.7 s touch hold), the Fire chip's explanation opens, no tap fires, a press outside closes it, the short tap after still opens the options.

**Cost.** Row height +10 px (phone 886x409: bottom 143 -> 153 px with chips on the bar, 37 % of the height); the dividers take 8 px each of the row's width: on the probe's selections the bar holds the same chips at 1231x568 and 886x409, one fewer (Stance goes under More) at 866x400 with the skirmish selection and in the "all" selection at 1006x464.

**Open.** The captions are 9 px: legible on a phone but small; a tap on a caption does nothing. The explanation is the tip text; a per-chip longer text and a legend page are later. The double stack (two rows of icon-only chips) is the next step if the row is still too long. The Keys page has a "Clusters" and a "Long press" line.

**The More grid's fit rule (2026-10-27).** With the clusters (a heading row each) and the countermarch chip, the stress selection's grid no longer fitted the room above the More chip at 780x360 and 844x390, and the popover came out wider than the viewport. `Hud._place_more` now counts the panel's padding in the height and the viewport in the width: first a grid with as few columns as fit between the top bar and the chip (never more columns than the width holds); if none does, the clusters flow like text (`MoreBox`, a heading stays with the chip after it, no padding cells), widening in 12 px steps until the rows fit under the bar, then until they fit up to the screen edge (over the top bar); only if even the widest flow is too tall does the popover scroll (a ScrollContainer, vertical). Chips keep their size; `hud_fit_test` passes at all three sizes with every chip inside the popover.

### The double stack and the Chips page (as built, 2026-10-29)

The clusters build's next two steps (owner: "The logos are great but there are a ton. Maybe we can double stack them?"), view only (nothing under `sim/` or `campaign/` changed).

**The double stack.** A fit step between "state-only texts" and "overflow to More" (`Hud._fit_now`, `_two_rows`, `_split_rows`): when the one-row compact fit still leaves a chip for More (the forced Waypoints / Release alone do not trigger it), the bar grows a second row, `chips_up`, above itself (the first child of the bottom box, right-aligned, full bar width, its own `ClusterCaptions`). Every chip on either row is 36 px high (`CHIP2_H`, `AbilityChip.set_h`; 42 with one row and under More), texts state-only as in the compact step. A cluster is never split: the lower row keeps Halt / Run / More / Withdraw and the clusters that fit beside them, the others go up. All splits of the present clusters (at most 16) are tried; the fewest chips left for More wins, then the cheapest clusters upstairs (`UP_FIRST`: Move, Kit, Fight, Shoot, so Shoot and Fight stay next to Halt and Run when both fit). The upper row's chips that do not fit go under More with the forced ones; the armed ability stays on a row. The split is taken only when it leaves fewer chips under More than the one-row fit. On a width where one row holds everything nothing changes.

(2026-10-29) An armed ability chip reads "Tap a target" in the state-only texts (double stack, compact step) and "Use now: tap a target" at full width; `hud_fit_test` accepts the text its mode gives.

(2026-10-29) Scripted runs never touch the player's `settings.cfg` pack preference: `PackView.save_pref` does nothing and `load_pref` answers Rome when `Saves.dir()` is the test folder (tests/, tools/, the testing aids); a "Start the tutorial" press in a test had saved `west` and broke `campaign_input_test` (`faction_rome` missing). The campaign screen's 6 s toast timer captures the toast's instance id, not the node (a freed capture logged "Lambda capture at index 0 was freed").
- Captions: every cluster is captioned under its own chips, on either row (not "once under the lower row": a cluster caption under the other row's chips would point at the wrong chips); each row is chip height + the 10 px caption row, dividers likewise. `cluster_caption_rects()` and `divider_rects()` cover both rows.
- Cost: the lower row is 46 px (36 + 10, was 52), the upper 46 + 5 gap: the bar is 44 px taller than one row in the worst case (phone 866x400 logical: `bottom_height()` 198, was 153; 1180x820 and 1398x645: 162, was 117 with one row), and only while a selection needs it. `bottom_height()` reports `chips_up` while it is visible, so the camera's frame, the pan limits and the co-op toasts rise with it; `chips_up` is in `_ui_controls` (a tap on it is not a map tap).
- Popovers: the options, the long-press explanation and the confirmation sit above their chip as before; when there is no room above (an upper-row chip on a short screen, or a lower-row chip under the taller bar) `_popover_pos` puts them beside the chip, clear of it.
- Probe numbers (`tests/bar_room_probe.gd`, battle_2000, now prints `rows=`, `bottom=` and the upper row): 866x400 guns: up Deploy, bar Fire Refill Drop, More Waypoints; skirmish: up Stance, bar Fire Skirmish Bounds; all: up Stance Bounds Deploy Drop, bar Fire Skirmish Refill, More Waypoints; all at 198 px. 800x800 (guns / skirmish / all) also two rows.

**The Chips page.** The battle menu has a Chips entry (after How to play): `game/chip_legend.gd` builds it from `Hud.legend_entries()`, which reads the chips' own `tip_title`, `tip_body`, glyph and `_chip_rows` (the states' words), so there is no second copy of the text: "Always on the bar" (Halt, Run, Withdraw), then Move, Shoot, Fight, Kit, each chip with its glyph, name, states ("Fire - At will, Hold") and its full tip. The page scrolls with the menu column (`TouchScroll`); Back sits beside the title because the page is long. The Keys page keeps its Chips section and gains a "Two rows" line.

**Tests.** `hud_fit_test`: at every size and selection the upper row is hidden or inside the viewport, above the lower row and clear of the cards and the capsule, chips 36 high (42 with one row), a cluster in one row only, captions and dividers per row, `bottom_height()` at least the bar; the stress bar is double stacked at every size under 2000 px and not at 2560; an armed ability stays on the bar with two rows; the More popover still fits; every chip's explanation is above its chip or beside it, clear of it. `input_test`: the menu's Chips page (every legend row, the four headings, the Fire row's states and tip, Back) and a tap on an upper-row chip opening its options.

**Open.** A single chip on the upper row costs 44 px of map (a guns selection at 866x400); the other order (taking Drop or Deploy to More before opening a row) is a rule change if the map is wanted more. The legend is the tip text, not a longer one.

### The last-seen ghost (as built, 2026-10-27)

Line of sight (docs/design/battle_sim.md "Cover and line of sight") hides an enemy unit from a side with no memory, which on a field drawn in full reads as a glitch. View only, part (1) of the plan in STATUS (the sim's sight linger is part (2), another build): `game/last_seen.gd` (`LastSeen`, held by the overlay as `last_seen`) is called once a frame from `Overlay._process` for the viewer's side (`player_side`; each co-op peer its own). An enemy unit that was drawn at the last update and is `hidden_from` now gets a record: centroid, formation front, facing, files, alive count, the men's positions (copied once, at that moment; none on Graphics Low) and the wall-clock time. A hidden unit never seen since the battle began gets none. The record clears at once when the unit is not hidden (seen anywhere), is destroyed or the battle has a winner; it is never refreshed while hidden, so nothing about where the unit really is leaks.

Drawn by `Overlay._draw_last_seen` over the markers: the men as frozen grey dots and a faint grey footprint fill, 55 % alpha fading to nothing over `GHOST_FADE` 4 s; the footprint outline (55 % to 20 %) and a smaller grey marker with a "last seen" word under it stay until the record clears. The reveal ring (`REVEAL_FX`) is untouched. A ghost is never selectable and never a target: `_marker_unit` and `_pick_unit` still skip hidden units, so a tap on it is a tap on the ground; no order path changed. No sim read beyond `hidden_from`, the unit arrays and the soldier positions; no hash, no lockstep input.

**As built, not as briefed.** The frozen men are dots drawn by the overlay, not sprites in the soldier layer: the layer's shaders (GPU texture path and the CPU path) have no grey or frozen flag, a third path-pair change was not worth the risk, and the overlay costs nothing while no unit is a ghost. No hover tip (the word on the marker carries it). Test: `tests/ghost_test.gd` (asym_woods: a ghost appears with its last place, stays through the fade, clears when seen again, destroyed or at the battle's end; Low keeps no men).

### HUD chrome in the table's language (as built, 2026-10-27)

Part 4 of the visual pass (`overworld_view.md`), one pass through the kit. The fills and contrast stay (phones over a busy
map); no text size, padding or hit area changes: every line is drawn inside the old rect and the content margins are the
ones the StyleBoxFlat had.

- `game/rule_box.gd`: one StyleBox (the fill, an inked double rule: the 1 px edge line in the state colour and a lighter
  line 2 px inside it, rounded like the old plate; optional 4.5 px diagonal corner ticks; optional wood band with a brass
  bottom rule). Built by `Kit.rule_box(col, margin, radius, edge, marks)` and `Kit.band_box(col, margin)`.
- Plate buttons (`Kit.nav_style`, the battle plates and lit plates in `battle_theme.gd`, the menu's page buttons in
  `menu_style.button_style`): the double rule at 1 px, no ticks; hover / pressed keep their edge colours (dim gold, gold,
  bright gold), disabled stays grey.
- `Kit.panel` and the battle HUD's own boxes (stats panel, cards bar): the double rule with corner ticks.
- Dialogs, the side panel, popovers (More, options, the chip explanation, confirmations) and tooltips use `Kit.TrimBox`
  (already the trim): it gained the second, lighter rule 2 px inside the ink edge, ahead of the old gold rule and brackets.
- Top bars: the campaign bar is a `band_box` on `Kit.WOOD_BAND` (the diorama board's brown, hue 7:4:2, at a quarter to a
  third of its value) with horizontal grain: rows of 2 to 3 px cut into soft lighter and darker streaks along the bar
  (a deterministic hash, no randomness), and a brightened brass rule on its bottom edge. The mean luminance is held at or
  under the old flat bar's (measured on the screenshot: 0.0033 against 0.0043 relative), so the bar text keeps its contrast
  (60 % of the board's tone would be three times as bright and cost contrast); the lighter and darker streaks balance.
  The battle's bar is `BTheme.bar_band()`, a mouse-ignoring Panel in the same box (alpha 0.88) behind the buttons, down to
  the old hairline. Quality Low draws the rules only (the fill and the rules, no grain).
- Not changed: the segmented capsules (their own StyleBoxFlat, trimmed margins), the hero button (End turn, its 2 px gold
  trim), the game / battle menu columns. `theme_test` reads the top bar's `border_width_bottom` from the RuleBox mirror.
- Measured: `bar_room_probe` room numbers identical before and after; `hud_fit_test` as before (the 2 stress More-popover
  FAILs at 780x360 / 844x390 are the same at the base commit).

## Building icons for the natives (2026-10-29)

`game/ui_icons.gd` has four new building glyphs in the existing stroke style, shown through
`CData.chain_icon(c, f)` (west.gd `CHAIN_NAMES`): `lodge` (a longhouse: gable roof with its ridge pole, a low
door; the War lodge), `hunting` (a bow drawn back on a nocked, feathered arrow; the Hunting ground), `canoe_yard`
(a dugout canoe on two blocks with a paddle across it; the Canoe yard) and `trading_post` (a stockade gate with
a hanging scale; the Trading post). The Palisade is the existing `palisade` glyph (stakes on a bank) and the
Milpa / Gardens the `farm` ear. They sit after `walls` in `UiIcons.NAMES`; no `_w` twins (the natives' only).
The build popup rows read "Unlocks: ..." / "Effect: ..." under each chain (docs/design/campaign_rules.md).

### Confirm orders and the placement tool (as built, 2026-10-30)

**The owner's report (phone play):** "The phone version has lots of accidental clicks or movements of the armies ...
Right now accidental clicks mid battle result in troops turning around in battle and getting wrecked." The cause:
with units selected any single tap on the board was a move order (keep frontage), so a stray tap behind an engaged
line turned it round, the selection never cleared, and stray taps come from pinch / pan gestures that end with one
finger still down and from palm and thumb contacts. View only: nothing under `sim/` or `campaign/` changed; the orders
are still `make_move_order` through `_queue`, issued later and once.

**The setting.** `[ui] confirm_orders` = auto | on | off (`game/confirm_orders.gd`; `--confirm-orders=` overrides it, tests
set `ConfirmOrders.force`), default auto. Auto is on while the last input on the field was a finger (`Battle._last_touch`:
set by every non-emulated touch press, cleared by a mouse click or a right press; it starts as `UiScale.is_touch()`), off
for the mouse. Options has the capsule Auto / On / Off beside UI size (same row, as Battle view shares Battle look's:
the page keeps its height, `menu_test` checks it at 1024 x 576). The Controls page has two rows (battle section): the
Placement tool and Stray touches; the touch cells of Move, Run, Line and Undo say what changes. The tool works in the
battle phase only (2026-11-02: the deployment too, see "The tool in the deployment phase" below).

**The tool** (`game/battle.gd`, section "confirm orders and the placement tool"; drawing in `game/overlay.gd`
`_draw_place`; the toolbar and the toast in `game/hud.gd`). With confirm on and units selected, a tap on the ground
(also on one's own footprint away from a marker, and the second tap of a double) or a line drag places a ghost and orders
nothing. One unit: a line ghost, its own frontage at the tap, facing the way it would travel (exactly the files it has
until an end handle is used); a line drag: a line ghost along the drag (one rank at most); two or more units from a tap:
the group's shape (`_group_move`'s offsets), moved and turned as a whole. The ghost is the order preview's: the footprint of
each unit (cyan-gold), the line, the dots of the men (woods green, walls red), the town routes and the facing arrow
(`_draw_preview` is reused for a line ghost through `preview_a` / `preview_b`; the sim's order rules do the predicting).
Handles, drawn upright in the oblique view like the markers (`_up`): **body** (a cross; drag to move), **front** (a
triangle ahead of the line; drag to turn, 15 degree steps, a soft stop within 5 degrees of the facing it had and of facing the
nearest enemy, with a word beside it), **ends** (a line only; drag to widen or narrow, the far end fixed, one rank long
at most). The nearest handle's centre wins where circles overlap (27 px on touch, 20 px with a mouse). The ghost is world
state in the view (it survives pan and zoom, the handles keep their screen size); a new selection, a two-finger tap, X, Esc
or a direct attack drops it. Re-tapping the ground elsewhere places it again.

**The toolbar** (HUD chrome: the popovers' trim box): **Go** (one move order for each unit, the run if lit; then the
selection clears, `_select(-1)`: tapping a card or symbol reselects; Enter too), **Run** (starts lit when every selected
unit runs; a double tap lights it; unlit by hand it sends walks), **Waypoint** (the ghost goes out as the next stop after
the current move, the waypoint tool stays on and the selection stays; the next ghost is the next stop, Go the last),
**X**. Beside the ghost on a wide window (first of right, left, above, below that fits between the bars and clear of the
handles), docked above the card bar on a phone or a touch device (`Hud.layout_floaters`). Attacks and shots (a tap on an
enemy or its symbol), the chips, Withdraw, the gate / building / wall / ability taps stay direct orders and keep the
selection, as with confirm off.

**Gesture guards (always, whatever the setting).** A finger down within 300 ms of a pinch or two-finger pan ending is a
stray: its tap is dropped (`tap_after_gesture_dropped`; a drag from it is a normal drag). A finger that moved past the pan
threshold (18 px) was never a tap (as before: with a selection it draws the line, without it pans). With confirm off, a tap
that would move a selection containing a unit in the fight (`u_fighting[u] > 0`, read only) must be held 0.25 s; a quick
one orders nothing and says "Hold to order a fighting unit" once a battle (`hold_to_order`). Only touch taps: a right click
and the tests' direct `_tap` calls are never held back.

**The Undo toast.** The Undo button is now inside a toast above the card bar (docked above the toolbar when both
show) with the order's words: "Pike 4: line, 60 m", "Heavy: move", "3 units: attack" (one unit: its short type name and,
when there are several of that type, its number; a batch of several: the count and the first order's kind; a drag ghost
sent by Go: "line, N m"). It shows `UNDO_SHOW_SEC` (6 s), the batches and the key (Ctrl+Z) are unchanged;
`hud.undo_button` is the same Button (name `undo`, in the toast), `Hud.set_undo_toast` shows and hides it.

| Input (touch) | Confirm off (today) | Confirm on |
|---|---|---|
| Tap the ground | move, keep frontage (a fighting unit: held 0.25 s) | ghost at the tap |
| Double tap the ground | move running | the ghost's Run lit |
| Drag with a selection | line order | line ghost |
| Tap an enemy / its symbol | attack | attack (the ghost drops) |
| Handles, toolbar | - | move / turn / widen; Go, Run, Waypoint, X |
| Tap within 300 ms after a pinch or pan | dropped | dropped |
| Two-finger tap | deselect | drops the ghost and deselects |
| Chips, Withdraw, gates, buildings | direct | direct |

**The tool in the deployment phase, and the Undo toast under the popovers (as built, 2026-11-02, view only).** The owner's
phone report: "The positioning tool doesn't show during the deployment phase" and "The undo button floats in front of the
'run selection' chit in the battlefield menu". (1) `Battle._confirm_on` required the battle phase, so a tap or a line drag
in the deployment placed at once (the old instant path) and no ghost, handles or toolbar showed. It now holds in the
deployment too (the same setting: Auto is on after a touch). The ghost is the same; `_place_zone_fit` holds each footprint
to the sim's own rule (`BattleSim.deploy_clamp`: outside the side's zone goes to its nearest point, a unit that can man a
wall snaps to the wall, a refusal in a settlement zone is marked and flashes "Place your units in the blue zone" at Go);
Go sends the same move orders, which `_queue` already turns into `ORDER_PLACE` in the deployment (and refuses where another
unit stands); Waypoint and Run are disabled there (`Hud.set_place_bar(..., run_ok)`: nothing marches, `ORDER_RUN` stays the
chip's), no Undo toast (placing is free); a change of phase drops the ghost (`_place_phase`). With Confirm off (the mouse)
the instant placement is as before; the deployment's pick-up, group move and rotate are untouched. Test: `_step_pd_*` in
`tests/input_test.gd`. (2) The toast and the toolbar were built after the chip popovers, so they drew over them: with the
Run chip's long-press explanation open ("Run or walk: the selection's pace.") the toast sat across it. They now sit under
the popovers in the draw order (`Hud._build_place_ui` moves them below More / options / explanation / confirmation), and the
toast steps aside (hidden, due time kept) while a popover reaches it (`Hud._popover_rects`, `undo_wanted`). The docking
reads the top of the bar's visible content (`_bar_top`: the chip rows, actions, capsule, cards) rather than the bar
container's rect alone, and on a wide window the toolbar's slot beside the ghost avoids the toast's. Test:
`hud_fit_test._undo_toast_check` at every size including a portrait phone 393 x 851 (toast and toolbar clear of every chip
and button of the bar, inside the viewport, under the popovers, the toast back when the explanation closes).
`tests/hud_undo_shot.gd` takes the shots (`--explain`, `--ghost`, `--menu`, `--ctl`, `--stress`, `--late`, `--flow`).

**Attack as the last waypoint (the owner's addition, view built against the sim contract).** "Waypoints are working well,
can we add attacking as a point?" In the waypoints tool (the lit Waypoints chip, the toolbar's Waypoint flow, Shift + right
click) a tap on an enemy unit or its symbol no longer attacks at once: it queues `make_attack_order` with `"append": 1`, which
the sim appends as the final waypoint (a record whose flags carry `WP_ATTACK`, x the target unit; nothing can follow it; an
ordinary attack when no move is under way). The sim's `chain_from` entries carry `"attack"` (-1 for a stop); the final attack entry is
at the enemy's place now (it follows the enemy each frame), `chain_end` skips it (the men's last place to stand is the stop
before), `Overlay._draw_chain` draws crossed swords in a red ring with the dashed link from the last stop, a tap on the dot
removes it like a numbered one (`_wp_remove` re-issues the rest, the attack as an appended attack order; the second tap of a
double that added it is ignored), and the tool stays on until the selection changes. Test: `_step_wa_*` in `tests/input_test.gd` .

**The caracole's phase (the owner's second addition, view only).** The owner saw pistoleers close, stand back at skirmish range and
"not seem to attack" and took the 30 s pistol reload for a bug. `Traits.caracole_text` reads `sim.car_on`, `u_car`, `u_crk`:
"Firing" (1), "Wheeling" (2), "Reloading 18 s" counting down from `CAR_RELOAD` for pistol riders (range <= `CAR_PISTOL_R`; muskets
"Reloading"), nothing at 0. It is the card's state word (`Hud.update_cards`; a narrow card shows F / W / R beside the count; the
tip's summary has the words), and a small label under the floating marker (`Overlay._draw_markers`). The Caracole chip's tip says "A double
tap on the enemy charges home" and the How to play battle line says what the drill does and that Hold or a double tap is a charge.
Finding: the double tap did NOT set the sim's `charge` key (only `run`), so a double tap on a caracole row's own target was ignored
in phases 2 and 3 (`_apply_unit`) and did not end the drill (`_car_order`); the view now sets `"charge": 1` on the attack orders of a
double tap (a key the sim already reads; no sim change). Test: `_step_car_*` in `tests/input_test.gd`.

**What differs from the brief, and why.**
- A tap with several units selected places the group's shape (as `_group_move` did) with a body and a front handle but no
  end handles; only a single unit or a drag has a width to change. A group dragged as a line is a line ghost with the end
  handles (the units share the length by their men, as the line order does).
- Tap-and-hold, three-finger group moves (`three_finger_move`, Alt+drag) and the box select are untouched: the three-finger
  move already shows its own ghost and places on lifting a finger.
- The mouse with Auto is off, so a right click orders as before; with On the right click and right drag place the ghost and
  the left button drags the handles.
- The deployment phase is not covered (placing there is instant and free). *Superseded 2026-11-02: see the paragraph after
  the table.*
- The Undo toast replaces the bar's button: the bar loses a 58 px item.
- `--demo-place=dx_m,dy_m[,deg]` (with `--select=`) puts a ghost up for screenshots and `--frame-stats`.

**Tests.** `tests/input_test.gd` runs its old steps with `ConfirmOrders.force = "off"` and a block of placement steps with it
on (a ghost by tap, by drag, moved by the body handle, turned by the front handle, widened by an end handle, re-placed, the
Run toggle, Go sends exactly one order and clears the selection, the toast names it and its Undo takes it back, X, a tap on
an enemy attacks, a double tap lights Run, a group's Go, the Waypoint button, a two-finger tap drops it; the guards: a tap right
after a pinch is dropped and one 450 ms later is not, the quick and the held tap on a fighting unit with confirm off).
`tests/menu_test.gd`: the Options capsule beside UI size, its stored value, the Controls page rows.

**Open.** The handles are small at the widest zoom-out (they keep their screen size, so a very small ghost has overlapping
handles: zoom in); the front handle has no "snap off" key for the mouse (hold nothing: 15 degree steps always); a ghost does
not follow units that stand on a wall walk; the toolbar's Run does not know the guns (they never run); the group tap ignores
a unit that cannot stand on the spot (the sim's refusal shows after Go as ever); the hold guard is touch only and does not
cover line drags; a short phone playtest should decide whether 300 ms and 0.25 s are right.


**The shared capsules are captioned (2026-10-31, view only).** The owner's phone shot of Options showed S M L and then Auto On Off
with nothing naming the second capsule (the description line that did was dropped on short screens). Every capsule placed with
`OptionsRows._beside` now sits in a caption unit: a 12 px `COL_DIM` label (its `tip_title`: Confirm orders, Battle view, Table
motion, Crest ghost) over the capsule. The row's own capsule (S M L, Diorama / Painterly) sits in a unit too, so the capsules stand level: its caption line is blank, wide
or narrow (the row label names it; in narrow mode it sits right under that label). In narrow mode the pair is a `Kit.flow` filling
the row's width (a flow shrunk to its minimum is only as wide as its widest child and wrapped every unit onto its own line), so the
units sit side by side when they fit and wrap as wholes when they do not. At fit level 3 (the shortest
wide page) the caption moves to the left of its capsule (the unit turns horizontal) so the row keeps its height and
`menu_test`'s 1024 x 576 no-scroll check holds. The captions are not in `descs`, so they stay at every level; the shared rows'
description lines lost the sentences that only named the capsules.

### Rome emblems (as built, 2026-10-30)

The owner: "the roman side needs symbols for their flags and armies. I think it is still only color right now." Cause:
`FactionEmblem.KEYS` held only the West's eight, so Rome's factions fell back to the colour swatch (`Kit.faction_mark`)
and a colour-only pennant; only the painted menu crests existed for them. View only; nothing in `sim/` or `campaign/`
changed.

`game/faction_emblem.gd` now draws eight more, keyed by the FACTIONS `key` (so `has()` is true and every caller picks
them up with no other change: `Kit.faction_mark` for cards, Diplomacy, Realm, the battle screen's lists and the command
bar; `map_overlay._standard` for the overworld armies; `tabletop_marks.draw_standard` for the battle standards). The
motifs follow the painted crests (`assets/ui/crests/rome/*.png`), not the first brief where they differ:

| key | motif | field |
|---|---|---|
| rome | gold spread eagle (head, two wings, tail) | red c8402f |
| carthage | gold elephant with a palm on its back (the crest's; not the sign of Tanit) | purple 7a4fc4 |
| macedon | Vergina sun, 16 rays (8 long, 8 short), gold with a brown edge (the crest's helmet is left out) | cream |
| epirus | cream eagle over the Molossian hound (the crest's pair; the eagle is a smaller cousin of Rome's) | orange e07a2a |
| greeks | Corinthian helmet in profile, bronze, eye slit and nose guard | blue 3f7fd8 |
| syracuse | two gold dolphins round a ship (the crest's ring, without Arethusa's head) | teal 2fa8a0 |
| iberians | falcata (curved blade) beside a round shield | brown 8a5a2b |
| gauls | gold boar with a bristle crest under a carnyx | green 3c9a3c |

Style as the West's: flat shapes, the INK outline, the faction colour (or the crest's cream for Macedon) as the field.
Below 22 px (`simple`) the Rome shapes drop their ink edges (`_re`) and the finer details (the eye, the palm trunk) so
the silhouette reads at the standard's 13 px; the West code paths are unchanged (the West half of
`tests/emblem_gallery.gd` is pixel-identical to before, apart from a strip of background below the old sheet). The
painted crests stay for the menu under the painted emblems setting. `tests/emblem_gallery.gd` renders both packs
(West top, Rome bottom; 96, 16, 24 and 32 px on dark and light grounds).

**Open.** The motifs are code-drawn approximations: the elephant's palm trunk is hidden behind its back, the dolphins read
as a ring at 16 px, the Epirus hound is crude; a painted-style pass or a sprite sheet would do them justice. Carthage's
sign of Tanit and the Iberian horseman were not used because the crests show other things; if the crests change, change
these. The STATUS "Crests" item "Rome's references are plain shields" is about the painted crests' references and is
untouched. `tools/menu_art/render_refs.gd` still says Rome has no drawn emblem (its comment and the Rome references are
for the painted crests' generation; a re-render would now use these marks).

### Control groups (as built, 2026-11-02)

The owner: "We need to add control groups." View only (nothing under `sim/` or `campaign/`; no lockstep input, no hash): the
groups are `Battle.control_groups` (`game/battle.gd`, section "control groups"), n 1..9 -> unit ids of the player's side, kept
by each co-op peer for itself, empty at the start of a battle. A unit may be in several groups; a unit destroyed or gone off the
edge (`u_state >= U_DESTROYED`) drops out of every group, a group left empty goes (`_cg_sync`, every 0.25 s with the cards and
after each edit). In co-op only units this player commands (`_mine`) are kept.
- **Keys** (`controls.gd` rows `group_select`, `group_set`, `group_add`; `Battle._on_key` reads the digit before the table):
  Ctrl+digit sets the group to the selection (replacing it), Shift+digit adds the selection, the digit selects the group
  (replacing the selection), the same digit again within 0.4 s (`GROUP_DOUBLE_MS`) centres the camera on the group and keeps the
  selection. A flash at the group says "Group 3 (4 units)" / "Group 3: 4 units". **Moved binding:** the digits 1-6 were the role
  buttons' keys (all, line, skirmish, shock, horse, guns); they are now **Alt+1 to Alt+6** (Ctrl+A still selects all). The Keys
  page and its Chips section say so; `input_test` presses Alt+2. Known: browsers keep Ctrl+1..8 for tab switching, so on the web
  build Ctrl+digit may not reach the game (Shift+digit and the chips do); the owner's eye.
- **Chips** (`hud.gd`): a fifth cluster "Groups" (after Kit; `CLUSTERS`, `cluster_of`: any chip key starting "grp"): a chip per
  group that exists (38 px wide, the digit; `AbilityChip.set_min_w`), lit while the selection equals the group, and a "+"
  chip while a selection exists and fewer than nine groups do (touch and narrow screens only, `not BTheme.desktop`; a desktop
  keeps its bar's width and makes groups with the keys, its group chips appear once a group exists). They are ordinary chips of
  `_chip_order`, so the fit, the double stack (`UP_FIRST` starts with Groups: it goes upstairs first), the captions, dividers
  and More work unchanged. With nothing selected the chip row still shows (the group chips only; Halt, Run and Withdraw hide
  with no selection) so a group can be selected from nothing. A tap selects (`group_tapped`), a second tap within 0.4 s centres;
  "+" makes the next free group from the selection (`group_new_pressed`). A long press (the 0.45 s hold) opens the options
  popover (`_open_group_options`, the `opt_panel`): "Group 3 (4 units)", "Tap selects, tap again centres.", and the rows Set
  to selection, Add selection, Clear (`group_edit`); the two first are disabled with no selection. Tip: "Group 3 (4 units): tap
  selects, tap again centres the camera, hold for options ...". The Chips page has one "Groups" entry; the Keys page's Chips
  section a "Groups" line and three key rows.
- **Badges:** `CardFace.group_text` draws a small dark tab with the gold numbers at the card's top left ("2", "1 3", "1 2+":
  the first two groups, then "+"); `Overlay.group_tags` draws the same tab at the unit's field marker (top right of its disc,
  `_draw_markers`; own side only). The standards at the tray's corner carry no digit (the marker is the cheap place).
- **Selection says it:** the lit chip and the flash say "Group 3 (4 units)". The selection capsule (All / Line ... / None) has
  no text of its own, so it was not made to carry the sentence.
- **Deployment:** groups work in the deployment as any selection does; a selection that changes drops the placement ghost as it
  always did, assigning a group does not change the selection and leaves the ghost; chip taps do not reach the field.
- **Tests:** `hud_fit_test` `_groups_check` (0, 3 and 9 groups at all six sizes: chips on the bar xor under More and inside the
  viewport, "+" on touch only, the fit checks, the badges inside the cards, the Undo toast clear of the chips, the chips with
  nothing selected); `input_test` steps `_step_cg_*` (Ctrl+digit sets and replaces, the digit selects, again centres, Shift+digit
  adds, a destroyed unit drops out, a chip tap selects, the long press opens the options and Set / Clear / "+" work).
  `tests/groups_shot.gd` takes the shots (`--mode=one|two|empty|hold|deploy`, `--crop`).
- **Known:** on a phone the Groups cluster often takes the upper row (the bar is 198 px tall with one chip row of its own);
  nine groups in the stress selection leave some chips under More; groups are not saved between battles; a card's tip does not
  list its groups; the digits' old meaning moved to Alt (a window manager may take Alt+digit).

### Cover chips and hittable marks (as built, 2026-11-06)

The second pass of line of fire and cover (docs/design/battle_sim.md "Cover and line of fire, second pass (as built,
2026-11-06)"); the owner wants a Company of Heroes kind of read of cover and lines on the phone. View only
(`game/overlay.gd`; nothing hashed: caches refreshed once a sim second).
- **Cover chip** (`_draw_cover_chip`, `chip_state`): every ready unit's marker carries a disc at its upper left (the
  control-group tab's pattern: a small token on the disc, drawn upright in the oblique view), green for heavy cover,
  yellow for light, a dark empty ring for none, against the nearest enemy unit it sees within 250 m (its facing with
  none), for what its troop type gets (`BattleSim.cover_rating_front` with `cover_who`: a musket line behind a 1.3 m
  yard wall yellow, a rider there nothing). A dark tick on the rim points at the threat (the covered side). A held
  building or a wall's walk reads heavy. Engines, ships and characters carry none; riders show only heavy. At least 5
  CSS px in radius (`logical_px`: the camera's zoom times the window's stretch, the device's CSS pixel ratio from
  `UiScale`).
- **Hittable / blocked marks** (`_draw_hit_mark`, `hit_state`): while a missile unit of this player with shot left is
  the primary selection, each enemy it sees within its reach (`range_vs`) gets four green ticks round its marker when
  the unit has a line of fire to it, a struck red ring when a house, wall or crest is between (`BattleSim.lof_units`,
  the sim's own unit-level answer); cached per pair per sim second.
- **The range ring cut at houses** (`_house_cut`): a flat missile weapon's ring is pulled in, ray by ray (72), to the
  face of the first house, wall, tower or shut gate in the way (`lof_works_block`), cached per unit per sim second (the
  lob rule's ring already pulled in at a wall).
- **The preview's text** (`_draw_blocked`, `_plate_str`): "NO LINE OF FIRE" / "NO LINE OF FIRE: MOVING AROUND" on a
  dark plate, at least 12 CSS px; the way to the spot reads the sim's kept spot (`_fire_spot_steady`: it changes only
  when the sim keeps another; with none kept, one search a sim second, not every frame).
- **The destination shield** (`_draw_dest_cover`) asks with the unit's troop type too.
- Tests: battle_screen_test `_cover_cases` (both views: the chips' ratings and tick, the marks blocked behind a house and
  hittable beside it). Shots: session scratchpad `cover2/shots/` (order, marks, chips, wall_line; 844 x 390 and 393 x
  851, top and oblique).
- Known: the "none" ring is faint at a distance; the marks and the chip are not on the unit card; a chip on every
  marker adds clutter in big battles (the owner's eye); no device check.

**Third pass (as built, 2026-11-06;** docs/design/battle_sim.md "Cover and line of fire, third pass"**).** The second
evaluation (session scratchpad `eval2/eval2.md`) found the chip misleading in town fights: line troops read "none" 97 %
of the time and the ring was invisible at 844 x 390; a pike block beside a garrisoned house read green while the
windows cut it down (26 lost per 100 balls against 19 with no chip), because the chip was rated against the nearest
enemy, and a house counted as cover from the men at its own windows.
- **Rated against the shooters** (`_chip_eval`, `_chip_threats`, `CHIP_SHOT_T` 3 s): the enemy units that shot at the
  unit in the last 3 s (`BattleSim.cover_shooters`: the sim notes each unit's two latest shooters when a missile is
  launched at it, `u_sbu0` / `u_sbt0` / `u_sbu1` / `u_sbt1`, read by nothing in the rules), the worst rating among
  them; with nobody shooting, the nearest enemy it sees as before; the tick points at the threat rated (`chip_state`'s
  fifth element is that unit).
- **No cover from a garrison's own house** (`cover_rating(..., skip_b)`, `held_building`): the cells of the building
  the threat holds do not count toward the rating against it.
- **Nothing for open ground**: the faint ring is gone; heavy is a small green shield, light a yellow shield filled on
  its left half, both at least 7 CSS px tall with a dark rim (readable at 844 x 390: session scratchpad
  `cover3/shots/`).
- **The cut range ring without spikes** (`_ring_open`): the 72 rays' house cuts get a grey-scale opening (the least
  within 2 steps either side, then the most of those), so a ray reaching the full range down a street between houses a
  few metres off (a reach narrower than 25 degrees) is pulled in to its neighbours; wider open sectors and every cut
  stay. The hittable marks are unchanged.
- Measured (`chip_truth3`, the evaluation's 8 West town battles, line troops, men lost per 100 balls aimed at the unit
  in the next second): heavy against shooters 3.4 (52 unit-seconds), none against shooters 13.9, none against a
  shooting garrison 19.6; the false green against a garrison (before 79 unit-seconds at 26.2) is down to 11
  unit-seconds with no loss. Cover troops: none against shooters 7.5, against the nearest 1.8.
- Tests: battle_screen_test `_cover_cases` (the chip rated against a unit that shot at it; the opening pulls in a
  two-step spike and keeps a wide sector), custom_battle_test `_check_cover3` (the sim's shooters and the garrison's
  house). Known: the chip still is not on the unit card; still no legend; no device check.
### Suppression chips (as built, 2026-11-06)

The fifth pass of cover (docs/design/battle_sim.md "Suppression (as built, 2026-11-06)"): what a unit under fire can no
longer do must read on the phone at a glance. View only; it reads `BattleSim.supp_state` (the sim's hashed state).
- **The marker chip** (`Overlay._draw_supp_chip`): a suppressed unit's marker carries a small dark-rimmed plate at its
  upper right (the cover chip sits at the upper left) with one yellow chevron pressing down onto a bar; a pinned unit's
  plate is red with two chevrons (Company of Heroes' grammar: the chevrons say "pressed down", not a shield). At least 9
  CSS px tall (18 device px on a phone; the cover chip 7: this state changes what the orders do). Drawn for every
  side's ready units: the enemy's pinned line is the reward for the fire.
- **The unit card and the tokens** (`Battle._card_states`): "Suppressed" / "Pinned" first in the card's state strip
  (new UI icons `suppressed` and `pinned`: the chevrons), so it is the glyph a narrow card keeps; the marker's
  tokens show the same (yellow and red bodies, `Overlay.TOKEN_BODY`).
- **The order line's text** (`Overlay`, the attack order's branch): a pinned unit's attack order reads "PINNED: CANNOT
  CHARGE" (melee) or "PINNED: SHOOTING FROM HERE" (missiles) on the dark plate at least 12 CSS px, beside the unit.
- **The men's stand-in crouch** (the sheets have no crouch pose; a real one is a sprite action, about an agent-day):
  each formed man of a suppressed unit is drawn squashed toward his feet, to 76 % of his height and 94 % of his width,
  a pinned man's to 60 % and 90 %, and a little darker (10 %, 20 %); the top view's figure shrinks round his place to
  86 % / 76 %. A miniature pressed low on the table. It scales the placed quad, so the frame and its texels are the
  sheet's own. Both soldier paths and the 3D view: the CPU-fed flags + 64 x level (`SoldierLayer.F_CROUCH`; the 3D
  view's cards read the same buffer), the texture path's block 8 + 2^20 x level (`CROUCH_B8`; `soldiers.gdshaderinc`
  `crouch_k`, `crouch_top`, `crouch_tint`; `soldier_bases.gdshaderinc` strips it before the wall height).
- Tests: battle_screen_test `_supp_cases` (top, oblique, 3D: the state, the crouch level in the flags and the CPU
  buffer's column, the card strip and the tokens, suppressed then pinned). Shots: session scratchpad `sup/shots/`
  (844 x 390, top, oblique and 3D, suppressed and pinned).
- Known: no legend; the chip adds to the marker's clutter in big battles; the crouch is a squash, not a pose; no device
  check.

### Suppression chips, second pass (as built, 2026-11-06)

The fourth evaluation (session scratchpad `eval4/eval4.md`, legibility at 844 x 390) found the marker chip and the order
plate readable, but the squash read as pale mushrooms in the oblique view and lumps in the top view, the card strip's
10 px pinned glyph read as a red square with a cross, and the word "Pinned" never showed at the strip's width. View
only, with the sim's second pass (docs/design/battle_sim.md "Suppression, second pass (as built, 2026-11-06)").
- **The crouch** (`soldiers.gdshaderinc` `crouch_ob`, `crouch_top`, `crouch_tint`; the sheets still have no kneeling or
  crouching frame, so it is still the placed quad, not a pose). Oblique: the figure keeps its full width (the
  narrowing made the round shields and hats into discs) and is lowered, a suppressed man to 90 % of his height and a
  pinned one to 80 %, and leaned toward the way he faces (the card's top sheared by 14 % / 28 % of its height: a man
  hunched over his piece); darker by 14 % / 28 %, the state tint's colour darkened with the shade, so a selected or
  under-fire unit no longer washes pale. Top: the figure shrinks round his place to 88 % / 78 % and darkens the same,
  so a pinned line reads as small dark heads beside the dead lying full size. 3D: the squat card of the first pass
  kept (it read best there). Shots: session scratchpad `sup2/shots/` (`crop_line_oblique.png`: a musket line pinned
  side-on, leaning toward its enemy; `crop_line_top.png`; `pinned_3d.png`).
- **The card** (`Hud.CardFace`): the strip's suppression glyph is drawn as the marker's chip (`_supp_glyph`: a dark-rimmed
  plate, one yellow chevron on a bar or two red ones, thicker strokes) instead of the 11 px line icon; and the count line
  says the state where the card is wide: "58 Pinned" in red, "45 Suppressed" in yellow (beside the shot count, where
  the whole word does not fit, "Supp."), on a dark plate so the colour reads over the side's bar. The state comes
  before the morale word (which stays in the tip and the summary); a narrow card keeps the glyph alone.
- **The marker chip** (`Overlay._draw_supp_chip`): the pinned pair of chevrons flatter and further apart, so at 9 px they
  no longer close into a cross.
- **The legend** (the battle menu's Chips page, `Hud.legend_entries`, `chip_legend.gd`): a new heading, "Marks on the
  units", with three rows: Suppressed (one yellow chevron: fires at 70 %, cannot run or charge, clears a few seconds
  after the fire stops), Pinned (two red chevrons and the men crouch: fires at 35 %, crawls, cannot charge, morale drains;
  holds while the fire goes on; charge it now, or move out; one company does not pin a line behind a wall, two do; men
  in a building can be suppressed, never pinned) and Cover (the green / half-filled yellow shield at the upper left).
- Known: the crouch pose proper is a sprite action per set (pose functions, a re-pack, the oblique sheets and the 3D
  cards taking the same frames: about an agent-day of art, eval4's estimate 8 hours); no device check.

### The 3D battle view's camera (as built, 2026-11-06, view only)

docs/design/art_pipeline.md "The 3D battle view, step one" has the view itself; this is its setting and its controls.

- **The setting.** Options > Looks > Battle view gains a third capsule, **3D**, beside Top and Oblique (`[video] battle_view =
  3d`; the default stays Oblique; takes effect at the next battle; on the web it fetches the oblique sheets' pack as Oblique does,
  and a battle without them is drawn from the top). Graphics High turns the lamp's shadows on, Low off.
- **The camera** is the oblique view's (the same zoom levels, the fit, the clamp, the dive, the pinch and pans) plus a free turn in
  yaw and a tilt from 25 to 60 degrees (40 the start). The battle opens facing the player's side. A turn keeps a little inertia
  when let go (decays in 0.35 s); there is no snapping (the men's sheet directions step every 45 degrees as they do when the men
  turn; the houses swap renders every 90).
- **Touch.** A two-finger twist turns the table about the fingers' midpoint once it passes a dead zone of 8 degrees (so a
  pinch or a pan does not turn it; the dead zone's turn is then applied at once), while the pan and the pinch go on as in the other
  views. The twist is read once a frame from both fingers' latest places (the touch events come a finger at a time, so a
  parallel pan would otherwise swing the line between them). Three fingers with nothing selected (there is no group to move) turn the table as they drag across and tilt it as they
  drag up or down (down: more from above). One finger and three fingers with a selection are unchanged (select, drag orders, pan
  with nothing selected; the group move). (A two-finger vertical drag stays a pan: it is the phone players' common pan, which
  input_test checks.)
- **Mouse and keys.** A right drag with nothing selected (Alt + right drag with a selection; any right drag in a battle you only
  watch) turns the table across and tilts it up and down, about the screen's centre (the spike's orbit: 0.3 degrees a pixel across,
  0.2 up and down); a right drag with a selection still lays out a line, a right click still orders. Q / E held turn the table
  (when no group move is under way; during one they still turn the group), Home / End held tilt it. Middle drag, W A S D and the
  arrows pan, the wheel and Page Up / Down zoom, as before. The Keys page lists "3D view: turn the table" and "3D view: tilt the
  camera" in the battle's view section.
- **Taps and the overlay.** Every tap, drag and long press goes through the same board transform as the other views
  (`Battle._screen_to_world` -> `BoardView.to_world`, now the 3D camera's inverse onto the board's ground), so orders land where
  tapped at any yaw and tilt; the overlay (selection, previews, the placement tool's ghost and handles, range rings, cover chips,
  hittable marks, deployment zones, group badges, standards, smoke) is drawn in 2D over the 3D through the lift shader with the
  yaw (`game/board_lift3d.gdshader`); the Paths hatch is drawn by the board's own shader. The HUD is unchanged.
- **The drag box (as built, 2026-11-06).** The owner, after turning the table: "The way the drag rectangle is drawn is also
  different. It is cool, but the square should be drawn from the screen and projected down the same way that Rome and Company
  of Heroes do it." In the 3D view the mouse's left-drag box (Shift adds) is now the screen's rectangle: drawn square to the
  screen from the point pressed to the pointer (`Overlay.box_sa` / `box_sb`, viewport px, drawn upright through the lift
  shader so neither the board's tilt nor its turn reaches it; before, the two corners' ground points made a world rectangle laid
  on the turned board, a rotated parallelogram on screen), and it picks the player's units whose marker, centre or any living man
  projects inside it (`Battle._box_end`: the corners' board points, the board's space being the screen's up to the camera's
  scale and offset; each man through `BoardView.to_board`, the 3D camera's projection of the ground). Any yaw and tilt.
  The Top and Oblique views are unchanged (their world rectangle is already nearly square to the screen there). Touch has no
  box select (a one-finger drag pans or draws the order line, as before), so nothing changed on touch. Tests: v3d_test 4b (a box
  round a unit's men at yaws 0 / 120 / 240 draws the dragged screen points and selects exactly the units whose men, marker or
  centre the Camera3D projects inside), input_test's box steps (the drawn corners checked in the 3D view).

### The battle's loading bar (as built, 2026-11-06, view only)

The owner: "we should add a loading bar to the battle sandbox, sometimes it can take a minute for the battle to load once you hit
start." View only: nothing under `sim/` or `campaign/` changed; the sim is still built whole, in one step (`BattleSim.setup`), and
the view's layers are built around it, so both peers' setup order is what it was.

- **The plate** (`game/battle_loading.gd`, a CanvasLayer under the oblique pack's own download bar): over the battle from the
  Start tap (the sandbox's scenarios and settlement sieges, a custom battle solo or online, a campaign battle, the tutorial's)
  until the first playable frame. The wood of the table (`LoadingPanel.keyart`) covers whatever has been built so far and
  takes the taps; on it a rule-box plate (`Kit.panel`) with the battle's name in the display face, a brass bar in a rule-box
  trough and the phase in hand on one line. The plate itself fades in only after `SHOW_SEC` (0.4 s), so a load that is quick
  shows nothing but the cover; the cover and plate fade out in 0.18 s once the first frame is drawn. Fits both phone windows
  (the project's logical size is at least 800 x 400, the plate 360 x 124 at most). The campaign battle's old one-step
  `LoadingPanel` ("Preparing the battlefield", shown only after a slow build) is gone: it is the same setup, so it gets the same
  plate (`CampaignScreen._enter_battle` just adds the battle).
- **The setup as steps** (`Battle.LOAD_STEPS`, `_load_run`): `_ready` is the old body cut at its natural seams into 12 methods
  (`_ld_scenario`, `_ld_sim`, `_ld_board_terrain`, `_ld_city`, `_ld_works`, `_ld_soldiers`, `_ld_trees`, `_ld_overlay`, `_ld_v3d`,
  `_ld_hud`, `_ld_connect`, `_ld_finish`), in the same order. A staged battle (`Battle.staged`, set by `main.gd`'s four starts
  and the campaign's two) awaits a frame before a step when the last one took over 20 ms (and before the first), names the
  phase on the plate ("Drawing up the armies", "Laying out the town / ground", "Painting the board", "Raising the buildings",
  "Setting out the works", "Placing the figures", "Planting the trees", "Marking the orders", "Building the table" (3D only),
  "Setting the controls", "Last touches"), and the bar is the share of the step weights done (`LOAD_STEPS`, about the measured
  shares; a step that does nothing in this battle, the town of a field or the 3D table of another view, weighs 0). On the web,
  while the oblique pack downloads the plate says "Fetching the battle sheets" and its bar follows the download, then starts again.
  Nothing is playable until `loaded`: `_process`, `_input` and `_unhandled_input` return early, the cover swallows taps, and the
  plate is released one drawn frame after the last step. No threads (the web build is single-threaded; this is frames, not
  workers). An unstaged Battle (every test and tool that builds one) runs all steps inside `_ready` as before, `loaded` true when
  `add_child` returns. `tests/battle_loading_test.gd` checks both, and that the staged sim hash equals the unstaged one.
- **Waiting for a staged battle:** `Battle.loaded` / `Battle.loading` and the signal `load_done`. `tests/input_test.gd` and
  `campaign_input_test.gd` hold their step runner while any node of the root has `loaded == false` or a plate; `main.gd`'s `--shot`
  counts its frames from the first playable one. Testing aids: `--load-hold=K` (stop before step K for good: shots of the plate),
  `--load-slow=MS` (MS more in each step), `--quit-after-load`, `--scenario-wait=SEC` (start the `--scenario` after SEC s in the
  menu), `--no-warm`, `--warm-now`; on the web `?quality=low|high`, `?battle-view=top`, `?no-warm=1`, `?warm-now=1`;
  `server/cmd/webprobe` gained `waitlog:TEXT:MS` (wait for a console line).
- **Timing** (`Battle.load_timings`, printed as "battle load: N ms tap to frame (lead, steps, frames, first)"; `tests/load_timing.gd`
  builds a scenario twice in one process, cold then warm, one machine load for both). lead = tap to the setup's start (the web's
  oblique pack download); frames = the frames awaited between steps (the plate's draws, plus whatever the engine did in them:
  shader compiles on a cold cache); first = the last frame, the first one the player sees. This desktop (RTX 3070, 1280 x 720)
  was shared with other jobs the whole time (load average 18-37 on 16 cores), so absolute numbers are 1.5-3 x a quiet machine's;
  the cold row and the warm row of a case were taken seconds apart. Warm: the warm-up below done (`--warm-now`), the mapgen
  column taken from the cold row (the second build of one seed found it cached) and the total adjusted for that.

Desktop, a first Start in a fresh process (cold) against one after the menu's warm-up (warm), ms:

| scenario | view | q | start | total ms | mapgen | sim | board+terrain | city | soldiers | trees | 3D | HUD | other | frames | first frame |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| battle_2000 | top | high | cold | 6361 | 1 | 249 | 668 | 0 | 648 | 0 | 0 | 209 | 19 | 3341 | 1227 |
| battle_2000 | top | high | warm | 735 | 1 | 150 | 344 | 0 | 72 | 1 | 0 | 71 | 4 | 69 | 20 |
| battle_2000 | top | low | cold | 1275 | 1 | 214 | 297 | 0 | 357 | 0 | 0 | 105 | 16 | 180 | 104 |
| battle_2000 | top | low | warm | 757 | 1 | 247 | 309 | 0 | 63 | 0 | 0 | 68 | 4 | 48 | 16 |
| battle_2000 | oblique | high | cold | 2334 | 1 | 233 | 574 | 0 | 980 | 4 | 0 | 78 | 14 | 292 | 157 |
| battle_2000 | oblique | high | warm | 1137 | 1 | 250 | 557 | 0 | 129 | 2 | 0 | 71 | 6 | 98 | 23 |
| battle_2000 | oblique | low | cold | 1904 | 1 | 226 | 406 | 0 | 792 | 0 | 0 | 86 | 13 | 221 | 155 |
| battle_2000 | oblique | low | warm | 785 | 1 | 168 | 282 | 0 | 121 | 0 | 0 | 97 | 5 | 57 | 55 |
| battle_2000 | 3d | high | cold | 2413 | 0 | 215 | 432 | 0 | 802 | 0 | 231 | 71 | 18 | 577 | 67 |
| battle_2000 | 3d | high | warm | 673 | 0 | 149 | 269 | 0 | 62 | 0 | 59 | 69 | 4 | 45 | 16 |
| battle_2000 | 3d | low | cold | 2434 | 0 | 234 | 436 | 0 | 828 | 0 | 256 | 84 | 14 | 493 | 85 |
| battle_2000 | 3d | low | warm | 586 | 0 | 122 | 215 | 0 | 71 | 0 | 52 | 66 | 4 | 40 | 15 |
| west_town | top | high | cold | 2600 | 330 | 291 | 442 | 634 | 329 | 165 | 0 | 69 | 12 | 238 | 89 |
| west_town | top | high | warm | 2009 | 330 | 359 | 409 | 619 | 64 | 66 | 0 | 65 | 4 | 73 | 20 |
| west_town | top | low | cold | 2332 | 333 | 342 | 362 | 411 | 334 | 163 | 0 | 67 | 14 | 207 | 98 |
| west_town | top | low | warm | 1711 | 333 | 345 | 352 | 416 | 57 | 66 | 0 | 63 | 4 | 56 | 18 |
| west_town | oblique | high | cold | 2884 | 330 | 359 | 610 | 562 | 627 | 102 | 0 | 48 | 11 | 172 | 61 |
| west_town | oblique | high | warm | 1722 | 330 | 328 | 323 | 471 | 64 | 68 | 0 | 65 | 4 | 51 | 17 |
| west_town | oblique | low | cold | 2942 | 327 | 357 | 505 | 458 | 752 | 160 | 0 | 65 | 13 | 219 | 86 |
| west_town | oblique | low | warm | 1773 | 327 | 357 | 349 | 454 | 62 | 66 | 0 | 63 | 4 | 73 | 17 |
| west_town | 3d | high | cold | 3570 | 333 | 345 | 526 | 432 | 770 | 167 | 241 | 68 | 13 | 567 | 107 |
| west_town | 3d | high | warm | 1764 | 333 | 368 | 364 | 432 | 72 | 41 | 32 | 46 | 3 | 60 | 12 |
| siege_city | top | high | cold | 1511 | 60 | 208 | 34 | 364 | 331 | 136 | 0 | 76 | 11 | 214 | 76 |
| siege_city | top | high | warm | 1037 | 60 | 311 | 35 | 371 | 53 | 38 | 0 | 69 | 4 | 74 | 21 |
| siege_city | top | low | cold | 1584 | 163 | 319 | 59 | 185 | 355 | 134 | 0 | 69 | 16 | 196 | 86 |
| siege_city | top | low | warm | 995 | 163 | 365 | 36 | 181 | 56 | 41 | 0 | 76 | 5 | 50 | 21 |
| siege_city | oblique | high | cold | 2388 | 88 | 309 | 81 | 598 | 771 | 140 | 0 | 74 | 16 | 243 | 69 |
| siege_city | oblique | high | warm | 1125 | 88 | 348 | 41 | 384 | 59 | 40 | 0 | 72 | 6 | 68 | 19 |
| siege_city | oblique | low | cold | 2267 | 92 | 318 | 49 | 386 | 834 | 172 | 0 | 71 | 15 | 240 | 89 |
| siege_city | oblique | low | warm | 941 | 92 | 315 | 40 | 228 | 64 | 39 | 0 | 66 | 4 | 75 | 19 |
| siege_city | 3d | high | cold | 2178 | 71 | 221 | 51 | 321 | 620 | 85 | 180 | 70 | 16 | 476 | 66 |
| siege_city | 3d | high | warm | 990 | 71 | 316 | 39 | 243 | 56 | 38 | 60 | 65 | 4 | 82 | 15 |
| siege_city | 3d | low | cold | 2626 | 90 | 307 | 53 | 414 | 771 | 136 | 246 | 77 | 15 | 458 | 57 |
| siege_city | 3d | low | warm | 956 | 90 | 314 | 37 | 209 | 53 | 26 | 62 | 64 | 4 | 68 | 29 |

Web export in headless Chromium (software GL, the same load): the best of the runs per case and phase (13 of the 18 cases; the top
runs of the first pass were oblique, the page had no `?battle-view=top`). download = the oblique pack (16 MB, localhost, 4-40 s
under the load: on a phone it is the first minute); steps = the sum of the phase columns (the phone's CPU time); frames and first
frame are software-GL render time and say little about a GPU. Not measured warm (every warm run timed out at 240 s under the
load); expected from the desktop pair: the soldiers column ~1.2 s -> 0.2 s, trees 0.4 -> 0.1 s, board+terrain -0.2 s.

| scenario | view | q | steps ms | download | mapgen | sim | board+terrain | city | soldiers | trees | 3D | HUD | other | frames | first frame |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| battle_2000 | top | high | 3856 | 54 | 2 | 349 | 1772 | 0 | 1475 | 1 | 0 | 235 | 22 | 4080 | 4452 |
| battle_2000 | oblique | high | 2565 | 4305 | 1 | 266 | 754 | 0 | 1027 | 411 | 0 | 94 | 12 | 1114 | 746 |
| battle_2000 | oblique | low | 1648 | 4299 | 1 | 196 | 476 | 0 | 845 | 0 | 0 | 119 | 11 | 1019 | 435 |
| battle_2000 | 3d | high | 4268 | 4280 | 0 | 258 | 494 | 0 | 970 | 0 | 2468 | 69 | 9 | 7460 | 1896 |
| battle_2000 | 3d | low | 4026 | 4298 | 1 | 196 | 523 | 0 | 873 | 0 | 2361 | 63 | 9 | 6236 | 1100 |
| west_town | top | high | 5524 | 43 | 480 | 594 | 1302 | 1521 | 891 | 336 | 0 | 378 | 22 | 3559 | 4253 |
| west_town | oblique | high | 6118 | 6844 | 423 | 560 | 1023 | 1094 | 1572 | 1291 | 0 | 145 | 10 | 2693 | 1770 |
| west_town | oblique | low | 4101 | 8830 | 450 | 482 | 742 | 661 | 1279 | 313 | 0 | 160 | 14 | 2555 | 1206 |
| west_town | 3d | high | 7933 | 13456 | 476 | 599 | 1193 | 741 | 2135 | 690 | 1917 | 164 | 18 | 27160 | 572 |
| siege_city | top | high | 2047 | 21 | 105 | 276 | 114 | 775 | 428 | 199 | 0 | 139 | 11 | 1700 | 565 |
| siege_city | oblique | high | 3708 | 6597 | 119 | 400 | 120 | 1154 | 1309 | 437 | 0 | 158 | 11 | 2059 | 675 |
| siege_city | oblique | low | 3721 | 12860 | 180 | 447 | 241 | 879 | 1481 | 318 | 0 | 155 | 20 | 2832 | 1012 |
| siege_city | 3d | high | 11585 | 40099 | 265 | 933 | 431 | 2167 | 3402 | 432 | 3690 | 222 | 43 | 40966 | 16090 |

- **Where the time goes.** (1) Five static caches the first battle of a process builds on the Start tap, desktop ms each in
  isolation: the soldiers' procedural atlas 266 (`SoldierLayer._make_atlas`, a per-pixel loop), the tree atlas 145, the oblique figure
  sheets `SpriteOb.ensure` 689, the kit sheet `KitOb` 210, the 3D kit meshes `Kit3D` 159: 1.47 s of 2.3-3.6 s, about 5 x that on
  the web. (2) Per battle, the sim's own construction (mapgen 330 on a West town, 60-160 on a Rome city, 0 on a field; `sim.setup`
  210-360), the ground (the veg texture's loops 135, the height texture 140, a town's rock and land kit about 300), the town (the
  streets' raster 370, the kit's shadow bake 85 for the land kit and 185 for a West town's, none in 3D), the trees 85-170, the
  3D table 180-250, the HUD 50-80. (3) The first frames: 60-110 ms on a warm shader cache, 1-5 s on a cold one (the web's
  every launch). Not found: a bake that runs twice (the city's kit and the land kit are two bakes, none in 3D), `kit3d.res`
  reloaded per battle (static; so are the sheets), a kit rows build that grows badly (houses 1 ms, instances 0.2 ms), a
  decode on the main thread that repeats (the ground tiles load from the importer's cache in 13 ms; `_raw` of the kit atlases 5 ms).
- **What was fixed.** (a) The warm-up (`game/battle_warm.gd`, started by `main.gd`): from 4 s after the menu is up, one of the five
  caches every 1.2 s (only what the Battle view in use needs, on the web only once the oblique pack is mounted, never headless,
  never once a battle is open or starting), so a first Start finds them built: desktop warm against cold, the same minute: west
  town oblique 2.9 -> 1.7 s, 3D 3.6 -> 1.8 s, siege city 2.4 -> 1.1 s, a field 2.3 -> 1.1 s. The price is one 0.15-0.7 s hitch (desktop) a
  second apart in the menu, about 5 x that on the web, none after the fifth. (b) Graphics Auto's first-3-seconds fps check
  (`TerrainLayer._process`) counted from the terrain layer's build, so a load of more than 3 s ended Auto on Low for the session
  with the fps of the load; it counts from the first playable frame now (`restart_measure`): a phone that loads slowly but runs
  well keeps High, one that runs under 40 fps still drops. (c) Testing: the web's `?quality=` and `?battle-view=top`.
- **Tests.** `tests/battle_loading_test.gd` (new: unstaged ready at once, staged not ready on its first frame, the plate, the
  cover, the plate clear for a quick load, the bar only rises, the phases named, the same sim hash, the plate released, its fit),
  battle_screen_test (three views), custom_battle_test, hud_fit_test, input_test, menu_test, campaign_input_test, theme_test,
  lockstep_test, determinism_test --only=deploy, v3d_test, `check_scripts.sh` and the web export with `webcheck -v3d`: see STATUS.
- **Known.** The plate shows the setup's steps, not time: a step of several seconds (the sim's construction on a slow phone) leaves
  the bar standing, the phase text says what it is on; the bar's weights are the desktop's shares; the plate has no Cancel (the
  oblique pack's own bar does, while it downloads); a sea battle (`game/sea_battle.gd`) has no plate; a step's frame is
  awaited only when the last took over 20 ms, so a phone that runs steps in 30 ms gets a frame per step; the warm-up is a hitch
  in the menu and was not tried on a phone; the web cold shader compile on the first frames is not touched; the cold-vs-warm
  mapgen saving of a repeated seed is the engine's cache, not the warm-up.
