# Strategic Command — Status and Handover

Last updated: 2026-10-05. Read this first, then `docs/DESIGN.md` for the full
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
| 2. Full battle mechanics | Built, playtested, **not yet committed**; tuning pass in progress |
| Unit symbols and unit book | Built, **not yet committed** |
| Artillery (bolt and stone throwers) | Built, **not yet committed**, not yet playtested |
| 3. Minimal campaign | Not started |
| 4. Async backend (Go + SQLite) | Not started |
| 5. Live co-op battles (lockstep) | Not started |
| 6. Depth (sieges, tech, more factions) | Not started |

### What exists

- **Battle sim** (`sim/`): deterministic, integer-only, per-soldier, 10 Hz.
  Nine unit types (heavy swords, light infantry, spearmen, pikemen, archers,
  javelinmen, shock cavalry, bolt throwers, stone throwers); melee with
  shields, armour and flank/rear bonuses; multi-rank pikes; projectiles with
  friendly fire; cavalry charges with knockdown and brace reflection;
  artillery engines with crews, set-up / pack-up, piercing bolts and
  ploughing stones; morale, routing, withdrawal; a battle
  AI that only issues orders; a plain-data battle result for the campaign.
- **View and controls** (`game/`): one-draw-call soldier rendering from a data
  texture, touch and mouse controls, multi-select, show-all-orders overlay,
  instant order preview while paused, unit symbols, unit book, HUD, telemetry.
- **Tests** (`tests/`): determinism, benchmark, scripted input (needs a
  window), balance matchups across seeds.
- **Tools** (`tools/`): web export, HTTPS dev server with telemetry logging,
  playtest report, script warning check.

### What has been proven

- GDScript is fast enough: 4,000 soldiers cost about 9 ms mean, 30 ms worst
  per 100 ms tick on a Snapdragon 865 phone browser (milestone 1 build).
- The sim is deterministic across devices: an Android phone, a Linux desktop
  browser and the native Linux build produced identical hashes for the
  fixed-seed benchmark (milestone 1 build).
- The touch control scheme works; the user likes it.

### In progress right now

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

- **iPhone Safari has never been tested.** It is the riskiest target. Run the
  4,000 benchmark there and check the logs.
- Phone performance of the milestone 2 build is unmeasured.
- Occasional frame hitches at 4,000 soldiers (a whole sim tick runs inside one
  frame). Fix by spreading tick work across frames if it becomes annoying.
- "A unit with a move order does not fight" was chosen so cavalry can pull out
  and units can retreat. Unconfirmed that it feels right in play.
- The top button bar nearly touches the performance readout on narrow screens.
- Installing as a home-screen app is off until the game is hosted behind a
  real certificate (browsers refuse to install from a self-signed one).
- Deferred battle features: fatigue, horse archers, terrain, a manual brace
  toggle, walled sieges, spreading tick work across frames.
- Artillery is unplaytested: look and readability of engines, bolts, stones
  and impact marks on a phone; whether the Deploy button and set-up times
  feel right; whether AI batteries and guards behave sensibly in play.
- bench_4000 (two armies a side) now runs ~10 min to a decision (2,000:
  ~5 min); the AI's second line and batteries could be looked at.

## Where we are headed

1. Playtest, then commit the tuning pass, milestone 2, the unit book and
   artillery.
2. **Battle depth, agreed with the user on 2026-10-05:** artillery, then
   terrain height, before the campaign; vegetation and map generation are
   done alongside the campaign (milestone 3), since they tie together.
   - **Artillery: built, uncommitted, awaiting playtest** (bolt throwers and
     stone throwers as engine entities with crews; see DESIGN.md
     "Artillery").
   - **Terrain height:** an integer height grid in the sim affecting movement
     speed, missile range, melee and charges (high ground matters). Drawn as
     thin contour lines with soft hill shading on the background, in a shader.
   - **Trees and vegetation (with milestone 3):** forest zones that slow and disorder formations
     (cavalry most), reduce missile effect, and make the field look alive.
   - **Map generation (with milestone 3):** generate each battle map (heights, forests) deterministically
     from the campaign map location, so both players get the same field.
3. **Milestone 3, minimal campaign:** region-node map, armies, recruitment
   (reusing the unit book page), a few building chains, money and upkeep,
   war / peace / trade diplomacy, campaign AI, pending battles, auto-resolve,
   and battles launched from the map using the sim's result data.
4. **Milestone 4, async backend:** a single Go binary with SQLite on the
   user's Proxmox server: campaign save blob with optimistic versioning, turn
   submission, WebSocket relay, Discord webhook pings. HTTPS with a real
   certificate, which also unlocks home-screen install.
5. **Milestone 5, live co-op battles:** lockstep over the relay, unit gifting
   and gifting back, reinforcements, pause and speed by vote, desync recovery
   by snapshot.
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
# Tests
godot --headless --script res://tests/determinism_test.gd
godot --headless --script res://tests/benchmark.gd
godot --headless --script res://tests/matchups.gd
godot --headless --script res://tests/matchups.gd -- --fair=100   # mirrored AI battles
godot --script res://tests/input_test.gd        # needs a window
tools/check_scripts.sh                           # GDScript warnings as errors

# Web build and playtest server
tools/export_web.sh                              # writes build/web
python3 tools/serve_web.py 8060 --cert .certs/dev.crt --key .certs/dev.key
python3 tools/playtest_report.py                 # summarise playtest_logs/
```

- Godot's web build needs a secure context, so phones must use HTTPS. The
  self-signed certificate in `.certs/` (gitignored) is created with
  `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout .certs/dev.key
  -out .certs/dev.crt -subj "/CN=strategic-command-dev"
  -addext "subjectAltName=IP:<lan ip>,IP:127.0.0.1,DNS:localhost"`.
  Each browser shows a warning once; accept it.
- `?scenario=bench_4000` on the URL jumps straight into a scenario. Benchmark
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
