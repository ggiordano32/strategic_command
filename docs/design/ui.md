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
desktop sizes on any monitor), times an S / M / L setting (0.85 / 1 / 1.18,
menu "UI size", saved in `user://settings.cfg`). CSS size and touch come
from `window.innerWidth` and `matchMedia("(pointer: coarse)")` on the web,
the screen scale and DisplayServer natively; stretch stays canvas_items, so
the battlefield is drawn at full window resolution. Never laid out smaller
than 800 x 400 logical. A 780 x 360 CSS phone is 886 x 409 logical; a
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
- Two-finger tap deselects all (touch, battle only): both fingers down within
  120 ms, both up within 250 ms of the first touch, each moved under 12 px;
  pinch / pan motion cancels it (`TWO_TAP_*` in `game/battle.gd`).
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
under collapsible class headers with the best tier of each line and a
"+n tiers" chip for the lower ones; an army card opens with a composition
strip (class glyphs with unit counts) that folds the unit rows (armies of up
to six units start open). Fold state is per session, never in the campaign
state.

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
132 px (96 on a phone: narrower than 700 or lower than 560 logical px, one
horizontally scrolling row); the map key buttons, the End turn row, the hint
and the toasts rise above it while it shows. Versions before 6 keep the side
panel only. Testing aids: `--details` / `--no-bar` (the old behaviour).

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
Button names are kept for the tests: `home_campaign`, `home_grand`, `home_battles`, `home_options`, `home_continue`
are new; `home_controls`, `home_sandbox`, `home_custom`, `home_server`, `home_soldiers`, `home_quality`,
`home_battle_look`, `home_map_style`, `home_Join`, `home_Import` live on their new pages. (After pass 2 the Options names are capsules: `home_<key>` with its segments `home_<key>_<value>`, e.g. `home_quality_low`; the in-game Menu's use `menu_<key>`; `home_Join` is the Join page's, the card's Join is `grand_join`.)

**Backgrounds** (`[menu] background = art_west | art_rome | diorama_west | diorama_rome` in `user://settings.cfg`, set by
the selector at the bottom of the title screen, see "Background selector" below; `--menu-bg=` forces one for the session
and also takes the old values; a test run defaults to the picture so it never switches the content pack):
- *diorama*: the live overworld. `game/menu/diorama.gd` builds a non-interactive copy of the campaign screen's layer
  stack (MapView, LandTrees, TownLayer, MinisLayer, MapOverlay) inside a SubViewport (the layers use canvas layers)
  on `CState.new_campaign("Menu", 7, [0], {"fog": 0}, [], pack)`, never saved, fog off, at a fixed scene per setting
  (Port Royal from the sea at zoom 2.6; Campania / the Bay of Naples at 2.0), drifting 13 px each way over a 4
  minute sine (about 20 px a minute at its fastest). The map style is forced per scene while it shows (the Caribbean the
  table, Rome the relief map, whatever the campaign map's own setting; it and the stale bake are put back on release). The build is queued as steps that `_process`
  runs one a frame (map, relief, landscape, state, layers, refresh), so the menu is never blocked and freeing the
  node in between is harmless. It holds the content pack (`CData`, `Geo`) of its setting, so it is freed when the
  menu hides (`release()` puts Rome back) and built again when it shows. It is built for the selected
  setting only (one world at a time; the setting's key art stands in until it is ready); the campaign-card hover
  cross-fades the key art, not the diorama.
- *art*: `assets/ui/keyart/<pack>.jpg` fitted cover-style with a 1 % parallax (pointer, or tilt on a phone), a
  dark gradient placeholder when the file is missing; it follows the selected choice, and the hovered setting card on the campaign pages (0.5 s cross-fade).
- There is no *auto* any more: Quality Low no longer forces the picture; a chosen diorama on Low uses the Low layers
  as the campaign does.
Measured on this PC (RTX 3070, relief cached): Caribbean about 1.0-1.3 s (the first world after a Rome menu also
rebuilds the map geometry), Rome about 0.65 s; the longest single frame is the landscape bake, about 250 ms.

**Background selector** (owner 2026-10-22, after Rome 2's menu): bottom centre of the title page only, a thin gold rule
over `[<]  The Caribbean, painted  [>]` (`bg_selector`, built in `main.gd`): 44 px nav-style arrow buttons (36 px on
phones) with a chevron drawn in code (the kit has no chevron icon), the name in Cinzel 18 (16 on phones) in bone with a
dark outline. The choices, in order and wrapping: The Caribbean, painted (`art_west`), Rome, painted (`art_rome`), The
Caribbean, the map table (`diorama_west`), Rome, the relief map (`diorama_rome`). The arrows, the Left / Right keys and
a 40 px swipe along the name step it; the switch cross-fades the pictures over 0.5 s (`MenuBg.switch_to`) and a diorama
builds as before. The choice is saved at once; old saved values migrate (`art` and `auto` to the picture, `diorama` to
the diorama, of the last-played setting; first run: the painting of the last-played setting). The wordmark's emblem and
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
  Soldiers Auto / Compatible, Fullscreen, Battle look Diorama / Painterly, Campaign map Auto / Table / Relief; the title
  page adds Emblems Drawn / Painted (the menu picture moved to the title screen's selector) and its Help section (Controls, Unit book,
  Tests with `--dev`). Audio: a Sound On / Off capsule and three sliders (master, effects, ambient) with their percent.
  The page sits in a trim panel so it reads over any picture; it scrolls (the Help buttons are at the bottom).
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
  dice, Victory as two steppers, Turn timeout, Battles, AI aggression, Battle AI, Campaign AI, Fog of war, Deployment,
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

### UI theme (as built, 2026-10-21, pass 1: the kit and the campaign screen)

Owner's call: "the in game menu needs some work. trim, font, anything else". The title menu's dressing (Cinzel, gold
`b08a40` / ink `1a1410` / bone `e8dcb0`, the dark warm panel, the 3 % hover growth, the setting emblems and key art)
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

**Loading** (`loading_panel.gd`): the setting's key art (`assets/ui/keyart/<pack>.jpg`, cover-fitted, darkened 40 %,
a dark fill without the file) behind a trim panel with the title in Cinzel, a one-line tip from `LoadingPanel.TIPS`
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
  Inf / Missile / Cav / None** are one capsule (`group_capsule`): momentary, nothing stays lit, 50 x 42 touch
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
- *Loading*: the battle build uses the themed panel (key art of the campaign's pack, tip, trim; `_enter_battle`) when the
  last build was slow; a sea battle is added directly (as before; its build is fast).
Tests: `tests/battle_theme_test.gd` (windowed; `-- --shots=DIR`, `--phone` for an 844x390 touch layout), `sea_help_test`
(the Key lists every kind, the drawing uses only those kinds, six distinct colours, remembered, the hint), `input_test`
(its Leave text check), `sea_screen_test`, `battle_screen_test`, `theme_test`. Frame time (RTX 3070, 1920x1080, vsync off,
mean ms over 8 s from tick 600, HEAD -> now, 2 runs): bench_2000 paused 3.06 / 2.99 -> 2.94 / 2.85, running 3.19 / 3.02 ->
2.98 / 2.86; bench_4000_city paused 4.89 / 5.43 -> 5.22 / 5.21, running 5.20 / 5.71 -> 5.54 / 5.46: within noise.
