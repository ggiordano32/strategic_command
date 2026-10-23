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
cycle frames 0, 2, 3 slowly. The texture path reads the table from a uniform array (`frame_tab`),
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
