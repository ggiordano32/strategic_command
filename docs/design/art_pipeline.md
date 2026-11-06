# Art pipeline (sprites, battle kit, battle look, characters)

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

## 8. Art

**Faction crests** (view only, `game/faction_crest.gd`): painted crests for all 16 factions of both packs, FLUX.2 Klein 4B (Apache-2.0) editing our own drawn mark (the West emblems; a faction-colour shield for Rome, which has no drawn emblem) into a heraldic crest, picked by eye of four, flattened to gold / ink / the faction colour / bone, 256 px and 64 px files in `assets/ui/crests/<pack>/`. `Kit.faction_mark` returns the crest under the painted emblems setting (the 64 px file at 64 px and below) and the drawn emblem or swatch under drawn or when a file is missing. Army banners keep the drawn marks (they do not go through `faction_mark`; the crests are readable at 24 px by silhouette and colour but the drawn flags read better there). Route and prompts: `tools/menu_art/README.md`; sheet `docs/screenshots/crests.png`.

- Placeholder top-down sprites, tinted per faction, until the game is proven fun.
- Per unit type: idle, walk, attack, die. One sprite sheet each.

Ground: a topographic-map look from one shader (see "Terrain height: as
built"): thin 2 m contours, soft hill shading from the upper left, a subtle
tint by height, the faint 50 m grid. Screenshots in `docs/screenshots/`.

Milestone 2 placeholder: one procedurally drawn atlas with nine top-down
greyscale sprites (sword and shield, spear, long pike, bow, javelins, horse
and rider, gun crew, bolt thrower, stone thrower; cells 6 x 2.5 m), tinted per side and state in the shader; each sprite has its own
quad size so pikes and horses are long. Still one MultiMesh draw call for all
soldiers, plus one for missiles in flight.

Soldier rendering has two paths with identical output (`game/soldier_layer.gd`,
`game/soldiers.gdshaderinc`, `game/projectiles.gdshaderinc`):

- **Texture (default, cheapest):** per tick the sim's int arrays are copied
  as raw bytes into an RGBA8 data texture (one texel per int32); the vertex
  shader fetches and decodes them per instance (texelFetch) and interpolates
  between ticks. About 0.23 ms a tick at 4,000 men natively.
- **CPU-fed (compatible fallback):** the same arrays are converted to floats
  and interleaved into the MultiMesh buffer, one bulk upload per tick
  (positions, previous positions, facing, state through the instance
  transform, read back as MODEL_MATRIX with `skip_vertex_transform`; sprite
  and side / selected / under fire in INSTANCE_CUSTOM, filled per unit run);
  missiles are re-uploaded only when one is fired or lands, and only the
  slots in use. No texture fetch, uniform array or int uniform in the vertex
  stage. About 0.5 ms a tick at 4,000 men natively.

Chrome on an Adreno 650 tablet (ANGLE on GLES) drew nothing from the texture
path (Firefox on the same tablet did). A battle's self-check renders only the
soldier layers around the biggest unit offscreen ~30 frames in (telemetry
`soldier_probe` with `drawn`, `men`, `path`); zero pixels with men alive on
the texture path switches to the CPU-fed path at once, probes again, and
remembers it in `user://settings.cfg [video] soldiers=cpu` for later
battles. The home menu's "Soldiers: auto / compatible" button sets the same
preference; `--soldiers=cpu|gpu` (or `?soldiers=` in the URL) forces a path
for testing and `--soldier-probe-fail` fakes a failing texture path.

Icons (2026-10-09, phase 1): every UI icon is drawn in code by
`game/ui_icons.gd` (80 icons, no asset files), one line style matching the
unit glyphs: round-capped strokes 0.16 of the half-size, the glyph filling
90% of its cell, one colour. An icon is a `VecIcon` (a Texture2D drawing
vector strokes through the RenderingServer), so it is crisp at any UI scale,
sits in a Button's `icon` and takes the button's icon colour per state
(Kit sets them to the text colour; disabled is an opaque grey). Size follows
the text (13 px text: 18 px icon, 15: 20, 17: 22). Kit helpers:
`icon_button(text, icon, ...)`, `set_icon`, `tint_icon`, `icon_label`,
`label_icon` (a content margin plus a draw hook: the label keeps its name,
text and wrapping) and `section(text, icon)`. Text stays beside the icon
everywhere except Undo, Deselect and Menu (bare, with tooltips). The top bar
reads faction, season icon + year, treasury, income; Deselect / Undo / End
turn are one bottom-right row. Gallery: `tests/icon_gallery.gd` writes
`docs/screenshots/icons.png`; before / after: `docs/screenshots/icons_*_phone_*.png`.

West icons (2026-10-21; owner: "Arrows and shield don't quite fit" the Caribbean): the West pack's unit rows
carry their own glyphs in `game/unit_icons.gd` (display only, the sim never reads "icon"): 23 musketeers (a
musket: thick stock, thin barrel, the cock, a ramrod), 24 rodeleros (a round targe with a boss, a sword behind
it), 25 cutlass men (a cutlass crossed with a boarding axe), 26 buccaneers (a plumed wide hat over a long fowling
piece), 27 lancers (horseshoe, a lance with a swallow-tailed pennon), 28 pistoleers (horseshoe, a flintlock
pistol), 29 culverins (a cannon on a wheeled carriage, muzzle up-left), 30 the fort gun (the same on a
parapet), 31 light guns (a short piece on a spoked wheel), 32 native warriors (a macana and a feathered arrow),
33 native bowmen (a short slanted bow, a fletched arrow), 34 the West general (a tricorne over crossed cutlasses;
`icon_of` maps the shared general row's 15 to 34 while `CData.pack` is "west"); pikemen keep 3. UI icons with a
bow, arrow, crested helmet, Roman shield, spear or ram have a "_w" twin in `game/ui_icons.gd` (`WEST_NAMES`:
cl_missile, range, fire, hold_fire, barracks, general, workshop, tr_siege, stance_default, cl_spear,
tr_anti_cav, tr_ap, tr_long_range, ammo); `UiIcons.resolve(name)` (used by `draw_rid` and the icon raster atlas)
picks it while the West pack is active. Movement arrows (move, merge, skirmish, bound, undo...) stay. The West's
buildings keep the Rome chain names (Barracks, Range, Stables, Workshop); only their icons change. Gallery:
`tests/icon_gallery.gd` also writes `docs/screenshots/icons_west.png` (glyphs at 16 / 24 / 48 px on both sides,
tier marks, the twins beside the Rome icons).

### Characters (as built)

The three Hunyuan characters (tools/hunyuan: the Captain, Captain Rook, Mercy
Teague) are wired in as view-only art, nothing in `campaign/` or `sim/`:

- **Busts as story portraits.** `game/bust_portrait.gd`: the 256 px
  `assets/portraits/NAME.png` fitted inside the code-drawn frame of
  `game/story_portrait.gd` (`StoryPortrait.draw_frame`, the character's colour),
  the same outer square as `make_control`, so no layout moves. `BUSTS` maps the
  story keys `captain`, `partner` (Captain Rook) and `mercy`; a `crop` rect per
  key is there for a bust that reads small (all full for now: head and
  shoulders already fill the frame at 36 px). Every other key keeps the
  code-drawn portrait or the badge. `StoryView.portrait()` and the choices'
  speaker pictures both go through `_face`. Portrait textures are imported
  with mipmaps and the control draws with mipmapped filtering.
- **Figures beside the banners.** `game/campaign/minis_layer.gd` (child
  `_figs`, no ship material, under the overlay): in a story campaign the lead
  human's faction gets the captain, the second human's Rook, the faction
  `CHARS["mercy"]` marks gets Mercy (the same faction as the captain in the
  Brethren story: a second slot, further left). The army: the one a hero
  character rides with, else the faction's largest on land; an army in a city
  stands beside its banner there too; carried on a fleet: none. The figure
  stands left of the banner, feet on the banner's base line, 58 px tall at
  marker scale 1 (scaled with `mk()`), the 48 px sprite below 0.6 and on
  Quality Low. Positions are the overlay's cached, fog-filtered banner
  positions (an army out of sight has none, last-seen markers get no figure);
  one `draw_texture_rect` per figure, redrawn only when the overlay's epoch,
  transform or zoom changes. No taps: `army_at` is unchanged. The masks (coat,
  sash) are not used yet.
- **Export.** `assets/characters/*` (the 4.7 MB glb meshes) is in every export
  preset's exclude filter; only the PNGs ship (about 0.25 MB imported).

### Sprite pipeline (step 1a, 2026-10-13)

Owner's direction: all art made by us from text, consistent across frames
and angles because it comes from 3D. `tools/sprites/` (README there):
`spec.json` describes units as parts lists over a shared rig; `build.py`
(Blender 5.2, headless, EEVEE on the GPU) builds each part as a chunky
low-poly mesh (bmesh boxes with bevels, spheres, cylinders, cones, a curved
scutum), rigidly parents it to a bone (no skinning), keyframes the actions
from pose functions shared by every humanoid (and one set for horses: a
rider's bones live in the horse's armature, prefix `r.`), and renders each
frame orthographic at 24 px per metre (`ATLAS_PX_PER_M`) in three passes:
**shade** (toon lighting in three flat bands with an ambient floor, a key
light fixed in camera space from the top left, a mild lighter-when-higher
term; faction parts white), **mask** (R primary, G secondary, B accent) and
**pattern** (the cloth check). `pack.py` (stdlib Python) hardens the alpha,
adds a 1 px dark outline, crops each action to its frames' union, packs one
shade + one mask sheet per unit (mask A = 255 - 128 x check, never 0) and
writes `assets/sprites/manifest.json` (frame rects, anchor = the man's
feet, fps, loop, palettes). Recolour: `rgb = shade x ((1 - r - g - b) +
r x mix(primary, pattern, check x pattern_k) + g x secondary + b x
accent)`.

Built: Heavy Swords (Roman: curved scutum with rim and boss, crested
helmet with neck guard, plated shoulders, gladius), Spearmen (hoplite:
round shield with rim and emblem, Corinthian helmet with a tall crest,
2.9 m spear), Shock Cavalry (horse with a saddle cloth and trim, rider
with crested helmet, round shield, 3.6 m lance). Actions: idle 1, walk 6
(leg and arm swing, shield bob, body bob), attack 4 (wind-up, twist and
thrust, recover), death 3 (falls on his back; the horse rolls on its
side). Palettes: Rome red / gold / bronze; Carthage white / Tyrian purple
/ silver; the Gauls green / ochre / iron with a blue check on cloaks and
saddle cloths. The same models render isometric: the Heavy Swords walk at
32 degrees elevation in 8 directions (`iso_heavy_swords_*`), so a bird's-eye
view is a camera change, not new art. Total output 184 KB; a full build
takes about 14 s. Preview: `tools/sprites/preview/preview.tscn` (1x, about
12 px a man, about 7 px a man, rotated blocks, iso). Wired into the battle
in step 1b (below).

### Sprite pipeline (step 1b, 2026-10-13)

The rendered sprites are in the battle. **Art fixes** first (owner's
notes on 1a): the horse is chunkier from above (broader barrel, chest and
rump, thicker neck and head, a larger muzzle and ears) and its legs splay
outward as they swing, so hooves show beside the barrel; the death no
longer rolls the horse onto its side (which read as a standing horse in
profile) but sinks it flat on its belly, legs splayed out both sides, neck
and head laid down on their side, the rider thrown clear. (1a built the
right legs on the left legs' bones, so they moved as one pair; fixed: the
gait is diagonal now.) Infantry heads and shields are a few % bigger to
read at 7 px a man. A fourth set, **Pikemen**, is the Spearmen with a
5.6 m sarissa and a smaller shield.

**Atlas.** `pack.py` packs every set's frames into one pair,
`assets/sprites/atlas_shade.png` and `atlas_mask.png` (1024 x 332; every
frame starts on a 4 px step with a 4 px gutter so mip levels up to 2 never
mix frames; imported lossless with mipmaps). It also generates
`game/sprite_atlas.gd` (the frame table, the palettes) and
`game/sprite_frames.gdshaderinc` (the same table as shader constants).
The table: per set and action (idle, walk, attack, death) frame 0's rect
(x0, y0, w, h) and (anchor x, anchor y, step, frames); frame k is at x0 + k
x step. The manifest keeps the same numbers for tools.

**Which set.** A display field on the unit rows, `sprite_set` (0 = the
procedural sprite, `sprite`): 1 Heavy Swords for the heavy and light
lines, 2 Spearmen for spear lines, 3 Pikemen for pike lines, 4 Shock
Cavalry for every horse row (cavalry, missile cavalry, generals). Archers,
javelins, slingers, camels, elephants, dogs, artillery crews and engines,
wagons and characters keep their procedural sprites until their own sets
are built (`tools/sprites/README.md`).

**Palettes per faction**, not per side: Rome, Carthage, Macedon (saffron,
crimson), Epirus (violet, cream), the Greek League (sky blue, white),
Syracuse (teal, gold), the Iberians (undyed white with a crimson check),
the Gauls. A campaign battle passes CBattle's `unit_faction` to the
battle; a unit without one takes its side's (the most common among its
side's units, else the faction whose roster alone has its units, else Rome
for side 0 and Carthage for side 1: scenarios and custom battles). The
side shows by the unit markers and the selection tint, not on the men.

**Shaders** (`game/soldiers.gdshaderinc`). An atlas man's action comes
from his state: dead, the death's last frame (the corpse layer); knocked
down, its middle frame; fighting, or his unit shooting while he stands,
attack; moving (more than 2 cm a tick) or routing (1.6 x faster), walk;
else idle. The frame comes from the view clock `now` (ticks, interpolated:
the soldier materials get it with `alpha`) plus a phase fract(index x
0.618), so a block does not step in lockstep; nothing is written to the
sim. A powder-weapon man (flag 32 gun) never plays attack frame 1, the
muzzle flash, unless his unit fired in the last 0.3 s (flag 16 fired, from
the overlay's shot tick; battle_sim.md "Firearms"): aiming and reloading
cycle frames 0, 2, 3 slowly.

**The muzzle flash is the man's own (2026-11-06, owner: "I want to verify the muzzle flash is only taking place when a soldier
fires").** The paragraph above lit the *unit*: flag 16 fired showed attack frame 1 on every man of a gun unit for 0.3 s after any
shot of it (a countermarch's front rank of 25 flashed all 100 men, a brace of pistols all 60, a man behind cover with them).
Measured (`tests/muzzle_flash_probe.gd`, both soldier paths, both views): the sim's shots that tick against the men the old flag
lit, musket 25 of 100 against 100, pistols 21 of 60 against 60. Now the soldier layer never sets flag 16 (the bit and the shader's
`fired` stay, always off: a gun man cycles frames 0, 2, 3); the flash is the overlay's, one per shot, started in `_tr_note` from
the missile's own start (`Overlay._flash_add`: a half metre ahead of the man who loosed it along the ball's flight, in the
oblique view at 1.1 m up with the tongue along the shot's screen direction), drawn by `GunSmoke.flash` after the smoke, aged by
real time: 0.12 s a musket or arquebus (0.34 m glow scale), 0.06 s a rider's pistol (0.22 m), none for a man without powder (bows,
slings, javelins: no gun row, no flash), a gun engine's or ship's flash stays the main puff's (0.09 s; the ring and dust puffs
and the men's bank puffs no longer carry one). The puff bank is as before (one puff a cell a second). Same pixels on the CPU
path (the flash is not in the soldier shader). `battle_screen_test` checks the flashes shown equal the sim's gun shots on every
fire tick and none a second later; bows make none.
Known: the sim records no per-man fired flag (the missile's start position stands for the man; a man leaning out of cover shoots
from his lean spot, which is where the flash shows); the pistol brace a melee man fires at contact is a sim effect with no missile,
so it has no flash; the old frame-1 recoil pose is gone with it.

The texture path reads the table from a uniform array (`frame_tab`),
the unit's set, palette and shooting from its flags (bits 12-15, 16-19,
3); the CPU-fed path from constants (an if chain, as `sprite_rect`), with
INSTANCE_CUSTOM.z = set + 16 x palette and .w = the instance's index. The
fragment stage recolours by the mask from a 4 x 8 palette texture with the
1a formula and folds the state tints (routing, knocked down, under fire,
selected, corpse) into one multiply-add. Still one MultiMesh draw call per
soldier layer; the probe is unchanged. Rendering only the soldiers of one
frame offscreen on both paths gives identical pixels (sub-pixel edge
differences far from the origin predate the atlas). Frame time at 4,000
men is unchanged within noise on this desktop; Graphics Low keeps the
animation (holding it measured no cheaper).

**Men turn to their march (2026-10-22, owner: "it looks like the units just
enable a walking motion and then slide to the area as a group"; view only).**
The drawn heading is no longer always the sim's facing. `SoldierLayer.
_update_yaw` (once a tick, from the sim's arrays; nothing is written back)
keeps per man a drawn yaw. A formed man is *large-moving* when he moved at
least 0.6 m over the last 0.5 s (a ring of 6 position snapshots) and either
his unit has an order (a move the sim does not snap: more than 12 m from the
anchor, an attack advance) or his place in the formation is 8 m or more
away (a big re-form). A large-moving man is drawn along his own movement;
anyone else at the sim's facing. The drawn yaw chases that target at most 34
angle units (1024 a turn) a tick, 120 degrees a second, so a unit whose sim
facing flips (the sim turns a marching unit at once, then to its final facing
at the last stretch) wheels visibly instead of snapping, and men return to
the unit's facing smoothly on arrival. Only men still off the sim's facing
cost anything: a unit with no order, settled, not turning and with no man
overridden is skipped (a 4,000-man march costs about a millisecond a tick).
Passing it to the shaders needs no new data: the state word (texture block 5,
CPU `[1].y`) is `state + 16 x hd`, hd 0 = the sim's facing, else yaw (10
bits) and this tick's step (7 bits), interpolated like the positions (yaw -
step x (1 - alpha)). **Short re-forms** (dressing the line, the snaps of 12 m
or less, the last metres to a place) keep the facing and the shader picks
the gait from his velocity against his heading: forward as before; a side
step plays the **sidestep** action and a back step the **backstep** action
(2026-10-22, below). Both shader variants share the
code (`soldiers.gdshaderinc`); texture and CPU paths draw identical pixels
(`tests/soldier_facing_test.gd`, 0 px differ on a marching column and a
dressing line). Frame time, 1080p vsync off, mean over 8 s from tick 600
(old / new, two runs): bench_2000 texture 3.06 / 3.13, 3.03 / 3.04 ms, CPU
3.19 / 3.20, 3.00 / 3.05; bench_4000_city texture 5.33 / 5.54, 5.46 / 5.55,
CPU 5.57 / 5.47, 5.57 / 5.60: within noise.

**Side and back step frames (2026-10-22, view only plus the sprite tables).** The
walk-cycle stand-ins for a re-form are replaced by two real action rows on
the three humanoid foot sets (heavy swords, spearmen, pikemen; the cavalry,
elephants, camels, missile and West sets keep the walk, and a horse does not
side-step). `spec.json` `actions` gains `sidestep` and `backstep` (6 frames,
8 fps, loop) with a `units` list; `build.py` renders them for those units
only (`humanoid_pose`: sidestep = the legs open and close along y with a
small sway and the guard held to the front, rendered as a step to the man's
left; backstep = short steps backwards, shield tucked, the weapon forearm
raised so the blade foreshortens from above), timeline 41-46 and 51-56, same
scale, light and ink. `pack.py` packs them (atlas 1024 x 1804 -> 1024 x
2016, PNG 907 -> 949 KB) and points the other sets' rows at their walk, so
the frame table is 6 actions a set (`((set - 1) * 6 + action) * 2`, new
`ACTIONS` constant in `sprite_frames.gdshaderinc`). The shader (`atlas_frame`)
takes the new action for a formed man whose velocity is against his heading
(along it less than half his speed: sideways -> sidestep, mirrored in the
quad (lp.y negated) for a step to his right; backwards -> backstep) when his
set's row differs from its walk row, else the old slower / reversed walk;
the march is unchanged. Both paths share the code. `SoldierLayer.step_action`
mirrors the choice for `tests/soldier_facing_test.gd` (lateral, mirrored
lateral, backward, march, turned heading; a heavy swords line mid-shuffle
and mid back step on both paths, 0 px differ). The mirror swaps his weapon
hand for a right step (a top-down man at 12 px; accepted). Frame time, 1080p
vsync off, mean over 8 s from tick 600 (HEAD / now, two runs): bench_2000
texture 2.88 / 2.86, 2.82 / 2.83 ms, CPU 2.88 / 2.76, 2.79 / 2.79;
bench_4000_city texture 5.19 / 5.27, 5.26 / 5.32, CPU 5.00 / 5.01, 5.02 /
5.24: within 0.25 ms.

**Missile sets (step 1c, 2026-10-13).** Four more sets on the shared
humanoid rig, each with a pose variant (spec `pose`) replacing the shared
attack: 5 **Archers** (cloth tunic, coloured cap, quiver, bow in the off
hand; attack = draw, full draw, release, recover; the string is a V to the
drawing hand and the arrow is aimed at the bow, both re-aimed per frame by
build.py "cord" parts), 6 **Javelinmen** (leather cap with a band, small
round shield, two javelins in the off hand and one in the throwing hand;
attack = wind-up behind the head, step, release (the javelin vanishes),
follow-through), 7 **Slingers** (the javelin body without shield or
javelins; cord and pouch on a new `weapon.R` bone that whirls overhead for
the shot; a stone bag), 8 **Gastraphetes** (the archer body behind a stocked
belly-bow held in both hands; a lean and a kick). `sprite_set` 5-8 sit on
the archer, javelin, slinger and gastraphetes base rows (tiers, Cretans and
faction rows inherit); camel archers, hero rows, dogs and engines stay
procedural. Testing aid: `--factions=syracuse,carthage` sets the two sides'
palettes in a sandbox battle.

**Beasts, engines and wagons (step 1d, 2026-10-13).** Seven more sets and
three props. 9 **War Elephant** (a rig of its own: barrel body, thick legs,
a three-bone trunk curled forward, flapping ears, tusks; a faction
caparison and bronze frontlet, a howdah with shields hung on its sides, a
driver on the neck and two javelin men standing in the howdah; build.py
units may carry several `riders`, each with its own pose (`stand`,
`fall: roll`); walk = a slow lateral amble with ear flap, trunk and tail
sway; attack = trunk up and across, then the head down for the tusk gore
with a lunge, the crew throwing; death = the whole beast, head and trunk
included, rolls onto its side, legs out, the crew rolled off with the
howdah; amok reuses the walk at the routing rate), 10 **Camel** and 11
**Camel Archer** (the horse's animation on a camel rig: hump, long neck;
turbaned rider with sword and shield, or the archers' rider with the
archer pose), 12 **Engine Crew** (the javelin body without weapons; attack
= cranking the winch; on every battery, tower engine and wagon crew row),
and three **engine sets** on a new display field `engine_set`: 13 Bolt
Thrower (tripod, stock and slide, two springs with bronze washers, arms, a
V string to the claw, a faction plate; also the tower bolt thrower), 14
Stone Thrower (onager: wheeled frame, skein, one arm with sling and stone,
padded faction buffer, spoked winch; also the tower onager), 15 Scorpion
(the bolt thrower at 60 %, carried shoulder high on two poles, legs
folded, while it moves). Engines: walk = packed / carried; wrecked = the
death's last frame (toppled, an arm snapped, scorched); the **firing cycle
follows the sim**: the view gives each working engine of a shooting unit
a state 9-12 from its `e_reload` (0 loaded, 1 just shot, 2 / 3 winding),
so the release frame shows on the tick the bolt or stone leaves (view
state only, read from the sim). An abandoned engine is a state of its own
(8: idle frame, darkened, on the corpse layer) instead of drawing as a
wreck. Texture path: flags bits 20-23 = engine set; CPU path: the engines'
runs carry engine set + 16 x palette in INSTANCE_CUSTOM.z; the procedural
engine sprite stays the fallback (engine_set 0). **Props** (`atlas.props`:
hand cart, wagon, draught horse; fixed colours, no faction mask) are
packed in the same atlas but drawn by `game/overlay.gd` from the shade
sheet (a child node with mipmaps under the overlay's lines; `PROPS` in
sprite_atlas.gd): the cart or the wagon (walk frames while it moves, the
wreck), its horses ahead (a dead horse lies, the death's last frame); the
stock bar stays. The atlas is 1024 x 1184 (15 sets + 3 props): the 4-bit
set fields are full, so a further set needs a wider field (palette and set
share bits 12-19). Still procedural: dogs, characters, and the siege
equipment drawn in overlay.gd (ladders, ram, siege tower, mantlets: the
next step, as props like the wagon).

### Battle kit walls, towers and gates (as built, Level 1 phase 1, 2026-10-14)

Look: variant A (grounded painterly) by the user's choice; B (tabletop diorama) stays an option
for a later `[video] battle_look` setting, so `game/battlekit.gdshader` keeps `rim`, `outline`,
`sat`, `contrast`, `amb`, `key` as uniforms (A is the default; B's values are in the shader header).

The settlement's walls, towers and gates on the battle map are Blender kit pieces
(`tools/battlekit/build.py`: `wall_<t>_<pp>` for the sim's five (thickness, parapet) pairs, `pal_<t>`,
`tower_round` / `tower_sq` / `tower_timber`, `gate_c|o|b`, `pgate_c|o|b`; `bastion` is packed but unused:
the map generator has no star trace yet). `tools/battlekit/pack.py` crops and packs them into
`assets/battlekit/atlas_albedo.png` + `atlas_nrm.png` (8 px/m; normal xy, height, mask class) and
the 4 px/m pre-lit `atlas_low.png`, and writes `game/battlekit_atlas.gd` (anchors, rects).
`game/battlekit.gd` (child of `CityLayer`) turns `sim.map_info["city"]` into instances: walls tiled
along each polygon edge (x scaled to the edge, the variant picked so the walkway sits where men stand),
a gate piece over the wall at each gate (state from `sim.g_state`, a flash while struck), towers
from the sim's tower list (the gate towers are in it). High: one MultiMesh and `battlekit.gdshader`
(NW key, normal turned by the instance angle, culture palette by the mask class: Latin, Greek, Punic,
Celtic, Spanish colonial, native). Low / CPU path: the same instances through `draw_texture_rect_region`
from the pre-lit atlas, no shader, no shadow layer. `game/battlekit_shadow.gd` bakes a cast shadow + AO
from the pieces' heights (0.5 m grid, one multiplied sprite), re-baking only the window round a gate
that breaks. Since 2026-10-20 the walls are not tiled pieces but one mitred strip mesh per ring (`BattleKit._wall_ring`: a quad per stretch from the repeating `assets/battlekit/strips/ws_<t>_<pp>` / `ps_<t>` texture, outer and inner edges meeting the neighbouring stretch's at the mitre, bevelled beyond 2.5 thicknesses), drawn between the houses and the gates / towers. Stairs and banners are drawn above the kit (`CityDraw.draw_over`); the campaign's city
preview keeps the old polygon drawing (`draw_static` without `kit`). Testing aids: `--no-kit` (old
look), `--no-kit-shadow`, `--kit-culture=N`, `--city-info`. The crenellated round tower is the
default; the roofed round tower (read as a ball at game scale) is not used. View only.

### Battle look: diorama default, kit houses / trees / rocks, splatted ground (as built, Level 1 phases 2-6, 2026-10-14)

`[video] battle_look = diorama | painterly` in user://settings.cfg (default **diorama**; `--battle-look=` for
a session; a "Battle look" button on the settings row in `game/main.gd`; read at battle start; `game/battle_look.gd`
holds the values: diorama amb 0.50, key 0.88, rim 0.22, outline 0.55, sat 1.22, contrast 1.12; painterly 0.66 /
0.55 / 0.05 / 0.24 / 0.86 / 1.04). All view only.

- **Houses and props** (`battlekit.gd` `_build_houses`): every `lay["buildings"]` footprint (rect, quad or round) gets a
  kit piece scaled and turned to it (long axis along the footprint's long side, a hash flips it 180 degrees): gable /
  hip / L / long houses by aspect and size, `hut_round` / `hut_thatch` for round shapes and Celtic / native styles,
  `temple` (Latin, Greek, Punic) / `church` (Spanish colonial) / `longhouse` for the shrine, `longhouse` for
  barracks, stables, range, a gable_l workshop, a grid of `stall` over a market; a `well` over the agora's fountain and
  four stalls at its corners. Culture palettes through the mask classes (`i_cul` per instance; `--kit-culture=N`
  forces one). The old polygon houses are no longer drawn on the battle map (`draw_static` with `kit`).
- **Streets** (`city_streets.gd`, under the kit): one 0.5 m texture painted from the sim's own `lay["streets"]` segments (gate to plaza, main streets, lanes; width from the segment) and the agora square, plus the lanes between blocks (free ground within 3 m of any footprint); cobbles with a curb for Latin / Greek / Punic / colonial towns, packed dirt for Celtic / native. Houses are chosen by footprint aspect (hip, gable s / m / l, longhouse) so nothing is squashed; markets are filled with scaled stalls. build.py's `house()` bug (ridge along y swapped the roof against the walls) avoided by making the long side x. Hill shade is softer in the diorama look (no dark band).
- **Rocks and cliffs**: a second `BattleKit` (`setup_land`) under `land_layer.gd`: one rock piece per boulder
  (a / b / c by radius), cliff pieces laid along each cliff's brow every 6.5 m, the piece's lower side to the downhill
  normal. `--no-kit` keeps the drawn ones.
- **Trees** (`tree_layer.gd`, `trees_kit.gdshader`): the woods and orchards keep their positions, clustering, fading over
  men and occupancy texture; each instance is now a kit tree (broadleaf a / b / c, pine a / b, bush, palm a / b)
  by kind and shade, lit by the normal atlas, tinted toward the palette's tree colours, its cast shadow sampled from
  its own silhouette shifted south-east; palms replace broadleaf / pine / olive when `CData.pack == "west"` (or
  `--tropic`). The ground cover under the men (tufts, reeds) keeps the old glyph shader.
- **Shadow and AO**: houses, towers, walls, gates, rocks and cliffs are instances of the same `BattleKit`, so
  `battlekit_shadow.gd` bakes them all (0.5 m cells in a settlement, 1 m for the land kit via `shadow_cell`).
  Trees do not enter the bake (40,000 would be too slow): the tree shader draws its own shadow.
- **Splatted ground** (`terrain.gdshader`, `terrain_layer.gd` `_splat`, `tools/battlekit/pack_ground.py`): six 256 px
  tiles in `assets/battlekit/ground/` (grass, dry, dirt, rock, sand, plough; 64 m a tile, mipmaps made at load): grass
  or dry grass modulates the palette colour; dirt for settlement ground, streets and plazas; plough on fields; rock where
  the existing slope / height rule says; sand on wet ground; contours and the 50 m grid fade back. At most 2-4 tiles per
  pixel. Graphics Low: no tiles (the flat ground as before).
- **Board** (`board_layer.gd`, diorama only): a wooden table 900 m beyond the field and a 4 m bevelled board edge
  lit from the north-west with a soft shadow; **light depth of field** (`battle_dof.gd`, High only, diorama only): the
  outer part of the screen blurred a little, under the HUD. `--no-board`, `--no-dof`, `--no-splat`, `--no-kit` test
  switches.
- **Low / CPU path**: houses, rocks and cliffs draw from the pre-lit `atlas_low.png` (roof palette tint by modulate), the
  trees from the same low atlas in `trees_kit.gdshader` (no normals, own shadow), no baked shadow, no splat, no DoF.
- Atlas now 1024 x 1024 with 47 pieces (`pack.py`; frames rendered with `build.py --ppm 8`): about 4 + 4 MB albedo /
  normal, 1 MB low, ground tiles about 2 MB with mipmaps.

### Battle look: relief, cliff faces, fields, Punic roofs, board (as built, 2026-10-14, second pass)

- **Ground relief** (`terrain_layer.gd`, `terrain.gdshader`): the dark ring round hills was the valley darkening
  (ground lower than the 24 m round it, so every hill foot got a band, plus the grade darkening): it is off in the
  diorama look (`valley_max` 0, 0.07 painterly). The hill shade is a clearer NW hillshade from the 2 m height field
  (diorama relief exaggeration 5.5, shade 0.95; painterly 4.2 / 0.8, softer and realistic); shaded slopes darken
  less than lit ones brighten. Diorama only (`terrace` uniform): stepped height bands on the 2 m contour lattice (a
  band's own elevation tint, a touch lighter each step, a lit or shaded riser at each edge by the hill shade),
  and a slope tone (steep grass turns to earth before it turns to rock). Bands fade where they crowd (zoomed out).
- **Cliffs** (`land_layer.gd`): one continuous face along the cliff polyline, corner-cut (Chaikin x2) so curves stay
  curved: lit brow line, rock tile (the ground `rock.png`) mapped along the length, darker toward the foot, strata
  courses, ribs, a talus gradient with fallen stones, soft drop shadow; drawn with `draw_primitive` quads (no
  triangulation). Rocks stay kit pieces; `battlekit.gd` `setup_land` no longer places `cliff_m`. `--land-info` prints
  each cliff's start.
- **Fields** (`city_draw.gd` `draw_surround`): furrows, rows and edges follow the field's long axis; plough = ridge and
  furrow, crop = shaded green rows, stubble = pale dashes, fallow = weeds; a headland and a hedge of round bushes or a
  post-and-rail fence round every field (drawn, not kit pieces). All of a field is batched into a few
  `draw_multiline_colors` calls and one mesh (single draw calls cost 5 ms a frame on bench_4000_city).
- **Punic houses**: `house_flat_s` / `house_flat_m` in `build.py` (plaster block, parapet, earth roof deck, cornice,
  roof stair head or a smaller upper room, a water jar), packed (49 pieces, atlas still 1024 x 1024), used for culture
  style 2 (`_house_piece`). Shader tables are 64 entries now (`rects[]`, `anch[]`), no longer 48.
- **Board** (`board_layer.gd`): bevel 6 m in two faces with a flat lip, mitred corners, grain, a pale rim on the
  lit sides, a soft shadow on the table (28 falloff rings, drawn as rings only), table of planks with seams and grain
  (detail to 450 m out; the board's own span is not painted, it is under the ground).
- Frame time bench_4000_city High GPU paused (1920x1080, mean of 8 s): 4.76 ms before, 4.8 ms after.

### Seven Caribbean sets and the 6-bit set field (2026-10-23)

- **The field.** Sprite set ids are 6 bits (up to 63; 33 used). Texture path: unit flags bits 12-17 set, 18-21 palette
  (16 palettes), 22 fired, 23 gun unit (the flash bits moved up one; all below 2^24, exact in the float decode); the
  engine-set block is masked with 63. CPU path: `INSTANCE_CUSTOM.z` = set + 64 x palette (was 32). Touched: `soldiers.gdshaderinc`,
  `soldier_layer.gd` (`_unit_look`, `_unit_elook`, `_upload_gpu`), `pack.py` (limit 63), `spec.json` atlas `_doc`.
  `tests/soldier_facing_test.gd` now draws every set (palette 10) on both paths and compares pixels.
- **Sets** (ids in `atlas.sets` order): 27 grenadiers (fur-and-plate cap, turnbacks, grenade pouch, musket slung on the back;
  pose `grenade`: attack 1 is the release, the grenade shows in frames 0-1 with an ember), 28 dragoons (mounted, round hat with
  cockade, short musket across the saddle, rider pose `musket`, flash on frame 1), 29 coureurs (fur cap with a tail, hide
  coat with fringes, sash, long musket, pose `musket`), 30 boarding_grenadiers (cutlass body, wide sash, grenade in the off hand;
  pose `boarder`: the cutlass cut with the off hand throwing the grenade, released at frame 1), 31 canoe_raiders (native
  warriors body, feather headband, a javelin in hand and two across the back; pose `javelin`), 32 holcan (quilted cotton armour,
  a tall fan of feathers, a long macuahuitl in both hands; pose `twohand`: raised overhead, cut at frame 2), 33 mortar (engine
  set, rig `mortar_engine`, anim `cannon`: short fat barrel elevated 65 degrees on a wooden bed with painted rails; attack 1 is
  the recoil and flash). Atlas 1024x2156, 1.2 MB of PNG. New poses in `build.py`: `grenade`, `boarder`, `twohand`.

### Seven more Caribbean sets, batch 2 (2026-10-24)

- **Sets** (ids in `atlas.sets` order, appended; 40 of 63 used): 34 mounted_arquebusiers (horse rig and rider as the dragoons;
  morion with a comb and plume, buff coat with linen collar and cuffs, a long arquebus across the saddle; rider pose `musket`,
  flash on frame 1), 35 marines (musketeers' body re-dressed: round hat, short sea coat, linen crossbelt, cartridge box, cutlass
  and scabbard at the belt; pose `musket`), 36 naval_gun (engine set, rig `cannon_engine`, anim `cannon`: a long heavy gun low on
  a timber sledge with runners, a rope breeching, hauling ropes and a hand spike; attack 1 is the flash; its crew is the existing
  w_crew set 25), 37 colonial_militia (straw hat, linen shirt, patched vest, breeches, powder horn, a shorter musket; pose
  `musket`), 38 maroons (bare chest and a torn shirt on one shoulder, head cloth, rope belt, machete in hand, a short musket
  slung on the back; the default melee pose), 39 atlatl (Itza body of the canoe raiders, a light fan of four feathers, an atlatl
  and dart in the throwing hand shown in attack frames 0-1, a bundle of darts across the back; pose `javelin`), 40 w_slingers
  (native body of the bowmen with one feather, sling and stone bag of Rome's slinger set; pose `sling`). No new poses or shader
  changes; sets 1-33 are pixel-identical (every frame rect of the old atlas compared with the new one, shade and mask).
  Atlas 1024x2460, 1.4 MB of PNG. Build: the seven units about 2 s each; the new sets need `sprite_set` (and `engine_set` for
  the naval gun) on their unit rows in `sim/unit_types.gd`, not done here.

### Four character sets, batch 3 (2026-10-24)

- **Characters are not drawn by a set in Rome**: `UT.CHARS` rows carry `"sprite": 0` and no `sprite_set`, and are drawn
  by the procedural path (their story busts / figures are the view-only art of "Characters (as built)"). These four sets
  exist so the batch-3 rows can point at them with `"sprite_set": N`; wired 2026-10-24 (the four West character rows carry sprite_set 41-44, battle_sim.md "The Caribbean roster, batch 3 (as built)").
- **Sets** (ids appended; 44 of 63 used; one man each, no new poses, default melee pose with the right forearm holding the
  weapon): 41 sea_captain (broad hat with plume, long laced sea coat, sash, crossbelt, two pistols at the belt, drawn
  cutlass), 42 privateer (dark coat, tricorn with cockade, sash and neck scarf, knife in the right hand and a pistol in the
  left), 43 missionary (brown hooded habit with a rope cord, tonsured bare head, book and a tall cross held up; unarmed),
  44 shaman (bare painted torso, tall fan of eleven feathers, bone necklace, feathered cape, a rattled staff and a gourd
  rattle). The musket / pistol and assassin / diplomat / chieftain poses the plan hoped for do not exist; the melee pose is used.
- Sets 1-40 are pixel-identical: Blender re-renders of old units differ by a few EEVEE noise pixels (max channel delta 9 in
  archers, gastraphetes, crew, atlatl), so the new atlas has every old frame rect overwritten with the old pixels (a Godot
  script, kept out of the repo) after pack.py; 2236 shade and mask rects compared, 0 differ. Atlas 1024x2540, 1.4 MB of PNG.



### The torch raiders' set (native siege, 2026-10-29)

- **Set 45 torch_raiders** (appended; 45 of 63 used): the native warriors' body (bare painted torso, paint bands, baldric,
  loincloth, armbands) with three feathers of the warriors' nine in the headband, a trade axe in the right hand (wooden
  haft, iron head, a rope lashing), a burning torch in the left (stick, charred wrap, an ember-coloured flame cone) and
  two clay fire pots at the belt; the default melee pose (the axe). `spec.json` unit `torch_raiders`, `atlas.sets` +1;
  the row carries `"sprite_set": 45`. The palette is the faction's (the Miskito's purple) as for every set.
- Sets 1-44 pixel-identical, as before: a full rebuild (Blender 5.2.1, about 2 s a unit) differed in 11 frames by 3-6
  bytes (EEVEE noise: gastraphetes, cannon, shaman), so the old pixels were put back over every old frame rect after
  pack.py (a Godot script kept out of the repo); 2,444 rects compared, 0 differ. Atlas 1024x2564, 1.5 MB of PNG.

### The battlefield ground, painterly (as built, 2026-10-27)

Part 5 of the visual pass (`overworld_view.md`). View only: the ground reads the sim's `veg_d` density (the vegetation texture's
R channel, density / 3) and height grids and writes nothing; no file under `sim/` changed and no hash moved.

- **Ground patches** (`terrain.gdshader`): two octaves of value noise (17 m and 6.5 m, the second domain-warped by the fine
  noise) give patches of lusher grass (`+7 %` brightness) and bare earth (`earth_col`, the palette's base mixed 45 % with its
  sand, `0.92` x; up to 34 % mix), on top of the existing lush / dry patches. A brushed grain: noise stretched 11:1 along the
  NW-SE diagonal (the hill shade's light), fading out when zoomed far out (pixel above 0.2 m). The hill shade, contours and crest
  line are unchanged and apply after. Graphics Low: one octave, no brush grain, no crown shadow.
- **Crowns** (`crown_at()` in the shader, `crown_centre()` in `tree_layer.gd`): one jittered crown per 5.5 m cell (3 x 3 cells
  searched), radius `5.5 m x (0.46 .. 0.60) x (0.55 + 0.6 x density)`, so a thin wood has small crowns and a dense one merged
  clumps; the floor darkening and shadow are gated by `smoothstep(0.04, 0.14, density)`, the lit disc and rim only by `smoothstep(0.18, 0.30, density)`, so in thin or open vegetation only the slightly darker floor and the edge shadow remain, no discs. Each crown is shaded from
  the upper left (lit side, darker scalloped rim, 0.22 to 0.52 at the wood's border where density is low), tinted from the
  palette's two tree colours (x 1.3) with a per-crown random; between crowns the floor is 20 % darker; a soft shadow (the crown
  field shifted 1.5 m, 1.7 m to the lower right) darkens the ground outside the crowns by up to 36 %. The kit tree sprites keep
  their draw order and look and none is dropped (test_woods: 1338 trees, as before); `tree_layer.gd` places them clumped: each tree leans 70 % of the way to its crown's centre (the
  same hash as the shader's, mirrored in GDScript), so the trees bunch on the crowns. Cover, line of sight and
  the sim's woods are untouched (the sim never reads a tree).
- **Edges** (`city_draw.gd` `draw_surround`, the decals): fields get two faint bands (8 % and 14 % alpha, 2.2 m and 1.2 m
  out) beyond the headland and tracks two wider faint bands under the dirt, so the field and the track blend into the grass in
  a short ramp. The settlement's own streets and plaza keep the vegetation texture's linear edge.
- Web: nothing beyond the existing shaders' set (no `textureQueryLod`, no bit ops, constant loop bounds, one extra
  `texture()` read for the shadow).

### The tabletop battlefield (plan, 2026-10-27; agreed with the owner)

The owner: "I really really like the direction toward miniatures on a
tabletop" and, for the battlefield, "really focus on reworking the visuals
to look like miniatures on a tabletop ... I assume it will take many passes".
The overworld reached that reading with the painted-miniature towns, the
chart sea and the parchment table (overworld_view.md, the visual pass of
2026-10-27); the battlefield follows, in passes, each view only (no sim rule,
no hash, no lockstep change) and each checked on the phone. Every soldier
and every kit piece is rendered from our own Blender models (the sprite
pipeline above), so an oblique view is a camera change in the build, not new
art; that decides the order.

1. **Trays and bases.** A thin movement tray (dark card edge, a faint
   bevel) under every unit's formation footprint; a round base with a
   faction-coloured rim under every figure (the basing convention), a soft
   contact shadow; the unit's standard on a pole at the tray's corner (the
   overworld's pennant language, with the unit number on a roundel); the
   state tokens (shaken, disordered, out of ammunition, Hold / Use now) as
   small plastic counters on the tray's edge instead of bars; casualties
   as toppled figures left on the table (the death action's last frame,
   kept, fading slowly); routed units lifted off the tray. The cheapest
   pass and the strongest "these are miniatures" cue.
2. **The terrain board.** Hills as stepped foam terraces with bevelled,
   lit risers (the relief pass's bands and risers, made literal); flock and
   static-grass texture on the ground pass of 2026-10-27; model trees on
   felt patches; roads as sand strips, rivers as poured resin with a
   painted bed, fields as flock squares with a card edge; the table's lamp
   light (a warm key with a soft vignette and the tilt-shift of the
   overworld frame); the board's bevelled edge and the wooden table beyond
   it, already drawn, tied to the overworld's table tone.
3. **The oblique camera.** Every sprite set re-rendered at about 40 degrees
   elevation in 8 directions (the pipeline's `iso_` variant generalised;
   the owner asked that the kit houses, walls, towers and gates be
   re-rendered at the same angle, in the same build), figures drawn upright
   on a foreshortened board (the ground, the decals and the overlay
   squashed by the camera's cosine, heights lifting by its sine), taps and
   drags mapped through the same transform, the HUD untouched. The big
   pass; it waits for 1 and 2 and for the overworld's performance pass
   (the West table at about 39 ms a frame on the desktop before any pass of
   2026-10-27: profile and cut the polylines and whole-map redraws first).
   Two characters are modelled in this build, for the asymmetry rather
   than for flavour: a **native war chief** (an aura that hides and
   ambushes harder near him; orders the feigned retreat once the native
   ambush play exists) and a **European engineer** (faster siege works and
   batteries, the only one who raises the star-fort tier).
4. **Painted figures.** A shading pass in `build.py` / `pack.py`:
   black-lining, edge highlights, a varnish gloss term, flock on the bases.
5. **Furniture and motion.** A brass ruler for the deployment line and the
   range rings, cotton smoke everywhere (the diorama's already is), the
   dive from the overworld onto the table as the battle opens, and, rule of
   cool, a die that rolls across the table on an auto-resolve. (Built
   2026-10-30: "Pass 5, furniture and motion" below.)

**Client (the owner deferred the decision; decided 2026-10-27).** Web first
stays: the measured lag is our own drawing cost and a native build would
carry it unchanged; the phone and friends joining by link are the loop. A
native desktop export preset is added beside the web one (no code change)
for the owner's desktop sessions and for profiling; a native-only direction
reopens only if a pass needs true 3D that the phones cannot take.

### Pass 1, trays and bases (as built, 2026-10-27)

Pass 1 of the tabletop plan above. View only: nothing under `sim/` changed, no hash moved, no lockstep input; `game/campaign/`
(`map_overlay.gd`) is untouched. Code: `game/tray_layer.gd` + `tray.gdshader` (new, the trays), `game/soldier_bases.gdshaderinc` +
`soldier_bases.gdshader` / `soldier_bases_cpu.gdshader` (new, the bases), `game/soldier_layer.gd` (the base layer, the casualties),
`game/soldiers.gdshaderinc` (a dead man's fade), `game/tabletop_marks.gd` (new, the standard and the token drawing),
`game/glyph_bake.gd` (new, one-shot texture bakes), `game/overlay.gd` (`_draw_standards`, `_tokens`), `game/battle.gd` (wiring),
`tests/battle_screen_test.gd` (`_casualty_cases`).

- **Trays.** One MultiMesh quad per visible unit under the men (between the works and the soldier layers); the card is drawn in the
  fragment shader from the pixel distance to the edge: a 1.5 screen px dark edge (the ink tone), a faint lighter bevel line just
  inside, a 12 % dark translucent fill. The quad is the footprint's rectangle (files x ranks from `u_files`, `u_alive`, the type's
  `file_sp` / `rank_sp`, 0.6 m margin) at the unit's anchor and facing, **interpolated between ticks like the men** (previous
  anchor kept per unit; a jump over 14 px, or the deployment, is not interpolated), so it turns with the facing and shrinks with
  the alive count. None for a unit routing (lifted off; it returns on rally), off the field, reserve, or an enemy not seen
  (`hidden_from`: the last-seen ghost keeps its own outline). `TrayLayer.quads[u]` (front left, front right, rear right, rear
  left) is what the standards and tokens sit on. First tried as polylines in `_draw`: each polyline or polygon cost about 0.35
  ms a frame for 19 units, so the whole layer is a shader.
- **Bases.** A third MultiMesh layer on the soldiers' own MultiMesh, drawn first (under corpses and men), with its own small shader
  pair (texture-fed and CPU-fed like the men's; Tab S7 path included), not a second instance per man and not part of the men's
  quad: a darker ring in the faction palette's primary (x 0.4), the colour at 50 % saturation inside, a lit top, a soft contact
  shadow to the lower right. **Diameter 1.0 m (radius 0.5), not the planned 0.7 m**: the top-down figure (a head, shield and
  shoulders about 0.9 m wide) hides a 0.7 m base completely; at 1.0 m the ring shows round the shield. Horse and rider and camel 0.65
  m radius, elephant 1.1, dog 0.36. Graphics Low (`base_low`, set at battle start): a plain dark ellipse, no ring. Cost within
  noise (0.05 ms): the vertex work is a small second pass over the same instances.
- **Standards.** The overworld's pennant language (`Overlay.draw_banner`: pole, swallow-tailed pennant, parchment roundel, gold rim
  when selected, the faction crest where `FactionEmblem` has one) at the tray's rear-left corner (the pole's foot on the corner),
  upright, drawn in the overlay above the men. 29 px tall at zoom 1 (the banner's own size), scale `clamp(zoom, 0.62, 2.0)`, so
  never under 18 px. The pennant is the unit's palette primary (the men's main colour), the roundel the card number (`u + 1`). If
  its box would touch the marker's selection ring (1.7 r) it moves to the rear-right corner. **The drawing is copied into
  `tabletop_marks.gd` (not moved out of `map_overlay.gd`)**, so the campaign file does not change while the overworld is being
  profiled in another tree; merge them later if wanted. The marker disc stays where it was and is still the only tap target
  (`input_test` PASS). Routed units keep a standard (at the men's centroid) but no tray.
- **Tokens.** The card strip's states (`Battle._card_states`, passed to the overlay as a Callable: hold fire, a non-default stance,
  an ability on Hold or Use now, in its order, the glyphs the strip uses) plus out of ammunition (`ammo`, struck through), shaken
  (morale - fright < 450; a zigzag) and disordered (`u_disorder >= DISORDERED`; scattered dots), as round plastic counters (dark
  rim, body colour, a lit arc, a shadow) along the tray's front edge from the unit's left, as many as fit. Own ready units only.
  **14 px across at zoom 1, never under 12 (the plan said 8 / 6: at 8 the glyphs could not be read on the 886 x 409 phone, 14 px
  reads at 4 x magnification and next to the 22 px marker)**. The lists are rebuilt every 6th frame.
- **Casualties.** `SoldierLayer._casualties` (once a tick, inside `upload`): a man seen dead (state 4) keeps his last frame and base
  for 600 ticks (60 s), at most 40 a unit and 2000 in all, the oldest first; the remaining life rides in the state word's heading
  code (`4 + 16 x fade`, fade 1..32; the shader fades the sprite and the base, and greys the dead a little more), men past a limit
  or their time are sent off the field (state 5), and a routed unit's casualties are not drawn while it routs. Cost 50 us a tick. The
  sim keeps its dead; before this pass every corpse stayed for the whole battle.
- **Baked draws.** The vector drawing is cheap to look at and dear to run (a standard 36 us, a UI icon 280 us, a counter with its
  icon 280 us), so `glyph_bake.gd` renders a standard (per colour, number, rim, crest) or a token (per glyph and colour) once in a
  SubViewport and the overlay draws the texture (one call). While a bake is pending (two frames) and in headless runs a plain
  pennant or disc is drawn.
- **Cost** (desktop RTX 3070, 1280 x 720, vsync off, 8 s after tick 600, mean frame ms, 3 runs each, before = de2f911):

  | scenario, zoom, path | before | after | delta |
  |---|---|---|---|
  | bench_4000_hills, default fit, GPU, running | 6.03 | 6.50 | +0.47 |
  | bench_4000_hills, default fit, GPU, paused | 5.63 | 5.98 | +0.35 |
  | bench_4000_hills, default fit, CPU path (`--soldiers=cpu`), running | 6.01 | 6.46 | +0.45 (+7 %) |
  | bench_4000_hills, default fit, CPU path, paused | 5.59 | 6.01 | +0.42 (+7 %) |
  | bench_4000_hills, zoom 2.0, running | 6.07 | 6.25 | +0.18 |
  | test_woods, default fit, GPU, running | 1.16 | 1.20 | +0.04 |
  | test_woods, zoom 2.0, running | 1.08 | 1.12 | +0.04 |

  Under the 1 ms and 20 % limits. On the first build (trays as polylines, standards and counters as vector draws) the same bench
  was +1.5 ms: the lesson is in "Baked draws" and "Trays".
- **Checked:** scripts clean (warnings as errors); `battle_screen_test` (casualty caps, fade, lifted when routed, none past 60 s),
  `hud_fit_test`, `lockstep_test`, `determinism_test`, windowed `input_test` PASS; `git diff --stat sim/` empty.
- **Open.** The owner's eye on the base size (1.0 m), the tokens' size and the standard against the marker on the phone; the Tab S7
  (the CPU-fed base shader runs on the desktop's `--soldiers=cpu`, not on the device); the standards and tokens are screen-scale
  marks and will want their lift and anchor reworked with pass 3's oblique camera; the standard's pennant for the Rome pack has
  no crest (as on the overworld); the tray's fill is faint on dark ground.

### Pass 2, the terrain board (as built, 2026-10-29)

Pass 2 of the tabletop plan above. View only: nothing under `sim/` or `campaign/` changed, no hash moved; the shaders read the sim's
height and vegetation textures (built once per battle) and write nothing. Diorama look only (a `board` uniform set with the splat in
`terrain_layer.gd _splat`); the painterly look is exactly as before. Code: `game/terrain.gdshader` (foam steps, flock, tufts, felt,
sand streets, resin water), `game/terrain_layer.gd` (the flags, `apply_quality`), `game/city_draw.gd` (`draw_surround(..., board)`: sand
tracks, flock-square fields), `game/battle_dof.gd` (the lamp, vignette and tilt-shift joined to the existing edge blur), `game/board_layer.gd`
(the table's tone and grain). No new file, no new asset.

- **Foam terraces.** In the terrain block: the step tops are flat (the hill shade is cut to 40 % where bands are resolved, `tshade`; the
  old in-band gradient is gone), and each band edge gets a **riser** on its upper side, `clamp(0.2 / fwidth, 2, 8)` px wide (crisp, a
  fixed screen width), a **lip** (a thin pale line along its top edge) and a **foot** shadow line (about 2 px, 30 % dark) just below the
  edge. A riser is lit or shaded by the way the face looks, from the height gradient of the four nodes (`dot(grad, (0.71, 0.71))`: the
  ground falling away to the upper left is lit, +26 %; to the lower right shaded, -42 %; a hair of foam cream, 7 %), not by the smoothed
  hill shade, so even a gentle hill steps (a floor of 45 % on the old grade gate). Fades out where bands crowd (`fwidth(lv) > 0.1 .. 0.2`),
  so a far-out hill is the continuous hill shade as before. On Graphics Low too (the Low flag leaves `terrace` alone).
- **Flock.** `flock_mul()`: two grids of round specks (0.16 m a cell, snapped to an octave of the pixel size so a speck is never under
  about 1.6 px, the second grid 1.43 x larger and rotated so there is no lattice), a colour multiplier in two greens and a straw tone,
  `0.95` strength, fading out between 1.3 and 2.6 m a pixel (far out). Mask `open_m`: off on streets, plazas and paved ground, water, the
  ford, bare rock (85 %), wet sand (70 %) and the felt (80 %); on in fields. **Static grass** (`tuft_at()`, High only): one in four 0.9 m
  cells holds a tuft of three thin vertical blades (leaning a little, lighter to the tip and on the left), multiplied green over the
  ground; fades out between 0.3 and 0.5 m a pixel, so it shows from about zoom 0.25 of the default fit up (**not at the default fit**,
  where a pixel is 0.8 m: there the flock grain is the texture).
- **Felt under the woods.** The vegetation density's own 0.075 contour (wobbled by noise, 0.035) is the sheet's cut edge, crisp to a
  pixel; inside, a flat dark green (`felt_col`, with fibre grain, a little deeper with density) over the forest floor, a thin lighter rim
  at the cut and a dark shadow line just outside it. The crown discs and the kit trees are unchanged on top. The sheet follows the sim's
  `veg_d` (the cover), so what is felt is what is wood.
- **Roads as sand.** Tracks (`city_draw.gd`): a 3.7 m strip of sand (the ground mixed 14 % in), a light line shifted a little to the
  upper left and a dark one to the lower right under a slightly narrower body (the faint raised edge), a pale centre line; Low keeps its
  flat tint. Streets and plazas (shader): lighter and warmer sand (the pave tone 35 % / 45 % toward `(0.80, 0.69, 0.48)`), a lit / shaded
  line along the mask's edge for a raised edge.
- **Rivers and the sea as poured resin.** `wr` (the raw water mask) gives the pixel distance to the shore line: a crisp dark meniscus
  line there, the painted bed (sandy teal, `bed`) showing through the water's rim (by `wr`, so it scales with the mask's ramp), the
  animated foam band cut to a quarter, and on High a glossy band 1.4 to 12 px inside the edge, brighter on the banks that face the lamp,
  and a broad stretched sheen across the surface. The derivatives are taken outside the water branch (uniform flow).
- **Fields as flock squares.** The decal is translucent (62 %), so the ground's flock grain and plough tile show through; a soft contact
  shadow to the lower right, a thin dark card edge (0.2 m) and a pale line inside it on the upper left; the soft bands of the painterly
  ground are replaced; rows and hedges are as before.
- **The lamp** (`battle_dof.gd`, one pass; the existing edge blur stays and the whole is still High only and diorama only): a key tint
  from the upper left (`+6 %` red, `+3.5 %` green, `-3 %` blue at the corner, mirrored to a cooler lower right), a vignette (the overworld
  frame's shape, `0.2`), and the **tilt-shift** of the frame on the top and bottom thirds (blur radius growing to the edges; the screen
  texture is blurred with 16 taps where the blur is on, none elsewhere). It sits under the HUD (the same layer as before). **Decision
  beyond the plan:** one shader with the DoF, not a second full-screen pass (each pass copies the screen), and the old pass's alpha blend
  is now an opaque result. The board layer's table is `Kit.WOOD_BAND` x (4.0, 4.4, 5.2), the same brown as before (the band was derived from
  it), now read from the overworld's constant, with a finer grain (strokes 1.3 to 3.9 m apart, was 2.2 to 6.2).
- **Quality Low:** terraces and flock only (no tufts, resin gloss, lamp, tilt-shift or edge blur); the felt, sand and card edges stay (they
  cost nothing). **Painterly:** unchanged.
- Web: nothing beyond the existing set (no `textureQueryLod`, no bit ops; the loops have constant bounds, `exp2` / `log2` / `dFdx` are
  core GLSL ES 3.0).
- **Cost** (desktop RTX 3070, 1280 x 720, vsync off, `--quality=high`, 8 s after tick 600 with the sim running, mean frame ms, 2 runs each, before = f3dee69):

  | scenario, zoom, look | before | after | delta |
  |---|---|---|---|
  | bench_4000_hills, default fit, diorama | 6.55 | 6.58 | +0.03 |
  | bench_4000_hills, default fit, painterly | 6.50 | 6.45 | -0.05 |
  | bench_4000_hills, zoom 2.0, diorama | 6.33 | 6.33 | +0.00 |
  | bench_4000_hills, zoom 2.0, painterly | 6.31 | 6.21 | -0.10 |
  | test_woods, default fit, diorama | 1.23 | 1.26 | +0.03 |
  | test_woods, zoom 2.0, diorama | 1.15 | 1.16 | +0.01 |
  | west_town, default fit, diorama | 3.75 | 3.80 | +0.05 |
  | west_town, zoom 2.0, diorama | 3.42 | 3.48 | +0.06 |
  | (painterly: test_woods, west_town) | within +-0.02 | | |

  All within noise (the limit was 1 ms). The frames are bound by the CPU side here, so a weak GPU (the Tab S7, a phone) is the
  open question: the ground shader gained about 3 hashes a pixel for flock (more with tufts) and the lamp pass about 2 taps more
  than the old blur where it blurs (16 instead of 8), none elsewhere.
- **Checked:** scripts clean (warnings as errors), `battle_screen_test` PASS, windowed `input_test` PASS, `determinism_test --only=flow`
  PASS, `git diff --stat sim/ campaign/` empty. Shots (1280 x 720): hills at the default fit and zoomed on a terrace edge, woods,
  the West town with its sea, painterly hills, Low.
- **Open.** The owner's eye on the strength of the flock, the riser contrast and the lamp at the phone's size (the tilt-shift softens the
  top and bottom thirds, where the HUD bars sit over it only partly); tufts are not visible at the default fit by design; the felt reads
  as a darker floor rather than a sheet at the default fit (the crowns cover it), its cut edge shows from about zoom 0.3; rivers were checked
  on the sea only (no battle map with a river crossing was shot); the bed tint scales with the water mask's ramp (4 m texels on the sea,
  2 m on a river); the Tab S7 for the extra shader work; pass 3 (the oblique camera) will want the tufts redrawn as upright blades.

### Pass 3, the oblique sheets (contract, 2026-10-29)

The agreed interface between the art build (`tools/sprites`, `tools/structures`) and the view (`game/`): both are built against it.

Oblique sheets live beside the top-down ones and never replace them. **Units:** `assets/sprites_ob/atlas_shade.png`, `atlas_mask.png`,
`manifest.json` with the same unit keys, actions, fps, loop and palettes as the top-down manifest, each action's frames listed per
direction: `"frames": {"S": [[x, y, w, h], ...], "SW": ..., "W": ..., "NW": ..., "N": ..., "NE": ..., "E": ..., "SE": ...}` with 8
compass directions of the unit's facing (S = facing the camera, the camera looking north from the south as the kit does; sprite
direction 0 = S and clockwise through SW, W, NW, N, NE, E, SE), the anchor per action at the figure's feet in sheet pixels, the
elevation in the manifest header (`"elevation_deg": 40`), the same `px_per_m` 24 on the ground plane (so a man's feet-to-feet spacing
matches the top-down sheet; a figure's height on the sheet is sin-stretched by the camera), the mask semantics unchanged. **The kit:**
`assets/kit_ob/atlas.png` (+ the shade / mask passes the kit uses today) and `manifest.json` with the same piece keys as the
top-down kit, each piece rendered once at the same yaw convention as today plus the 180-degree flip the kit's hash uses, at 40
degrees elevation, with the piece's footprint rectangle on the ground plane (in metres, the same as the top-down manifest) and the
anchor at the footprint's centre on the ground, so the view places it by footprint and draws it upright. **Generated GDScript
tables:** `game/sprite_atlas_ob.gd` and `game/sprite_frames_ob.gdshaderinc` beside the existing ones (same shape, the frames per
direction), never touching the existing two files.

### Pass 3, the oblique sheets (as built, 2026-10-29)

Art half only (no `game/` or `sim/` change besides the two generated tables); built against the contract above.

- **Units.** `build.py --oblique` (or `--oblique-only`; `--units a,b`, `--out-ob DIR`) renders every unit of spec.json (45 sets, 3 props)
  in all 8 directions for every action into `tools/sprites/_frames_ob/<unit>/<action>_d<k>_<i>_<pass>.png` (git-ignored): same meshes,
  poses, three passes, camera-space key light, 24 px/m on the ground, `spec.json` `"oblique": {"elevation_deg": 40, "directions": 8}`.
  Direction k = armature yaw -90 - 45k degrees (k 0 = S, facing the camera). The camera box per unit is its top-down `render_box`'s
  radius by the highest mesh point over all frames (`ob_extent`); `info.json` holds the feet anchor. Cost: 48 units, 46 CPU-minutes
  serial; in 5 parallel Blender processes (units split by index mod 5, see "Run") **583 s wall** on the RTX 3070 (a foot set with
  sidestep / backstep about 45 s, a horse 18 s). Run:
  `~/.local/bin/blender -b --factory-startup -P tools/sprites/build.py -- --oblique-only --units a,b,c` (several in parallel, disjoint units).
- **Pack.** `python3 tools/sprites/pack.py --oblique [--mirror] [--steps] [--units a,b] [--jobs 8]` (about 55 s with `--mirror`, 2 min
  without; atlas 4096 wide, since the 8-direction set is 25000 rows tall at 2048) writes `assets/sprites_ob/{atlas_shade,atlas_mask}.png`,
  `manifest.json` (header: `elevation_deg` 40, `px_per_m` 24, `directions`, `mirror`; per unit per action `frames` per direction,
  one `anchor` and one frame size per action for all directions: the crop is the union over the directions and frames, and always
  holds the anchor, the scorpion floats above its origin), and the generated `game/sprite_atlas_ob.gd` and
  `game/sprite_frames_ob.gdshaderinc` (entry `(((set - 1) * 6 + action) * 8 + direction) * 2 + j`, j 0 rect of frame 0, j 1 anchor, step,
  frames; shader names end in `_ob`). The top-down pack is unchanged (`git diff --stat assets/sprites game/sprite_atlas.gd
  game/sprite_frames.gdshaderinc` empty; a re-render shifted 24 noise pixels in gastraphetes, crew and atlatl, the committed atlas was kept).
- **What differs from the contract.** (1) **Mirrored by default: `"mirror": true`**, only S, SW, W, NW, N rendered; SE, E, NE list the
  frames of SW, W, NW and the view draws them flipped horizontally about the anchor. Size: 8 directions would be 16.2 MB of PNG
  (shade 11, mask 5), the mirrored set is 8.9 MB (shade 6.2, mask 2.7), still over the 4 MB guide. The key light is fixed in camera space
  from the top left, so a flipped E, NE, SE figure is lit from the top right and its weapon hand is swapped; accepted at this size.
  More levers, measured: 5-bit shade and 3-bit mask posterising 5.5 MB; a per-direction crop (one anchor per direction) about -15 %
  (the 5.6 m pikes make their sets the biggest, 20 % of the atlas); a 4-frame walk. (2) sidestep and backstep are not packed for the
  three foot sets (they play the walk, as the other sets already do; `--steps` keeps them). (3) The kit is the **structures kit**
  (`p_<piece>` minis pieces: houses, walls, towers, gates, trees, rocks); the battle's own kit is the next bullet. (4) Kit files are `atlas_shade.png` and `atlas_mask.png`, not `atlas.png`.
- **Kit.** `build.py --oblique` (structures; `--ppm`, `--zex` options) renders each `p_<piece>__y0` and, where the top-down kit
  has one, `__y4` (the 180 degree flip) at tilt 50 from vertical (elevation 40; the overworld's own is 52, 38 degrees) and **8 px/m,
  true heights (zex 1.0, the overworld exaggerates up to 1.7)**: 160 sprites in 71 s into `tools/structures/_frames_ob/`;
  `python3 tools/structures/pack.py --oblique` writes `assets/kit_ob/` (2048 x 1280, 1.8 MB: shade 1.5, mask 0.3): per key `rect`, `anchor`
  (the footprint's centre on the ground, px from the rect's top-left), `footprint_m` [x0, y0, x1, y1] relative to the anchor (x east, y
  north, front south), `size_m`, `height_m`, `px_per_m`. The footprint is the bounds of the standing parts on the ground; the
  ground's vertical screen scale is sin(40) x px_per_m. The kit is 8 px/m against the men's 24: draw it scaled by the metres.
- **The battle kit (`tools/battlekit`), 2026-10-29.** `blender -b --factory-startup -P tools/battlekit/build.py -- --oblique` renders every piece
  (94 of the atlases' pieces: walls, palisades, towers, gates, bastion, houses, church, temple, stalls, trees, rocks, cliffs, the West
  town pieces, the magazine, the `lm_*` landmarks and `cv_*` civic forts; 106 built) at yaw 0 and yaw 180 into `tools/battlekit/_frames_ob/`: the same
  four G-buffer passes (albedo, world normal, height / 20 m, mask) from the 40-degree camera, 8 px/m, a canvas that is the piece's
  own projected bounds (47 s for 212 renders), the piece turned about its origin (y0 = outer face +y, away from the camera, as today; y4 = outer
  face to the camera). `python3 tools/battlekit/pack.py --oblique` (10 s) writes `assets/battlekit_ob/` (2048 x 1920, 188 sprites): albedo
  4.3 MB, nrm 0.9 MB, low (pre-lit, 4 px/m, no AO: the height field is a top-down map) 1.3 MB, manifest 52 KB; 6.4 MB in all, not shipped on
  the web. The normal pass is the world normal, so the yawed piece is lit right with the same shader maths. Footprint = the bounds of the geometry
  up to 1 m high. The top-down battlekit atlases re-pack pixel-identical (checked). The strips (`ws_*`, `ps_*`) are not rendered: the view
  builds the walls from the mitred strip mesh, which an oblique pass will want redone as upright sprites or a raised mesh.
- **Preview and test.** `python3 tools/sprites/preview/ob_contact.py OUT.png [--scale 2]` (units in 8 directions on a metre cell with
  the anchor dot, kit pieces at the same world scale with their footprint rectangle). `tests/oblique_sheets_test.gd` (the three manifests
  against the top-down ones, the rects, anchors, table length; PASS, 32631 checks).
### Pass 3, the oblique view (as built, 2026-10-29)

Pass 3 of the tabletop plan above, the view half (the oblique sheets are the art pass's, built in parallel against the
contract above). View only: nothing under `sim/` or `campaign/` changed (`git diff --stat sim/ campaign/` empty), no hash, no
lockstep input; the view reads the sim's positions, facings and heights and writes nothing. A setting, **`[video] battle_view =
top | oblique`** in user://settings.cfg (`game/board_view.gd` `pref` / `save_pref`; `--battle-view=` for a session, `?battle-view=oblique`
on the web), a **Battle view** capsule (Top / Oblique) beside Battle look's in the Options rows (`game/menu/options_rows.gd`), read at battle
start; the default stays **top**, which draws exactly as before. (The capsule shares the Battle look row: a row of its own made
the Options page scroll at 1024 x 576, menu_test.) Code: `game/board_view.gd` + `board_view.gdshaderinc` (new: the
transform), `board_lift.gdshader`, `board_ground.gdshaderinc` / `board_ground.gdshader` / `board_ground_mul.gdshader` (new: the ground
layers), `game/sprite_ob.gd` (new: the figure sheets), `game/kit_ob.gd` (new: the kit sheet), `game/kit_occluder.gd` (new: the kit's
nearness), `soldiers_ob*.gdshader`, `soldier_bases_ob*.gdshader`, `projectiles_ob*.gdshader` (new: `#define OBLIQUE` wrappers), and
changes in `battle.gd`, `overlay.gd`, `soldier_layer.gd` + `soldiers.gdshaderinc` / `soldier_bases.gdshaderinc` / `projectiles.gdshaderinc`,
`battlekit.gd` + `battlekit.gdshader`, `tree_layer.gd` + `trees_kit.gdshader` / `trees.gdshader`, `terrain_layer.gd` + `terrain.gdshader`,
`tray_layer.gd` + `tray.gdshader`, `city_layer.gd`, `city_streets.gd`, `game/campaign/tutorial_battle.gd` (its pointer).

- **The board transform.** One mapping for the whole battle view, in world pixels before the camera's zoom and pan (the Camera2D
  works in board pixels): a ground point (x, y) at height h goes to **(x, y x OBLIQUE_COS - lift)**, lift = (h - base) x px_per_m x
  OBLIQUE_SIN, `OBLIQUE_COS = 0.6427876` and `OBLIQUE_SIN = 0.7660444` fixed constants. **Decision beyond the plan:** the plan's
  formula reads "cos(40 deg) / sin(40 deg)", but the contract's sheets are rendered with the camera **40 degrees above the horizon**
  (`elevation_deg`, as `tools/sprites/build.py` `setup_camera_light` means it), which squashes the ground by sin(40) and shows heights
  by cos(40); so the constants are cos / sin of the **50 degree tilt from the vertical** (= sin / cos of the elevation), and a figure's
  base, a house's footprint and the board foreshorten alike. **Heights:** one coarse lift grid per battle (`BoardView.begin`: at most 29
  x 29 nodes, a node every max(20 m, field / 28), each the mean of 5 x 5 samples of the sim's `height_at` round it, the map's commonest
  height (1 m bins) as 0), bilinear between nodes. Every layer shares it (the shaders read it as a uniform array, `ob_lift[211]`, packed
  four to a vec4; no vertex texture read), so the figures, trays, overlay and kit meet the ground exactly; the ground's own shading (hill
  shade, terraces, contours, flock) still comes from the fine 2 m height texture. Hills rise toward the camera by up to 15 m x 0.77 on
  the test maps (battle_2000 on a hill: 15.6 m; bench_4000_hills 9.8 m; the West town 6.4 m). **The inverse** (`to_world`,
  `ob_world`): the board point to the ground plane at h = 0, then Newton steps along y (the lift is linear along y inside a cell, so a
  step inside one cell is exact): 3 for taps, 4 per pixel in the ground shader. Nearness along the view (what draws over what):
  y x OBLIQUE_SIN + h x OBLIQUE_COS (`near_px`, `ob_near`).
