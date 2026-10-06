# Strategic Command — Status and Handover

Last updated: 2026-10-05 (battle maps with character built: woods, settlement maps, ground palettes). Read this first, then `docs/DESIGN.md` for the full
design and `CLAUDE.md` for working rules. Update this file whenever a
milestone lands or the plan changes.

## What this is

A 2D, top-down, co-op grand strategy game inspired by Rome 2: Total War, in
Godot 4 (GDScript), played in a browser on phones and desktops. Two friends
play an asynchronous turn-based campaign against AI factions and fight
real-time battles solo or together. Built for two players first; accounts,
anti-cheat and original art only if it proves fun.

## Where we are

| Milestone | State |
|---|---|
| 1. Battle sandbox | Done, committed (`6b3a1cf`), playtested on an Android phone |
| 2. Full battle mechanics | Done, committed (`49c1022`), playtested; tuning pass included |
| Unit symbols and unit book | Done, committed (`49c1022`) |
| Artillery (bolt and stone throwers) | Committed (`49c1022`), not yet playtested |
| Terrain height | Built, **not yet committed**, playtested ("feels good so far") |
| Playtest round (HUD scale, stones, ammo, refill) | Built, **not yet committed**, not yet playtested |
| 3. Minimal campaign | Built 2026-10-05, **not committed**, not yet playtested (see below) |
| 4. Async backend (Go + SQLite) | Committed (`fad7399`); port 8060 runs it; first phone playtest done (live battles were missing) |
| 5. Live co-op battles (lockstep) | Built 2026-10-05, **not committed**; tested headless, end to end and in two headless Chromiums; the 8060 server binary is not yet updated; not yet played on phones |
| Battle maps with character (woods, city maps, palettes, shading) | Built 2026-10-05, **not committed**; tested headless; not yet played on phones |
| 6. Depth (siege equipment, tech, more factions) | Not started |

### What exists

- **Battle sim** (`sim/`): deterministic, integer-only, per-soldier, 10 Hz.
  Nine unit types (heavy swords, light infantry, spearmen, pikemen, archers,
  javelinmen, shock cavalry, bolt throwers, stone throwers); melee with
  shields, armour and flank/rear bonuses; multi-rank pikes; projectiles with
  friendly fire; cavalry charges with knockdown and brace reflection;
  artillery engines with crews, set-up / pack-up, piercing bolts and
  ploughing stones; morale, routing, withdrawal; a battle
  AI that only issues orders; a plain-data battle result for the campaign.
- **Terrain height** (`sim/terrain.gd`, built 2026-10-05): an integer
  height grid (4 m nodes) generated from kind + seed + a few parameters
  (flat, rolling, ridge, valley, hill, slope, or hand-placed features),
  hashed into `state_hash()`; slopes slow units (cavalry and artillery most),
  higher ground helps in melee, charges hit harder downhill, missiles reach
  further from above, javelins and bolts are blocked by crests, stones
  plough less uphill; the AI uses high ground. Drawn as a contour map with
  hill shading in one shader. Details in DESIGN.md "Terrain height: as built".
- **View and controls** (`game/`): one-draw-call soldier rendering from a data
  texture, touch and mouse controls, multi-select, show-all-orders overlay,
  instant order preview while paused, unit symbols, unit book, HUD, telemetry.
- **Tests** (`tests/`): determinism, benchmark, scripted input (needs a
  window), balance matchups across seeds.
- **Tools** (`tools/`): web export, HTTPS dev server with telemetry logging,
  playtest report, script warning check, server build / run scripts.
- **Server** (`server/`, milestone 4): one Go binary with SQLite that serves
  the web build (brotli), the telemetry endpoint and the online co-op
  campaign API; Discord notifications; Dockerfile and deployment files.
  Reference: `docs/SERVER.md`. Client side: `game/net/`,
  `game/campaign/online_ui.gd`.

### What has been proven

- GDScript is fast enough: 4,000 soldiers cost about 9 ms mean, 30 ms worst
  per 100 ms tick on a Snapdragon 865 phone browser (milestone 1 build).
