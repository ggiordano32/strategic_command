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

### Overworld view layers follow the pan every frame (2026-10-22)

The ships (`minis_layer.gd`) are screen-space, so unlike the armies (slid by the overlay) they are redrawn; on Quality Low the 10 Hz throttle now limits only the bobbing, and a frame where the overlay transform or zoom changed always redraws (measured max lag while panning 21.6 px before, 0 after; High was 0 already: the screen sets the view in its own `_process`, a parent of the layer, so it runs first). The town and fog layers sit in the scaled world node and the figures redraw on every transform change, so they never lagged. Probe: `tests/zoom_sweep.gd -- --lag`.

### Subtler sea lanes, explained last-seen markers (2026-10-23)

Phone playtest: the trade-route lines were too loud, and the faded markers the fog leaves for an enemy army or fleet out of sight were not understood. The sea lanes are about half as loud (relief: alpha 0.6 -> 0.32, width 1.6 -> 1.25; table style: alpha 0.62 -> 0.38, halo alpha 0.22 -> 0.10, width 1.9 -> 1.5); the raided lane (bold red) is unchanged, since it is the player's signal. The marker painting is the static `MapOverlay.draw_last_seen(ci, c, m, fleet, col, n)`, shared by the map and the Key; with the fog on in a grid campaign the Key gains two rows after the army rows ("Last seen: an enemy army that was here on that turn (out of sight now; tap it)" and "Last seen: an enemy fleet, likewise"; the Key rebuilds when the fog turns on or off). The marker's small label now reads "seen tN" and shows at every zoom (11 * max(scale, 0.8) px), and the idle campaign hint ends with "Faded markers: where an enemy was last seen." while the fog is on.
