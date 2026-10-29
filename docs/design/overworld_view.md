# Overworld view

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

### Overworld: real geography and the landscape layer (as built, 2026-10-10)

## STATUS row
- Real geography (view data + static grid, no state change, `CState.VERSION` 6): the overworld is fitted to ETOPO 2022 elevation (NOAA, public domain) and Natural Earth 1:10m coasts and rivers (public domain). `tools/geo_fit.py` (+ `tools/geo/med.json`: window, projection, cell size, settlements, rivers; the Mediterranean is only the default config) writes `geo_rome.gd` (was `map_geo.gd`) LANDS / ISLANDS / RIVERS, `campaign/data/elev_data.gd` (per cell mean / max / relief / distance to river / class plain-rolling-valley-hill-ridge) and `game/campaign/relief_data.gd` (0.025 degree fine elevation, slope, relief); `campaign_grid.gd` derives hill / ridge from the real class (434 hill, 140 ridge override cells; was 200 / 215 from hand areas, now deleted) and asserts every settlement is on its landmass and every sea-lane port is a coast cell. Terrain view renders the real relief (hillshade + subtle hypsometric tint + crest line, one cached texture; `geo_fields.gd` serves elevation / slope / class to the view). Nudged: Carthago, Hadrumetum by 0.01-0.02 degrees. Re-pinned: campaign_test goldens (3007c1ab / 4197043257, be6e10a3 / 3786296811) and the Tarentum march rows (from Venetia). campaign_sim --seeds=6 --turns=60: hash 8562cf3a (HEAD 803bf309); no collapse; Epirus is eliminated in 5 of 6 seeds (3 of 6 at HEAD), Macedon in 0 (2 of 6). Sea depth (2026-10-17): the same ETOPO download gives `DEPTH` (one byte per fine sample, mean depth of the DEM's sea samples: 1 m steps to 30 m, then logarithmic to about 3000 m; decode in the `tools/geo_fit.py` header, `GeoFields.depth_at(p)`), baked for both packs (`--depth-only --dem`); `water.gdshader` colours the sea by it (sandy turquoise under 8 m, the shelf the earlier blue to 200 m, darker and more saturated to the deep, a faint shelf-break line where steep; the 3 / 8 km contour lines are gone), so the Bahama and Campeche banks, the Mosquito coast, the Gulf of Batabano and the Adriatic / Aegean shelves read as pale shallows.
- The overworld sea (2026-10-13, view only, third pass, `water.gdshader` + `sea_waves.gd`): printed-map look kept (thin calm shallow band, sharp 1 px contour lines at 3 / 8 km, crisp 1.6 px coast outline) with **waves** and **surf**. Waves (pass 4, 2026-10-13, after the user found pass 3 uniform and too large): five directional trains (56 / 39 / 27 / 18 / 12 map px at 0 / +30 / -28 / +45 / -40 degrees from the wind, speed about 6 sqrt(L/46), none dominant), Stokes-like sines whose phase warp and group envelope are value noise (not periodic), times a drifting gust field (noise at 650 / 300 px, 0.25..1.15: rough and glassy patches) on a wind that veers up to 0.4 rad (noise at 800 px); 7 noise samples a fragment shared by the trains; `tests/sea_waves_test.gd`; lit as a normal map from the NW (soft crests and troughs, a very small glint), damped near the coast and in sheltered water, each train fading out when under about 6 screen px; motion slow (phase speed 4.5-6 map px/s). Surf: breaker lines (3 km apart) advancing and fading in a 2.5-7 km zone, broken by noise gaps, plus a ragged swash at the waterline, only where the baked **exposure** says the sea reaches the coast (half the fetch along the wind, three rays, half the openness all round, 16 rays; heads of bays, lees of islands and the Tyrrhenian side under a NW wind get almost none), stronger on steep shores (baked `SHORE`); zoomed out the lines become a dim ragged edge; sparse whitecaps on high crests only in strongly exposed open sea; the 3 km contour fades where there is foam. `[map] water = low` (and Graphics Low): depth tint and contours, static. **Reuse for ships and other maps:** `GeoFields.wind_dir()` / `wind_strength()` / `exposure(p)` / `shore_steep(p)` come from `relief_data.gd` (`WIND_FROM_DEG`, `WIND_STRENGTH`, `EXPOSURE`, `SHORE`), baked by `tools/geo_fit.py` from the config key `"wind": {"from_deg", "strength"}` (`med.json` 315 / 100, the mistral; a Caribbean config says 90, the trade winds from the east; `python3 -I tools/geo_fit.py --config X --exposure-only` re-bakes only these from the COAST and SLOPE already in the file). `SeaWaves.height(p, t)`, `normal(p, t)` and `amp(p)` are the CPU twin of the shader (same trains; `SeaWaves.t` is the clock `map_view` also sends the shader). A ship sprite sits on it: its lift is `height * amp * k`, pitch and roll are the normal's components on its hull axes (times `amp`), its heading is its own; its wake is a `Line2D` of stern positions kept in world space that widen and fade over a few seconds (no drift with the sea: the waves are a phase pattern, not moving water), and the hull is drawn above the water node, below labels and armies. Nothing of this is in any hashed state.
- Graphics quality (2026-10-13, view only, `game/quality.gd`): `user://settings.cfg [video] quality = auto | high | low` (home settings row; `--quality=` overrides). Auto is Low when the soldier probe chose the CPU path (Chrome on the Tab S7) or when the first 3 s of a battle average under 40 fps (session only, toast "Graphics set to Low for speed"). Low: the ground shader's `low` uniform drops the noise patches, grain and the sea / ford animation; the settlement surroundings are flat-tinted fields and one-line tracks (`CityDraw.draw_surround(..., low)`); the tree layer hides the cover MultiMesh (tufts, scrub, bushes, reeds, willows) and the orchard rows (`visible_instance_count`), gameplay woods stay; the overworld sea is the still `hi = 0` water and the landscape tree / speckle mesh is skipped below zoom 0.9 (the relief texture stays). All switch live in a battle (the auto downgrade) and apply on the next battle / map open from Settings.

**Map table style (as built, 2026-10-14).** `[map] style = auto | table | relief` (Settings
button "Map", `--map-style=`): auto is the table for the West pack and the relief for Rome
(Rome in relief is pixel-identical to before). Table: `table_land.gdshader` draws the land
(brighter palette, 4-level posterised hillshade from the real elevation, ink contours,
sand coast band); the sea (`water.gdshader` `table = 1`) has five clean depth bands with softer
waves; the owner wash is 15 % with a stronger inked border; `table_frame.gd` adds the parchment
frame, vignette and an optional tilt-shift (`--map-tilt=0|1`, off on Low). Settlements and
fleets are painted miniatures (`minis_layer.gd`, tools/structures; exaggerated scale, tile
about 88 px x sqrt(zoom) wide, shown from zoom 0.55, ships from 0.35): base by culture and
size, harbour (port), slipway (Shipyard level), walls (palisade / stone / star fort), ships by
heading; the overlay keeps names, banners and hit areas.

**The table frame fills the screen (as built, 2026-10-27; view only).** Owner: "There is this paper texture glitch to the top left when you zoom all the way out on the overworld. It's happening on the desktop as well." `table_frame.gd` set its full-rect anchors in `_ready` with `set_anchors_preset`, which (in the tree) keeps the control's current rect: 0 x 0, offsets of minus the viewport. So from the table style's landing (2026-10-14) the frame drew nothing (no parchment surround, ink border, vignette or tilt-shift), and when the viewport grew after the screen was built (a resized window or web canvas, the UI scale applied) it drew only the growth as a rectangle at the top left, all of it outside the map, so paper. Now `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`: the frame is the viewport at every size and zoom, so the table style shows its parchment beyond the map's edge, the ink border, the vignette and the tilt-shift as designed for the first time. Probe `tests/zoom_probe.gd` (windowed: min, max and a middle zoom at the map's corner; `--grow` grows the viewport after the screen is built; fails if the visible frame is not the viewport).