- The sim is deterministic across devices: an Android phone, a Linux desktop
  browser and the native Linux build produced identical hashes for the
  fixed-seed benchmark (milestone 1 build).
- The touch control scheme works; the user likes it.

### In progress right now

**Battle maps with character (built 2026-10-05, uncommitted).** CAMPAIGN.md
"Later" item 1. Design as built: DESIGN.md section 4 "Battle maps: woods
and settlements" (rules, numbers, AI, view, measurements). In short:
- Woods on any map (region coverage 0-100, density 0-3 per 4 m cell): slow
  units (artillery and cavalry most), disorder formed units (pike walls
  drop), blunt charges, stop arrows and stones, block flat shots; riders
  fight badly in them. The field AI keeps cavalry, pikes and batteries out
  and shelters archers from cavalry in them.
- Every settlement battle on the settlement's own map from a fixed
  `city_seed` (+ level, walls, buildings, region ground): streets and
  houses, plaza, walls with walkway and towers, 2-4 gates with hp,
  orchards and fields outside; paths through the streets, squeeze in
  narrow streets, missile troops on the walls, gates shut / opened /
  broken (artillery or hacking foot), plaza capture (60 s) breaks the
  defenders. Siege AI for both sides (`sim/siege_ai.gd`). The campaign's
  ridge stand-in for walls is gone.
- Ground palettes by region (arid / dry / green / rocky) on the battle map
  and the campaign map; stronger height shading; trees as one MultiMesh
  fading over soldiers; the city drawn in one static layer; gate taps;
  sandbox Ground and Settlement battle choices; unit book pages; the region
  panel's "View battle map".
- Campaign state format 2 (`city_seed`), local saves migrated on load;
  online campaigns stay format 1 on the server and play identically (no
  server change; see CAMPAIGN.md "State format").
- Verified: determinism test PASS (golden digests and every earlier run's
  hash unchanged; woods / village / city / hill city / scripted gate runs
  identical on repeat and across snapshot / restore); lockstep test PASS
  (with a walled town, players attacking and defending); live_e2e PASS and
  online_e2e PASS on scratch servers; campaign tests PASS (v1 save
  migrates); matchups `--only=maps` (no draws, settlement battles decided
  in 4-12 min); benchmarks bench_4000 2.65 / 6.0 ms, hills 3.0 / 6.2,
  bench_4000_city 2.69 / 7.8 (max over budget: first path tables after a
  gate falls).
- **Not yet done / next:** play it on the phones (look of the ground,
  trees and city on real screens; WebGL2 cost of the tree quads and the
  second ground texture; ground texture build 0.1 s on the desktop, maybe
  0.3-0.4 s on a phone); city benchmark spikes on phones; sallies; siege
  equipment.

**Milestone 5, live co-op battles (built 2026-10-05, uncommitted).** Why:
in the first online playtest one player started a battle and the other's
join button only returned them to the map. Now a battle with both armies is
fought live: the host opens a lobby (the ally is pinged), the ally taps
"Join battle", each commands their own army, as in Rome 2 co-op. Design as
built: DESIGN.md section 5 "Live battles: as built"; relay protocol:
SERVER.md section 17. In short:
- Deterministic lockstep over the server's WebSocket relay: only inputs
  travel, each for a frame a few frames ahead (delay from the round trip,
  2-12 frames of 100 ms; none while alone), the sim waits for a missing
  player's input. `sim/lockstep.gd` holds the frame, pause / speed and their
  votes, who takes part, and the command table, all hashed;
  `BattleSim.snapshot()` / `restore()` for joins, reconnects and desyncs.
  Golden digests unchanged.
- Gifts and gifts back, pause and speed by vote (chips under the controls:
  Accept / No), ally's unit cards framed in their colour and not orderable,
  a co-op strip (players, host, connection, round trip), waiting / catching
  up / resync indicators, lobby, Continue / Wait when the ally has been gone
  10 s (their units come to you, held for them; they get them back when they
  return), mid-battle join and rejoin by snapshot, host handover, result
  uploaded once by the host (any seat that took part may upload it).