- **The ground.** `terrain.gdshader`: in the oblique view its rectangle covers the field's board area (`BoardView.board_field`, the
  lift's range above and below) and every pixel finds the ground under it (`ob_world`), then shades as before in that point's world
  coordinates (the derivatives, so the screen-width lines and the fades, follow); outside the field it is transparent (the board
  layer's edge and the table show). **Draw-based layers** (the board edge and table, the decals, the cliffs, the works, the city's
  own drawing, gates, stairs and banners, the landmark pieces, the rubble, the overlay and its wagons) get `board_lift.gdshader`
  (`BoardView.lift_node`): every vertex goes to its board point (squashed and lifted, so long straight lines are exact only at their
  ends); their cull rect is widened (`canvas_item_set_custom_rect`), since the drawing moves on screen. **Textures on the ground** (the
  streets, the Paths hatch, the kit's baked shadow: Sprite2D quads) use `board_ground.gdshaderinc`: the quad stretched over the area its
  ground can rise to, each pixel sampling the texture at its own ground point, as the terrain does. The streets lose the dark footing
  under a house (the house stands up; its ground is the lane's).
- **The overlay.** The ground marks lie on the board (footprints, the order preview, the selection box, the ghosts, range rings,
  the deployment zones, waypoint chains). The screen-scale marks stand **upright**: `Overlay._up(anchor)` sets a draw transform
  carrying a mark (`BoardView.up_xf`: scale (1, 0.999), origin anchor x 0.001) that the lift shader recognises, drawing the following
  items unsquashed at the anchor's board point: unit markers (floating `marker_dy(r)` = 2.2 r + 1.7 m above the unit's centre, over the
  figures), standards, tokens, the last-seen ghost marker, free engines and towers, and every label (`_dstr`). The marker is still the
  tap target: `Battle._marker_unit` measures on the board (`marker_board`).
- **Input.** `_screen_to_world` = the canvas inverse then `BoardView.to_world`; `_screen_to_board` for zoom and pan (`_zoom_at`,
  `_clamp_camera` to the board field); `_cam_to(world)` for every "centre on" (`--cam`, `--cam-unit`, cards, the demo aids); the fit
  frames the armies' box on the board; a box selection is tested on the board; a three-finger or mouse group move's screen drag is
  divided by OBLIQUE_COS along y. `Battle.world_to_screen` and `marker_screen` serve the tests and the tutorial's pointer.
- **Upright figures.** `SoldierLayer` in the oblique view uses the `OBLIQUE` shader variants (both data paths): each man an upright
  quad standing at his feet's board point (plus his wall walk's height for a unit on a wall: `wall_h`, texture block 8 + 64 x dm / the
  CPU path's sprite column + 16 x dm), his frame by his drawn heading against the camera (8 directions, 0 = S facing it, clockwise;
  the sheet's mirror honoured), his action as on the top-down sheet (idle, walk, attack, death; the side and back steps play the walk,
  slower, a back step reversed). **The CPU-fed path needs no texture read in the vertex stage:** the vertex stage only places the set's
  quad (`ob_cell[set]`: half width, above and below the feet in sheet px, the frame counts per action packed 4 bits each); the fragment
  stage looks the frame's rect and anchor up in `ob_tab` (RGBA float, nearest) and clips to it. An action without upright frames
  (the stand-in's death) is the top-down sprite lying on the board: the casualties lie as their last frame. The **bases** are the
  pass 1 circles squashed into ellipses under the feet; the **missiles** fly a real arc over the board (height up to 0.28 of the range
  for a stone, 0.18 an arrow, 0.08 a javelin, 0.03 a bolt), turned along their board path.
- **The sort.** Nearer over farther. **Texture path:** a per-tick order (texture block 9, the instance's man): every man (and engine)
  sorted by ground y with native calls only: a 64-bit key, y in the high half and the index in the low, built by blitting the y
  column next to a fixed index column of an RGBA8 image, `to_int64_array().sort()`, the low halves read back (110-200 us a tick for
  4,000 men; `order_us`, printed by `--frame-stats` in the oblique view). **CPU-fed path:** the buffer reordered a unit at a time with
  native blits (units by their centre's y; a unit facing the camera has its rows reversed, so its rear rank draws first): about 110 us
  a tick. The two paths draw the same pixels for a standing line (tests/soldier_facing_test.gd with `--battle-view=oblique`: 0 px of
  8,202 differ) and differ by 48 to 361 px of 20,000 to 33,000 for marching or stepping men, where the per-man and per-unit orders
  part (the CPU path's sort is the coarse one; it is the fallback for the tablets).
- **The sheets and the fallback.** `game/sprite_ob.gd` loads `assets/sprites_ob` by the contract (the top-down sheets' unit keys
  mapped to the set numbers through `SpriteAtlas.SETS`; per action "frames" by direction S..SE, "anchor" per action or per direction;
  "mirror"; a warning when `elevation_deg` is not 40). Until it exists: a warning once, and the **stand-in**, tools/sprites/iso's
  `iso_heavy_swords` sheet (32 degrees, 8 directions, the walk only; d0 faces east, counter-clockwise, so contract direction d is its
  (6 - d) mod 8) loaded from the file (it is not imported: desktop runs from the project only), for every set but the engines (drawn
  flat); idle is its first walk frame. Without either, every figure is flat. **The kit sheet:** `game/kit_ob.gd` loads `assets/kit_ob`
  (atlas.png, manifest.json: per piece "rect", "anchor" at the footprint's centre on the ground, "foot" in metres, "px_per_m"); until
  then the stand-in. Testing aids: `--sprites-ob-dir=` and `--kit-ob-dir=` point the loaders at another folder (both paths were run on
  synthetic sheets made from the iso and top-down atlases).
- **The kit upright.** `BattleKit` in the oblique view draws every piece (houses, towers, gates, rocks, the West town's stakes and
  bastions) upright at its ground point: the kit sheet's frame with its anchor there (unturned, scaled by the instance's footprint
  scale), else **the stand-in, the top-down piece stood up with its lower edge at the footprint's centre**. **Decision beyond the
  plan:** the strip rings' **walls are extruded** in the shader instead of drawn from sheet pieces (a piece rendered once at 40 degrees
  cannot follow a wall at any angle): per stretch of at most 8 m (none in a gate's opening) a front face (the side the camera sees)
  and a top, as MultiMesh rows already on the board, shaded as dressed stone in courses with a darker foot and a lit lip (a palisade:
  pointed stakes), a parapet along the top's front edge. Pieces and wall rows are **one MultiMesh sorted by nearness** (farther
  first), so a nearer house hides a farther one; the gates' and fallen buildings' rows are rewritten in place (`_ob_slot`). Graphics
  Low draws the same order from the pre-lit atlas, the walls as flat-shaded quads.
- **Men behind the kit.** The soldiers draw after the kit, so a man in front of a house covers it; a man behind one must not show:
  `game/kit_occluder.gd` draws the kit's sorted MultiMeshes again every frame into a screen-sized SubViewport of its own world with the
  main view's canvas transform (synced at `frame_pre_draw`), each opaque pixel coloured with its nearness (16 bits in R, G; the
  nearest wins, the MultiMesh being sorted); the figure and base shaders read it at `SCREEN_UV` and drop a fragment where a nearer
  piece is. A man on a wall walk is nearer than the wall under him (his height counts), so he stands on it. Not on Graphics Low (no
  MultiMesh there: the men draw over the kit). `--no-occluder` turns it off.
- **Trees.** The kit trees stand up at their feet (sorted by y once at build, the woods and the orchards each), the crown unturned
  above a trunk drawn in the shader, no cast shadow of their own (the ground's crown shadows lie under them); each part of a tree fades
  by the men on the ground it hides (the occupancy sampled behind it), so men in or behind a wood show as under a canopy in the top
  view. They draw after the men (not in the occluder: 40,000 trees twice would cost too much). Ground cover lies on the board.
- **Quality and cost** (desktop RTX 3070, 1280 x 720, vsync off, `--quality=high` unless noted, 8 s after tick 600 with the sim running,
  mean frame ms; each view at its own default fit, which in the oblique view is closer since the board is shorter; HEAD = this tree
  with `--battle-view=top`, identical to the top view before):

  | scenario, zoom, path | top | oblique | delta |
  |---|---|---|---|
  | bench_4000_hills, default fit, GPU (3 runs) | 7.00 | 7.07 | +0.07 |
  | bench_4000_hills, default fit, CPU path (3 runs) | 7.21 | 7.25 | +0.04 |
  | bench_4000_hills, zoom 2.0, GPU (2 runs) | 7.22 | 7.16 | -0.06 |
  | bench_4000_hills, default fit, Graphics Low (2 runs) | 6.55 | 6.56 | +0.01 |
  | west_town, default fit (2 runs) | 4.23 | 4.25 | +0.02 |
  | west_town, zoom 2.0 (2 runs) | 3.70 | 3.93 | +0.23 |
  | test_woods, default fit (2 runs) | 1.34 | 1.36 | +0.02 |

  Under the 1 ms limit everywhere; the sort is 0.1 to 0.2 ms a tick (once in 6 frames at 60 fps); the town's +0.2 ms at zoom 2 is the
  occluder pass and the extruded walls. These frames are bound by the CPU; the GPU cost a phone would see is the ground's per-pixel
  inversion (4 Newton steps of 4 uniform reads each), the figures' two table fetches a pixel and the occluder pass.
- **Checked:** scripts clean (warnings as errors); `battle_screen_test` RESULT PASS (the whole run twice, the second in the oblique
  view, 148 checks, the battles opening in that view with the order block); windowed `input_test` RESULT PASS in both views (393 checks
  each; with `-- --battle-view=oblique` every tap, drag, pinch, box, chip and card step; its world-to-screen helpers go through
  `Battle.world_to_screen` / `marker_screen`, the gate-marker set-up places the unit under its marker by the board, and the Shift + right
  drag line expects the facing of the line's own ground); `soldier_facing_test` RESULT PASS (top view; the oblique numbers above);
  `menu_test` RESULT PASS (the new capsule sets its value; the Options page still fits 1024 x 576); `lockstep_test` RESULT PASS; `git diff --stat sim/ campaign/` empty. Shots (1280 x 720, the stand-in sheets): the field battle at the
  default fit, zoomed in on a line, the West town with its fort.
- **Open.** The real sheets: `assets/sprites_ob` and `assets/kit_ob` (until then heavy swords for every set, engines and the dead flat,
  houses as stood-up roofs, trees as stood-up crowns); the stand-in is not in a web export (tools/ is not packed), so the web shows
  flat figures in the oblique view until the sheets land; the default view (top until the owner flips it); the Tab S7 for the uniform
  arrays read in the CPU path's vertex stage (the kit trees already do so) and the per-pixel ground inversion; smoke, fire and the
  effects still lie flat on the board; pass 2's tufts want upright blades; the standards and tokens float with the marker but ignore a
  wall walk's height; long overlay lines across a hill follow the ground only at their ends; the CPU path's coarser order.

#### The real sheets (2026-10-29)

The view switched from the stand-ins to the art pass's sheets (above). View only; `sim/` and `campaign/` untouched.

- **Figures.** `game/sprite_ob.gd` reads `assets/sprites_ob` (the manifest's header: `elevation_deg` 40 above the horizon, the 50 degree
  tilt the board's constants already use; `px_per_m` 24, the board scaling it by px_per_m / 24): every one of the 45 sets has its
  8 directions; `"mirror": true` is honoured (SE, E, NE list the SW, W, NW frames and are drawn flipped about the anchor: before, the
  loader flipped only a direction that was missing). Texture first (`ResourceLoader.exists`), then the stand-in, then flat; the web
  export leaves the folder out, so it prints one notice and falls back (stand-in on desktop runs from the project, flat on the web).
  The engine sets (bolt, stone, scorpion, cannon, mortar, naval gun) stand up too now; the dead lie as the death's last frame.
- **The kit.** `game/kit_ob.gd` now reads **`assets/battlekit_ob`** (the battle's own kit: albedo / world-normal / low passes, `<piece>__y0`
  and `__y4`, the anchor at the footprint's centre, 8 px/m): every piece the battle draws is in it (the 62 block 1 pieces, walls to trees and
  rocks, and the 32 landmark and civic pieces), so **`assets/kit_ob` (the structures kit, the overworld's minis) is not used by the
  battle**: no battle piece maps to a `p_` key only. A piece's row carries code 100 + its sprite (a table of up to 192 in
  `battlekit.gdshader`), its footprint's centre and its x scale; the shader lights it from its own normal pass exactly as the top-down kit
  (the normal is the world's, so no turn), culture tint, rim, outline, the look's saturation and contrast. **y0 or y4:** the 180 degree
  render when the instance's image right points west (`i_e.x < 0`: the hash flip, or a footprint turned past 90 degrees), else y0. A
  piece turned near 90 degrees shows its yaw 0 / 180 sprite (only two renders): its width is then the piece's, not the footprint's.
  The town plan's landmarks (`lay.pieces`) join the sorted MultiMesh as sprites (no longer drawn flat by `_PieceDraw`). The walls stay
  extruded. Graphics Low draws the sheet's pre-lit pass (rects halved). The trees (`tree_layer.gd`) draw the sheet's tree sprites
  (yaw 0) at their feet with the same lighting; the stand-in trunk is gone.
- **The sweep.** `tests/oblique_sets_shot.gd` (windowed, `-- --out=DIR`): every set on flat ground, a unit's men in a row facing S, SW, W,
  NW, N, NE, E, SE, a set a row at zoom 2, nine frames put together into `p3b_sets.png`. Feet on the ground for all 45 (the contact
  shadow under each); horses, camels and the elephant stand taller than the men by the sheets' true heights (the elephant's howdah
  about twice a man); the mirrored E, NE, SE are lit from the upper right and carry the weapon in the other hand (the art pass's
  accepted cost); pikes and lances read at full length.
- **Checked:** scripts clean; `battle_screen_test` RESULT PASS (both views, 148); `input_test` RESULT PASS in both views (393 each);
  `soldier_facing_test` RESULT PASS (top; with `--battle-view=oblique` a standing line 0 px differ, moving men 36 to 873 px of 18,000 to
  37,000: the CPU path's per-unit order); `lockstep_test` RESULT PASS.
- **Cost.** The machine was shared during this round (load 12 to 21 from other processes), so the frames are noisy: bench_4000_hills at
  the default fit, interleaved, best of 10 each: top 6.22 ms, oblique 6.32 ms (+0.10; the clean round above: top 7.00, oblique 7.07);
  the sort 104 to 217 us a tick, as before. The bigger atlas (4096 x 5248, no mipmaps) shows nothing measurable
  on the desktop; a phone's texture limit (4096 on many) and memory are the open questions (the sheets are not shipped on the web).
- **Open.** A phone build of the sheets (size, the 4096 limit, mipmaps), the owner's eye on the kit's yaw choice for turned houses and on
  the baked top-down shadow under the upright houses, the CPU path's order.

#### The on-demand pack for the web (2026-10-29)

The web export keeps `assets/sprites_ob` and `assets/battlekit_ob` out of `index.pck` (the "Web" preset's `exclude_filter`, unchanged; the
main pack's size does not move) and `tools/export_web.sh` now also writes **`build/web/oblique.pck`** with the "Web oblique pack" preset
(`--export-pack`: the five atlas PNGs with their imports plus the two manifests; `assets/kit_ob` stays out, the battle does not use it).
View only; `sim/` and `campaign/` untouched, the native builds unchanged (the files are in their pack).

- **Fetch.** `game/oblique_pack.gd` (a node on the root, so it outlives scene changes): on the web, with the Battle view Oblique and
  `res://assets/*_ob/manifest.json` absent, `ObliquePack.ensure()` downloads `<page directory>/oblique.pck?v=<ob token>` with an
  HTTPRequest (the body written to `user://oblique.pck`; the web build does not honour `download_file`), mounts it with `ProjectSettings.load_resource_pack` and calls `SpriteOb.reset()` /
  `KitOb.reset()` (they forget a failed decision) so the next `ensure` finds the real sheets. Triggers: the start screen (`main.gd`, deferred),
  the Battle view row picking Oblique, and the battle's `_ready` (which also waits for a running download, so the first oblique battle
  already draws the real sheets). A bar on its own canvas layer shows "Downloading the oblique sheets, 15 MB  42%" with a Cancel button.
  A failed or cancelled fetch (HTTP error, network, a pack that will not mount or lacks the sheets) leaves the loaders' one notice and the
  flat figures; the next `ensure` (another Oblique pick, the next boot) tries again. Once mounted it stays for the session.
- **Cache.** The server answers every file `Cache-Control: no-cache` with an ETag (a 304 after the first time); `build_stamp.txt` gains an
  `ob:<sha1 of the sheets>` token, used as `?v=` so a URL changes only when the sheets do. No server change: `web.go` serves any file of
  `build/web`, `.pck` as `application/octet-stream`, compressed on request.
- **Tests.** `tests/oblique_pack_test.gd` (the state machine against a stubbed request: absent, downloading, loaded, cancel, HTTP and
  network failures, an unmountable pack, a pack without the sheets, retry, `wait()`, the URL); `server/cmd/webcheck -oblique`.

#### Walls as a mesh, the ghost and the default (2026-10-30)

The owner's look at the oblique view: "oblique as default and keep working on it; the walls need some sorting to look
right; and we need to work out how we are going to see inside the walls". View only: `sim/` and `campaign/` untouched
(`git diff --stat sim/ campaign/` empty), no hash, no lockstep input. Code: `game/battlekit.gd` (`_ob_walls`,
`_ob_wseg_rows`, `_ob_face`, `_ob_top`, `_ob_fill`, `ob_fade_update`, the Low path's `_wall_row`), `battlekit.gdshader`,
`kit_occluder.gd`, `soldiers.gdshaderinc`, `soldier_bases.gdshaderinc`, `board_view.gd`, `oblique_pack.gd`,
`menu/options_rows.gd`, `battle.gd`; `tests/oblique_pack_test.gd`.

- **Walls as one mitred geometry per ring.** The per-8 m slabs (a front face and a full-thickness top each, unmitred, so
  they overlapped and fanned at every bastion and corner: "a pile of paper cards") are gone. Each ring's outline (the
  sim's polygon, merged and counter-clockwise as `_wall_ring` takes it) is offset to four lines across the sim's
  thickness t: the outer face, the merlons' inner edge (+ pp, the sim's parapet), the walk's inner edge (+ 4 m,
  `MapGen.WALK_W`) and the inner face, each **mitred at every vertex** exactly as the top view's strip is (a mitre longer
  than `MITRE_MAX` thicknesses bevelled, the wedge filled with its own rows). The cross-section is the battle kit's own
  (`tools/battlekit/build.py` `b_wall_sim`): the body to the walk's height h, merlons 1.2 m above it on the outer edge
  (1.1 m wide every 2 m, as the strips), the 4 m walk, the inner rampart 1.1 m lower. Per standing stretch of at most
  8 m (`WALL_SEG`, kept only for the sort's locality: subdividing a mitred band along both its lines is exact) the rows
  are: the outer face (0 to h + 1.2, the gaps between the merlons cut out), the merlons' inner face, the step down from
  the walk, the rampart's inner face, the walk's top (outer edge to the walk's inner edge), the merlons' tops, the
  rampart's top, and **end caps** where the ring is cut. Every face is exactly its edge between two lines' points, so
  adjacent faces meet with no gap and no overlap. **Cuts:** a gate's opening (the gate piece stands in it), a tower's body
  (0.8 of its radius: the wall ends inside the tower sprite) and a **breach** (the sim's `C_RUBBLE` cells sampled every
  metre along the centre line): the walls are rebuilt when `sim.rub_n` changes, so a breached stretch is a gap with
  capped ends and the rubble lying in it. A palisade is the same geometry with pointed stakes (0.46 m) for merlons, a
  plank walk and an earth bank (`--kit-palisade` draws any ring as timber, a testing aid: no scenario has a palisade).
- **The rows.** Still rows of the one nearness-sorted kit MultiMesh (no separate ArrayMesh: a canvas has no depth buffer,
  so only one sorted draw lets a nearer tower or house cover a wall and a nearer wall cover a house). A row carries
  world px in its transform (a face: its ground edge A, B and its top; a top: three corners) and small numbers in its
  custom data: **the compatibility renderer keeps a MultiMesh's custom data in half floats** (found here: a code of
  1000 + 128 x height decoded to nonsense), so the code is 400 + kind + 8 x height dm (exact below 2048, above the kit
  sheet's 100 + 288), the top's fourth corner an offset from the third, the culture a uniform. The shader puts every
  vertex on the board through the shared lift grid (per corner, so a wall follows the ground) and computes its
  nearness per vertex for the occluder. **Sort keys:** the stretch's centre's nearness, then within it the faces turned
  away, the tops lowest first (rampart, walk, merlons: the merlons stand on the walk's outer edge and must cover it),
  then the faces toward the camera. A tower sorts by its front (centre + 0.8 r toward the camera) and a gate by the
  wall's half thickness, so the wall beside a tower draws under it and the wall in front of it over it.
- **Shading.** Dressed stone in 0.55 m courses (the old pattern), each face lit by its own ground normal against the
  kit's key light (upper left; half-Lambert so a face toward the camera sits in half shade), a darker foot, a lit lip
  along the top of the solid part (the crenel bed in the gaps, the merlons' tops); the merlons' tops lighter, the walk
  darker than the faces (worn flags, a lit lip at its inner edge) and the rampart darker still, so the wall reads thick
  but walkable; the look's saturation and contrast as the kit's. **Graphics Low** draws the same rows flat-shaded (by
  the same face direction) as polygons in the sorted order (merlons as a solid band); edge-on faces and bevel corners
  are skipped (no "Invalid polygon" from the walls).
- **Seeing inside: the ghost** (the main session's decision, built as given). A man whose pixel is behind a nearer kit
  piece or wall (the occluder's nearness, as before) is no longer dropped: he is drawn as a **ghost**, his figure flat in
  his unit's faction colour (the palette's primary, the standard's colour, lifted 15 % toward grey so a black faction
  still shows) at 40 % with a 1 px lighter outline (a neighbour pixel one screen pixel away outside the figure: four
  extra fetches, only on ghosted pixels), in both data paths (`soldiers.gdshaderinc`, so `soldiers_ob.gdshader` and
  `soldiers_ob_cpu.gdshader`); a flat figure (no sheet) ghosts without the outline; his base is not drawn; a corpse
  behind a piece is not drawn either (a field of grey dead read as noise). Only the part of a man that is behind the
  piece ghosts, so a man half behind a parapet shows his head and shoulders and his legs as a ghost.
- **Seeing inside: the fading face.** Past camera zoom 1.5 (`FADE_ZOOM`), every 6 frames, each on-screen stretch whose
  face toward the camera (|normal.y| > 0.3) has a unit box (its living men's bounding box, 9 sample points; not on a
  wall; not hidden from the viewer) from its far face to 10 m beyond it (`FADE_BEHIND`) fades; a fading value moves
  over 0.3 s, written into the stretch's rows' custom data every frame while it moves (a clock in the shader would
  need seconds in a half float). **Decision beyond the plan: the whole stretch fades, not only the face.** Seen from
  40 degrees the face of a 6 to 9 m wall covers only the wall's own body on the screen; what hides the ground behind
  it is the walk and rampart tops (the top of a 7 m wall covers about 8 m behind its inner face), so fading the face
  alone showed nothing; towers and houses never fade. The faded stretch draws at 55 % alpha; the occluder writes the
  fade in its B channel, and a man behind a fading stretch is drawn in full colour at 60 % alpha mixed from his ghost
  by the fade, his base too: he shows through the wall. `--no-wall-fade` turns it off (screenshots of the ghost alone).
- **The kit's turned houses (pass 4's renders).** `KitOb.MAX` and the shader's `ob_krect` / `ob_kanch` grew to 288;
  `_ob_sprite` picks the render whose yaw is nearest the instance's (`KitOb.index_yaw`, the yaw from the image right
  `i_e` with y negated), so a house turned near 90 degrees shows its y2 / y6 render at the footprint's width; pieces
  with only y0 / y4 draw as before. (The landmark pieces still use `KitOb.index`.)
- **Oblique as the default.** `[video] battle_view` defaults to **oblique** (no setting, or anything but "top"); the
  Options capsule still offers Top (its tip now says Oblique is the default, the ghosts, and the web's one download);
  `--battle-view=top` still works. **The web flow for a first-time player** (`game/oblique_pack.gd`): the start screen
  starts the fetch of `oblique.pck` (12 MB) with the progress bar and Cancel; a battle started meanwhile waits for it.
  A battle whose sheets are not mounted is drawn **from the top** (`BoardView.web_top`, set by the battle after the
  wait), never as flat oblique figures. After **Cancel**: that battle from the top; the menu does not ask again by
  itself; the next battle's start asks once more (one bar per battle, no loop). After a **failure**: one notice for the
  session ("Could not download the oblique figures: battles use the top view. Pick Oblique in Options to try again."),
  no automatic retry; picking Oblique in Options retries (`ObliquePack.should_start(state, user, battle)`, tested).
  The headless determinism, lockstep and campaign tests do not read the view (`git grep` finds no `battle_view` /
  `BoardView` in them); `battle_screen_test` pins top then oblique (`BoardView.force`); `menu_test` restores the
  settings file; `input_test` and `soldier_facing_test` follow the default unless `--battle-view=` is given (both views
  run below).
- **Testing aids.** `--move-unit=U:x,y[,w]` (battle.gd: unit U marched there, its side's AI held for the march, the sim
  run until it arrives, at most 900 ticks; it cannot get a unit through a closed gate), `--no-wall-fade`,
  `--kit-palisade`; `--seed=N` makes shots repeatable.
- **Cost** (desktop RTX 3070, 1280 x 720, vsync off, `--quality=high --seed=7`, 8 s of `--frame-stats` after tick 600,
  mean frame ms, 3 runs each interleaved with HEAD before this pass (a `git archive` copy); the machine was shared and
  rounds 2 and 3 overlapped the windowed tests, so the spread between runs is 0.1 to 1.5 ms and the deltas are noise):

  | scenario, zoom, view | before | after | delta |
  |---|---|---|---|
  | bench_4000_hills, default fit, top | 7.89 | 7.97 | +0.08 |
  | bench_4000_hills, default fit, oblique | 8.22 | 8.13 | -0.09 |
  | bench_4000_hills, zoom 2, top | 7.36 | 7.47 | +0.11 |
  | bench_4000_hills, zoom 2, oblique | 8.38 | 8.30 | -0.08 |
  | west_town, default fit, top | 4.56 | 4.67 | +0.11 |
  | west_town, default fit, oblique | 4.76 | 4.78 | +0.02 |
  | west_town, zoom 2, top | 4.27 | 4.28 | +0.01 |
  | west_town, zoom 2, oblique | 4.61 | 4.51 | -0.10 |

  Within the +0.3 ms allowed on west_town zoom 2 (the harbour fort's walls are 418 rows, drawn twice with the
  occluder; the fade's look every 6 frames is a few unit boxes against the on-screen stretches; the
  ghost's outline fetches run only on ghosted pixels). The top view does not draw any of it.
- **Checked:** scripts clean (warnings as errors); `battle_screen_test` RESULT PASS (148, both views); `lockstep_test`
  RESULT PASS; `input_test` RESULT PASS by default (oblique, 393) and with `-- --battle-view=top` (393);
  `soldier_facing_test` RESULT PASS by default (oblique: a standing line and every set 0 px differ; the four moving cases
  36 to 870 px of 18,000 to 37,000 differ, now allowed up to 4 % in the oblique view, the CPU path's known per-unit
  order) and with `-- --battle-view=top` (all exact); `menu_test` RESULT PASS; `oblique_pack_test` RESULT PASS (39);
  `git diff --stat sim/ campaign/` empty. Shots (1280 x 720, `--seed=7`): the harbour fort at zoom 1.8 and 1.0, every
  wall culture at the default fit (siege_city, siege_castrum, siege_polis, siege_oppidum, west_town, west_fort_storm),
  a Rome gate and towers at zoom 2, a breach (`--demo-breach`), a palisade (`--kit-palisade`), Graphics Low, both soldier
  paths, the ghosts (men in the fort's bastions after the storm, cavalry behind the Rome south wall, men behind houses)
  with and without the fade, the town's turned houses.
- **Open.** The owner's eye on the walk's darkness and the ghost's strength (a white faction's ghosts read brighter
  than a dark one's); a ghost crowd behind a long wall is a grey mass at the default fit (the fade only acts past zoom
  1.5); men climbing a ladder or stepping onto the walk ghost for a moment where the sim puts their feet inside the
  wall; the stairs (`over_node`) still lie flat as lifted drawings (they read as light ramps on the inner face); the
  gatehouse sprite's dark passage under it; the baked top-down kit shadow under the walls; the landmark pieces' yaw
  (still y0 / y4); the Tab S7 and the phone GPU cost of the occluder pass with more rows; the web flow above wants a
  real first-visit check on the phone (webcheck `-oblique` covers the fetch, not the Cancel path).

#### Pass 3 leftovers (2026-10-30)

The seven leftovers the as-built list above named, in that order. View only: `sim/` and `campaign/` untouched (`git diff --stat sim/
campaign/` empty), no hash, no lockstep input. Code: `game/battlekit_shadow.gd` + `kit_shadow_ob.gdshader` (new), `game/gun_smoke.gd`,
`game/overlay.gd`, `game/tuft_layer.gd` + `tuft.gdshader` (new), `game/terrain_layer.gd`, `game/tray_layer.gd` + `tray.gdshader`,
`game/battle.gd`, `game/unit_icons.gd`, `game/soldier_bases.gdshaderinc`, `tests/input_test.gd`.

- **1. The kit's ground shadow stands up.** In the oblique view `battlekit_shadow.gd` no longer rasterises the upright pieces (houses,
  towers, gates, bastions, rocks, props: every piece but the walls, palisades, low walls, stakes, cliffs, piers and the tree and bush
  sprites, `OB_FLAT`) into its top-down height field; the walls keep the field (the strips' cast shadow and rim are right for a wall).
  Each upright piece gets instead, in one MultiMesh under the pieces (`kit_shadow_ob.gdshader`, multiplied over the ground, lifted with
  it), the footprint's **soft contact shadow** (60 % at the foot, gone 1.5 m out; the footprint's oriented box, from the piece's
  anchor and scale) and a **cast shadow to the lower right** (the lamp is the upper left key), the footprint swept along (0.707, 0.707) by
  `CAST_K` 0.35 x the piece's height (the atlas normal pass's highest B x 20 m x the instance's height scale x `H_SHADOW` 1.4, capped
  15 m), 45 % dark, soft-edged over 1.3 m, a little lighter with distance. A gate that breaks or a building that falls refreshes the
  rows (`_ob_refresh`, from `rebake_*`). **Differs from the brief:** the brown squares in `fort_12.png` are **not** this shadow. They stay
  with `--no-kit-shadow`, and they are the terrain shader's *trodden ground* (`terrain_layer.gd _west_built`: the West town's urban
  channel at 4 m cells, 8 m round every house and road, hence the stair-stepped edge) which the top view has too. The squares are unchanged
  here (a design item for the owner: soften the mask's edge or lighten it in the oblique view). The top view is unchanged (a paused
  `--seed=7` shot of both trees differs only in the animated sea and under the new bases).
- **2. Upright effects.** The gun smoke (`GunSmoke.draw`, `upright` by `BoardView.oblique`): each puff is the same cotton-wool tile
  drawn as a billboard at its ground point (`up_xf`), lifted by `0.7 x` its radius plus its rise, a dust kick by 0.3 of its radius, the
  muzzle flash at the muzzle's height and its tongue along the shot's screen direction; the long-fire haze keeps lying on the board. In the
  overlay (`_up(p)` per effect, so the existing offsets, which already meant "up", now stand): fire sparks and smoke, blast flash and
  smoke (its shock ring stays flat), ruin dust, dust puffs, chips, engine hit puffs (the hit line and ring stay flat), burning men,
  burning gates, engines and equipment, burning buildings and their smoke columns. They draw in the overlay, after the men
  (the brief allowed that for smoke): a puff in front of a man covers him, a man in front of a puff does not cover it.
- **3. Upright tufts.** `tuft_layer.gd`: the shader's tufts are off in the oblique view (`tufts_on` false there) and a MultiMesh of small
  upright quads stands in their place (High and diorama only, from camera zoom 1.2, at most 6,000): `tuft.gdshader` draws three blades in
  each (0.2 to 0.32 m, dark at the foot, lighter to the tip and on the left, a little lean). **Same hash as the shader's:** the 0.9 m cell
  id, the 0.24 threshold, the tuft's offset in the cell and the blades' lengths come from the same `hash12` inputs (ported to
  GDScript), so a tuft stands where the top view's stroke is. Open ground only, tested on the sim's own data: no felt (the wood density at
  the shader's 0.075 contour), road, plaza or urban cell, field, water, ditch or river bank, building or other obstacle cell, nor ground
  steeper than 0.45. (The West town's untrodden yards, which the shader keeps flocked, get no tufts here: the urban flag alone cannot say.)
  **Differs from the brief:** not rebuilt whenever the camera moves by a cell. The ground is cut into 27 m chunks (30 cells), each
  worked out once (at most two a frame, kept: 80 at most) and the MultiMesh buffer is put together from the chunks in view when that set
  changes, so a pan costs one buffer copy a chunk crossed and no per-frame work; a 6,000 cap takes the chunks nearest the view's centre first.
  Tufts sit under the men and under the kit (the ground layer), and are not sorted with them (0.3 m tall).
- **4. Standards, tokens, markers and trays on a wall walk.** `TrayLayer.wall_lift(sim, u)`: the unit's wall walk height
  (`sim.wall_h` for a unit with `u_wall > 0`, the value the soldier layer's `_unit_ext` carries to the men) as board px. The marker,
  the standard, the tokens and the marker's test circle in the overlay, `Battle.marker_board` (the tap target) and **the tray itself**
  (custom data z of its instance, read by `tray.gdshader`: not in the brief, but a tray left at the wall's foot under men standing on
  the wall looked wrong) go up by it. `tests/input_test.gd` (the gate doorway's marker set-up) adds the lift to its unit's marker.
- **5. Long overlay lines follow the hill.** `Overlay._dl`, `_dp`, `_dd`, `_da`: in the oblique view a ground line, polyline, dashed line
  or arc is drawn in pieces of at most 8 m (`SEG_M`; dashes in whole dash periods so the pattern carries on across the joins; arcs get
  the point count their length needs), so it follows the lift grid. Used for the order preview and chains, move and attack lines,
  the fire and blocked lines, range arcs and sector edges, the occupy marks, wall stretches and the formation box; the markers' own small
  drawing is unchanged. `order_preview.gd` draws nothing (it predicts orders), so it is not touched. The top view calls the engine's
  functions directly.
- **6. "Invalid polygon data".** The unit marker's glyph for icon 3 (three pikes) drew each pike's tip as a triangle of about 0.04 s^2:
  under about 4 px2 (a marker of radius 22 px / zoom, so from zoom 2) the engine's triangulator refuses it and prints the error each frame
  (10 to 23 lines a frame at HEAD: both views). Below s = 10 px the tip is now a short heavy stroke. Zoom 1.8 and 3 on the town and zoom 3 on
  the fort in both views print none.
- **7. Flock on the bases.** `soldier_bases.gdshaderinc` (both views, both data paths): inside the ring the base is a dark earth with round specks
  of two greens and straw (a 0.2 base-radius lattice, hashed by cell and by the man's position, so no two bases match), a tenth of the
  old faction-tinted fill kept; fades to its mean colour where a speck would be under about 2 px. The faction-coloured ring, the lit top and the
  contact shadow are as before; Graphics Low keeps its plain ellipse.
- **Cost** (desktop RTX 3070, 1280 x 720, vsync off, `--quality=high --seed=7`, 8 s after tick 600, mean frame ms, interleaved,
  before = 5227d38 in another folder; the machine was shared with other builds, so the runs scatter by 1 to 2 ms and the means are
  good to about 0.3):

  | scenario, zoom, view | before | after | delta |
  |---|---|---|---|---|
  | bench_4000_hills, default fit, oblique | 6.75 | 6.74 | -0.01 |
  | bench_4000_hills, default fit, top | 6.47 | 6.58 | +0.11 |
  | bench_4000_hills, zoom 2.0, oblique | 6.56 | 6.42 | -0.15 |
  | bench_4000_hills, zoom 2.0, top | 6.46 | 6.10 | -0.36 |
  | west_town, default fit, oblique | 3.91 | 3.99 | +0.08 |
  | west_town, default fit, top | 3.82 | 3.84 | +0.02 |
  | west_town, zoom 2.0, oblique | 3.77 | 3.79 | +0.02 |
  | west_town, zoom 2.0, top | 3.79 | 3.89 | +0.10 |

  (Means of the first two of three runs: the third ran while the machine was loaded by other builds, 7 to 15 ms, before and after alike. The tufts are in the west_town zoom 2.0 oblique line: +0.02 ms.)

- **Checked:** scripts clean (warnings as errors); `battle_screen_test`, `lockstep_test` RESULT PASS; windowed `input_test` RESULT PASS in
  both views (the oblique run after the test's wall-lift set-up); `soldier_facing_test` RESULT PASS; `git diff --stat sim/ campaign/`
  empty. Shots (1280 x 720) before / after for each item: the town's houses, a musket line's smoke, the field's tufts, the bases and a siege
  wall's markers.
- **Open.** The brown trodden-ground squares round the West town's houses (item 1; see there); smoke is drawn after the men, not sorted with
  them; the tufts' hash agrees with the shader's to float precision (a cell at the 0.24 threshold may differ), and the West
  yards get none; the flock is dim at the default fit (it is a 1 m disc there) and its look on the phone is the owner's eye; the tuft layer
  and the kit shadow rows on the Tab S7 (no measurement); the tray lift is a whole-card shift, so a unit on a stair shows its tray at
  the walk's height while the men are still climbing.

#### (2026-11-01) Siege equipment in oblique

The owner, playing the Itza in the oblique view: "some of the siege units do not have oblique sprites so they are flat". The unit rows were not
the cause: every West row has a set (`musketeers2`, `w_pikemen2` and `cuirassiers` inherit their base row's `sprite_set`, the four gun rows use set 25
`w_crew` and engine set 26 `cannon`, all in `assets/sprites_ob/manifest.json`, which is keyed by spec unit, not by row). The flat pieces were the
**siege equipment** (`q_*` pieces: ladder sets, scaling poles, the ram, the siege tower, mantlets, the ammunition wagon), which `overlay.gd`
`_draw_siege_gear` draws as lines and polygons on the ground plane, so the oblique view squashed them onto the board; the wagon came from the
top-down prop sprites. Route (b), upright solids, was taken over new Blender spec units (route a): the procedural drawer is a handful of
polygons, the pieces are boxes and bars, and no atlas grows (the oblique pack is 12 MB for the web download; this adds none). New
`game/siege_gear_ob.gd` (view only, `sim/` and `campaign/` untouched, no hash, no lockstep input; the top view draws exactly as before)
projects each piece's metres to the board with the view's own constants (ground y x `OBLIQUE_COS`, height x `OBLIQUE_SIN` x px/m) and draws it
as an upright group at its ground point (`BoardView.up_xf`, as the markers): a planted ladder leans from its foot (`set_ladder_foot`) toward
the stretch (`ws_dir`) and its top clears the walkway (`sim.wall_h` + 0.9 m, poles + 1.6 m); a bundle lies at 0.2 m or rides at 1.7 m on the
carriers' shoulders; the ram is a shaded box with its hanging beam and iron head; the tower is a box `sim.wall_h` + 2.6 m high with storey
lines, its drawbridge down on the walkway when planted and a raised flap while it moves; a mantlet is a plank screen its panel line long with
seams and two props; a wrecked piece is low and dark with a cross; the wagon is a box with canvas hoops, wheels and its horses as blocks (its
stock bar stays flat). Faces are shaded by the key light and sorted far to near; pieces are drawn far to near too. Known: pieces are boxes, not
painted figures (the wagon sprite and the draft horses of the top view are not used in oblique); a burning piece keeps `_draw_fires`' flame over
its ground point; a tower's drawbridge face is behind its box seen from the south. `tests/oblique_siege_shot.gd` places the pieces by hand
before a wall (planted, on the ground, carried and wrecked) and saves three 1280x720 shots.

### Pass 4, painted figures (as built, 2026-10-30)

Art half (`tools/`, the two sheet sets, one loader in `game/kit_ob.gd`); `sim/` and `campaign/` untouched, the generated tables did not change.

- **Passes.** `build.py` renders two more passes a frame beside shade / mask / pat: `nrm` (camera-space normal * 0.5 + 0.5, a material
  override with a Vector Transform world to camera) and `id` (R part id = the mesh object's index in name order, G 255 on metal parts
  (`m_metal`, `m_bronze`), B view depth over 26..34 m). Both are hard: filter 0, one EEVEE sample, no dither (with the default dither the id
  had +-1 noise), so a pixel is one part. `--no-aux` skips them. The three old passes are pixel-identical (checked on heavy_swords; the
  old pipeline itself shifts a few noise pixels between runs in a handful of frames, as before). Cost: top-down about +40 %
  (all 48 units 3 min), oblique 48 units in 4 parallel processes about 16 min wall.
- **The paint** (`pack.py`, `paint_frame`, numbers in `PAINT`; `--no-painted` packs today's sheets; on by default when the passes exist),
  inside the silhouette only: (a) **black-lining**: where the part id steps between 4-neighbours, the farther part's pixel (greater
  depth, ties by id) is multiplied by 0.55; (b) **edge highlights**: x1.35 with a warm tint (1.05, 1.0, 0.90) on the top row of the
  silhouette, on the left / top rim of the nearer part of an id step when its normal faces the key (n.L > 0.2), and on a lit facet (n.L > 0.55)
  beside a facet 0.30 less lit (a bevel's rim); (c) **varnish**: the lobe of n.H (H = half vector of the key (-0.55, 0.60, 0.75) and the view),
  starting at 0.90, squared; gain +25 % on the lit side, +65 % and a +40 white lift on metal parts; (d) contrast x1.10 about mid grey and
  saturation x1.10 first. **Recolour.** The game does `rgb = shade * (rest + team)`, team parts being white in the shade sheet, so a
  highlight on a team part cannot exceed the white: team pixels lose 8 % x their team weight before the paint (the highlights climb back to
  white, +8.7 %); the mask sheet is unchanged (the highlight is in the shade, so it takes the faction colour with it, a lighter faction
  colour, not a white glint). Lines and highlights are in the shade, so they survive every palette.
- **What differs from the plan.** No flock (the other agent's). No depth pass of its own beyond the id's B channel. The lines are 1 px at
  the sheets' resolution (24 px/m), so on the 1x top view they read as texture; the oblique view's larger figures show them.
  The varnish is on the shade, not a second map: a glint cannot be recoloured, so it is as team-coloured as its part.
- **Sizes** (PNG bytes, shade; mask and manifests unchanged): top-down atlas 980,924 -> 1,026,929 (+4.7 %; against an unpainted re-render of the
  same frames 948,909, +8.2 %); oblique atlas 6,209,098 -> 6,719,382 (+8.2 %, 4096 x 5248; the sheet set 9.7 -> 10.2 MB, +5.1 %). No
  posterising needed. `git diff --stat game/` shows only `kit_ob.gd`: the frame rects and anchors are as committed.
- **The turned houses.** `tools/battlekit/build.py --oblique` also renders `__y2` and `__y6` (yaw 90 / 270, the same camera) for every
  piece whose footprint's long side / short side > 1.2 and whose long side is at least 1.5 m: 52 pieces, 104 renders. `pack.py
  --oblique` packs the 86 whose piece the atlas list holds: 274 sprites, 2048 x 2496 (was 188, 2048 x 1920), albedo 5.6 MB, nrm 1.2 MB, low 1.7 MB, 8.3 MB in all. Key numbers are
  the yaw in 45 degree steps: y2 = counter-clockwise seen from above, the piece's local +x pointing north and its outer face west; y6 the
  opposite. `KitOb.yaws(name)` lists the yaws a piece has, `KitOb.index_yaw(name, yaw_deg)` picks the nearest. **Open:** the shader's tables
  hold 192 sprites (`ob_krect[192]`, `ob_kanch[192]`; `KitOb.MAX`): the loader loads y0 / y4 first, so today only 4 of the 86 turned sprites fit and the rest
  wait until the shader's arrays and `MAX` grow to 288 or more and `battlekit.gd` calls `index_yaw` (see the STATUS row).
- **Preview.** `pack.py --contact` (top) and `preview/ob_contact.py --sheets DIR` (oblique, a folder of the same layout) for before / after.
- **Open.** The owner's eye on the line weight and the warm edge; the mirrored E / NE / SE figures have their highlights on the right
  (flipped with the sprite); the elephant's many small parts get busy lines; a 6-bit posterise stays available if the on-demand pack grows.

### Pass 5, furniture and motion (as built, 2026-10-30)

The plan's item 5 and the leftover "trodden-ground squares"; view only (`sim/` and `campaign/` untouched, `git diff --stat sim/ campaign/` empty).
Built in this order, each shot in both views.

- **0. The squares round the West houses.** **Differs from the brief:** the dark squares are **not** the terrain shader's trodden-ground mask.
  With `--no-kit` they vanish and with `trod = 0` in the shader they stay: they are `city_streets.gd`'s *lane zone* (the free ground within
  `LANE_GROW` 3 m of every footprint, painted at 0.5 m cells in "a warmer, darker earth" with a darker rim on the zone's edge cells), the sprite that
  lies under the kit in both views. Fixed there: in a West town the yard is lighter bare earth (0.62, 0.50, 0.35, was 0.56, 0.44, 0.31), the rim darkening is
  gone, and its **alpha follows the depth** in from the yard's edge (`_depth`, a rounded rectangle per footprint, the largest where yards overlap,
  `LANE_FEATHER` 6 cells = 3 m: smoothstep, x 0.85-1.15 by the cell's noise, at most 0.8), so the yard fades out at its rim and has no cell edge at
  zoom 2. The terrain's own mask was softened as asked too (`_soften_trodden`: the G channel blurred over a 3-cell box twice before the bilinear
  sampler, `trod_soft` in the shader: bare earth warmer and mixed 0.6 with the ground, a value-noise wobble 0.5-1.4 on its strength, so half as dark), a subtler
  change, since the splat ground under a town is mostly the street texture. Both views (the top view's old black footing round the houses fades the same way).
  The owner still reads "a yard round the house": about 3 m of earth round each building, strongest at the wall.
- **1. The brass ruler** (`game/brass_rule.gd`, drawn by `overlay.gd`). The deployment line (the player's zone's four edges, ticks from each corner; the
  enemy zone keeps its thin red line) and the **full range ring** of a selected missile unit or battery (a battery's firing sector keeps its coloured
  edges and arcs: they carry information) are a band 0.8 m wide (never under 5 screen px): a soft contact shadow to the lower right (two
  translucent passes), a dark brass edge, the brass body (0.94, 0.65, 0.17), a thin bevel highlight shifted to the upper left (the lamp), cut into
  pieces of at most 8 m so it follows the hills through the lift (the overlay's own `SEG_M`). Engraved ticks every 10 m from the outer edge inward
  (0.5 of the band; 0.78 with a small number every 50 m on the deployment line, in metres from the corner, left out when closer than 5 screen px / 26 px
  for the numbers); a ring's numbers would be lengths along the circle, so it carries one label "140 m" at its top instead. A ring with no ammunition is the
  same rule in pewter. The deployment fill stays. Checked on grass (custom battle) and sand (siege_city) at the fit and at zoom 2, both views: the dark edge
  and the saturated orange keep it legible on sand. **Open:** ticks on a ring are along the arc from east, not from the unit.
- **2. Cotton smoke** (`gun_smoke.gd`, `overlay.gd`). The four cloud tiles are re-baked: each is 2 to 4 round lobes (3, 2, 4, 3) as a smooth sum of soft
  discs with lumps from noise, a silhouette soft all round (alpha = smoothstep of the field, no hard edge), shaded from the field's slope with the lamp
  upper left, an underside shade per lobe (weighted by its share of the field), a darker core, a grey-blue shade against a warm white light. The tile
  atlas is one texture as before, so the gun smoke still batches. The **fire smoke, a blast's cloud, the ruin dust, the dust kick, a chip's dust and
  the burning columns** draw the same tiles (`GunSmoke.tuft`, tinted, instead of `draw_circle`) and stand up in the oblique view as before; the long-fire
  haze, blast rings, sparks and the flash are as they were. Both soldier data paths and Low use the same atlas (the shading is baked in, so Low has no extra
  work); the atlas is baked in the overlay's first frame, not in the frame that draws the first puff.
- **3. The dive onto the table** (`game/table_motion.gd`, `Battle.dive`). Set by every screen that opens a battle for a player (the scenario / siege /
  custom starts in `main.gd`, the campaign's Fight and the live co-op start in `campaign_screen.gd`): the camera starts at 0.35 of the fit centred on the
  field (the wood and the board's edge show), drops to the fit over 1.2 s (ease-out cubic on the zoom taken geometrically, the position linearly) and the HUD
  (a `CanvasModulate` on its layer) fades in over the last 0.4 s. A tap or a key skips it to the end and is not an order; the sim does not step during it. The top view dives the same
  way (the tilt is not animated: the oblique camera is baked into the sheets). `[video] battle_dive` (default on; Options "Motion / Still", see ui.md) and
  `--no-dive` turn it off. **No dive** under any command-line aid (`--shot`, `--frame-stats`, `--skip-ticks`, `--zoom`, `--cam`, `--cam-unit`, `--select`,
  `--pause`), in benchmark mode, for a non-interactive battle, and **in any test script**: `TableMotion.allowed()` also needs a current scene, which `--script` runs
  lack (`TableMotion.force` overrides it for `tests/table_motion_test.gd`). `--dive-hold=S` holds the dive at S seconds for the strip of shots.
- **4. The die on the auto-resolve** (`game/campaign/die_roll.gd`, `campaign_screen.gd _roll_die`). When the resolver finishes, the progress bar gives
  way to a wooden die (a rounded face with a grain, a bevel and the icon engraved) that tumbles across the dialog for 0.9 s with a decaying bounce and a soft
  shadow, flips five times (the front face squashes as the next comes over its top edge) and settles for 0.45 s on the face the **rules** gave this player:
  a laurel (`victory`) for a win, a broken shield (`broken_shield`, new in `ui_icons.gd`) for a loss, crossed swords (`battles`) for a draw (or no
  seat); then `_apply_battle` runs and the result shows as before. The faces on the way are a fixed order counted back from the result, nothing random, and the
  result was applied by the rules before the die rolled; the die only shows it. A tap or a key skips to the settled face. Off with the setting and in tests. No die for the AI's battles
  (they resolve inside `cturn`, there is no screen) nor for a **sea** battle's instant auto-resolve (no dialog to roll in: open).
- **The setting.** One row, one capsule, shared with Battle view (`options_rows.gd _beside` joins a third control; on the narrow layouts the capsules are a wrapping flow):
  the Options page still does not scroll at 1024 x 576.
- **Cost** (3 runs each, before = HEAD 64c97c2 in a scratch copy, after = this tree, seed 7, tick 600, `--disable-vsync`, high; the smoke case is siege_city
  at tick 3000 with `--ai-both`, zoom 2, `--cam-unit=11`). The machine's load average was 15 to 20 on 16 cores (another agent's harness), so the frame
  means swing +-2 ms between two runs of the same build (an after of 25 ms and a before of 20 ms in the same pair); the render times were taken
  with a temporary `viewport_set_measure_render_time` read in `_frame_stats` (not kept) because the GPU time is not shared with that harness, and they scatter
  +-0.5 ms. **Result: no systematic cost.** The deltas of the nine of ten rows within -1.1..+0.7 ms have both signs; the one over the +0.15 ms line, bench_4000_hills
  at the default fit, oblique (+0.68), is one pair where the after run met a 25 ms load spike (the other two pairs: after lower than before in the top view and
  equal at zoom 2). The expected cost is nil: the terrain's new branch runs only where the trodden channel is set (`trod_soft && v.g > 0.02`), the brass ruler draws
  only in a deployment and for a selected shooter, the cotton tiles replace circles one for one, the smoke atlas is the same size. **To redo on a quiet machine.**

  | case | zoom | view | GPU render ms (before / after) | CPU render ms (before / after) | frame mean ms (before / after) | render GPU + CPU delta |
  |---|---|---|---|---|---|---|
  | bench_4000_hills | default | oblique | 4.52 / 4.75 | 6.27 / 6.71 | 15.19 / 16.79 | +0.68 |
  | bench_4000_hills | default | top | 4.23 / 4.34 | 6.40 / 6.45 | 15.37 / 16.19 | +0.16 |
  | bench_4000_hills | 2 | oblique | 4.15 / 4.04 | 5.90 / 5.88 | 13.99 / 13.68 | -0.13 |
  | bench_4000_hills | 2 | top | 4.05 / 3.85 | 5.91 / 5.71 | 13.64 / 12.74 | -0.39 |
  | west_town | default | oblique | 2.07 / 2.23 | 3.59 / 3.75 | 8.25 / 9.07 | +0.32 |
  | west_town | default | top | 2.06 / 1.83 | 3.72 / 3.34 | 8.59 / 7.31 | -0.61 |
  | west_town | 2 | oblique | 2.15 / 2.19 | 3.55 / 3.38 | 8.16 / 8.18 | -0.12 |
  | west_town | 2 | top | 1.78 / 1.80 | 3.14 / 3.15 | 6.85 / 6.70 | +0.04 |
  | siege_city, 3000 ticks, guns | 2 | oblique | 1.71 / 1.47 | 5.05 / 4.15 | 8.92 / 7.51 | -1.14 |
  | siege_city, 3000 ticks, guns | 2 | top | 1.31 / 1.29 | 3.34 / 2.88 | 6.35 / 5.65 | -0.48 |

- **Open.** The die's faces are drawn flat (a 2D flip), not a rolled 3D cube; a sea auto-resolve has no die; the dive's tilt is not eased (the camera is baked);
  the dive and the die are not yet on the phone (Tab S7, the web build); ring ticks start at east; the lane zone's "yard" of a **non**-West town is unchanged
  (Rome's cobbled lanes keep their rim); the first top-view shots of the smoke at Low were not compared.

### Pass 6, the hills (as built, 2026-10-30)

The owner: "Now that the cities are oblique the hills feel a bit flat on the battlefield", and on the rocks: "They feel placed down instead
of part of the landscape." View only: `git diff --stat sim/ campaign/` is empty, no hash, no lockstep input. The hills stay foam steps on a
table (the felt, the flock and the resin water are untouched), not a terrain renderer. Code: `game/board_view.gd` and
`board_view.gdshaderinc` (the field, the exaggeration, the inverse), `game/terrain_nodes.gd` (new: the 2 m height nodes, one copy for the
terrain texture and the lift field), `game/terrain.gdshader` (steps, shadows), `game/ground_depth.gdshader` (new, the crest ghost's pass),
`game/kit_occluder.gd`, `game/battlekit.gdshader` / `battlekit.gd` (rocks sunk), `game/land_layer.gd` (earth skirt and halo),
`game/tuft_layer.gd` (tufts at a rock's foot), `game/soldier_layer.gd` (one line), `game/menu/options_rows.gd` (the crest capsule).

- **1. The exaggeration.** `BoardView.HEIGHT_EXAG = 1.4`, folded into every lift value (`lift = (h - base) x px_per_m x OBLIQUE_SIN x exag`,
  the coarse grid and the fine field alike), so every layer that meets the ground through `ob_board` / `to_board` / `near_px` meets it
  exactly: figures, trays and bases, the kit, the walls' mesh, the overlay's marks, trees and tufts, the missiles' arcs (they ride the
  ground under both ends, their own arc height is not terrain) and a wall walk (its height is above the ground, not the terrain's).
  Nearness (`near_px`, `ob_near`) uses the drawn height (lift / OBLIQUE_SIN), so what hides what matches the picture. The top view never
  reads it (no lift there); `--height-exag=` overrides it for a run. **Differs from the brief:** nothing; the arcs' own height and the
  walk's are not scaled (a figure's height is a figure's, not the hill's).
- **2. The fine field.** `BoardView._build_fine`: the terrain's 2 m height nodes (`TerrainNodes.build`, the same cubic interpolation of the
  sim's 4 m heights the ground texture uses; **2 m, not 4 m**: the field of bench_4000_hills is 281 x 301 nodes, the largest map 2 m
  keeps under 1,100 nodes a side, past that the builder takes every second node) as a **half-float texture (R16F, converted from R32F
  natively; half floats are filterable in WebGL2 without an extension)** read with `textureLod(ob_ftex, uv, 0)`: one bilinear fetch in
  the vertex stage (and in the fragment stage for the ground). `ob_lift_px` is the one entry point; everything that included
  `board_view.gdshaderinc` (soldiers, bases, trays, kit, trees, tufts, projectiles, the lift shader, ground-texture sprites) gets it with
  no change. GDScript replicates it (`lift_px`: the same bilinear of the same float array, then the same quantiser) for the overlay, taps and
  `near_px`. **The fallback:** the coarse grid (29 x 29, uniform array) is kept and used for the **CPU-fed soldier shaders** (`CPU_FED`:
  no sampler is declared there, `ob_lift_px` compiles to the grid), for **Graphics Low** and for `--lift-grid`. The decision is made once per
  battle in `begin` (soldier path forced or remembered as cpu, Low, the flag) and a run-time switch to the CPU path (the probe) calls
  `BoardView.use_grid()`, which re-applies every registered material (`_mats`, weak refs) so the **whole** battle (ground included) is on
  the grid together and never half-and-half. The union of both ranges is what the rects and culls use, so that switch needs no resize.
  **The inverse** (`ob_world`, `to_world`): the grid keeps its Newton steps; the fine field cannot (a step's riser is steeper than the
  view), so it marches the view ray: from the near end of the field's lift range in 14 steps (GDScript 48) until `y x COS - lift - b.y`
  changes sign, then 5 bisections (24): the nearest surface, so a hill hides what is behind it. A flat map skips it.
- **3. Foam steps.** With the diorama look the fine lift is quantised into the same bands pass 2 shades (`minor_m` 2 m, origin the
  terrain's commonest height), in the shaders (`ob_quant`) and in GDScript (`_quant`; one formula, a smoothstep ramp over the first 0.18 of a band's
  height, so the field stays continuous and the march finds every face). A band edge is therefore a **vertical face 0.36 m x 1.4 high
  on the board** (about 21 board px at the default scale), with the **flat top** of the step above it. The ground shader's riser logic for
  this mode is by height, not by pixel width: the face (the ramp's middle) is darker, earthier and lit or shaded by the way it looks (the
  same node gradient as pass 2: a face that looks south, the only kind the camera sees, is in shade); a **lit lip** on the step's top edge
  (cream, 32 %, +12 %); a **soft foot shadow** on the step below (a band's tenth of the face's height and a metre and a half of slope), stronger
  where the face looks away from the lamp; the hill shade on the tops is cut to 40 % as pass 2 had, the slope darkening and the earthy slope tone
  nearly off (the tops are flat now) and the contour lines off (the face is the line). The flock stays on the tops. The **painterly look** and
  the grid fallback keep the smooth field and pass 2's drawn risers. The top view's terrace shading is untouched.
- **4. Shadows and crests.** `terrain.gdshader`, High, oblique, diorama: three taps of the smooth height (3 m and 8 m toward the lamp, 3 m away):
  a soft cast shadow on the lee of a rise (the ground toward the upper left higher, `smoothstep` of the difference, a cool 30 % at most) and a
  lit rim along a crest facing the lamp (convexity of the three taps times the drop toward the lamp; +0.1 warm). Both subtle. **The crest
  ghost** (`[video] crest_ghost`, default off, `--crest-ghost=on|off`, a capsule on the Battle look row): `kit_occluder.gd` draws the ground's
  nearness (`ground_depth.gdshader`: `ob_world` per pixel, `ob_near`, the kit's 16 bit encoding) first into the occluder viewport; a man
  whose nearness is below the ground's at his pixel is drawn as the faction ghost by the existing code (his base not at all). The kit
  pieces are drawn over it, so a house farther than a crest in front of it keeps its own nearness (a corner case). Its cost is measured on its own below.
- **5. Rocks.** Every kit rock (`rock_a / b / c`, `battlekit.gdshader`'s `ob_rockq`) is drawn `ob_sink = 0.14` of its height lower and its foot fades out
  over the bottom third (alpha, so the ground's flock shows through) and darkens a little above that; `land_layer.gd` (`_Skirts`, a child node with its own lift material so the skirts stand on the steps): under every boulder, both views,
  High, a soft skirt of bare earth (five translucent discs to 1.7 radii) and a dark halo hugging the foot; `tuft_layer.gd`: three tufts on the boulder's south
  half. Positions are the sim's: nothing moves, only how the rock sits. **Not done, and why:** (a) a rock **on a terrace face flush with the riser**
  with the riser's lip: the rock records carry no knowledge of the bands, and a flush outcrop needs its sprite clipped by the face (a per-pixel test
  against the field in the kit shader); a rock on a face currently stands on the ramp like any figure. (b) **Cliffs as risers with a rock
  material**: `land_layer.gd _cliff` still draws the straight face polylines (lifted per vertex); the sim's cliff lines and the terrain's bands do not
  coincide (the cliff face height is a separate datum, 4.4 m, the terrain's slope there is gentle), so a riser cannot replace a cliff without moving
  heights, which is the sim's. Where the terrain is steep the steps' faces take the rock tile by the grade (pass 2's `rock` mask), which is the nearest thing.
- **Draped layers.** A draw-based layer whose pieces are long (the cliffs' faces and brow, the settlement surroundings' tracks and fields) gets the
  **smooth** field (`BoardView.lift_node(ci, true)`: `ob_fq.x = 0` on its material): their vertices are metres apart, so a step between two of them tore the
  cliff's lit brow into a floating band (seen in the first shot). The short marks (overlay, rubble, skirts, bases) stay on the steps.
- **What differs from the brief, and why.**
  (1) The coarse grid is not replaced by the texture on the **CPU-fed path**: there the *whole battle* (ground included) uses the grid with the exaggeration,
  and the ground keeps pass 2's drawn risers; the steps are a texture-path feature (Tab S7 Chrome therefore does not get them: it chooses the CPU path and Low).
  (2) The riser's foot shadow and lip are by height (bands per metre of slope), not pixel width, because a face is now geometry.
  (3) Rocks on a riser flush with the face and cliffs as risers are **not built** (see 5).
  (4) The crest ghost is built and switchable but was **not seen working on a clean example**: the two maps tried (test_ridge_defend, bench hills) had no man
  standing right behind a crest in view; the pixels differ where men stand near risers (410 and 2,863 px of 921,600 in two shots). It needs a look on a ridge map.
  (5) The top view is **not pixel-identical** only by the rocks' skirt and halo (intended: the brief's top-view rule); ground, trees and kit are identical in
  a paused same-tick shot (test_woods: 0 px differ outside the figures; the figures differ by 548 px that a before / before pair does not, which the
  run's tick phase explains but was not proved: **to recheck** with `--pause` and the same tick on both).
- **Cost** (desktop RTX 3070, 1280 x 720, vsync off (`--disable-vsync` before the `--`), `--quality=high`, `--soldiers=gpu`, seed 7, 9 s after tick 600, 3 interleaved runs, mean
  frame ms of the three means; before = the main repo at 4e3f13f, after = this tree). **The machine was shared** (another agent's determinism test and a script check ran
  the whole time, load average 4 to 5), so single runs scatter by +-1 ms (a 17 ms first run is in the crest rows): read the signs and sizes, not the second decimal.

  | scenario, zoom, view | before | after | delta |
  |---|---|---|---|
  | bench_4000_hills, default fit, oblique | 8.46 | 8.34 | -0.12 |
  | bench_4000_hills, zoom 2, oblique | 7.85 | 8.12 | +0.27 |
  | west_town, default fit, oblique | 4.46 | 4.74 | +0.28 |
  | west_town, zoom 2, oblique | 4.57 | 4.70 | +0.13 |
  | bench_4000_hills, default fit, top | 8.27 | 8.91 | +0.64 (noise: the top view runs the same code; runs 7.44 / 9.99 / 9.29 vs 7.48 / 8.92 / 8.42) |
  | bench_4000_hills, zoom 2, top | 7.53 | 6.91 | -0.62 (noise) |
  | west_town, default fit, top | 4.45 | 4.56 | +0.11 |
  | west_town, zoom 2, top | 4.32 | 4.41 | +0.09 |
  | crest ghost on vs off, bench_4000_hills, default fit, oblique | 9.12 | 9.38 | +0.26 |
  | crest ghost on vs off, bench_4000_hills, zoom 2, oblique | 8.59 (median of 3; one 17 ms outlier) | 8.77 (median) | +0.18 |
  | the grid fallback (`--lift-grid`), default fit / zoom 2 | 8.87 / 8.26 | | about the fine path's cost |

  The oblique rows are +0.13 .. +0.28 ms, inside the +0.3 ms line the brief set, but not clear of the noise; the ground shader's march (14 + 5 texture fetches a
  pixel where the lift range is large, none on a flat map) is the new work, the figures' one fetch a vertex is not measurable here. The frames are CPU-bound on this
  machine, so the **GPU-bound phones are the open question**.
- **Checked.** `tools/check_scripts.sh` clean; `tests/battle_screen_test.gd` PASS (both views); `tests/input_test.gd` PASS (taps on the hills go through the
  new inverse; both views); `tests/soldier_facing_test.gd` PASS in both views (the two soldier paths draw the same pixels for a standing line, 0 differ, on the test's
  flat board: the lift is zero there, **the two paths on a hill are not compared**); `tests/oblique_sets_shot.gd` runs (the sets sheet; flat board too);
  `tests/lockstep_test.gd --quick` PASS; `tests/menu_test.gd` PASS with the fourth capsule (the row still fits at 1024 x 576 and the narrow layouts);
  `git diff --stat sim/ campaign/` empty.
- **Open.** (a) The phone: vertex texture fetch (half-float, linear) on the Adreno 650 Chrome path is untested (that tablet falls to the CPU path today, so it
  would not use it), the ground's 19-fetch march on a mobile GPU is unmeasured, R16F filtering on old Mali / Adreno WebGL2 is assumed. (b) Flush rocks and cliff
  risers (above). (c) A **river** crossing: the bed lies below the plain, so with the fine field the water sits in a one-band trench (the coarse grid averaged
  it away); no river map was shot. Water should be clamped to the bank's height in the field. (d) Overlay marks, trays and the walls' mesh are per vertex: a long piece
  across a riser slants over the face (the overlay cuts at 8 m; trays and long wall stretches were not checked on a hill town; `west_hill_village` and `siege_hill`
  were not shot). (e) A tap on a riser's face resolves to the face's world point (the ramp's 0.36 m), which is the nearest surface, as the eye reads it.
  (f) The cast shadow and the crest rim are subtle by design and have not been judged by the owner. (g) The crest ghost's corner case: a kit piece farther than a crest
  keeps its own nearness over the ground's. (h) The exaggeration 1.4 and the ramp 0.18 are guesses at the owner's eye: `--height-exag=`, `RAMP`, `ob_sink`.
- **(2026-10-30) Shots fly straight over the lift** (the owner: "the bullets take an interesting trajectory over the obstacles before getting to their target"). The
  missile shader placed a shot at `ob_board(mix(s, e, f))`, which includes the lift of the ground under each point of the track, so a shot crossing a terrace or hill
  rose and fell with the foam steps beneath it. Now (`projectiles.gdshaderinc`, `OBLIQUE`) the height is the lift under the shooter blended to the lift under the target
  by f, plus the shot's own arc: board position `(w.x, w.y * OB_COS - (mix(ob_lift_px(s), ob_lift_px(e), f) + h0 * OB_SIN))`, the heading from the same formula at f
  and f + 0.02 (`ob_board` is no longer called for the track). Two lift fetches a vertex (the coarse grid on the CPU-fed path: `ob_lift_px` exists on both).
  **Gunpowder small arms get a ball look** (missile kind 5, `soldier_layer.gd _pr_flag_of`): any non-artillery unit whose `m_speed >= 10240` (100 m/s) that is not a sling
  row, which today is exactly musketeers, musketeers2, marines, buccaneers, colonial militia, coureurs, maroons, dragoons, cuirassiers, pistoleers and mounted arquebusiers
  (all 200 m/s; bows 45, slings 40, bolts 50-55, guns are `CLS_ART` and keep their stone look). Before, they fell through to the javelin look and its arc. The ball is a dark
  dot with a short pale streak (3 m quad, head at uv.x 0.9) and an almost flat arc (hk 0.01). Arrows, javelins, bolts, stones and sling bullets are unchanged. Aid:
  `tests/shots_over_hill.gd` (a line shoots across a ridge or hill, paused with shots at mid-flight).


**Projectiles at the target's height (as built, 2026-11-02, view only)** (the owner, phone, oblique, a siege: "The arrows look like they are impacting the floor below the walls when hitting things like siege towers or units on the wall top ... The arrow impacts should match the unit's height that it is firing at"). A drawn missile ran from the ground under the shooter to the ground under the target; a man on a wall is drawn `wall_h` up (`soldier_layer._unit_ext`), so the arrows at him ended at the wall's foot and those from him started there. Now `soldier_layer._pr_heights` works out, once per slot when its `t0` changes (`_pr_h_t0`, slots up to `_pr_hi + pr_count`), two heights in dm: at the firing point `wall_h` if the shooter has `u_wall > 0`, else the point's cell (`obs_kind`: walk and tower `wall_h`, stair half, else 0), and at the landing point `wall_h` if the unit aimed at (`pr_tu >= 0`) has `u_wall > 0`, else the landing cell the same way (a stone lobbed at a point on a walk or a tower; a gate or a point on the ground 0). It mirrors what the men are drawn at, not `u_h` / `elev_at`, so a shot lands where the figure stands (a man in a building or on a siege tower is drawn at the ground and so is shot at there). They reach the shader as texture block 9 (`hs + 1024 x he`, `PR_BLOCKS` 10) and, on the CPU-fed path, as the `INSTANCE_CUSTOM.y / .z` columns `C_FLAGS` / `C_LOOK` (free for missiles). `projectiles.gdshaderinc place()`: in the oblique view the board height is `mix(lift under shooter, lift under target, f) + (mix(hs, he, f) + arc) x OB_SIN` (the heading from the same formula), so a shot from below at a wall climbs and one from the wall falls, the arc's apex standing over the straight line between the two heights; in the top view the same heights make the missile a little larger (`lift += 0.06 x height in m`, scaled with the existing mid-flight swell). `overlay._draw_impacts` (oblique): a stone that lands on a walk or tower draws its dust puff and a ring upright at `wall_h x OB_SIN` above the ground point (the flat furrow is skipped there); no stuck-arrow marks exist to move. `SoldierLayer.missile_heights = false` (a static testing aid) restores the old ground-to-ground flight for before / after shots; `tests/arrow_height_shot.gd` steps a siege (`siege_test`, AI both sides) to a missile of the wanted kind (`--want=up|down|engine|stone`, `--view=`, `--cpu`, `--before`, `--start`, `--back=`, `--dy=`). Hashes, pins and the sim untouched. Known: the shot ends at the target's feet height, not the chest; the heights are fixed at the shot's launch (a man who climbs meanwhile is not followed); the tower engines' crews are drawn at `wall_h`, not the tower's `wall_h + 4 m` of the line-of-fire rules, so their bolts start at the drawn height; shots at a closed gate end at the ground; the top view only grows the missile (no lift is drawn there); Graphics Low draws missiles with the same layer and was not shot separately.

**Men in a held building, on a ladder and at a siege tower (as built, 2026-11-02, view only)** (the open of the paragraph above: "men in buildings and on siege towers are drawn at ground level and shot at there"). What the sim has: a siege tower carries no men (they cross its eight lanes by `_ladder_step`, one at a time onto the walk, and wait at its foot on the ground), so the only things "on" it are the shots that land on its body; a held building's men stand at `ob_z` (`_unit_elev`); a unit climbing ladders has `u_wall` set from the start of the climb, while most of its men still queue below. **(1) Held building: lifted** (the cheap way: the unit lift exists, `_unit_ext`; no second mechanism). `soldier_layer._stand_dm(u)`: `wall_h` on a wall, the building's deck in a held building, else 0; the men are drawn at that height in both paths (texture block 8 `64 x dm`, CPU path the sprite column `16 x dm`), so a garrison stands on its roof's parapet or at the upper windows (the diorama look). The sim's `ob_z` is a per-building number that does not follow the drawn piece (flat roofs 4.2-5.2 m against decks drawn at 3.2 / 3.5 m, up to 1.7 m of men floating over the roof), so `BattleKit.DECK_DM` / `held_dm` (filled by `_add` by the layout's building index, cleared at `setup`) gives the drawn deck of `house_flat_s` 32, `house_flat_m` 35, `shop` 38, `governor` 70 dm; any other piece (the pitched ones: the sim's windows 2.0-3.0 m sit inside the drawn walls) keeps `ob_z`. **(2) Ladders and tower lanes:** a unit with `u_stair == ST_LADDER` is lifted by no unit height; `_stair_lift` gives each man the walk's height only where his own cell is a walk or tower cell (block 10 / the sprite column, the stair flights' mechanism), so the queue at the foot stands on the ground (before, the whole unit, `u_wall` set, was drawn 7 m up in the air with the men up on the wall). **(3) Shots:** `_pr_heights` takes each end's height from `_end_dm` (the unit's `_stand_dm` if above 0, else `SoldierLayer.point_dm`: walk or tower `wall_h`, half on a stair, a held building's deck, a live siege tower's `wall_h`, within 1.25 x `EQ_DEPTH2` of `eq_centre`); a shooter or target on a ladder is read by the cell its end stands on. A shot at a man on a roof climbs to the deck, one from a window drops; one landing on a siege tower ends at the body (it stops 70 % of the arrows in the rules). `overlay._draw_impacts` uses `point_dm` too (a stone landing on a held roof or a tower piece draws its dust upright at that height). Top view: the same heights grow the missile; the men's lift is oblique only. `tests/held_height_shot.gd`: `--want=house|house_from|tower|ladder` (a West town with the defenders' musketeers sent into houses, as `tests/open_town_probe.gd`; the siege tower put at the wall by hand with arrows injected into the missile slots; a ladder climb), `--view=`, `--cpu` / `--gpu`, `--before` (`missile_heights` off), `--back=`, `--zoom=`, `--dy=`. CPU and GPU soldier paths draw the same lifts (the ladder queue, the roof ring, the tower shots). Hashes, pins and the sim untouched. Known: the pitched houses keep the sim's `ob_z` (the drawn windows are not modelled); the deck table is by piece name (a new flat-roofed piece needs a row); the men of the building's back faces stand on the roof's far edge and the roof sprite is the stand-in's low-resolution one in a run without the kit sheets; the heights are still fixed at the shot's launch; men on a walk at the top of a ladder still draw as ghosts on the GPU path when the occluder says so (unchanged); the tower is drawn at the tower's `walk + 2.6 m`, shots end at its deck height `wall_h`, not its middle.

### Rome and Greek figure sets (as built, 2026-11-01)

The owner: "Update the Roman oblique images". Every Rome row drew from the 13 generic antiquity sets, so the Roman elites looked like the generic swordsmen
and the Greek hoplites like the generic spearmen, in both views. Three sets are appended after `torch_raiders` (set ids 46-48; every earlier id and every
row's index unchanged; `atlas.sets` now 48 of the 63 the 6-bit field holds), each a copy of the nearest set's spec entry with the same rig, actions, frame
counts, fps and render_box (the pose and table shape unchanged), built within the existing part vocabulary (no new mesh code):

- **46 `legionaries`** (from heavy_swords; rows principes, extraordinarii): Montefortino helmet (a dome, neck guard, cheek box, a crest knob and disc on top),
  mail shirt, cape and skirt (boxes in the `metal` material over the red tunic), the big oval scutum, pilum and gladius, caligae. The oval scutum is a flattened
  sphere (the `sphere` part's `scale`; the `scutum` part is a bent rectangle and has no oval form), team-coloured face, secondary rim, boss and a vertical rib
  in the accent. The pilum (wood shaft, thin iron shank, cone head, 1.75 m) is on `forearm.R` where the sword was, so it follows the attack pose; the gladius is a
  static scabbard and hilt at the right hip (`hips`).
- **47 `triarii`** (from spearmen; row triarii): the same Montefortino and mail, with a tall black plume (a box and a rounded top, `dark`), a smaller oval
  scutum, greaves (accent limbs on the shins), the long hasta of the spearmen's overarm pose.
- **48 `hoplites`** (from spearmen; rows hoplites, picked_hoplites, sacred_band): bronze muscle cuirass (a box with a pectoral ellipsoid, the `bronze` material),
  pteruges, the Corinthian helmet of the source set with a longer horsehair crest and a tail down the neck, a bigger round aspis (bronze rim, team face, accent
  device disc), bronze greaves, the dory.
- Fixed meshes: the helmets are domes with boxes (no true Montefortino or Corinthian profile), the shields a flattened sphere (scutum) and a 16-sided disc
  (aspis), so the difference from the generic sets is colour, size, crest and plume, the mail and bronze, and the shield outline; the faction palette still
  decides the red and the secondary colour.
- Wiring: `"sprite_set": 46 / 47 / 48` on the six rows in `sim/unit_types.gd`; `_derived` now copies a tier row's own `sprite_set` over the base's (before, a
  tier row's own field was ignored). View only: the sim never reads `sprite_set` (grep), `determinism_test` unchanged.
- Build: the packer repacks the whole atlas from the frames, so all 48 units were re-rendered (top about 3.5 min, oblique about 12 min with three Blender
  processes) and both packs rewritten; the existing sets' rects in the tables moved (262 of 288 entries) and 18 entries changed size by a pixel or two (the
  re-render noise the README mentions); all tests pass. The imported copies under `.godot` are older than the files until the project's next import.
- Sizes before / after: top-down atlas 1024x2564 -> 1024x2732, shade 1,026,929 -> 1,082,605 B, mask 461,332 -> 495,711 B (+6.1 %), manifest 161,502 ->
  166,956 B. Oblique atlas 4096x5248 -> 4096x5648, shade 6,719,382 -> 7,043,598 B, mask 2,709,769 -> 2,901,566 B (+5.5 %), manifest 1,019,523 -> 1,081,760 B
  (`oblique.pck` not rebuilt here; about 0.6 MB more of the 12 MB).
- **Audit (before the build).** Contact sheet of principes, triarii, hoplites, cav, cav2, cav3, bodyguard, scorpions, tower_bolt and tower_stone in the oblique
  view: all stand upright and face the 8 directions. The earlier claim that scorpions and the tower engines lack oblique sets was wrong: engine sets 13 bolt,
  14 stone and 15 scorpion are in `assets/sprites_ob` and draw through the same engine path as any battery (a tower engine is an ordinary engine of a `fixed`
  CLS_ART row; the soldier layer has no special case). Not staged on a walls-3 town (the engines drawn on flat ground; the path is the same). No mapping gap,
  nothing fixed. What drew wrong was only the look: ~~the Rome cav rows are the generic shock_cavalry (not changed here)~~ (superseded 2026-11-05: the 2026-11-02 "The Roman equites" below gave Rome's tier-2 and tier-3 cavalry their own set 49; only the tier-1 `cav` row and the legate's bodyguard still draw the generic shock_cavalry).
- Aids: `tests/rome_audit_shot.gd` (the contact sheet of those rows, `--top` for the top view), `tests/rome_battle_shot.gd` (principes against hoplites, 40 a
  side; `--view=top`); both load the atlases from the files (the imported copies are stale until the next import).

### The Roman equites (as built, 2026-11-02)

The owner: "Let's give Romans their own horseman. Model and line name." Rome's shock cavalry drew the generic `shock_cavalry` set (4) under the shared
names Shock Cavalry / Veteran Cavalry / Guard Cavalry. Set 49 `equites` is appended after `hoplites` (`atlas.sets` 49 of 63; every earlier id unchanged),
a copy of the `shock_cavalry` entry (same rig, horse body, rider seat, render box, actions, frame counts), with new `rider_parts` only (no new mesh code):

- **49 `equites`** (a Republican citizen horseman of the Punic Wars): the legionaries' Montefortino (dome, neck guard, cheek box, crest knob in the secondary,
  crest disc), a mail shirt (box, `metal`) over the red tunic with the shoulder doubling and a short mail skirt at the hips, a small round parma (a flattened
  sphere, team-coloured face, `bronze` rim and boss) on `forearm.L`, the hasta (wood shaft, iron head, butt spike, 2.7 m) on `forearm.R` so it follows the attack
  pose as the legionaries' pilum does, a sword scabbard and hilt at the right hip. The horse and its team-coloured saddle cloth with trim are the base set's body
  (the cloth was already `primary`, so nothing was added there).
- **Rows.** `equites` (tier 2, `"Equites"`, short `Equites`, +5 charge) and `equites_extra` (tier 3, `"Equites Extraordinarii"`, short `Eq. Extraord.`, +10
  charge) are appended at the end of `TIERS` in `sim/unit_types.gd` with `"sprite_set": 49`; their numbers are cav2's and cav3's. Rome's tier-1 cavalry is still
  the shared base row `cav` ("Shock Cavalry"), and the legate's bodyguard row is unchanged.
- **Rome's roster.** `ROSTERS["rome"]["cav"]` in `campaign/data/rome.gd` is `["cav", "equites", "equites_extra"]` (was `["cav", "cav2", ""]`): Rome now has a
  tier-3 cavalry row, and the Rome AI recruits the new keys. The campaign state hash holds unit keys, so the Rome `campaign_sim` pins moved on 2026-11-02 (format 6
  seed 4 `59dc0582` -> `7eb76327`; format 10 seeds 5 and 6 `6e903a40 61462ab2` -> `871032c7 a28f5226`; format 8 seed 4 `e8075f25` -> `c1e4bbe0`; the same
  seeds moved with tier 3 left empty, so it is the renamed keys); the West pins, the Easy and Average goldens and pack_test's ROME_20 / V7 / V8 are equal.
  Appending to `TIERS` shifts the siege, wagon, beast and West row indices by two (`ROME_N` moves with them). The Rome cavalry rows are no longer the generic
  horsemen except the tier-1 `cav` and the bodyguard.
- Fixed meshes: as the legionaries (domes and boxes, a flattened sphere for the shield), so the difference from the generic horseman is the grey helmet and mail
  against the red tunic, the small round bronze-rimmed parma, the shorter hasta without a pennant and the missing crest; from behind the rider's back reads red
  (the tunic over the mail box) and the horse's rump the same as every other cavalry set.
- Build: all 49 units re-rendered (the raw frames are not kept) and both packs rewritten (oblique with `pack.py --oblique --mirror`, as the committed sheets).
  Top-down atlas 1024x2732 -> 1024x2808, shade 1,082,605 -> 1,114,654 B, mask 495,711 -> 509,492 B, manifest 166,956 -> 170,082 B. Oblique atlas 4096x5648 ->
  4096x5784, shade 7,043,598 -> 7,252,952 B, mask 2,901,566 -> 2,975,295 B, manifest 1,081,760 -> 1,102,922 B.
- Aids: `tests/rome_audit_shot.gd` lists equites and equites_extra beside cav, cav2 and cav3; `tests/rome_battle_shot.gd --cav` shoots two squadrons charging
  hoplites, one along the board (from the side), one away from the camera (from behind).

### The Roman cavalry on a town (audited 2026-11-05, view only, nothing to fix)

The equites of 2026-11-02 were shot in the field only. `tests/rome_town_cav_shot.gd` (windowed; `--plan=` 0-3, `--walls=`, `--view=top|oblique`,
`--goals=` the ticks of the shots) plays a settlement battle (both sides AI) with `equites`, `equites_extra` and the shock `cav` on both sides, sends every
squadron at the nearest enemy foot (the siege AI otherwise keeps the horse back: the defenders' horse stood in the streets all battle) and shoots the
squadron nearest the town, per row and side. Read: Castrum walls 0 (a grid street, the defenders' three squadrons in column along it, the attackers
riding up the field to the gate), Punic walls 2 (the defenders' horse inside the wall at the gate and the arcade, both views), oblique and top. Seen: every
squadron stands on the street or ground with its contact shadow under the horse, no horse or lance cuts into a house (a 4-wide column fits the street, the
roofs sort over the rear rank only where the street turns), no lift on a street, the attack pose and the hasta read from the back and the side, the
equites' grey mail and parma read against the red cloth in both views (top view: round parma and hasta from above). The only oddity is the crowding of a
40-man squadron in a street (the packing of the sim's column, not the view). No view change. Shots: scratchpad `left/s1/` (not committed).

### The timber stockade (as built, 2026-11-01)

The owner on the palisade walls: "They should be raised platforms behind the wooden palisade, not a solid block wall just wooden
coloured." A walls-1 timber ring (lay "palisade" 1, a level-0 settlement with walls; `--kit-palisade` on any ring) was the stone
wall's solid geometry in timber colour (oblique) and an earth bank 2.5 m high across the band (top view). View only: `sim/` and
`campaign/` untouched, the sim's band (thickness t, parapet pp, the 4 m walk at `WALL_H[walls]`, the inner band) where it was; no
hash, no pin moves.

- **The oblique rows** (`game/battlekit.gd` `_ob_tseg_rows`, `_ob_stairs`; `battlekit.gdshader` `ob_timber_col`). With the timber
  flag the ring's second offset line is the logs' inner face (`STAKE_W` 0.5 m in from the outer edge) instead of the parapet's,
  and each stretch is: the logs' outer face (ground to hm + `STAKE_TIP`), their inner face, a post row under the platform's middle
  and one under its inner edge (posts every `POST_STEP` 2.5 m, 0.3 m, knee braces, the joist along the top; the rest discarded,
  so the ground shows under the platform), the plank platform from the logs to the walk's inner edge at hm (planks 0.3 m across
  it, an edge beam, a lit lip), its rail (posts over the posts below, a top and a middle rail, `RAIL_H` 1 m), caps where the ring
  is cut; nothing over the inner band. The same eight row kinds carry the stockade's meanings (WK_STEP posts, WK_IN the rail,
  WK_MTOP a stair, a top sloping from the ground at A to hm at B, WK_RAMP a garden fence, a face). Logs: 0.46 m, each its own
  height (0 to 0.32 m short) and shade, a pointed and fresh-cut top, rope lashings on the outer face and rails behind on the inner
  face at 1.1 m and hm - 0.7, an earth footing; both faces agree (|u| along the wall). **Sort:** explicit ranks per stretch, since
  the facing rule put the logs' inner face over the platform: a wall whose inner side faces the camera draws outer face, inner
  face, middle posts, platform, inner posts, rail, caps; one whose outer side faces it the reverse (rail and inner posts first, the
  outer face last). **Stairs:** one plank stair (`STAIR_W` 1.6 m, run 2 x `STAIR_RUN` 1.8 m) at each of the sim's stair points
  (lay "segs", the point in the inner band), along the wall, its top toward the stretch's end unless that climbs toward the camera
  (then the other way: a stair climbing toward the camera foreshortened to a sliver); keyed just after (inner side toward the
  camera) or before its wall; never fading. The flat stair marks of `CityDraw.draw_over` are not drawn over a stockade in the
  oblique view, and are plank-coloured in the top view. The ring's height for a stockade is `WALL_H[walls]` (it was 5 m for any
  level), so the platform is where the men are drawn. **Graphics Low** (`_LowDraw._timber_row`): the logs one polygon with a
  saw-tooth top, posts, rails and fences thin quads, platform and stairs quads.
- **The top-down strips** (`tools/battlekit/build.py` `stockade`, used by `b_pal_strip` and `b_pal_sim`): 27 logs a 12 m tile
  (0.46 m, 5 m plus a 0.8 m point) on a 1.2 m earth footing, two lashing rails, the plank deck at 5 m from the logs to the walk's
  inner edge, two rows of posts (5 a tile) and the rail; the inner band is empty, so the strip's texture ends at the rail
  (`battlekit_strips.gd` ps_8 v -4.75 .. 4.75 -> -4.5 .. 2.25, ps_10 -> -5.5 .. 1.25, ps_12 -> -6.5 .. 0.25) and the ground and the
  deck's baked shadow show behind it. Rebuilt with Blender (ps_8 / 10 / 12, pal_8 / 10 / 12) and repacked with `pack_strips.py`
  and `pack.py`; the other 59 atlas crops are pixel-identical (only their places moved); the stone strips were not rewritten.
  Sizes: ps_8 albedo / nrm / low 10,368 / 3,951 / 3,403 -> 7,605 / 1,759 / 2,531 B, ps_10 12,212 / 4,017 / 3,983 -> 7,603 /
  1,850 / 2,501, ps_12 14,224 / 3,980 / 4,571 -> 7,671 / 1,820 / 2,469; atlas albedo / nrm / low 800,636 / 169,642 / 251,896 ->
  787,884 / 156,346 / 246,313 B (1024 x 1024 unchanged).
- **Kept.** The round log towers (`tower_timber`) and the timber gate pieces (`pgate_*`); no square blockhouse.
- **Also, the native lesson's village** (siege_and_towns.md "The native lesson's village", second pass): garden fences as wall
  rows (oblique) and `_FenceDraw` (top), palm thatch (an instance culture + 8 shades the kit's light thatch grey-brown;
  the Low path darkens it), the chapel's tower on the plaza and a cross before it, the earth floor.
- **Checked:** shots `tests/native_village_shot.gd` (now `--print` for the ring, the fields and the units) before and after in both
  views, High and Low; `siege_oppidum` (the Celtic oppidum plan the native towns use) with `--kit-palisade` in both views (Tayasal is a West open town: no ring to draw).
- **Open.** A wall running exactly north-south shows its faces edge-on (the platform reads, the logs' faces do not; the same for a
  north-south fence, whose posts vanish); the posts are drawn on the platform's two lines only, not under the logs; men on the
  platform are drawn by the occluder as before (the rail ghosts their legs on a wall whose inner side faces the camera); the
  owner's eye on the log size and the platform's colour.

### Stone stairs (as built, 2026-11-02)

The owner: "I also want to add proper stairs to the stone walls. These palisade stairs look great now and it gives the units
something to move along while traveling up to the top of the wall and down." A stone wall's stairs were four flat lines on the
ground at each stair point (`CityDraw._draw_stairs`, from `draw_over`), and a climbing unit was drawn wholly at the walk's height
from the moment it started up (`u_wall` is set at `_climb`) and wholly on the ground going down. View only: `sim/`, `campaign/`
and mapgen untouched; no hash, no pin moves.

- **The run is the sim's.** A man climbs from the foot D (on the ring road, half its width in from the inner face) to the stair
  point S (the middle of the inner band) and on to the walkway point E, straight across the wall (`_stair_set`; the stair's cells,
  `C_STAIR`, are the inner band `STAIR_HW` either side of S). A probe (`stair_probe`, a walls-2 ring) put the climbing men within
  1.5 m of S's line on the stair cells, on them from about 3.3 m in front of S to 1.2 m behind it, then on walk cells. So the
  flight runs across the wall, not along it as the stockade's planks do: `CityDraw.stair_flights(lay)` gives, per segment end in
  the sim's order, S, the inward normal and the distances from S of the foot (c_foot = the inner face + `RING_W` / 2, D), the
  landing (c_land) and the walk's inner edge (c_top); the flight rises from the ground at c_foot to the walk's height at c_land
  (`FLIGHT_LAND` 0.8 m before the walk's edge, where the walk's cells begin) and a landing runs on to the edge; `FLIGHT_HW` 2 m
  either side (4 m wide). Walls 1: 4.2 m of run for 5 m, walls 2: 6.2 for 7, walls 3: 6.2 for 9 (steep, 50-55 degrees: the sim's
  band is that narrow). Every stone ring: walls 1-3 of each plan and the West harbour fort with its bastions (the citadel's
  edges are too short for a walkway stretch, so it has no stair points).
- **The oblique rows** (`battlekit.gd` `_ob_stairs`, `_ob_stone_flight`; `battlekit.gdshader` `ob_stair_col`). `_ob_stairs` now
  serves both rings over `stair_flights`: the stockade's plank stairs as before, a stone wall's flight as rows of its own
  stretch with no facing (never fading), keyed just after its wall when the inner side faces the camera and just before it when
  the outer side does (the stockade's rule), the usual ranks inside it (faces turned away, tops, faces toward the camera): the
  sloped top (a `WK_WALK` top), the landing (a plain walk top), the two sides (`WK_CAP` faces) and the landing's sides. Stair rows
  carry `STAIR_ROW` (2.0) in custom.w, where a stretch's fade goes (they never fade); a side's custom.y says which end is high.
  The shader: treads of about `TREAD_RISE` 0.3 m (rounded to fit the walk's height: 23 steps on walls 2), each a riser then a
  tread, the riser's share as the camera sees it (about half a step when the flight climbs away from the camera, in the light by
  its own direction; a shadow line when it climbs toward it; a faint line seen from the side, where strong lines read as a fence),
  a lit nosing, each tread its own wear, a coping on both edges, the foot darker; the sides coursed like the walls with their top
  cut to the steps' profile (the quad reaches a step above the slope and the rest is discarded) and a lit lip on each step; the
  wall's culture tint (`STONE_TINT`). **The notch:** the flight stands in the inner rampart (`RAMP_DROP` below the walk, drawn solid
  across the inner band), so `_ob_walls` cuts the band's inner rows (the step down, the rampart's top and inner face) over each
  flight's width and caps the rampart's cut ends (`_ob_wseg_rows` `inner`, `ics`, `ice`); on an edge with a notch every line is
  cut square across at the same distance along it (the mitred lines are not the centre line's length: the old proportional
  split put the notch 2-3 m off the flight on a castrum's square corners); the edge's own ends keep their mitred points.
  A flight on a breached stretch (rubble at S) is not drawn. **Graphics Low** (`_LowDraw._stair_row`): the treads one quad with a
  line at each step, a side one polygon with the steps' profile on top.
- **The men on the treads** (`soldier_layer.gd` `_stair_lift`). A man of a unit going up (`u_stair` 3) or down (1) a drawn
  flight is lifted by his own place on it: on a walk or tower cell the walk's height, else by his distance along the run from
  the foot (0) to the landing (the walk's height), 0 more than `FLIGHT_HW` + 0.75 m off to its side; his unit's own lift is 0
  meanwhile. Texture path: a per-man block 10 (dm) after the order block (oblique: `BLOCKS` + 2), added to the unit's lift in
  `soldiers.gdshaderinc` and `soldier_bases.gdshaderinc`; CPU path: his own sprite column (sprite + 16 x dm) after the run fill.
  The nearness takes the height, so a man on a tread is not ghosted by the flight behind him. A stockade keeps the unit's lift
  (its plank stairs are not on the run). Not lifted: ladders, and the tray, standard and marker (still the unit's).
- **Two runs crossing.** At a re-entrant corner (the West fort's bastion flanks, 4 pairs a fort) two stairs' runs cross and the
  sim's foot can fall in the other wall's body; of such a pair only the one whose foot is clear is drawn (`stair_flights`' sixth
  element), and the other's men keep the unit's lift as before.
- **The top view** (`CityDraw._draw_stairs`, static, drawn once; also the campaign's battle-map preview): the same flight from
  above, its shadow pushed to the lower right by its height, the base, a band per step (a dark riser line and a lit nosing,
  lighter as they rise), the landing, a shaded coping on the side away from the light and a lit one on the other. The oblique
  view no longer draws the flat stair lines (stone or plank). A stockade's top-view stairs stay its plank lines.
- **Checked:** shots (st_shots, `stair_shot.gd`: a defender ordered up, the sim stepped to mid-climb) before and after: a Rome
  walls-2 ring's north wall (inner side toward the camera) climbing, both views, both soldier paths, Low; its east, south and
  west walls; the West harbour assault's walls-3 port with a unit coming down; `west_fort_storm` (the harbour fort and its
  bastions) in both views; `siege_castrum` (walls 3, square corners) close. Battle hash untouched (`git diff sim/ campaign/`
  empty).
- **Open.** On a wall whose inner side faces east or west the flight is seen from the side and the rampart beside its notch
  (nearer the camera) hides the lower part of the flight and the men on it, who are drawn as ghosts (the occluder's rule, true
  geometry); the flight at a stretch's south end there can stand behind the corner tower. On a wall whose inner side faces away
  from the camera the flight climbs toward it: behind the wall, and where it shows (a bastion's gorge) a thin sloped band (the
  stockade's "turn it to climb away" rule cannot apply: the run is the sim's). The flights are steep on walls 3 (the band is
  4 m). S comes rounded to the metre, so a flight can sit up to about 0.7 m off its stair's cells (a man's height then steps a
  little where he reaches the walk's cells). A man dying on the flight drops to the ground as a corpse. The owner's eye on the stone's tone (the treads are lighter
  than the faces).

### Gates at their wall's angle (as built, 2026-11-02, view only)

The owner: "If a gate is at an angle it should match that angle. Right now they are all straight on, even if the wall is at an angle."
**Cause.** The sim's gate carries its stretch's outward normal (`dir`, 1/1024 turns), and the top view and the battle kit already turn the
gate piece by it (`i_e`; `CityDraw.draw_gate`); the oblique view could not: it stands the gate up from the oblique kit sheet
(`KitOb.index_yaw`: a piece has its 0 / 180 render, a non-square one also 90 / 270), a sprite pre-rendered at 40 degrees that reads from
one direction only, so on every angled stretch (the polygonal Polis, Punic, Oppidum and Ring plans, the West forts and bastion faces) the
gate stood square to the camera, askew in its wall. The plans' square towers (`tower_sq`, the gate's two included) had the same defect;
round and log towers are symmetric. **Probe** (`scratchpad/gate/gate_probe.gd`: Rome plans x walls 1-3 x terrain / coast / level / seed,
and every West plan town at walls 1-3): of 673 Rome gates 497 are more than 1.4 degrees off the axes (Castrum 0 of 150, Polis 172 of 180, Punic 127 of 143,
Oppidum 62 of 64, Ring 136 of 136; by walls 1 / 2 / 3: 177 / 173 / 147), of 298 West gates 271 (84 / 84 / 130 at walls 1 / 2 / 3: 76 / 77 / 118).
**Built (the walls' own route: mesh in the kit shader, like the stretches, the stairs and the fort's corner drums).** `BattleKit._ob_gate_rows`
builds each off-axis gate as wall rows in the gate's own frame (`e` along the wall, `n` out, depth the wall's thickness + 1 m, height
`max(wall + 1, 7 x hw / 4)`): jamb piers either side of the opening (the stockade: two log posts a side), the outer lintel over the door's
height with the merlon band, the inner deck, the passage floor and the door leaves by state: shut, two leaves a little in from the outer face
(planks, iron straps); open, swung back along the passage sides; broken, the jambs' stumps at three heights, a few stones and a fallen beam,
no lintel or deck. Parts are appended back to front along the camera's view of the gate (`n.y x v`) and share the gate's sort base (the
sprite's: the ring's nearest point), so the faces turned away, the tops and the faces toward the camera sort as the stretches' do. The rows
carry `GATE_ROW` (3, the wall's stone or the ring's timber) or `DOOR_ROW` (5, planks and floor) + the flash in custom.w
(`battlekit.gdshader` `v_gate`, `ob_door_col`; a stair is 2, a stretch's fade 0 .. 1), so a struck gate flashes (`_ob_gate_flash`, the rows'
custom data only) and never fades; a state change (`refresh`) builds the oblique rows again as a breach does. `_ob_sqtower` builds a stone
square tower off the axes the same way (the sprite's size: body 0.87 r, platform 9.9 / 6.1 r, merlon band, a stretch of its own). Graphics
Low draws the same rows flat-shaded (`_LowDraw._wall_row`: a door brown, the floor dark). The shadow keeps the sprite's instance: the
shadow bake already rotates a footprint by `i_e`, and the instance stays in the kit's list (the top view, the shadow, `_gate_state`).
**Kept as before.** A gate or tower within `AXIS_TOL` (4 / 1024, 1.4 degrees) of the axes keeps the sprite (every gate and tower of the
Castrum plan, 27 of 298 West gates): its oblique shots are pixel-identical to before; `ALL_MESH` (one constant) makes every gate and square
tower rows for one look in every town. The top view is unchanged (it always followed the angle). **Stockade:** the ring's gate is the
`pgate_*` piece and is built the same way (log posts, a beam, planks); the native lesson's garden fences have a 3 m gap that is not a gate
piece (axis-aligned plots), and the ring's own palisade gap is the gate: neither was given a piece. **Checked** with `scratchpad/gate/`
shots (shut / open / broken, High and Low, the Punic plan's gate 0, Cartagena's fort gate, a Ring village's stockade gate, the Polis' north-facing
gate) in the oblique view before and after, the top view before and after identical, an axis-aligned Castrum gate before and after
pixel-identical (`--bare`: no soldiers, no HUD). **Open:** the mesh gate reads lighter and plainer than the sprite (the sprite was
a dark baked render); a town with one aligned and one angled gate mixes the two looks; the round and log towers beside an angled gate are
symmetric and unchanged; the owner's eye on the jambs, the lintel height and the door; no phone look.

### (2026-11-05) The ship on the board (as built, view only)

A fleet supporting the shore lies on the water of a port town's battle (battle_sim.md "A fleet at the shore (as built,
2026-11-05)"); `game/ship_layer.gd` draws each hull under the men (added after the field works, before the trays and
the soldiers, lifted by the board like them: `BoardView.lift_node`), so her gun crews stand on her deck and her guns
(the engines' own sprites, the landed naval guns' set) on top of it. **Which route:** the sea screen's hull drawing,
placed on the battle board, not a mesh piece: the top view draws `game/sea_battle.gd` `_draw_ship`'s hull outline
(seven points; a canoe's pointed both ends) flat at the sim's anchor and keel (`sh_x` / `sh_y` / `sh_head`, `sh_len` /
`sh_beam` from the sea sim's row): the waterline's foam, the hull, the deck, the rail in the owner's colour, the
gunports, the masts with their sails furled on the yards across the hull, the ensign at the stern; the oblique view
stands the same outline up as a small solid in the siege gear's way (`ShipLayer.Solid` extends `game/siege_gear_ob.gd`:
drawn in the lifted node's upright groups, `BoardView.up_xf`, with the board's oblique constants): the hull's sides
(shaded by the key light, the faces turned away left out) and the deck 0.5-2.6 m above the water, gunports along the
near side, the masts (a miniature's: 0.42 x her length, at most 18 m), two yards a mast braced round 23 degrees so the
furled sails (a pale roll under each yard) show from the table's side, a pennant at the masthead. A canoe has paddles
shipped along both sides and no mast; a piragua one mast. A ship whose guns are all silenced is drawn dark and lower,
her masts but the first shot away to stumps; one out of the fight fades. The colours are her fleet's faction's
(the scenario's `f`; else her side's); the men aboard and her party wear the same (battle.gd extends `unit_faction`
over the units the sim adds). Redrawn only when a ship's state changes. The landing party is drawn as the amphibious
men are (figures standing on the water while they paddle). Shots: the session scratchpad `shore2/` (top and oblique, a
party coming ashore at the quay). Open: the deck is a flat plank colour (no hatches or boats); the hull does not rock;
the crew figures stand at water level under a deck drawn 0.5-2.6 m up (a few pixels low in the oblique view); the
owner's eye on the masts' height and the yards' brace.

### The 3D battle view, step one (2026-11-06; plan and as built, view only)

**The decision.** The owner, after the 3D spike on his phone (the session scratchpad `spike3d/report.md`): "go with the 3D view
with painted sprites." The spike drew 3,400 men as the oblique sheets' painted cards in a real 3D scene (orthographic camera, one
lamp, shadows on) at 112 fps on his Galaxy phone (Firefox, 2094 x 798, Fit; average 8.9 ms, p95 16.5 ms, 131k triangles),
against 23-27 fps (p95 64-77 ms) for the game's 2D soldier layer at the same count; mesh figures held 74 fps (800 triangles,
shadows on) but are not needed for this step. So the board, the camera and the lamp go 3D now, the figures stay the painted
sprites (cards), and meshes come set by set later where the close-up pays.

**What it is.** A third Battle view, **3D**, beside Top and Oblique (Options > Battle view; `[video] battle_view = 3d`,
`--battle-view=3d`, `?battle-view=3d` on the web, `BoardView.force = "3d"` in tests). The defaults are unchanged (Oblique); nothing
the player sees changes until he picks it. View only: nothing under `sim/` or `campaign/` changed, no hash, no lockstep input; the
view reads the sim and the 2D layers' built data and sends orders as the other views do.

**Architecture.**
- `game/view3d.gd` (a Node3D under the battle, `Battle.view3d`) holds the scene; the battle's own viewport renders it first and
  the 2D canvas (the overlay, the HUD) on top. The 2D world layers (board, terrain, city, works, ships, trays, soldiers, trees)
  are still built, since the overlay, the orders and the 3D layers read their data, but are not drawn (`visible = false`; the
  soldier layer keeps running its per-tick work, on the CPU-fed path).
- **One transform for both.** `game/board_view.gd` generalises the oblique board transform with the camera's yaw and elevation
  (`BoardView.v3d`, `set_view(yaw, elev)`): a ground point w goes to (dot(w, r), dot(w, f) x sin(e) - lift(w) x cos(e) / cos(40)),
  r and f the camera's right and toward-the-viewer directions on the ground. With yaw 0 at 40 degrees it is the oblique view's
  exactly. The orthographic Camera3D is placed every frame from the battle's Camera2D (its canvas transform: the board point at the
  screen's centre and the zoom; `View3D.sync_camera`), so this transform is the 3D camera's projection of the ground, pixel for
  pixel: the overlay keeps drawing in the board's space through `game/board_lift3d.gdshader` (the lift shader with the yaw), and
  the taps come back through `BoardView.to_world` (the inverse marched along the view ray, `_to_world_3d`). The camera's zoom
  levels, the fit, the clamp (the rotated field's bounding box) and the dive are the oblique view's.
- **The board**: a mesh of the fine lift field's nodes (2 m; a coarser stride past 200,000 vertices; the coarse grid sampled every
  4 m on the compatible path or Graphics Low), the foam steps quantised as `BoardView.quant` does, the 3D y the lift over
  `px_per_m x cos(40)` (the 1.4 x exaggeration included). Shaded by the terrain shader's own body: `game/terrain.gdshader`'s
  uniforms and fragment moved verbatim into `game/terrain_body.gdshaderinc` (`terrain_col(world, ob_in)`), the canvas shader now a
  thin wrapper, `game/terrain3d.gdshader` the spatial one with the 2D layer's material parameters copied (`View3D.copy_params`):
  the painted board of pass 2 and the hills of pass 6, the resin water where the map has it, the streets (the city's street
  texture) and the Paths hatch as ground decals. The baked hill shade is off (`shade_k` 0): the lamp lights the steps. The 2D
  shading's display values go to ALBEDO unconverted (the Compatibility renderer's output matches the 2D layers that way; linearised
  first, the board came out far too dark).
- **The table**: the board a cut slab on all four edges (`game/board_slab3d.gdshader`: foam layers a band high in two creams with
  a glue line, an MDF base strip, the flock's lip) standing on a wooden plane (`game/table3d.gdshader`: 26 m planks, seams, grain,
  falling off into a dark room).
- **The camera**: orthographic at the oblique view's 40 degrees, the same zoom levels and fit; turns freely in yaw (no snapping)
  and tilts from 25 to 60 degrees (`Battle._v3d_turn`, about a screen point: the ground under it stays under it); a turn keeps a
  little inertia (0.35 s). The battle opens facing the player's side (an army deployed in the north half turns the table half
  round). Gestures: ui.md "The 3D battle view's camera".
- **The lamp**: one DirectionalLight3D fixed to the camera's yaw frame, from the screen's upper left and the far side (the painted
  sprites' key light; shadows fall to the lower right as the 2D views' baked ones), light 1.0, ambient 0.42, linear tone mapping
  (the spike's). Shadows on at Graphics High, off at Low (orthogonal, the range following the camera's span).
- **Cards**: every card (a man, a tree, a house) is a quad placed in the vertex stage in the camera's plane from the camera's
  axes passed as uniforms (`cam_r`, `cam_u`, `cam_b`), so the shadow pass builds the same card and the card casts its silhouette.
  A card is moved toward the camera along the view (its screen place unchanged) by its sheet's part below the anchor x cot(e) so
  that part clears the ground in front: the depth buffer then orders men, houses, walls and trees (no per-tick sort, no occluder,
  no ghosts behind walls: a man behind a wall is hidden by it, a man in front is drawn over it). Alpha-cut (0.5), so cards write
  depth and cast shadows; unshaded (the light is painted in).

**Checkpoint A (the board and the camera).** The board mesh, the terrain shader port, the slab and the table, the camera with
yaw and tilt, the lamp and shadows, the trees as cards (`game/trees3d.gdshader`: the tree layer's woods and orchards at their
ground height, the oblique kit sheet's tree sprites, the canopy thinned over men by the tree layer's occupancy texture; the
ground cover, reeds and tufts not drawn yet).

**Checkpoint B (the kit and the men).**
- **The men** (`game/soldiers3d.gdshaderinc`; `soldiers3d.gdshader`, `soldiers3d_cpu.gdshader`): the soldier layer's CPU-fed
  buffer goes as it is into a 3D MultiMesh (`SoldierLayer.v3d_mm`, TRANSFORM_3D with no custom data: the 2D layout's 8 transform
  floats land where the 3D transform's do and its custom data in the transform's third row, `MODEL_MATRIX[0..3].z`, read back in
  the shader; the man's height on a wall, a stair, a ladder or in a held building in the sprite column as the oblique CPU path
  has it, without the reorder: `_ext_cpu`). The action, frame, tints and palette are soldiers.gdshaderinc's oblique branch (copied:
  the same numbers), the sheet direction against the camera's yaw (`cam_yaw` added on the one line, as the plan of 2026-11-05
  found); an action with no upright frames lies on the board as the top-down sprite. The ground's height in the vertex stage: the
  fine lift field (one texture read; the default) or the coarse grid's uniforms (`CPU_FED`: the compatible path, with the board
  then the grid too); the data itself is never a texture. The round flocked bases with the faction's rim lie flat under them
  (`soldier_bases3d.gdshader`, lit, shadows fall on them). The soldier layer's 2D probe is off in the 3D view (its layers are
  hidden); the 3D view has its own (`View3D._probe`, "V3D_PROBE drawn=N men=M path=v3d-gpu|v3d-cpu", the soldier layer's `probed`
  signal for telemetry): no men drawn on the fine path switches the men, bases, missiles and kit to the compatible shaders and
  remembers "cpu" for later battles.
- **The missiles** (`game/projectiles3d.gdshaderinc`): the CPU-fed missile buffer as it is (`v3d_pr_mm`); the shot flies a
  straight line from the ground under the shooter (plus his height) to the ground under the target plus its arc, now in real
  height, 1.1 m up (a man's chest); the streak a card turned along its path on the screen. The muzzle flashes and the gun smoke
  stay the overlay's (2D billboards over the 3D, placed by the board transform).
- **The kit** (`game/battlekit3d.gdshaderinc`; `battlekit3d.gdshader`, `battlekit3d_cpu.gdshader`): the oblique view's sorted
  MultiMesh rows as they are (`BattleKit.ob_buffer_3d`, 12 floats a row). A wall row (walls, merlons, the walk, the inner
  rampart, end caps, gates and square towers off the axes in their own frame, the trace forts' drums, stone stairs, the timber
  stockade's stakes, platform, posts, rail, plank stairs, the garden fences) becomes real geometry on the board's ground, coloured
  by battlekit.gdshader's own functions (copied); the sheet pieces (houses, towers, gates on the axes, bastions, rocks, the town
  plan's landmarks) are cards at their footprint's centre, re-picked from the sheet's renders for the camera's yaw (a piece at
  world yaw Y shows its render nearest Y - the camera's yaw: 0 / 180 for square pieces, 0 / 90 / 180 / 270 for the long ones; the
  rows are copied again when the camera crosses into another quarter, and when `BattleKit.ob_rev` counts a change: a gate's state,
  a fallen house, a breach). Lit softly by the lamp (no N.L: the faces carry the 2D key; lit 1.0, in shadow 0.71), casting
  shadows. The wall fade and the occluder are not needed. The kit builds its rows on every graphics setting in the 3D view
  (`BattleKit._want_low`: Graphics Low's pre-lit 2D drawing has no rows, so a Low or compatible-path device would have shown
  no town; found on the third cover pass's base, 2026-11-06), and skips the 2D shadow bake there (the lamp casts them).
- **The siege gear and the ships** (`game/solid3d.gdshader`): `game/siege_gear_ob.gd` gained a 3D emitter (`build_mesh`: every box,
  bar, quad and knob into a SurfaceTool in world metres on the ground under the piece's anchor; the 2D drawing unchanged, the
  overlay skips its oblique gear in 3D) and `game/ship_layer.gd` `build_mesh3d` (the hull's prism, rail, oars, masts, yards and
  furled sails through the same emitter); rebuilt each tick (the gear) or when a ship's state changes.

**Checkpoint C (the overlay, the orders, the HUD).** The overlay keeps its code: every mark it draws (selection, the move and
attack previews, the placement tool's ghost and handles, range rings, cover chips, hittable marks, deployment zones, group badges,
standards, tokens, smoke, flashes) goes through the board transform with the yaw (`board_lift3d.gdshader`; the few spots that
squashed a direction by OBLIQUE_COS now call `BoardView.dir_board` / `dir_world`), so it lies on the 3D ground but draws over
the 3D (no depth: a house does not hide a marker). The Paths hatch is drawn by the board's shader. Taps, drags and the long press
come back through `BoardView.to_world`; gestures in ui.md "The 3D battle view's camera". The HUD is unchanged; Options and the
Keys page gained their entries.

**Measured (2026-11-06).** tests/v3d_test.gd: the 3D camera's projection of the ground against the board transform 0.00 px
(4 yaws x 3 tilts x 3 zooms over the ridge), the board round trip 0.001 px, a turn's pivot 0.00 px, taps on a marker select and
taps on the ground order the unit 0.00 m from the tapped point at yaws 0 / 120 / 240 (tilt 30 at the last). input_test in the
3D view: 502 / 502 at yaw 0; at 120 and 240 two and three checks fail that assume screen-right is world east (a mouse line
"straight along the drag" in world y, the placement ghost's world dx after a screen drag, a right-click group's spacing near the
edge); input_test's artillery tap now aims at `marker_screen` (the old world offset north missed the marker in a turned view).
Frame cost (this desktop, RTX 3070, the battle running, HUD and overlay on, 1280 x 720, 8 s at the fit; the machine lightly
loaded): battle_2000 (2,028 men) 3D avg 4.98 ms, p95 8.46, GPU 1.40 ms, 372k primitives, against Oblique 5.40 / 9.24 / 1.49;
bench_4000 (4,055 men) 3D 9.54 / 20.5 / 2.76 against Oblique 9.27 / 20.5 / 2.69 (the frame is the sim's at that size);
3D on Graphics Low (no shadows, the coarse grid) 9.47 / 20.3 / 2.93. The phone is the real measure: the owner's readings of the
web export are the next step. Web: the export builds (index.pck 18.9 MB, oblique.pck 14.7 MB) and `webcheck -v3d` (new) passes
in headless Chromium (the scene built, the probe 811 px on the v3d-gpu path).

**Left for step two.** Meshes set by set (the spike's bone-texture route: musketeers and the West line sets first; 800
triangles the budget, 2,400 at the close zoom); the houses and towers as meshes or at least more renders (they swap between their
renders as the table turns); the board as a true cut slab following every hill (the foam faces with lit risers instead of the
2 m grid's sloped steps, which show zig-zag edges up close); things on the table (plan pass 9); the ground cover, reeds and tufts;
the tray fill (the standards and tokens stand, the card tray under a unit is not drawn); the terrain layer's drawn decals
(tracks, flock-square fields) as ground decals; the rubble's heap (the third cover pass's 1.3 m: the 3D view lays it flat as a decal); the gun smoke, flashes, standards and markers as 3D billboards
with depth (now 2D over everything); the top-down view as a steep 3D camera and the oblique view retired when the phone holds.

### The 3D battle view, step two: houses as geometry (as built, 2026-11-06)

**The ask.** The owner, after turning the table on his phone: "The 3D view looks great! The houses need more panels or to be
switched to 3D models, they rotate with the camera and then snap into the next view." Every kit piece the 3D view still drew
as a card is now a mesh: the Rome houses (house_gable_s / m / l, house_hip_s / m, longhouse, house_L, hut_round, hut_thatch,
house_flat_s / m), the church and temple, the West town's buildings (tavern, shop, store, warehouse, chandler, shack,
leanto, governor, magazine), the towers (tower_round, tower_sq, tower_timber), the bastion, the props (stall, well, cart,
barrels, crates, lowwall, stakes, pier), the rocks (rock_a / b / c) and the 32 block 2 landmarks and civic pieces (lm_*,
cv_*): 69 meshes. The gates and the square towers on the axes, which kept the sheet's sprite in step one, are built as the
wall rows they already were off the axes (`BattleKit._off_axis` is true in the 3D view). What stays a card: the trees and
bushes (a tree reads alike from every side; the owner did not ask) and the men (the painted sprites, as decided). View and
art only: nothing under `sim/` or `campaign/` changed.

**The pipeline.** `tools/battlekit/export3d.py` (Blender, `build.py` loaded as a module; tools/battlekit/README.md) builds
each piece with the kit's own builders, so nothing is modelled twice. `P.detail3d` adds what the top-down renders never
needed and the 3D camera does: per building a door (with lintel and step) on the street side (+y, the West pieces' street
front), windows on the front, back and ends, one row per storey, each a dark pane, two shutters in the culture's accent
colour and a sill, a few centimetres proud of the wall (`build.py openings`; the sprites are not rendered again, so the
atlases and the top and oblique views are unchanged). Per piece the parts are joined, the bottoms dropped, the foot pushed
1.2 m into the board (a house on a slope never floats), triangulated and collapsed to its budget only when over it; the UVs
smart-projected; the painted albedo baked with Cycles from the kit's emission materials (the noise, courses, tiles and
planks of the sprites; the masked roof, plaster and accent parts grey) times a soft ambient occlusion against a ground plane
(0.62 + 0.38 x AO: the darker foot and the eaves' shade the sprites' AO gave). `tools/battlekit/kit3d_res.gd` packs the
textures into one atlas and the meshes into one resource: `assets/battlekit_ob/kit3d.res` (one ArrayMesh, a surface per
piece; vertex, normal, the atlas UV, the mask class in UV2.x: a vertex colour is read as sRGB and the classes came out
wrong) and `kit3d_albedo.png` (lossy WebP, mipmaps). Both sit beside the oblique sheet, so the web's on-demand oblique pack
carries them (`export_presets.cfg` "Web oblique pack", `tools/export_web.sh`'s version hash); `game/kit3d.gd` loads them,
`--no-kit3d` (or no file) falls back to step one's cards.

**The budgets.** Triangles: 350 for a Rome house with its windows (350 gable, 348 hip, 462-474 flat roofed, 542 the longhouse,
1,022 house_gable_l with two storeys of windows), 92-338 the huts, 540-1,260 the West buildings (2,678 the governor's
palace), 282-440 a stone tower, 1,308 the log tower, 260 a rock (collapsed from 900-1,500), 22-622 a landmark; 28,339 for
all 69. A town's houses in all: West town 166 pieces, Rome city 115 (about 60k and 40k triangles drawn, against the board's
62k / 21k vertices and the men's 2,000 cards). Texture: 7 px per metre of surface (3.5 for the landmarks, 40-90 m across),
packed into one 2048 x 1984 atlas (the textures scaled 0.85 together to fit 2048), 16 MB in memory with mipmaps.

**In the view.** `View3D._build_meshes`: per kit a MultiMeshInstance3D per piece kind (TRANSFORM_3D, the culture in the
custom data; no node per house), filled from the kit's own instances (`i_pos`, `i_e`, `i_sx` / `i_sy`; the footprint's centre
on the instance's place as the oblique sheet anchors the card, x scaled by i_sx, the depth and the height by i_sy so a roof
keeps its pitch) and the landmark rows (`_ob_lm` now carries the piece's origin, yaw and scale), each on the board's ground
under it (`BoardView.ground_m`, so the compatible path's coarse grid needs no vertex texture read either: the shader reads
none in its vertex stage). The pieces turn with the table: a mesh's transform is world-fixed and never swaps. The cards of
the meshed pieces are left out of the kit's rows (code 0); a fallen house's mesh is left out when the kit's rows change
(`ob_rev`), its rubble drawn as before; the held building's outline and door mark are the overlay's, as in the other views.
Rome's houses have no street side in the plan: the mesh's door turns to the open side when its own side faces a building
or a wall 6 m out (`_street_flip`, the sim's obstacle cells read only). Shading (`game/kit_mesh3d.gdshader`): the baked albedo
recoloured by the culture's palette through the mask class (battlekit.gdshader's stone tint and pal_r / g / b, the palm
thatch), lit as the painted sprites are (an ambient with a sky term and one key, normalised so a face looking up reads at its
painted value, the battle look's saturation and contrast) with the key along the 3D lamp (from the camera's upper left and
the far side, as the sprites' key); half-Lambert with a floor (0.25 + 0.75 x the light), because the sprites light a wall
turned from the key at about 0.6 of its paint and a plain N.L made those walls olive-dark; the lamp adds only its shadow
(lit 1.0, in shadow 0.71, as the kit's cards) and only on faces it reaches, so a wall in its own shade is not darkened twice.
Casting shadows on High.

**Measured (2026-11-06; this desktop, RTX 3070, the battle running, HUD and overlay on, 8 s at the fit; meshes against step
one's cards, `--no-kit3d`).** Frame avg / p95 / GPU ms, primitives (the lamp's shadow pass draws the meshes again):
West town High 1280 x 720 5.48 / 9.40 / 1.32, 452k against 5.13 / 8.49 / 1.27, 291k; 844 x 390 5.17 / 8.71 / 1.27 against
5.10 / 8.41 / 1.20; Low (no shadows, the compatible path) 1280 x 720 4.78 / 6.64 / 0.91, 146k against 4.79 / 6.64 / 0.86, 66k;
844 x 390 4.89 / 8.20 / 1.08 against 4.80 / 6.77 / 1.01. Rome city High 1280 x 720 3.79 / 5.30 / 1.01, 218k against 3.75 / 5.29
/ 0.99, 127k; 844 x 390 3.70 / 5.15 / 0.81 against 3.63 / 5.04 / 0.82; Low 3.64 / 5.14 / 0.85 against 3.60 / 4.89 / 0.84 and
3.63 / 5.15 / 0.81 against 3.61 / 5.16 / 0.79. Draw calls +10 to +46 (a MultiMesh per piece kind, twice with shadows). So
the GPU pays 0.02-0.07 ms and Low does not need the cards: it draws the meshes too (the cards stay only as the fallback when
kit3d.res is missing). The phone is the real measure. Download: the web's main pack unchanged (index.pck 18.94 MB), the
oblique pack 14.7 -> 16.08 MB (+1.38 MB: kit3d_albedo 0.79 MB as lossy WebP with mipmaps, kit3d.res 0.61 MB). The build:
Blender 18 s for the 69 pieces, the packer 10 s. tests/v3d_test.gd's part 7: in west_town 166 and in siege_city 115 kit
pieces are meshes, every building the kit places (118 / 94) among them, their cards out of the rows, no gate card, and a
house's transform and mesh unchanged at yaws 37 / 90 / 180 / 271; `webcheck -v3d` now opens a West town and wants its kit
meshes.

**Known.** The baked textures are about 6 px per metre (the atlas scaled 0.85 to fit 2048), soft at the closest zoom
(the sprites are 8); the roofs are smooth planes (the tiles are paint, no ridge tiles or eaves boards); the meshes' foot
goes 1.2 m into the board, so a house on a steep step shows its skirt; Rome houses' doors face the street only where the
plan's cells say which side is open; the landmarks are at 3.5 px/m; the trees, bushes and the men stay cards; the rubble of
a fallen house is still the flat decal; no device check yet.

### The 3D battle view: the world lamp (as built, 2026-11-06)

**The ask.** The owner, after turning the table on his phone: "Shadows are rotating with the buildings, we should work on our
single light source now." Step one fixed the lamp to the camera's yaw (the painted sprites' key is the camera's top left), so as
the table turned the houses' shadows swung round with it and a house's lit faces changed with the yaw. View only: nothing under
`sim/` or `campaign/` changed; the Top and Oblique views are untouched.

**The lamp stands in the room.** `View3D.set_lamp(y)`: one DirectionalLight3D at the yaw-0 direction of step one (light travelling
(0.40, -0.77, 0.50): 50.3 degrees up, 38.7 degrees left of the camera's forward, from the far side) turned by the battle's opening
yaw (`lamp_yaw`, latched at the first frame, after `Battle` has set its view facing the player's side) and never moved again. So at
the opening view the lamp is where it was (the screen's upper left and the far side; the board, the houses and the walls read as
before) and from then on the shadows stay put on the board and the same faces of a house are lit from every yaw. On battle_2000
and west_town (opening yaw 0) the lamp stands at a bearing of 321 degrees (north-west); an army opening in the north half (yaw
180) has it in the south-east. What follows the lamp: the kit meshes' half-Lambert key (`key_dir`, the lamp's world direction);
the kit's wall rows, whose faces were lit by a world north-west key (`light_dir.xy`), turned by `lamp_yaw`; Graphics Low's painted
hill shade on the board (`terrain_body.gdshaderinc` `fake_ld`, default the old constant, turned by `lamp_yaw` in 3D); the trees'
sheet-normal key (`light_dir`, screen space) turned by the camera's yaw against the lamp's each frame.

**The figures (the paint's light).** The oblique sheets are painted with the key fixed in camera space from the top left, and only
S, SW, W, NW, N are rendered (`"mirror": true`: SE, E, NE are the W side's frames flipped, so already lit from the top right and
holding the weapon in the other hand). The three ways measured: (a) flipping the card when the lamp is on the camera's right
helps only S and N (a flipped SW is the SE render, which does not exist: SE is itself a flipped SW), so it would fix 2 of 8
facings and swap their weapon hand; (c) leaving the paint as it is shows, with the table half turned, men lit on their left with
their shadows falling to the left (shot `lamp/side/cmp.png`); (b) chosen, the cheapest that reads: a gentle side term over the
paint, `soldiers3d.gdshaderinc` `side_k` x the man's screen x (clamped to +-0.32 m about his feet), so the side toward the lamp is
lighter and the side away darker; `side_k` = `SIDE_K` (0.3) x the change of the lamp's screen x against the paint's (the painted
key turned by the camera's yaw against the lamp's), 0 at the opening yaw (the default view unchanged), +-0.22 at the figure's edges
half way round (yaw 180 from the opening), +-0.21 a quarter turn with the lamp on the camera's right (shadows to the lower left),
+-0.01 the other quarter turn (the lamp still on the camera's left, behind it). Cost: one varying and a multiply (no measurable change).
The kit's cards (only the fallback without kit3d.res) keep their paint. `--v3d-side=K` sets the strength (0 the paint alone).

**The cards' shadows.** A card faces the camera and leans back with it, so with a world lamp its shadow grew and shrank as the table
turned (the card seen edge-on from the lamp at one yaw, broadside at another). In the shadow pass (the view is not the camera's:
`INV_VIEW_MATRIX`'s z against `cam_b`) the men's, the trees' and the kit's cards now stand upright at the feet facing the lamp,
so a man's or a tree's shadow is the same length and width from every yaw; the drawn card is unchanged. At the opening yaw this
lengthens the men's shadows a little (the leaning card cast a short smudge; an upright 1.8 m figure under a 50 degree lamp casts
about 1.5 m).

**The shadow map.** Godot ignores `directional_shadow_max_distance` for an orthographic camera: the directional shadow covers the
camera's whole near-far range, and step one had near 1 m and far twice the camera's distance plus 200 m, so most of the map was
spent on empty air and at the phone's fit the houses had no shadows to speak of. `sync_camera` now fits near and far to the ground
in view (the screen's half height along the ground's slope in the view, the relief, the slab, 30 m for the tallest pieces and 10 m
spare), and the lamp uses two parallel splits at half that range (`SHADOW_SPLIT` 0.5: the near half of the ground, the screen's lower
half, gets its own map); shots `lamp/split2/` (844 x 390 fit and 0.3 zoom: one map against two; the two show the houses' shadows a
little crisper) and `lamp/cmp_wt_fit.png` (step one against the fitted range). `--v3d-splits=1|2|4` and `--v3d-split1=F` are the
testing aids. Cost, this desktop (RTX 3070, shared with other runs; one process switching the lamp's mode every second with the
battle running, 40 s, the GPU time per frame; `lamp/tools/ab_bench.gd`): West town 844 x 390 at the fit, shadows off 0.95 ms, one
map 1.44, two splits 1.24, four splits 1.55; battle_2000 844 x 390 1.09 / 1.21 / 1.30 / 1.35; at 1280 x 720 the machine was too
loaded to read (3.6-4.4 ms in every mode, the order of the modes not stable). So the two splits cost about 0.2-0.3 ms of GPU at the
fit on the desktop, no more than the one map.

**Checked.** v3d_test 4c (the lamp stands still at yaws 0 / 90 / 200, at the opening yaw), the whole of v3d_test, battle_screen_test
(three views), hud_fit_test, input_test (default view and 3D at yaw 0), custom_battle_test, lockstep_test, determinism_test
--only=deploy, menu_test; scripts clean. The web export builds (index.pck 18.97 MB, oblique.pck 16.08 MB); `webcheck -v3d` sees the
scene build with its 166 kit meshes but timed out on the men's probe at 0.1 fps in headless Chromium on a machine at load 30-50, and
step one's own export failed the same way in the same minutes (a load problem, not this change; to run again on a quiet machine). Shots: `lamp/before/` (step one) and `lamp/after/`
(the world lamp), battle_2000 and west_town at yaws 0 / 90 / 180 / 270, at the fit and zoom 2.5, 1280 x 720 and 844 x 390.

**Known.** The side term is a gradient, not a relighting: a figure's painted highlight stays on its left, only toned; the lamp
from behind the camera (half way round) still shows the paint's top-lit look; the cards' shadows are the figure's silhouette as
seen from the camera, cast from the lamp's side; the board's foam steps are lit by the lamp but most of the hills' look is painted;
the opening yaw decides where the lamp stands for the whole battle (a battle opening at 180 has it in the south-east); no device
check of the shadows' cost on the phone.
