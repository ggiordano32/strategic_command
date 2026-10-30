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
   cool, a die that rolls across the table on an auto-resolve.

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