- Server: rooms in memory (`rooms.go`) holding the battle's claim while in
  use, sequence-numbered stream with replay buffer, snapshot cache, roles,
  rate and size limits; battle list shows "Live now" with Join battle;
  `api: 2`. New table `battle_live` (created at start, nothing else changes
  in the database).
- Verified: `go test ./...` (rooms: entry and auth, ordering, reconnect and
  replay, drop / continue / ready, snapshots and cache, leave and host
  handover, lease renewal, upload by a seat that took part);
  `tests/lockstep_test.gd` (snapshot round trips on 6 scenarios up to 4,056
  soldiers; two peers through a simulated relay with different latencies
  and timing, every frame equal, with refused orders, gifts, votes, a drop,
  takeover and readmission, and a third peer joining mid-battle; solo
  through the lockstep layer = plain sim); `tests/live_e2e.py` (the Go
  server and two headless Godot clients fight three battles over real
  WebSockets: lobby join, mid-battle join, disconnect + takeover + return;
  hash equal on every frame on both, results uploaded once, both end on the
  server's state: PASS); `server/cmd/webcheck -live` (the web export in two
  headless Chromiums: lobby join, 600 frames hash-equal every frame,
  rejoin mid-battle from a snapshot: PASS); `tests/live_shots.py`
  (screenshots, and the real game as host uploading through its campaign
  screen). Screenshots `docs/screenshots/live_phone_*.png`.
- Numbers: snapshot 86-89 KB at 4,056 soldiers (36 KB at 2,000; 15-30 KB
  for small battles), ~10 ms to take and 2 ms to restore natively; on the
  local machine round trips 6-7 ms and no waits at delay 2; in headless
  Chromium 40-45 ms round trips (frame time included) and waits of up to
  ~170 ms when frames were run 4x faster than real time.
- **Not yet done / next:** restart the 8060 server with the new binary (the
  web build is already the new one); play it on the two phones; watch
  `coop_*` telemetry (round trips and waits on cellular, iOS Safari with
  the screen locked, backgrounded tabs); reinforcements arriving from the
  map edge; spectating without an army.

**Milestone 4, async backend and online co-op (built 2026-10-05,
committed in `fad7399`; 8060 runs the Go server behind Caddy, WebSocket
upgrade checked on the real domain).** Everything is in `docs/SERVER.md` (API, data model,
concurrency, notifications, deployment, security) and `docs/CAMPAIGN.md`
"Online play" (the screens). In short:
- Server: Go 1.27.1 (installed at user level in `~/.local/go`, checksum
  verified) + `modernc.org/sqlite`; static files with no-cache + ETag and
  precompressed wasm (39.5 MB -> 7.1 MB brotli); telemetry identical to
  `serve_web.py`; campaigns with every state version kept, join codes,
  per-device seat tokens (hashed), device codes, submissions with
  unsubmit, compare-and-swap uploads (one per version wins, an identical
  replay is "already"), turn deadline from the first submission with forced
  resolution, battle leases with heartbeats, Wait for ally / Take command /
  Ask to join, per-seat session blobs, long-poll change feed, WebSocket echo
  (milestone 5 relay goes there), history and rollback, determinism reports,
  Discord webhook notifications (queued, rate limited, deduplicated),
  invite key, rate limits, same-origin only, backups every 6 h.
- Client: Online co-op / Join / Continue-with-badges on the main menu, the
  share page, Submit turn and the waiting panel, the online battles list,
  the Online dialog (device code, Discord, timeout, history, rollback),
  Play online for a local campaign, offline cache, battle-result outbox,
  determinism check of the ally's results. Local play unchanged.
- Fixed on the way (affects every browser build): `main.gd` compared the
  iOS check's result `== true`, but this Godot build returns a JS boolean as
  an int, and int == bool is a runtime error that silently aborted the
  start screen's `_ready` before the URL shortcuts (`?scenario=` etc.). Also
  on the web `HTTPRequest` must not gunzip again what the browser already
  decompressed.