**The table's sea on the real bathymetry (as built, 2026-10-22; view only).** Owner: "use the ocean and ocean floor of the relief map in the table overworld map". The table sea had five bands from the coast distance only. `water.gdshader` (`table = 1`) now also reads the same DEPTH field the relief sea uses (`dm`, metres) and colours it with a table ramp (brighter and more saturated than the relief's): sand-green under 1 m, turquoise to ~8 m, the shelf blue to ~45 m, a deep blue to 600 m, a dark navy past 2500 m. It is blended, not pasted: `table_depth` (0.75) of the depth ramp over the banded colour, plus a quarter-strength offset of the old band colour so the clean steps survive as soft shelves round every coast, and the light line on each band edge stays (a little weaker); banks (the Bahamas, Campeche) show as pale shallows, trenches go dark. Waves, ship bobbing (`SeaWaves`), the beach foam line and the sea lanes are unchanged. Low: the same colouring, still (a texture read, no animation). Frame time within noise (+1 ms of ~30 on a loaded machine).

**Beaches and cliffs on the overworld (as built, 2026-10-22; view only).** Owner: "we should have beaches shown on the overworld so we know where we can and can't land a ship to load or unload an army". `map_view.gd` samples every land polygon's outline every 4 map px once with the geometry (like the roads) and classes each sample by its land cell: a **beach** where `CFleet.land_ok`'s geometric part holds (a passable cell with open sea beside it: `CFleet.is_sea`, any sea in Rome), **cliffs** on any other coast (water no fleet sails, unclaimed land). Table: a pale sand ribbon 4 px with a soft edge and a faint foam line on the water side; cliffs a dark rock line with short hatch ticks. Relief: a thin sand band, a darker coast line. Both packs (Rome has no fleets but the rule is pack-agnostic). Offsets are rebuilt per zoom band (1.08 steps) on their own node, so panning redraws nothing. With one of our loaded fleets selected, the beaches beside the sea it reaches this turn are lit (a glowing sand-gold line, `MapOverlay.set_landing`); with an army selected that can board an adjacent fleet, its boarding beach. A tap on a lit beach is today's land-the-troops order; hints and the Sail toast say "a lit beach". Key rows Beach / Cliffs. Fleet sight `FLEET_R` is 3 (was 1; owner: "the ships need a much wider range of view").

**Roads and sea lanes on both map styles (as built, 2026-10-22; view only, data in `geo_west.gd` / `west.gd`).** Owner: "add
actual roads for any road cells that we have ... ocean trade routes on both maps". The West has 25 roads (445 road cells)
baked like Rome's. Relief: roads are the thin tan lines of before. Table: roads are dirt tracks, an ochre ribbon (2.4 px
core, a soft double edge to 4.6 px) broken by a gap round every settlement so the town models stand on it; rivers and
crossings as before. Sea lanes (every pack, both styles) are dashed pale curves between the ports, routed through open
sea by `campaign/clanes.gd` (round the islands, off the coast, never across land) and smoothed in `map_view.gd`; the table
style's dash is longer and white with a faint shadow. `SEA_LANE_EXITS` adds a lane from a port to the map edge (the Florida
channel). The rules for raiding or blockading a lane come later and read the same cells. Pathing: a march may be at most
25 % longer than the direct path unless the longer one gets there a whole turn sooner (`CGrid.find_path`, docs/CAMPAIGN.md).

**Overworld towns modelled into the landscape (as built, 2026-10-15, step 1; view only).** A town is no longer
a sprite but kit pieces placed on the real terrain.
- **Kit pieces** (`tools/structures/gen_spec.py` "pieces", `build.py` frame "auto", `pack.py`): `p_<piece>__y<k>`
  at 8 yaws (k * 45 degrees, front towards the south at k = 0; half-turn symmetric pieces 4, round ones 1, big
  landmarks 1 to 4): houses by culture and wall colour (colonial tile roof S / M, adobe flat roof, native hut /
  palapa / chief hut, Maya house and pyramid, haven shack / tent, Roman house / hovel / temple / basilica),
  chapel, church, cathedral, mansion, fort, fountain, well, walls (palisade, stone, bastion: straight 6 m, post /
  tower / bastion point, gate), quay, pier, crane, warehouse, shed, slipway, lighthouse, beached boats, trees and
  palms. Camera and light as before (52 degrees, NW, no bases, diorama finish). Atlases: big 2048 x 1024 (pieces
  at 4.2 px a metre, ships at 128) about 14.7 MB of video memory with its mask, small 2048 x 256 (pieces 1.97 px a
  metre) about 3.1 MB; Graphics Low loads the small one only.
- **Plan** (`town_plan.gd`, pure view, deterministic from the region index): `site(r)` is the static layout: the
  footprint (24 radii, cut by the coast field, steep ground and the half way line to the neighbours; the centre is
  shifted up to 8 px for the best fit), the way up the slope, the sea direction and shore points, street axis
  (along the contour on a hill, along the shore at a harbour, else seeded), 3 to 7 street polylines that follow
  the contour, house slots along the streets (growth order: nearest the plaza first) plus infill, ring slots for
  huts, the church spot (inland / uphill), the citadel on the highest ground, field and orchard sites on gentle
  ground. `plan(st, r)` is what the state shows: size by level (0.62 / 0.8 / 1.0 of the footprint), houses chosen by
  culture, the harbour only for a port and only when the shore is within reach (quays on the real shoreline, piers,
  warehouses, the lighthouse on the most seaward point, boats, the slipway and shed when the shipyard is built),
  walls walked round the footprint as a lattice path in 8 directions with towers and a gate where the main street
  leaves (the harbour side left open). One metre is 1.2 px at every zoom, so the town scales with the map and
  never outgrows its land. 49 plans cost about 350 ms once.
- **Draw** (`town_layer.gd`): a child of the screen's `world` (map transform: pan and zoom are free), one canvas
  item per town, drawn again only when its plan changes or the atlas size flips at a zoom threshold (only the
  towns on screen, 8 a frame), pieces sorted by y together with the map trees in the ring just outside the cleared
  ground. Overlay questions (label lift, banner side, fleet spot in the harbour's water, hit rectangle) come from
  `minis_layer.gd` statics fed by the plan. `minis_layer.gd` now only draws ships.
- **Ground** (`town_paint.gd`, `table_land.gdshader` uniform `towns`): the whole town ground (feathered clearing,
  packed earth, streets and plaza, ploughed fields and orchards, fallow meadow, tracks to the road lines, quays)
  and the cast shadows of every piece are painted once into a transparent SubViewport texture (2 world px a texel,
  3 on Low) when the map loads and again when a town changes; the land shader mixes it in before the hillshade, so
  it is lit like the land and has no patch edge. `footprint.gd` is gone: no redraw on zoom or pan.
  `landscape.gd` clears the forest inside each footprint and field and hands the ring trees to the town.
  2026-10-27: each town's lawn colour (from its region's `ground`) is resolved in `bake`, not in the deferred
  `_paint`: a pack switch (`CData.use_pack`) between the bake and the frame that draws it read a West region
  index (41+) out of the Rome `REGIONS` (`campaign_input_test` after `_dp_run`).
- **Landscape trees and rocks as models** (`landtrees.gd`, `landtrees.gdshader`, not Graphics Low): the map's
  tree kinds (broadleaf x3, pine x3, scrub x2, cypress, palm x2 in the tropics) and rocks (x3, crag) from the
  atlas, one MultiMesh at the old dots' positions and sizes, tinted by the palette, sorted by y; both atlas sizes
  are prepared as instance buffers at bake, a zoom threshold swaps one buffer. Their cast shadows are baked into
  the same ground texture. Low keeps the mesh dots.
- **One map look** (`map_look.gdshaderinc`, `map_look.gd`): the terrain, pieces, ships and trees include the same
  constants (north-west light, ink colour, four light bands) and share one gradient-map LUT and one tiling grain
  texture sampled in screen space; the pieces' light is snapped to the terrain's bands, saturation 1.16 after
  the LUT, the coast ink on silhouettes. Graphics Low: LUT and saturation only (no bands, no grain).