- Verified: `go test ./...` (API, races, timeouts, leases, rate limits,
  notifier); `python3 tests/online_e2e.py` (two headless Godot clients, 10
  turns, battles, a resolve race, a device switch, a forced turn, network
  failures, Discord messages: PASS); `server/cmd/webcheck` (two headless
  Chromium browsers on the web export: create, join, WebSocket echo,
  submit, resolve, long-poll pickup: PASS); the container image builds and
  runs (Podman). Screenshots `docs/screenshots/online_*.png`.
- **Not yet done / next:** (8060 is switched and an invite key is set.)
  Keep playing it on the Android phone and the iPhone (share link, typing a code, device code to the
  desktop, background tabs and long-poll on iOS Safari); move to the
  Proxmox host. No token
  revocation UI, no campaign deletion yet.

**Milestone 3, campaign layer (built 2026-10-05, uncommitted, not yet
playtested).** Everything is in `docs/CAMPAIGN.md` (as built: rules,
numbers, map and adjacency, tier table, state and order formats for
milestone 4). In short:
- `campaign/` pure deterministic rules: 36 regions, 45 land routes, 14 sea
  lanes, 8 factions + 12 independent regions, two turns a year from 280 BC,
  simultaneous orders then AI, economy with buildings / trade / upkeep /
  debt / corruption, settlement growth, 7 building chains, recruitment by
  building level and tier, replenishment, merge / split / disband, 12-unit
  armies, reinforcements, garrisons and walls, conquest, retreat,
  elimination, victory; campaign AI and diplomacy; state as one JSON blob
  with a hash.
- Unit tiers: 31 derived unit types (tiers 2-3 of the seven core lines plus
  faction elites: principes, triarii, phalangites, silver shields,
  companions, sacred band, hoplites, scutarii, Gallic nobles...), with
  gold-chevron tier marks; the nine base types are unchanged (golden
  digests unchanged).
- `game/campaign/`: map screen (drawn coastlines, territories, routes,
  armies, planned moves), region / army / realm / diplomacy / battles /
  summary / goals panels, hot seat with hand-over, save slots with autosave,
  export / import as text, new-campaign screen; battles fought in the
  battle view or auto-resolved by the battle sim AI vs AI.
- Main menu reorganised (Campaign / Battle sandbox / Unit book / Controls);
  Controls page from one bindings table; battle additions: Shift / Ctrl
  click multi-select (also on cards), symbol markers as hit targets first,
  None (deselect) button, keyboard shortcuts, mouse drag-box select,
  three-finger / Alt+drag (or G+drag) group move with rotation and ghost
  preview, field long-press / right-click for the unit book.
- Web: manifest + icons for install (no service worker, so never a stale
  build); iPhone Safari tab told to use Share > Add to Home Screen.
- Playtest fixes (2026-10-05, after the first phone playtest, which went
  well): every list scrolls by dragging anywhere in it, buttons included
  (`game/touch_scroll.gd`, used by all scroll areas; taps fire on release
  only if the finger did not scroll; fling; long press on unit rows opens
  the unit page; scroll bars thin on touch); neighbouring regions an army
  cannot enter are shown dark and crossed, and tapping one explains why with
  a Diplomacy shortcut; the region panel says whether its owner is at war or
  peace with you. Test: `godot --resolution 1560x720 --script
  res://tests/touch_scroll_test.gd`.
- Needs: a phone playtest of everything above; three-finger gestures on real
  phones; auto-resolve time on a phone; campaign pacing with real players.

Playtest feedback round (2026-10-05, built, uncommitted):
1. HUD scaled by device (`game/ui_scale.gd`: touch 0.88, mouse 0.82 CSS px
   per logical px, menu "UI size" S / M / L), compact unit cards wrapping
   into rows (no scrolling: 26 units in 2 rows on the phone, 1 on a
   desktop), actions in one row above the cards, Withdraw army in the top
   bar, one-line collapsible readout, grouped start menu with folded Tests.
   Screenshots `docs/screenshots/hud_*.png` (phone 780x360 CSS, 1920x1080,
   3840x2160). Unverified on the real phone and the 4K monitor.
2. Stone throwers aim at the near face of the target, lead its movement and
   land short rather than over (beyond-the-rear 28-82% -> 1-27%).