- Costs (desktop, `cbench.gd`: steady frame at zoom 1.2 and a sweep 0.6 - 2.4 - 0.6, vsync off): the map is redrawn
  on zoom only after a 35 % change or when the zoom settles (the old path redrew it on every pan or zoom frame);
  High: steady 7.8 ms (HEAD 10.1), sweep worst frame 28 ms (HEAD 54), 7 of 400 frames over 16 ms (HEAD 399, the
  rest of the sweep averages 11 ms against 35); Low: steady 8.4 ms (HEAD 8.0, +4.7 %), sweep worst 33 ms, 8 over.
  The frames still over 16 ms are the map's own few redraws. After repacking the atlas run `godot --headless
  --import`. Not yet seen on the Tab S7. Step 2: landmarks (El Morro, Cartagena's walls, Tayasal's temple), growth
  polish, ships' baked contact shadow (they keep the per-frame one).
- **Follow-up (2026-10-15, view only).** (1) A tap anywhere on a town's model (an ellipse over `Minis.model_rect`,
  `MapOverlay._town_at`, nearest centre when two overlap) is a tap on its node for every map action
  (`settlement_at`); banners and fleets still win; a fleet tapped onto a town sails to its harbour cell.
  `tests/town_tap_test.gd`. (2) Army banners at a modelled town stand on land: `_side_spot` tries the side away from
  the harbour, the other side, below, above (each nearer in steps) and takes the first whose banner corners are on land
  (`Geo.region_at`, cached per zoom); the armies' cells were on land (Syracusae's site cell is the town's), it was the
  side offset pushing banners onto the water. (3) Too much sand: `table_land.gdshader` had the coast band inverted
  (`1 - smoothstep` made all low flat land sand); now a band along the coast, warm tint of the shader and LUT eased,
  wooded ARID / DRY regions less sandy in `landscape.gd`. (4) Close towns push their centres apart (scoring term
  in `_make_site`), overlapping labels stack upwards. (5) Native kit: `longhouse`, `rack`, `stilt_house`,
  `maya_platform` pieces (gen_spec.py, atlas repacked), native villages 11 / 17 / 22 huts, council longhouse from
  level 1, drying racks, more garden fields, stilt houses on the shore; Maya temple platforms by the plaza.

- **Step 2: landmarks and visible growth (2026-10-15, view only).** Rule of cool mixed with reality: slightly exaggerated,
  instantly readable silhouettes. (1) **Landmark pieces** (gen_spec.py "landmarks and growth", diorama finish, asymmetric
  ones at 4 yaws, the rest at 1; the big atlas is now 2048 x 1152, `pack.py` rounds the height to 64): `morro` (El Morro of
  Havana, triangular on its rock with the lighthouse), `fuerza`, `san_felipe` (terraced hill fort), `morro_sj` (San Juan, tiers
  + sentry boxes), `harbour_fort` (square, four towers, sea battery: Portobelo's two forts and every West port's first fort),
  `san_marcos` (star fort in its moat), `alcazar` (Santo Domingo), `ulua` (fortress on its rock island in the roads),
  `itza_temple` (Tayasal, the tallest silhouette), `fort_charles`, `tavern`, `gallows`, `rock_fort` + `careened` (Port-de-Paix),
  `baluarte` (Campeche's walls), `twin_cathedral` (Merida), Rome: `capitol`, `byrsa`, `cothon` (circular naval harbour),
  `euryalus`, `acropolis`, `greek_temple` (Massalia; Alexandria is not a region). `town_plan.LM` maps a region key to its
  landmarks (where: harbour mouth headland / other end / highest ground / offshore rock / between plaza and sea / a row
  along the shore / by the water; least walls `wl`, least level `lv`); `_landmarks` places them before the houses (which
  keep clear: collision radii in `PD`), the lighthouse step is skipped when the Morro has one. They show whatever the owner
  (tinted to it, so a captured Spanish fort stays) and need walls >= 1 (San Marcos 2, Cartagena's long sea walls 2 with a
  baluarte every fourth piece). Cartagena's walls, Campeche's walls (bastioned with baluartes from walls 1, harbour
  open), Merida's cathedral, Santo Domingo's cathedral from level 1 and Rome's Capitol from level 1 replace the generic
  piece. (2) **Growth** (all read-only from the state, `TownPlan.facts` / `sig`; deterministic per region so a town keeps
  its layout and gains houses): level (houses 8 / 16 / 28 in towns, a second street ring `s["ring_road"]` with houses
  along it from level 1, the church / cathedral as before), **walls in the West** follow the walls history: 1 a harbour
  fort beside an open port (inland towns a palisade), 2 the fort plus a stone curtain on the landward side, 3 the full
  curtain with bastions (Rome: palisade / stone / bastions; natives get more watch posts from 2), shipyard level (1 a
  slipway + shed + crane, 2 a second slipway across the quay, 3 a second crane and a second shed), market level and town
  level (a warehouse more from market 2; moored ships in the roads: `_moored`, up to 3, drawn from the ship atlas with a soft
  shadow, none counted in the label extents), a **sack** (`regions[r].sacked`, up to 8 turns: 55 / 30 / 12 % of the houses
  burnt, smoke column, fading by age), a **siege** (`CState.siege_at`: a ring of tents, guns and flags outside the
  footprint in the besieger's colour, items may carry a faction as a 4th element). The layer's signature is
  `TownPlan.sig`; the ground and shadows repaint only when a plan changes. Gallery and strips in the session scratchpad
  `towns3/`.

- **Step 2b: ships, camps, neighbours (2026-10-15).** Fleet spot (`water`) is found by `_find_water` (open water searched
  seawards along the harbour side, disc tested against the coast field). Moored ships (`_moored`): at most 2, whole hull
  footprint wet with a margin (`_hull_wet`), searched seawards, spaced from each other and from the fleet spot, on the
  side opposite the fleet row; yaws 2 / 6 (bow-on slivers) are never used, a hull takes the nearest of the other six to
  the quay. A port with no open water has no ships. New pieces `camp_tent` (off-white canvas ridge tent, faction pennant),
  `camp_fire`, `camp_stakes`, `camp_earth` (gun mound), bigger `camp_flag`; `_siege_camp` uses 30 slots on land only,
  stakes / earthworks with guns and flags facing the walls, tent rows behind (a third row where the coast cuts the ring),
  campfires. Neighbours within 2.2 town radii shrink both footprints (down to 0.42) and the centre never drifts toward
  them. `tests/town_plan_test.gd` checks every West and Rome port.

### Fleets join by tapping (as built, 2026-10-20)

Controls (campaign map, fleets): with our fleet selected, a tap on another
fleet of ours (not the flota) is a join: within a cell it is an `fmerge`
order at once (the merged-into fleet is selected, "Joining"); farther it is
a voyage to it (`fmove` with `tgt` = that fleet, drawn with the merge
glyph) that merges on arriving and goes on from turn to turn (`join` on the
fleet, dest refreshed to the target's cell) until it merges, the target is
gone, or Cancel / the same tap again. A tap on the selected fleet closes
the panel; an enemy fleet is an attack; an army selected + our fleet is
boarding. The fleet card has a Join button for each fleet alongside. Rules
in CAMPAIGN.md "Fleets"; no `CState.VERSION` bump.

### Overworld settlement markers and banners at towns (2026-10-22)

- **Every settlement has a marker that is its tap target.** Owner: "not all of the cities have icons in the Caribbean, some
  are just floating names, which makes them really hard to click." The relief style always drew `draw_site` (a disc in
  the owner's colour, a white rim, a wall ring for walls 1-3), so the floating names were the **table style's**: from
  zoom 0.55 the town models replace the icons, and the small or sparse ones (a level 0-1 hamlet of 8-14 pieces, 45-90
  world px wide, a hut at zoom 0.6) were a name over a few huts. Now the overworld overlay draws the disc over a model
  that is `Minis.weak(zoom, r)` (under 96 px wide on screen or 20 pieces or fewer; the model's piece count is in the
  town layer's `info`) at 85 % size, and in the relief style as before at `_site_rad` (the level's radius, at least
  4.5 / 6 / 7.5 px). A settlement with a harbour (`CFleet.harbour`) carries a small anchor mark beside the disc
  (`draw_harbour_mark`). The names stay above the marker. `settlement_at` takes a tap within 22 px of the anchor (was
  16), except within 30 % of a cell's width of the centre of a ring cell (a march or a siege camp laid on a cell next
  to the town stays that cell's tap); the model's ellipse still takes taps over big models.
- **Banners at towns.** A garrison's banner (and an army standing at a model) must stay with its own town; the first
  version put Veracruz's new 2-stack far west of the town, on the besiegers of Orizaba. `map_overlay.gd`
  `_army_positions6` places in three passes with one list of taken rectangles (banners and the five tents of every
  siege camp): field armies on their cells; then the armies of each town, a stack of banners, on a 24-spot ring at the
  town's footprint (the model's built-up core, 70 % x 85 % of its rectangle; in the relief style the marker with its
  walls) plus a banner, keeping the spots wholly on land and free, scoring the one furthest from the nearest other
  town (the side away from neighbours), not on the harbour side, not inside another town's model or siege ring, not
  over a besieger's own cell, beside the town rather than above it (the relief style tries the spot under the marker
  first, as before); with none free the stack goes under the model and lower by a banner while taken; then each
  besieger's group on its cell of the ring, and when that is taken pushed along the ring and out along up to three
  more rings (a banner's height apart), the nearest free spot wholly on land (any free spot when the land has none).
  `tests/banner_test.gd` (West table, Rome relief; every settlement, a garrison of 3 and 1 / 3 / 8 besiegers, two zooms:
  no two banners overlap, the garrison touches its footprint, the besiegers keep to the rings).

### Garrisons on the town, armies stable across zoom, a quieter port mark (2026-10-23)

Phone playtest: "when an army is in a city, the marker should be on top of that actual city. Right now it is to the side
with a small indicator and it results in weird pathing back to the city and then out again"; "the armies seem to move to
different locations when zoomed out vs zoomed in"; "what are the anchor markers?" The 24-spot garrison ring of "Banners at
towns" above is gone (`_garrison_spot`, and `_model_at`, which moved a free army standing at a miniature town beside it
only while the model was drawn, i.e. with the zoom). The rule now: an army inside a settlement (`CRules.inside`) is drawn
on it, the stack's first banner centred on the marker (relief style) or the model's footprint centre (table style,
`_garrison_centre`), the others one banner height lower each (the name label stays above, not moved); a free army stands
on its own cell at every zoom, armies sharing a cell side by side as before; besiegers keep their ring cells and
`_ring_nudge` (still in screen pixels, so a nudged besieger can differ a little between zooms). The halo and the tap target
use the same positions. The planned path of an army inside a town (`_path6`) starts at the settlement's site point, so it
leads straight out of the town. The harbour mark is 75 % of its size with a disc alpha of 0.6, and the Key has a row for it
("Port: an anchor beside the town; ships dock and are built here"); the port rule is in sea.md "Port rule" (27 / 37 ports
instead of 29 / 43). `tests/banner_test.gd` still checks overlap and the besiegers' rings.

### Overworld view layers follow the pan every frame (2026-10-22)

The ships (`minis_layer.gd`) are screen-space, so unlike the armies (slid by the overlay) they are redrawn; on Quality Low the 10 Hz throttle now limits only the bobbing, and a frame where the overlay transform or zoom changed always redraws (measured max lag while panning 21.6 px before, 0 after; High was 0 already: the screen sets the view in its own `_process`, a parent of the layer, so it runs first). The town and fog layers sit in the scaled world node and the figures redraw on every transform change, so they never lagged. Probe: `tests/zoom_sweep.gd -- --lag`.

### Subtler sea lanes, explained last-seen markers (2026-10-23)

Phone playtest: the trade-route lines were too loud, and the faded markers the fog leaves for an enemy army or fleet out of sight were not understood. The sea lanes are about half as loud (relief: alpha 0.6 -> 0.32, width 1.6 -> 1.25; table style: alpha 0.62 -> 0.38, halo alpha 0.22 -> 0.10, width 1.9 -> 1.5); the raided lane (bold red) is unchanged, since it is the player's signal. The marker painting is the static `MapOverlay.draw_last_seen(ci, c, m, fleet, col, n)`, shared by the map and the Key; with the fog on in a grid campaign the Key gains two rows after the army rows ("Last seen: an enemy army that was here on that turn (out of sight now; tap it)" and "Last seen: an enemy fleet, likewise"; the Key rebuilds when the fog turns on or off). The marker's small label now reads "seen tN" and shows at every zoom (11 * max(scale, 0.8) px), and the idle campaign hint ends with "Faded markers: where an enemy was last seen." while the fog is on.

### Every land cell belongs to a region (as built, 2026-10-27; West map data)

Owner (Costa Rica screenshot): a block of land between Bluefields, Granada and Talamanca was dark and unused and the armies waded the sea to avoid it. The West map had six unclaimed blobs (852 cells, `,` in the grid, impassable) carved by the hand-written `PHANTOMS` of `geo_west.gd` (extra Voronoi sites that kept the coastal regions from reaching inland). The West `PHANTOMS` is now empty (Rome keeps its own); `MapGeo._build_cells` therefore gives every land polygon to the nearest region site and `tools/campaign_grid.gd --pack=west` prints no corridor or connectivity fix and leaves no `,` cell (0 of 852). No region was added; every settlement and port cell is unchanged. Who took each blob (cells): the Pacific side of southern Mexico and Central America, 532 cells (x 0-63, y 69-95): Tabasco 123, Orizaba 120, Tayasal 118, Comayagua 105, Granada 43, Veracruz 14, Trujillo 8, Cabo Gracias 1; the Costa Rican interior (70): Talamanca 28, Granada 22, Bluefields 20; Cumana / Calabozo (148): Cumana 140, Calabozo 8; Barquisimeto / Calabozo / Maracaibo / Mompox (73): Mompox 29, Barquisimeto 27, Maracaibo 15, Calabozo 2; Cartagena / Darien / Mompox (24): Mompox 20, Cartagena 4; the Orizaba / Tampico edge (5): Orizaba 5. Roads: the 25 traced roads are unchanged (445 road cells, all on land before and after); the Bluefields - Talamanca land route had no road, so a "Costa Rica trail" was added (`ROADS`: Bluefields south along the Bluefields / Talamanca ridge foot to Talamanca, 22 road cells; 467 road cells on 26 roads). `CGrid.WATER_STEP` is now 20, the ridge cost (was 10, the flat cost): an amphibious army takes coastal water only where no land path of lower cost exists (`campaign_rules.md`, amphibious armies). Rome has no wet cells and no phantoms touched: its grid, campaign_sim hashes and pins are unchanged; the West pins moved (STATUS, `tools/balance/pins.json`).

### The chart sea, zoomed-out detail, hint plate (as built, 2026-10-27; view only)

Owner: "Rome the edges of the overworld fade out to a drawn map style which I like. Right now it feels like the overworld is floating over an ocean texture when you zoom out." Nothing in `sim/` or `campaign/` changes.

- **The deep sea fades into the chart** (`water.gdshader`, Terrain view, table and relief, both packs; the political view sets `chart = 0`). Blend `cf = max(smoothstep(400, 560, d), zone) * mix(0.5, 1.0, smoothstep(80, 400, depth_m))` (depth only delays the fade, to half strength in the shallows: far shallow banks go half way to the chart and keep a pale turquoise shoal tint; and the Terrain view's sea is 20 % less saturated before the blend) where `d` is the distance to the nearest land in map px (about 1.1 km a px) and the depth gate delays the fade in the shallows (under about 80 m): the shallows, the turquoise bands, the surf and the shelf keep their colour wherever they are. The baked COAST field stops at about 72 px, so `map_view.gd _chart_tex()` builds a coarse distance field once per pack (the coast field on cells of at most 8 map px, 6.7 on West and 7.5 on Rome; a true Euclidean distance, Felzenszwalb's two-pass transform, then two 7-cell box blurs, about a Gaussian of 2.8 cells, sampled with linear filtering; L8, px / 3, up to 765 px; outside the baked window = far; about 250 ms West and 90 ms Rome in a debug build, once). The sea colour goes to `chart_paper` (0.80, 0.76, 0.60; the frame's paper averages 0.84, 0.76, 0.58, so a touch cooler and darker; a shade darker still with depth) at 94 % of `cf`; across the band the blue first loses saturation (half of it at the far end) and lightens to the chart tone, so an island carries a soft pale coastal wash, not a halo, and on High engraved wave hatching is mixed in at up to 62 % of `chart_ink` (0.28, 0.38, 0.44): rows 7 map px apart of short tapered lens strokes (hashed per cell, about 60 % of cells, a slight sine wander), two octave layers cross-faded by `fract(log2(map px per screen px * 1.3))` so rows stay 9 screen px or more apart and nothing pops while zooming; stroke half width `max(0.6 px, 4 % of the row gap)` on screen. Static (no animation). Low (`hi = 0`): the tone only. The shelf-break line fades out in chart water. Rome's enclosed Mediterranean stays mostly blue (nothing is 220 px from a coast); the Atlantic strip, the Libyan sea corner and the far corners of the West map become chart. **Pushed out and rounded (2026-10-27, owner: "creeping into the usable map", "rather star-like")**: the land-distance rule now starts at 400 map px and completes at 560 (a box-blur bug had inflated the first numbers: measured, the SE Caribbean basin is about 260 px from land, the Gulf's centre about 320, the open Atlantic 570 and more), so by itself it charts only the far Atlantic. The field is a true Euclidean distance (circular contours, no chamfer star). On top, a hand-authored chart zone per pack (`CHART` in `geo_west.gd` / `geo_rome.gd`, like PHANTOMS: polygons in [lon, lat] of open ocean, 120 to 150 px off every coast): `_chart_zone_tex()` rasterises them on 24 px cells and stores the signed distance to the nearest edge (inside positive, +-150 px, L8, two EDTs and two small box blurs), and `zone = smoothstep(-75, 75, d)` is max-ed into `cf` in water and fog alike (a soft 150 px edge band). West: the Gulf's centre, the Atlantic north and east of the Bahamas and the Antilles, the Pacific off Mexico and Central America; nothing in the Caribbean. Rome: only the Bay of Biscay corner and a small patch off Morocco (the Atlantic strip and the Libyan sea are too narrow to keep 150 px of blue off every coast), so the Mediterranean stays blue and Rome shows hardly any chart. Open: a baked asset for the field (the build is about 250 ms West, 90 ms Rome in a debug build). The sea lanes and the flota route draw over it unchanged. The fog of war (`fog_layer.gd` + `fog_layer.gdshader`, which reads the water's `chart_d` and depth textures and the same `cf` rule) is 0.6 x as strong over chart sea, full over land and the shelf, so unseen far sea is a dimmer parchment, not dark grey (the look shots are `--nofog`; `look2_west_table_min_fog.png` is with fog).
- **Zoomed-out level of detail** (`MapView.far_lod`, `LOD_ZOOM` 0.55 = `Minis.SITE_MIN_ZOOM`, hysteresis 4 %: far below 0.528, near again from 0.572; `update_lod` is called every frame from the screen's `_tick` and redraws the map and the coast node only when it flips). Far: ordinary settlements are dots at half the marker radius (no walls ring, no harbour mark; capitals and key cities keep their marker, star and name; other names are hidden; a modelled town still shows its mini between 0.528 and 0.572), the owner washes are 1.6 x their alpha capped at 0.5 (terrain 0.30 -> 0.48, table 0.15 -> 0.24), the sea lanes' width 0.7 x (dash lengths unchanged); the flota route, the Key page and the hint text unchanged.
- **The hint's plate**: a translucent dark rounded `Panel` (0.04, 0.05, 0.07 at 58 %) behind the hint label, sized to the wrapped text (`_fit_hint_plate`, refit when the text or width changes). **The vignette** of `table_frame.gdshader` is a third lighter (0.27 -> 0.18).
- Probe: `tests/zoom_probe.gd` gains a middle-zoom shot on the Gulf coast (West: Veracruz, Rome: Massalia) and `--nofog`; `tests/look_bench.gd` times steady frames at 1.2, 0.6 and the minimum zoom.

### The visual pass (plan, 2026-10-27; agreed with the owner)

The owner, on the visual review of 2026-10-27: "I like all of your suggestions
for visual improvements. Lets do that next." The overworld's identity is the
painted-miniature towns, the inked coasts over the relief, and the chart sea on
the parchment table; everything below is brought to that standard. View only,
no sim or campaign change, no hash moves; each part its own build and commit.

1. **Lines as ink.** Province borders are drawn as curves: each shared edge
   between two regions (junction to junction) is smoothed once (Chaikin, two
   rounds, the same polyline for both neighbours so they agree), and a border
   vertex within 12 map px of a river snaps to the river. Roads are Catmull-Rom
   curves through their traced cell centres with a hand-drawn waver (a small
   deterministic offset per vertex, seeded by the road index), drawn as a dark
   edge with a lighter centre in the table's brown. The map's geometry (the
   grid, the cells) is untouched: smoothing is a drawing step over
   `MapGeo` cells and `road_line` in `map_view.gd`.
2. **Markers in the chart's language.** Armies: a standard (a pole with a
   swallow-tailed pennant in the faction colour carrying the crest) with the
   strength on a small roundel at its foot; fleets: a sail glyph with the
   same roundel. Towns below the minis' zoom: ink symbols by level (a dot, a
   small circle, a circle with a tick, a ring with battlements, a star for
   capitals) instead of the grey discs; the last-seen (faded) markers keep
   their meaning. Sea lanes: faint rhumb lines (thin, long dashes, 0.35
   alpha); the flota route keeps its red dashes. Legibility first: the
   strength number and the crest stay readable at phone size.
3. **Woods as patches.** The map's tree sprites cluster into patches by the
   region's forest share, each patch with a soft drawn edge (a darker green
   scalloped outline under it) and fewer single trees in the open; the same
   density as today over a region, so the forest reads as a wood, not as
   confetti.
4. **HUD chrome in the table's language.** The campaign and battle panels,
   bars and plate buttons keep their dark fills and contrast (phones over a
   busy map) and gain an inked double rule with small corner marks, the top
   bars a dark wood band with a thin brass rule; the same theme kit for both
   screens (`ui_kit.gd` / the theme): one pass through the kit, not per
   screen.
5. **The battlefield ground.** `game/terrain_layer.gd` + `terrain.gdshader`:
   painterly variation of the base ground (two octaves of grass and earth
   patches tinted from the palette, a soft brushed grain), the woods' canopy
   drawn as clumped crowns with a drop shadow and a darker scalloped edge
   rather than a uniform carpet, field and track edges softened; the diorama
   and painterly looks both get it (their grading applies after). Soldiers,
   houses and the kit pieces are unchanged.

Each part is measured for cost on the desktop benchmarks (`tests/look_bench.gd`
for the overworld; the battle's `--bench` run for the ground) and ships with
before / after screenshots for the owner's eye.

### Markers in the chart's language (as built, 2026-10-27)

Part 2 of the visual pass, view only (`map_overlay.gd`, a few lines in `map_view.gd`).

- **Army standards.** `draw_banner` (same signature, same returned hit rect, so taps and the map key do not
  move) draws a thin pole with a gold finial, a swallow-tailed pennant in the faction colour (27 x 16 px, about
  1.6 times the old emblem flag's area) carrying the crest at 13 px (was 15 px above the shield's edge, now
  inside the pennant), and the strength on a parchment roundel with an ink rim (radius 9, 14 px ink figures
  instead of 15 px white outlined ones; wider counts shrink to fit) at the pole's foot. The size floor is
  `max(m, 0.8)` so the standard stays as readable at the phone's zoom as the shield was; the strength bar
  stays under it. A player's army has a white rim on the pennant and roundel, the AI's is ink only. The
  selected army (`glow > 0`, passed by `_army_marker` and the map key) lifts 3 px and gets a gold rim; the
  pulsing halo is now a gold disc behind it instead of the old rectangle. Because the lift needs a redraw,
  `campaign_screen.gd` redraws the armies part when the selected army changes (one condition added).
- **Fleets** (without a painted ship): a triangular sail in the faction colour (and a lighter jib) on a dark
  hull with the same roundel for the ship count; with a painted ship the roundel replaces the black count plate.
- **Last-seen markers** are unchanged (faded shield / hull, dashed edge, "seen tN").
- **Towns far away** (`far_lod` where the minis do not draw): `draw_far_site`, an ink symbol over a tiny parchment
  disc with the owner's colour as a thin ring (grey when unowned): level 0 a small circle, 1 a circle with a
  tick, 2 a ring with six battlement notches, a capital a star (a key city the white star as before), a port a
  small ink anchor. There is no hamlet level in the data, so the plan's dot is not used. Names stay for
  capitals and key cities. Walls are not drawn when far (the dots had none).
- **Sea lanes** in the table style's Terrain view are rhumb lines (`MapView.rhumb_on()`): 1 px, dashes 16 / 9,
  alpha 0.35, no shadow; the Political view and the relief style keep their old look; the lanes at war cut
  their dashes the same way (`MapView.lane_dash` / `lane_gap`); raided lanes and the flota route are unchanged.
### Lines as ink and woods as patches (as built, 2026-10-27)

Parts 1 and 3 of the visual pass, view only (no sim, campaign or map data change, no hash moves).

- **Borders as ink** (`map_geo.gd smooth_cell(r)`, cached per pack in `_smooth`, built for all regions on first use). Each region piece's ring is cut into runs by what lies across each segment (a probe 0.6 px outside its midpoint: `region_at`, another region = a shared edge, the sea = coast). A shared edge is made once per pair of regions (the second neighbour finds the first's run by its end points, 2 px tolerance, and reuses it reversed), so both draw the identical curve. Steps: a run within 12 px of a river is cut into 10 px pieces and its inner vertices within 12 px of the river move onto it (the snap); otherwise, since a Voronoi bisector is ruler-straight and Chaikin leaves a straight line straight, the run is cut into 24 px pieces and each inner vertex moved sideways by up to 4 px (hash of the two region indices and the vertex index; a decision beyond the plan, without it nothing visibly changes); then two Chaikin rounds, ends fixed. Coast runs are the real coastline, untouched. `_draw_edges` (owner band, table border, independent dashes, blocked and target outlines), the selection outline and `cell_meshes` (the owner washes and pulse tints, so they meet the ink; a ring that does not triangulate falls back to the plain one) use the smoothed pieces; `region_at`, the anchors and the grid tool keep the plain cells.
- **Roads as ink** (`MapView.road_curve`): the traced cell centres (the same diagonal-corner skipping) with a waver of up to 2 map px per inner vertex (hash of road and vertex index, no RNG; ends fixed), a Catmull-Rom curve 4 samples a span (`Geo.catmull`). The town paint's track bake and the cuts at the towns read the same lines. Table style: a dark brown edge line (core width + 1.6, 62 %) and a lighter centre (core - 0.5, the track brown lightened 0.38, 90 %); the soft ochre ribbon is gone. Relief: the curve with a dark edge (ROAD_W + 1.5) under the brown. Bridges and fords unchanged.
- **Woods as patches** (`landscape.gd _patchify`): the plain scatter gives each region its count N (the `base` trees, positions unchanged). The same loop also makes a candidate pool 2.5 x as big (extra trees hash with `q + 4099`; pool trees never enter a town's ring list). Per region: 10 % of the base trees stay where they are (singles); one patch centre per about 22 trees (1 to 24, picked from candidates in hash order at least 34 px apart, each with a reach of 12 to 28 px); the other N - singles trees are the candidates with the highest `exp(-(d/reach)^2)` of their nearest centre plus 0.25 noise, so the count per region is the same and the trees gather round the centres. Under each kept patch tree one soft disc of darker green (0.07, 0.20, 0.06 at 14 %, radius 8 + tree radius, a wobbly broadleaf ring, one per 8 px cell so they do not stack to black) goes into the glyph mesh below the specks, so the wood has a scalloped shadowed edge (also in the table style, whose tree models draw above the mesh). `LOW_TREE_ZOOM` and Quality Low unchanged; `tree_count` unchanged.
- **Cost** (`tests/look_bench.gd`, steady frame mean, ms, base 4bf0a05 / after; the desktop's frames are 38 ms west, 19 ms Rome, noise about 0.5 ms): west table 1.2: 38.4, 38.0 / 39.5, 39.3 (+0.7 to +1.1); 0.6: 36.2 / 37.5; 0.226: 31.5 / 32.6. Rome table 1.2: 18.6 / 19.7 to 19.8 (+1.1); 0.6: 18.8 / 20.9; 0.379: 17.8 / 19.5. The border curves are the cost (about 1.2 ms with 14 px steps, about 0.7 with 24); the roads and the discs measured nothing. Bake: the pool adds a third of a second to a glyph bake at most (not measured separately).
- **Open**: the border waver and the soft discs are by eye, not tuned on the phone; `zoom_probe.gd` gained `--at=REGION_KEY` for the middle shot.

### Overworld frame time (as built, 2026-10-27)

View only (nothing under `sim/` or `campaign/` changed, no hash moves). The owner: "The web build is starting to lag a
bit even on my desktop."

- **Profile, not guess** (`tests/look_prof.gd`, new: the look_bench campaign at zooms 1.2, 0.6 and the minimum, each
  layer hidden in turn, 120 steady frames each; a layer's cost is the median frame with everything minus the median
  frame without it; also the draw calls per frame). West, table style, 2000 x 923, this desktop (RTX 3070, GL
  Compatibility), ms (draw calls the layer removes, read at 0.6; noise about +-1 ms):

  | layer | before 1.2 | 0.6 | 0.226 | after 1.2 | 0.6 | 0.226 |
  |---|---|---|---|---|---|---|
  | whole frame (median) | 27.2 | 27.9 | 25.1 | 6.1 | 6.1 | 4.7 |
  | territory edges (owner bands, borders, independent dashes) | 6.5 | 7.2 (460) | 6.5 | 0 | 0 (1) | 0 |
  | coast node (coastline, roads, rivers, crossings, sea lanes) | 8.0 | 8.5 (889) | 7.0 | 0 | 0 (34) | 0 |
  | beaches and cliffs | 6.1 | 8.1 (2757) | 5.2 | 0 | 0 (1) | 0 |
  | overlay (sites, fleets, armies, paths) | 2.6 | 6.1 (1180) | 4.5 | 2.9 | 3.5 (1180) | 3.3 |
  | ... of it settlements and names / fleets / armies | | | | 0.8 / 1.1 / 0.4 | 1.7 / 1.3 / 1.1 | 0.1 / 0.4 / 0 |
  | water shader, table frame shader, land / relief, map's own drawing, trees, towns, minis, fog, UI | each within noise (under 1 ms) | | | the same | | |
  | the sea, land and frame shaders alone (everything else hidden) | 1.4 | 1.7 | 0.6 | 1.4 | 1.6 | 0.6 |
  | draw calls a frame | 5444 | 5693 | 5676 | 1374 | 1624 | 1609 |

  The frame was the CPU recording draw calls, not the GPU: in GL Compatibility every antialiased `draw_polyline` is
  three polygon commands (the middle strip and two feather strips), each its own draw call, and every antialiased
  `draw_multiline` segment nine primitives recorded one by one each frame. The edges, the coast and the beaches were
  about 4300 of the 5700 draw calls; the shaders (the sea, the frame's screen-texture read, the land) cost little on
  this GPU, so they were left alone. The beach node's 2757 calls came from four polylines per beach run (289 runs).
- **The change: ink meshes** (`game/campaign/ink_lines.gd`, `ink_lines.gdshader`). A batch records polylines and
  multiline segments in drawing order and makes ONE triangle-strip mesh whose vertices are only codes (side, cap,
  segment corner; the polyline's id); the vertex shader rebuilds, per vertex, exactly the geometry Godot's
  `canvas_item_add_polyline` / `canvas_item_add_line` make for `antialiased = true` (renderer_canvas_cull.cpp 4.7: the
  compensated width, the bisector clamped to 3, the 1.25 px feathers, the caps and the end corner's swapped
  diagonal; a line's quad and eight feather quads) from the points (a float texture, read with `texelFetch`) and the
  width scale `lw` (a uniform). Colours are a parameter texture (an owner change recolours without a rebuild).
  Templates are cached per polyline length, so a batch is built with native array calls per polyline, not per
  point. A zoom sets a uniform; the mesh is rebuilt only when what it shows changes. Anything else drawn on the
  node passes through the shader unchanged. Used by:
  `_draw_edges` (`_edges_ink`: per region the owner band or the independent dashes, then every border; rebuilt when
  a region turns seen / independent / owned or the style changes; the target and blocked outlines stay ordinary
  draws after it), `_draw_coast_body` (coastline, tracks or roads, rivers: per pack and style), `_draw_beach_node`
  (`_beach_ink`: the runs moved along their normals by the band's scale as the shader's offset scale `ls`, so one
  mesh serves every zoom band; the cliff ticks' stride is per band, a mesh per stride, at most a handful), and the
  sea lanes (`_draw_lanes_ink` on a new child `_lane_node` of the coast node, drawn right after it: rebuilt when the
  dash cut changes, as the dashes were).
- **Devices without vertex texture reads** (Chrome on the Tab S7's Adreno 650 draws nothing from them, see
  `soldier_layer.gd`): `InkLines.probe` draws one line by the shader into a 16 px SubViewport once when the map opens
  and reads it back (console `INK_PROBE drawn=N state=S`); a device the battle's soldier probe already sent to the CPU
  path (`[video] soldiers = cpu`) and headless runs skip it. Until it passes, and where it fails, each batch replays
  its recorded calls as the `draw_polyline` / `draw_multiline` they stand for: the old picture at the old cost.
  `--ink=0|1` (web `?ink=0|1`) forces either.
- **Measured** (`tests/look_bench.gd`, steady frame mean, ms, two rounds each; base de2f911):

  | | West table 1.2 | 0.6 | 0.226 | Rome relief 1.2 | 0.6 | 0.379 | Rome table 1.2 | 0.6 | 0.379 | West relief 1.2 | 0.6 | 0.226 |
  |---|---|---|---|---|---|---|---|---|---|---|---|---|
  | base | 30.6, 29.7 | 29.6, 29.4 | 29.2, 28.8 | 10.5, 9.6 | 9.7, 8.9 | 9.0, 8.7 | 16.6, 17.0 | 18.4, 17.2 | 16.9, 17.1 | 22.7, 22.9 | 19.7, 19.8 | 17.8, 17.9 |
  | edges, coast, beaches as ink | 13.4, 14.0 | 13.9, 13.7 | 12.4, 12.5 | 6.3, 6.2 | 5.7, 5.6 | 5.3, 5.2 | | | | | | |
  | + the sea lanes as ink | 7.9, 7.1 | 8.0, 8.2 | 6.1, 6.9 | | | | | | | | | |
  | final (with the probe) | 7.0, 7.2 | 7.5, 7.8 | 6.2, 6.4 | 4.4, 4.4 | 4.3, 4.5 | 4.1, 4.4 | 4.4, 4.8 | 5.6, 5.5 | 5.0, 5.2 | 7.5, 8.0 | 6.7, 7.3 | 6.9, 6.6 |
  | `--ink=0` (the replay) | 29.0 | 29.3 | 27.5 | | | | | | | | | |

  `tests/zoom_sweep.gd` West table (2000 x 923): pan 20.1 -> 4.3 ms median (worst frame 54 -> 6 at 1.2), wheel zoom
  24.0 -> 5.0 (worst 62 -> 20), pinch 24.0 -> 6.7 (worst 58 -> 15), frames over 16 ms in the steady and pan phases
  60 / 90 -> 0 or 1. Another agent's battle benches ran on the machine during some runs.
- **Same picture**: `tests/zoom_probe.gd --nofog` shots (min, max, the corner at 0.6, Veracruz / Massalia at 1.0;
  `--fixed-fps 60` so the waves match) of base and after, all four pack / style pairs in the Terrain and Political
  views and the West table with fog: pixels differing by more than 2 of 255 in any channel 0 to 0.0008 % (at most
  14 px of 1.85 M, single anti-aliasing pixels); the `--ink=0` replay 0 px. A web export in headless Chromium
  (SwiftShader WebGL2, `?campaign=rome`) logs `INK_PROBE drawn=160 state=1` and matches `?ink=0` but for the waves.
- **Left**: the overlay is now most of the frame (about 3 ms: the settlements and names, the fleets, redrawn 14 times
  a second for the bobbing ships, and the armies, about 1200 draw calls of circles, AA arcs and text); the ink meshes
  carry about twice the old triangles (degenerate joins, lines as 4 triangles a quad), about 1.2 M a frame on the
  West, so on a weak GPU a level of detail (Douglas-Peucker per zoom band) may pay; the Tab S7 keeps the old cost
  (the replay); the table frame's full-screen screen-texture read and the water / fog shaders measured within noise
  here and were not changed; not yet seen on a phone.

### Overworld overlay cost (as built, 2026-10-29)

View only (nothing under `sim/` or `campaign/`, no hash moves). After the ink meshes the overlay was about half of
the West table's frame: about 1000 to 1200 draw calls of circles, antialiased arcs, polygons and text, its fleets part
redrawn 14 times a second and the miniatures' ships every frame (High), for the bobbing.

- **Profile** (`tests/look_prof.gd --parts`: the look_bench campaign, West, table style, 2000 x 923, this desktop;
  each part's cost is the median frame with everything minus the median frame without it, its draw calls in
  brackets; ms; noise about +-0.1 after, +-0.3 before; base f63c064):

  | part | before 1.2 | 0.6 | 0.226 | after 1.2 | 0.6 | 0.226 |
  |---|---|---|---|---|---|---|
  | whole frame (median ms, draw calls) | 7.21 (1912) | 6.67 (1624) | 4.98 (1609) | 2.61 (991) | 1.64 (462) | 1.59 (445) |
  | ... its GPU time | 4.88 | 4.17 | 3.80 | 1.43 | 0.85 | 0.79 |
  | the overlay | 3.74 (939) | 4.04 (1180) | 3.53 (1196) | 0.04 (25) | 0.11 (29) | 0.10 (32) |
  | ... settlement markers, far-town symbols, key-city stars | 1.02 (372) | 1.64 (613) | 1.15 (553) | 0.03 (2) | 0.05 (5) | 0.10 (4) |
  | ... names | 0.22 (98) | 0.24 (98) | 0.11 (10) | under 0.1 (5) | 0.05 (9) | under 0.1 (4) |
  | ... army standards and roundels | 0.88 (415) | 0.95 (415) | 0.85 (415) | 0.07 (9) | 0.05 (11) | 0.12 (14) |
  | ... fleet markers | 0.19 (53) | 0.08 (53) | 0.45 (217) | 0 (4) | 0.05 (6) | 0.04 (1) |
  | ... lanes at war and raided, blockades, wrecks, storms, the flota's course | 1.15 (2) | 1.08 (2) | 1.20 (2) | 0.08 (6) | 0 (7) | 0.07 (0) |
  | ... planned paths, last-seen markers (none at turn 1), fog | within noise | | | within noise | | |
  | the ships' wakes (`minis_layer.gd`) | 0.16 (8) | 0.12 (12) | 0 (0) | 0 (1) | 0.02 (3) | 0.08 (0) |
  | an army selected (frame with minus without) | +1.71 (+329) | +1.37 (+284) | +1.56 (+284) | +1.26 (+236) | +1.15 (+187) | +0.86 (+193) |
  | ... the overlay with the army selected | 4.31 (1102) | 4.41 (1278) | 4.24 (1294) | 0.36 (95) | 0.31 (30) | 0.16 (39) |
  | ... the map's reach, pulse and selected-region nodes | 1.00 (79) | 0.50 (14) | 0.51 (14) | 0.81 (79) | 0.70 (14) | 0.42 (15) |
  | ... the UI (the side panel) | 2.34 (846) | 0.41 (263) | 0.68 (263) | 1.70 (846) | 0.66 (263) | 0.51 (264) |

  At 1.2 (the first zoom of the run) about 530 of the frame's draw calls are a start-of-campaign UI panel, before
  and after. As in the frame-time pass the frame was the CPU recording draw calls: every circle and polygon is its own
  draw call in GL Compatibility and an antialiased arc or polyline three; the lanes at war cost no draw calls but
  about 1 ms of antialiased line primitives recorded one by one each frame.
- **The batch** (`game/campaign/ov_batch.gd`, new; the gain: the overlay 3.5 to 4.0 ms -> about 0.1, 940 to 1200
  draw calls -> 25 to 35). Each overlay part is recorded into an OvBatch instead of its canvas item: the same calls by
  the same names (`draw_circle`, `draw_arc`, `draw_polyline`, `draw_line`, `draw_multiline`, `draw_dashed_line`,
  `draw_rect`, `draw_colored_polygon`, `draw_string(_outline)`; the overlay's painters and `FactionEmblem.draw` take
  either a CanvasItem, as the map key passes, or a batch), tessellated on the CPU exactly as Godot 4.7 does
  (`renderer_canvas_cull.cpp` / `canvas_item.cpp`: a circle a 64-triangle fan, an antialiased polyline its middle
  strip and two feather strips with the compensated width and the bisector clamped to 3, a line its quad and eight
  feather quads, a rect its quad and feathers, a polygon by `Geometry2D.triangulate_polygon`), the same colours, in
  drawing order. `flush` emits ONE `canvas_item_add_triangle_array` per run of shapes and the text of a run together
  (TextLine glyph rects, which the renderer batches by glyph texture). An op is moved into an earlier run only when
  nothing drawn in between overlaps it (a grid of 48 px cells keeping the last run drawn over each cell; an op over
  more than 40 cells is checked by its rectangle and placed after everything), so a name still covers the marker under
  it and a later marker still covers an earlier name. No vertex texture reads: it draws on every device, the Tab S7
  included. The overlay's tap areas are computed as before (`army_positions`, `settlement_at`, `fleet_at`, ...).
- **Glyphs** (the gain: the redraw of the armies part 4.4 -> 1.5 ms, the settlements 4.0 -> 2.8, same session).
  The tessellation is on the CPU, so a redraw cost more than the calls it replaces until repeated shapes were kept:
  `OvBatch.glyph(key, at, f)` draws f once round (0, 0) and stamps it (its triangles moved by a native
  `Transform2D * PackedVector2Array`, its text placed); arcs are kept by radius, angles, points, colour and width. Kept:
  the standard's pole and pennant with the crest, the strength roundel, a settlement marker (disc, rim, walls, harbour
  mark), the far-town symbol, the key-city star, the battle mark, the fleet roundel, the last-seen marker (keys: what
  each depends on but its place). The caches empty past 400 000 vertices; their keys hold the marker scale, so between
  zoom 0.35 and 0.7 (where it follows the zoom) a pinch draws them anew: a part redrawn while zooming there costs
  about 1.5 times the old redraw (settlements 4.0 -> 6.3 ms, armies 2.5 -> 3.4, one part a frame), and the frame is
  still faster (below).
- **Static and moving parts apart** (eight nodes, was six; the drawing order is the old one): the fleets part was the
  selected fleet's reach, the landing beaches and boarding cells, the blockades, the lanes at war and raided, wrecks,
  storms, the flota's course, the voyages and the ships, all redrawn 14 times a second for the bobbing. Now `P_REACH`
  (the selection's: a fleet tap redraws it), `P_SEA` (blockades, the raidable lanes, the lanes at war and raided,
  wrecks: redrawn only with the state, the zoom, or when the raidable lanes change) and `P_FLEETS` (storms, the flota's
  course, voyages, ships). The settlements and the sea stay as drawn when a selection changes; the armies, paths, reach
  and fleets are redrawn as before (`redraw_parts`). The fleet positions and the raider tags are kept per state redraw
  and view.
- **The bobbing at 10 Hz** (the gain: the fleets part's redraw 14 x 1.9 ms -> 10 x 1.5 ms a second; the ships every
  frame, 0.65 to 0.86 ms, -> 10 a second: about 0.7 ms a frame of script time on High). `MapOverlay` steps a 0.1 s
  clock by the frames' time (`BOB_DT`, the throttle Quality Low's ships had) and redraws the fleets on a step when the
  screen asked (`redraw_fleets`); it emits `ships_redraw` then, and on a state redraw and a fleet selection or
  voyage change, and `minis_layer.gd` redraws the ships on it, so the roundels and the ships move in the same frames. A
  pan or zoom still redraws the ships in that frame (no lag under the finger). Quality Low: as before (no bobbing,
  redrawn at the steps).
- **The lanes' dashes on the ink shader** (the gain: the sea part's redraw about 11 ms with the dashes tessellated in
  script -> 2.2 ms, the old fleets part with the lanes 3.3). `InkLines.multiline_tris` (ink_lines.gd) records a
  multiline and returns its codes as a triangle list; with `ink` set (the sea part, when `InkLines.state` is 1) the batch
  puts them into its triangle array beside its own shapes and `flush` sets the node's material to the ink batch's
  (the shapes pass through the shader unchanged). Where the ink probe failed (the Tab S7) the dashes are tessellated
  on the CPU: the same picture.
- **The ships' wakes** (`minis_layer.gd _draw_under`: the shadow ellipses, foam lines and rings) are one OvBatch too
  (8 to 12 draw calls -> 1).
- **Not done**: a level of detail for the ink meshes at the minimum zoom: the edges, coast and beach meshes (about
  1.2 M triangles) measured within noise on this desktop's CPU and GPU (+-0.05 ms GPU each), so nothing to gain here;
  names through a Label or a text atlas: the batch already draws them in one or two runs of glyph rects.
- **Measured** (`tests/look_bench.gd`, steady frame mean, ms, two rounds each, base and after run in turn):

  | | West table 1.2 | 0.6 | 0.226 | West relief 1.2 | 0.6 | 0.226 | Rome table 1.2 | 0.6 | 0.379 | Rome relief 1.2 | 0.6 | 0.379 |
  |---|---|---|---|---|---|---|---|---|---|---|---|---|
  | base | 6.81, 7.17 | 7.69, 7.90 | 6.26, 6.47 | 8.04, 8.02 | 7.50, 7.61 | 6.83, 6.42 | 4.45, 4.24 | 5.65, 5.44 | 5.18, 4.94 | 4.45, 4.33 | 4.55, 4.33 | 4.29, 4.14 |
  | after | 2.76, 2.90 | 2.76, 2.87 | 2.66, 2.73 | 3.18, 3.13 | 3.23, 3.18 | 3.21, 3.13 | 2.63, 2.53 | 2.82, 2.63 | 2.63, 2.61 | 2.82, 2.85 | 2.84, 2.76 | 2.89, 2.77 |

  `tests/zoom_sweep.gd` West table (2000 x 923), median ms (frames over 16 ms): steady at 1.2 4.8 -> 2.4, wheel zoom in
  6.3 -> 3.3 (3 -> 1), pinch in 7.7 -> 4.3, pinch out 7.7 -> 4.1, pan 5.3 -> 2.7, the x1.25 stress 13.7 -> 8.7 (11 ->
  0). Other agents' tests ran on the machine meanwhile.
- **Same picture**: `tests/zoom_probe.gd --nofog --fixed-fps 60` (min, max, the corner at 0.6, Veracruz / Massalia at
  1.0), both packs, table and relief, Terrain and Political views, before and after: pixels differing by more than 2
  of 255 in any channel 0 to 0.027 % (at most 490 px of 1.85 M), all of them on the bobbing ships and their roundels,
  drawn at another instant of the bob (10 Hz steps); with the waves held still (the same probe with `SeaWaves.t` fixed)
  0 to 1 px in all 32 shots, and 0 px with the fog on (West table); an army selected (zones, boarding cells, halo)
  0 px, a fleet selected 30 px (its pulsing halo's phase). `tests/campaign_input_test.gd` (taps on markers by
  position) passes.
- **Profiling**: `tests/look_prof.gd --parts` (the parts above; `MapOverlay.prof_off` leaves a part out), `--fog`, a
  warm-up per zoom, the GPU time and the selection rows (`sel`, `sel+X`).
- **Left**: an army selected costs about 1 ms, most of it the side panel's UI (about 260 draw calls; at 1.2 the
  846 include the start panel) and the map's reach node, outside the overlay; the overlay's settlements part still costs 2.8 to 3.5 ms to redraw (names, label
  placement, fog lookups), on a state change or zoom step only; not yet measured on a phone or the web build.