3. More ammunition (archers 40, javelins 6, bolts 11, stones 15 per engine).
4. Artillery Refill order: one more load in the baggage, ~70-90 s to bring
   up, cannot move or shoot meanwhile; the AI uses it.
Details and numbers in DESIGN.md (Artillery "Stone aim", "Refill";
Missiles "Ammunition"; section 7 "HUD as built").

Terrain height (built 2026-10-05, uncommitted): needs a phone playtest of
the look (contours, shading, readability of units on top) and of the
WebGL2 terrain shader on the Android phone and an iPhone; the playable
battles now get random terrain (menu "Terrain:" button to choose, "Replay"
for the same seed and ground, `?terrain=ridge&seed=N` on the URL). Four
terrain test scenarios are on the menu. Flat battles play exactly as
before (checked against the previous build).

Earlier (committed in `49c1022`):

A tuning pass from playtest feedback (built, uncommitted):

1. Cavalry charges resolve per rider and lap around the enemy front instead of
   the whole unit stopping when a few riders make contact.
2. Archers must be able to kill cavalry in the open (suspected cause: arrows
   aimed at where a fast target was, not where it will be).
3. Units rout later and mainly because of casualties taken: heavy infantry,
   spears and pikes hold to roughly 50-60% losses in an even frontal fight,
   light and missile troops to 30-35%. Flank and rear attacks should break
   units by killing soldiers, not by a large instant morale penalty.
4. Follow-up (2026-10-05): cavalry was too strong against the front of
   formed heavy infantry. Fixed by causes: impact direction judged per
   victim (men who face or can turn to the rider take it frontally), frontal
   impacts into a steady unit meet shields / full armour / support from the
   ranks behind and a strike back, a full charge needs ~18 m of run-up (no
   momentum from running away), and turning away from a melee costs a free
   blow; a horse only carries on into a second man when it breaks through.
   60 cavalry into a standing heavy 100 at 30 / 60 degrees: 97 / 100 killed
   -> 35 / 47, and the riders mostly lose; repeated frontal charging went
   from a 100% cavalry win to a costly loss. Details and the keep-list
   in `docs/DESIGN.md` (Cavalry charge).
5. Mirrored fairness: the bottom army won ~58% of 420 mirrored AI battles.
   Causes found and removed (each confirmed with its own probe): the AI
   armies thought 5 ticks apart; unit think phases followed the global unit
   index (the army listed second reacted sooner); unit processing order
   alternated by tick parity, which the mirrored geometry fixed at contact
   (one side always struck first in cavalry clashes); the scenario left the
   top army 1-6 m off the mirror image; and some direction-dependent
   rounding / scan order. Now 50.6% top over 840 battles (both unit orders).
   Check with `godot --headless --script res://tests/matchups.gd -- --fair=N`.

### Open items

- iPhone Safari (iOS 18.7) ran the 4,000 benchmark on the terrain build at a
  steady 60 fps (sim 3.1 ms mean, 7 ms worst per tick) and the terrain shader
  works there. It only rotates to landscape when opened from the home screen
  ("Add to Home Screen"); a Safari tab cannot force orientation.
- **iPhone determinism is not yet cross-checked** against another device on
  the same build. Run the same fixed-seed benchmark on the iPhone and one
  other device and compare with `tools/playtest_report.py`.
- The user reports performance is good on every device tried so far.
- Occasional frame hitches at 4,000 soldiers (a whole sim tick runs inside one
  frame). Fix by spreading tick work across frames if it becomes annoying.
- "A unit with a move order does not fight" was chosen so cavalry can pull out
  and units can retreat. Unconfirmed that it feels right in play.
- The game is reachable at `https://strategiccommand.ggior32.dev` through the
  user's Caddy reverse proxy, which holds a real certificate and forwards
  plain HTTP to the dev server on port 8060. The dev server is not hardened
  and only lives as long as the session that started it.
- Install support (2026-10-05): the export writes `manifest.json` and
  192 / 512 px icons (tools/make_web_icons.gd), standalone, landscape. No
  service worker: Godot's PWA worker answers from its cache first, which
  could serve a stale build, so there is no offline play. Android Chrome
  offers install without a worker (unverified on the user's phone).
- A mild top/bottom bias may remain in mirrored AI battles (53-55% on some
  seed ranges, 50.6% on another). Settle before head-to-head play.
- Deferred battle features: fatigue, horse archers, a manual brace
  toggle, siege equipment (ladders, towers) and climbing walls, sallies,
  spreading tick work across frames; terrain visibility (hiding behind
  hills or in woods).
- Terrain: phone GPU behaviour of `game/terrain.gdshader` is unverified
  (desktop GL only); the AI's high-ground behaviour (hold, detour, rises)
  is unplaytested; menu buttons are 44 px tall to fit the new entries.
- Artillery is unplaytested: look and readability of engines, bolts, stones
  and impact marks on a phone; whether the Deploy button and set-up times
  feel right; whether AI batteries and guards behave sensibly in play.
- bench_4000 (two armies a side) now runs ~10 min to a decision (2,000:
  ~5 min); the AI's second line and batteries could be looked at.

## Where we are headed

1. Playtest terrain (and artillery), then commit terrain.
2. **Battle depth, agreed with the user on 2026-10-05:** artillery, then
   terrain height, before the campaign; vegetation and map generation are
   done alongside the campaign (milestone 3), since they tie together.
   - **Artillery: built, uncommitted, awaiting playtest** (bolt throwers and
     stone throwers as engine entities with crews; see DESIGN.md
     "Artillery").
   - **Terrain height: built, uncommitted, awaiting playtest.**
   - **Trees and vegetation (next terrain step, with milestone 3):** forest
     zones that slow and disorder formations (cavalry most), reduce missile
     effect, and make the field look alive. Hooks left: new feature types
     can be rasterised by `sim/terrain.gd` into a second grid next to the
     heights (same node layout, same hashing); the terrain texture's alpha
     channel is reserved for vegetation density so the ground shader can
     draw it in the same pass; movement already goes through one per-unit
     speed factor (`_fac_for`) where a vegetation factor can multiply in.
   - **Map generation from the overworld (next, with milestone 3):** the
     campaign fills the scenario's `terrain` dictionary from the region
     (kind + seed, optionally relief / scale or explicit features); both
     peers build the identical grid and `ter_hash` in `state_hash()`
     catches any mismatch at tick 0.
3. **Milestone 3, minimal campaign:** region-node map, armies, recruitment
   (reusing the unit book page), a few building chains, money and upkeep,
   war / peace / trade diplomacy, campaign AI, pending battles, auto-resolve,
   and battles launched from the map using the sim's result data.
4. **Milestone 4, async backend:** built 2026-10-05 (see above and
   `docs/SERVER.md`); next: switch 8060, phone playtest, Proxmox.
5. **Milestone 5, live co-op battles:** built 2026-10-05 (above); next: phone
   playtest, reinforcements from the map edge.
6. **Milestone 6, depth.**

## Decisions already made (do not reopen without the user)

- Co-op only for now; head-to-head and controlling the enemy army come later.
- Simultaneous turn planning; the turn resolves when both have submitted.
  Turn timeout is a campaign setting (off, or one of several durations).
- Battles never block silently: they become pending and are resolved by
  auto-resolve, solo real-time, or live co-op.
- If the ally's army is in range and they are offline, the present player
  chooses per battle: wait for them, or take command of their army.
- In co-op battles each player commands their own army; units can be gifted
  and gifted back. Pause and speed changes need both players to agree.
- Per-soldier combat (health, blocking, individual hits) is a hard requirement.
- Live battles use deterministic lockstep, so the sim must stay integer-only.
- Game rules run on the clients; the server stores saves and relays traffic.
- No generals, family, politics, agents or naval combat in the first version.
- Web first (Godot export with threads off). Notifications through Discord.

## How to run things

```sh
# Campaign tests
godot --headless --script res://tests/campaign_test.gd      # rules, determinism, JSON
godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60   # AI pacing
godot --headless --script res://tests/campaign_solo.gd      # 20 turns of a player policy
godot --headless --script res://tests/campaign_battles.gd   # auto-resolve timing, formula calibration
godot --script res://tests/campaign_input_test.gd           # needs a window
godot --headless --script res://tests/matchups.gd -- --only=tiers   # tier balance
# Campaign testing aids: -- --campaign=rome[,greeks][:seed] --sim-turns=N
#   --camp-attack=N:region --camp-fight --select-army=N --select-region=key
#   --cam-zoom=Z --dialog=battles|summary|diplomacy|realm|goals --new-campaign
#   --controls --ios-tab; battle: --demo-ghost=deg

# Tests
godot --headless --script res://tests/determinism_test.gd
godot --headless --script res://tests/benchmark.gd
godot --headless --script res://tests/matchups.gd
godot --headless --script res://tests/matchups.gd -- --fair=100   # mirrored AI battles
godot --headless --script res://tests/matchups.gd -- --only=terrain  # terrain effect sizes
godot --headless --script res://tests/matchups.gd -- --fair=50 --fair-terrain=4  # mirrored, symmetric hill map
godot --headless --script res://tests/matchups.gd -- --only=maps     # woods, streets, gates, settlement battles
godot --headless --script res://tests/matchups.gd -- --only=sieges   # settlement battles only
godot --headless --script res://tests/probe_maps.gd -- --scen=siege_town --png=1500 --out=/tmp  # siege debug pictures
godot --headless --script res://tools/city_dump.gd -- --out=/tmp --seed=1234   # generated settlements to PNG
# Sandbox URL / command line: --siege=seed:level:walls[:ground[:kind[:defend]]], --ground=N, --no-trees
godot --script res://tests/input_test.gd        # needs a window
tools/check_scripts.sh                           # GDScript warnings as errors

# Live co-op battles (milestone 5)
godot --headless --script res://tests/lockstep_test.gd   # snapshots, two peers, mid-battle join (-- --quick)
python3 tests/live_e2e.py                        # two headless clients, three live battles (~70 s)
python3 tests/live_shots.py                      # phone screenshots of the co-op UI (needs a window)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8074 -live)
                                                 # two headless Chromiums, live battle (serve a web export there)

# Server (milestone 4; see docs/SERVER.md)
tools/build_server.sh --test                     # go vet + go test + build build/server/scserver
SC_BUILD_OUT=build/server-test/scserver tools/build_server.sh   # elsewhere (tests do this)
tools/run_server.sh 8070                         # serve build/web + API + telemetry on a port
python3 tests/online_e2e.py                      # two headless clients against a test server (~30 s)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8070)
                                                 # the web export in two headless Chromiums

# Web build and playtest server
tools/export_web.sh                              # writes build/web
python3 tools/serve_web.py 8060                  # plain HTTP, behind Caddy
python3 tools/serve_web.py 8443 --cert .certs/dev.crt --key .certs/dev.key
                                                 # self-signed, direct on the LAN
python3 tools/playtest_report.py                 # summarise playtest_logs/
```

- Godot's web build needs a secure context, so phones must use HTTPS. The
  self-signed certificate in `.certs/` (gitignored) is created with
  `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout .certs/dev.key
  -out .certs/dev.crt -subj "/CN=strategic-command-dev"
  -addext "subjectAltName=IP:<lan ip>,IP:127.0.0.1,DNS:localhost"`.
  Each browser shows a warning once; accept it.
- `?scenario=bench_4000` on the URL jumps straight into a scenario;
  `&seed=N&terrain=ridge` fixes the seed and ground of a playable battle
  (flat, rolling, ridge, valley, hill, slope, random). The battle's seed
  and terrain kind are shown in the top-left readout. Benchmark
  scenarios use a fixed seed so hashes can be compared between devices, but
  only between builds with the same `sim:` hash in the build stamp.
- Web export templates for Godot 4.7.2 (no-threads variants only) are in
  `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Playtest telemetry lands in `playtest_logs/` (gitignored).

## How we work

- Design, architecture and review happen in the main session with the user.
  Code generation is delegated to the latest Opus model (see `CLAUDE.md`).
- The loop: build, re-export, the user playtests on their phone against the
  dev server, telemetry plus their impressions drive the next change.
- Commit only when the user says so.
