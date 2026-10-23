# Distribution and networking (lockstep, servers, platforms, itch.io)

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

## 5. Networking

### Live battles: deterministic lockstep

Per-soldier state is too large to stream, so only orders are sent.

- Both clients run the same simulation from the same seed and apply the same
  orders on the same tick. Orders are scheduled a few ticks ahead (~200 ms).
- The sim uses integer / fixed-point maths only, its own seeded RNG, and fixed
  iteration order. No floats, no engine physics, no dictionary-order dependence.
- Clients exchange a state hash every second. On mismatch, the host sends a
  full snapshot and the other client resumes from it. The same path handles
  reconnects.
- Side benefits: tiny bandwidth, replays, and solo battles use the same code.
- Transport: WebSocket relay through the server.

### Campaign: save-store server

- The server stores the campaign state as a versioned blob, accepts turn
  submissions, relays battle traffic, and sends notifications.
- Game rules run on the clients; the server does not validate them.
- Optimistic versioning: an upload based on a stale version is rejected and
  the client refetches.
- Notifications via Discord webhook: "your turn", "battle pending", "join now?".
- Identity: a shared campaign code plus a per-player token. No accounts.
- Hosting: a container on the Proxmox server behind HTTPS (required for
  WebSocket from a browser and for home-screen install).
- Stack: a single Go binary with SQLite (HTTP for campaign saves, WebSocket
  for the battle relay), run in a container behind the existing reverse proxy.

## 6. Platforms and tooling

- Working model: design decisions are made in the main session; code
  generation and other delegated work run on Opus (see `CLAUDE.md`).

- Godot 4 (latest stable), GDScript, Compatibility renderer.
- Web export is the primary target; installable as a PWA on both phones.
- Native Android build is optional later. Native iOS is out of scope.
- **VERIFY:** early smoke test of a web export on the iPhone (performance,
  audio unlock, memory limits, behaviour when the tab is backgrounded).

### Live battles: as built (milestone 5, 2026-10-05)

Code: `sim/lockstep.gd` (deterministic, no networking), `sim/battle_sim.gd`
`snapshot()` / `restore()`, `game/net/coop_session.gd` (the client side of
the protocol), `game/net/live_room.gd` (the WebSocket), `game/coop_hud.gd`
(the co-op UI), `server/internal/server/rooms.go` (the relay). Protocol,
messages and limits: `docs/SERVER.md` section 17.

**Frames.** Lockstep time is counted in frames of 100 ms of wall time,
separate from sim ticks. A frame applies its inputs, then, unless paused,
adds the speed (quarter ticks: any q from 1 to 16, 0.25x to 4x, 4 = 1x) to an
accumulator and steps the sim once per 4. So pause and speed are lockstep
state, orders keep a wall-time delay whatever the speed, and frames (and
input messages) keep flowing while paused, which is what lets a resume vote
land.

**Inputs and marks.** Every input (a sim order, or a control input: pause /
speed request, answer, gift, admit) carries the frame it executes on, `f`.
A player's inputs go out in numbered messages `{n, k, o}` whose mark `k`
promises no more inputs for frames `<= k`; one goes out each frame with
`k = frame + delay` (delay 0 while alone, otherwise 2-12 frames from the
measured round trip: `ceil((srtt + 4 rttvar + 50 ms) / 100 ms)`, 3 to start;
200-300 ms on a normal connection). A frame runs only when every player
taking part has a mark at or past it, so all peers apply the same inputs on
the same frame, in (frame, player, message, index) order. Own messages are
applied locally when sent (no round trip added to one's own orders); the
relay's echo is dropped as a duplicate by message number, which also makes
any replay of the stream harmless. Late input (for a frame its sender had
already promised) is dropped by every peer alike.

**Command table.** `u_cmd` (who commands each unit), `u_away` (for whom a
unit is held) and `u_home` (who commands it by default: the campaign faction
of the unit if it is a human of the battle, other units of a side with
players that side's lowest player friendly to them; `CBattle` "controller")
live in the lockstep layer and are hashed with the sim. A sim
order counts only from the player commanding the unit at its frame; an army
withdrawal withdraws only the issuer's units; a player not taking part
orders nothing. Units of a human who is not there at the start are held for
them by the host; admitting that player gives them back (unless they chose
"Join, X keeps my army").

**Gifts** are inputs (`C_GIFT unit to`), valid only from the unit's
commander to a player taking part on the unit's side; gifting back is the
same input. The selected units' action row has "Gift to <ally>" (several
team-mates on the side: "Gift to...", a picker of them).

**Pause and speed by vote.** Requests and answers are inputs. A request
applies at once if only one player takes part; otherwise it is a vote of
the players taking part (hashed yes / no bit masks): the requester counts
as yes, asking for the same thing (tapping Pause, or the same speed) or
Accept on the chip is yes, Decline is no; it carries when more than half
of the players taking part say yes and is cleared (the state kept) when
that can no longer happen (a tie keeps the current state); a drop
re-counts it. With two players this is the old rule: the other player asks
for the same thing or taps Accept on the chip under the control (the requester's colour and
"Rome Pause?", "Rome proposes 2.5x"); Decline clears it; asking again withdraws it. Applied on the
same frame for everyone. A speed vote is the value the player releases the
speed slider at (any quarter step 1..16; the command rules refuse others). Solo battles keep immediate pause and speed; the
unit book and the controls page no longer pause a co-op battle.

**Joining.** "Fight" / "Fight together" on a battle with both armies opens
the room (lobby; the ally gets the Discord ping) and the battle view shows
both armies deployed behind the lobby panel. The ally's battle list shows
"Live now ... Join battle" (and "Join, X keeps my army"). The host starts
3 s after everyone is in, or alone with Start now. Joining a running battle
(or rejoining): a snapshot (sim + lockstep state + receipt state, about 86
KB at 4,000 soldiers) comes through the relay from a player who has the
battle, the joiner restores it, replays the stream after it, catches up by
stepping fast, says "ready", and the host admits it (an input) - from that
frame on the battle also waits for the joiner's input.

**Several humans (N-player campaigns, 2026-10-13).** Every human with an
army in the battle, on either side, may join, and every alive human on
the team of a side's lead faction without an army there (a guest:
`CRules.battle_guests`, given units by a team-mate; `guest_side` passes
their sim side to `Lockstep.setup`, which keeps each player's side in the
hashed `p_side`). The relay admits up to 8. Each player commands their
own faction's units (`controller`); a side with a player is not the battle
AI's in a live battle (`CoopSession.live_ai_sides` trims the scenario's
`ai_sides`; the AI takes a side over only while none of its players takes
part, as in head-to-head custom battles); units of a player who is absent
are held by the keeper, a player of the same side taking part (the host
if it is one, else the first by faction index). Gifts go to any team-mate
taking part on the same side. Votes are by majority (above). The view
fights from the player's own side (`player_side`); the HUD strip lists the
players (colour, name, "(enemy)" for the other side), unit cards carry a
band in their commander's colour when a side has several players, and the
lobby lists every eligible human. Tested: `tests/lockstep_test.gd` (three
peers, 13), `tests/live_team_e2e.py` (three headless clients through the
relay), `campaign_test` `_team_battles`, Go `TestRoomManyPeers`. Not
built: per-army battle AI for AI allies on a side with players (the sim's
AI commands whole sides, so they stay with the side's lowest player);
three or more players in custom battles (seats 0 / 1).

**Disconnects.** The sim waits for a missing player's input ("Waiting for
Carthage..." after 1 s). If that player is disconnected (or silent for 8 s)
and the wait reaches 10 s, the other gets "Carthage has disconnected:
Continue without Carthage / Wait". Continue asks the relay to drop them: a
stream event fixing the frame after their last mark from which they are not
awaited, and their units go to the remaining player, held for them. When
they come back they rejoin like a joiner and get their units back. If both
drop, the room is kept for 90 s (the last cached snapshot lets the first to
come back resume); after that it closes and the battle is an ordinary
pending battle again (a half-played battle is not persisted; it restarts
from the beginning). A page that comes back from the background resumes by
replay, or by snapshot when more than 10 s behind.

**Desync detection.** Every peer sends its lockstep hash every 10 frames
(tests: every frame); a mismatch is logged to telemetry (`coop_desync` with
both hashes and the frame) and on the server (`LIVE DESYNC`), shown briefly
("Out of step: resyncing"), and the non-host resyncs from a host snapshot.

**Result.** At the end every peer computes the result and sends its hash
(compared; `coop_result_mismatch` if different). Going back to the campaign
after the decision: the host uploads the outcome (the existing outbox with
retries; it tells the others first, so a player who becomes host later does
not upload again); others just leave. Leaving mid-battle: your units go to
the remaining player and the host role moves if you were host; the last
player leaving mid-battle uploads a forfeit as in a solo battle. Any seat
that took part may upload the result (the server records who took part).

**Hashed state.** Golden digests are unchanged: the sim is untouched apart
from `snapshot()` / `restore()`, and the lockstep state is hashed in
`Lockstep.state_hash()` (the sim's hash plus frame, pause, speed, votes, who
takes part, the command table), which solo play never uses. A solo battle
through the lockstep layer with one player is bit-for-bit the plain sim
(tested).

**Telemetry:** `coop_start`, `coop_net` (every 10 s: round trip, delay,
waits, messages, reconnects), `coop_wait` (waits of 0.5 s or more),
`coop_catchup`, `coop_snapshot` (sent / restored, bytes, ms),
`coop_resync`, `coop_desync`, `coop_drop`, `coop_continue`, `coop_admit`,
`coop_result`, `coop_result_mismatch`, `coop_leave` (with the session
stats).

### Campaign server: as built (milestone 4, 2026-10-05)

Details in `docs/SERVER.md`. In short:

- Go 1.27 + SQLite (pure Go driver), one static binary that also serves the
  web build (brotli: the 39 MB wasm goes out as 7 MB) and the telemetry
  endpoint; Dockerfile, compose file and systemd unit for the Proxmox host.
- Every state version is kept with what produced it (the submissions, or a
  battle's outcome), so any version can be replayed, inspected or rolled
  back to.
- Identity: a 6-character join code (no lookalike characters, case-free)
  claims the ally's seat and stops working once both seats are taken; each
  device holds its own seat token; an 8-character device code (30 minutes)
  moves a seat to another device. Optional server-wide invite key.
- Turn flow: submit (replaceable, withdrawable); the last submitter's client
  resolves and uploads; another open client resolves after a few seconds if
  nobody did. One upload per version wins; the others adopt it.
- Turn timeout: the deadline starts at the turn's first submission; after it
  the waiting player may resolve without the absent one (who holds).
- Pending battles: leases (2 minutes, heartbeats) so only one device
  resolves a battle; with the ally's army in it the present player chooses
  Wait for ally (pinged) or Take command (told); "Ask to join now" is the
  live-battle invitation (the live battle itself is milestone 5). Results
  are kept on the device until the server confirms them.
- Live updates by long-poll (works through Caddy, in iOS Safari and in
  Godot's HTTPRequest); an authenticated WebSocket echo endpoint is where the
  milestone 5 relay will go.
- Determinism safety net: a client re-runs every version another device
  made from its parent and inputs and reports a different hash.
- Discord notifications per campaign (your turn, waiting for you, turn
  resolved with battles, take command, ping, deadline, won / lost), rate
  limited, deduplicated, never blocking.

### Custom battles and head-to-head (as built, October 2026)

Start screen > Custom battle (`game/custom/custom_battle.gd`, the setup and
its scenario `game/custom/custom_setup.gd`, server `docs/SERVER.md` section
18).

- **Setup** (plain JSON): the map (field: terrain kind, ground palette,
  woods %, seed; settlement: plan, site, level, walls, coast, seed and which
  side defends), the deployment time (none / 1 / 2 min), equal funds per
  side (none / 4,500 / 7,500 / 12,000 at campaign prices, Total War style),
  and two sides of 1-3 armies of up to 12 units each, picked from the whole
  roster (every line, tier and faction elite) with their prices. Each army
  is commanded by Player 1, Player 2 or the AI; each side has an AI skill
  (Easy / Average / Skilled) and personality used when the AI fights it.
  Templates: the sandbox's playable battles and test matchups (cav vs
  archers, pikes, artillery, woods, two settlements), each side one army.
- **Build.** Deterministic: armies one behind another per side, laid out as
  the campaign does (`Scenarios.army_layout`), side 1 the mirror image;
  settlements through `Scenarios.settlement`; `home` (who commands each
  unit) from the controllers. The sim's battle AI commands whole sides
  (`ai_sides`; per-side profile), so: a side with no player's army is the
  AI's; an "AI" army on a side that also has a player's army is commanded
  by that side's (lowest) player, as AI allies are in campaign co-op; the
  skill / personality is per side, not per army (decision kept for now:
  changing it means per-army AI in `sim/battle_ai.gd`). Not supported: two
  players on one side and one on the other (only two players anyway).
- **Solo:** Play solo starts at once (with the deployment phase); Player 2's
  armies count as the AI's (on Player 1's side: Player 1 commands them).
  The player may be on either side (side 2 deploys at the top; the view
  is not turned round).
- **Online:** Play online creates a custom battle room (setup, 6-character
  code, seat token); the friend types the code under Join. The lobby shows
  the code, both players (connected, ready), co-op or head-to-head. The host
  owns the setup (every change goes to the relay with compare-and-swap on
  its revision and comes back to both); Player 2 may only change the units
  of Player 2's armies. Any change clears both players' Ready; the host's
  Start battle needs every connected player ready at the current revision
  with the same scenario hash (else "the two devices build this battle
  differently"). Then the battle opens on both with the live session:
  deployment, battle, results as in campaign co-op. Leaving goes back to
  the custom screen.
- **Head-to-head in the lockstep layer.** Every player belongs to the side
  of the units they command by default. Gifts only to a player of the
  same side (the Gift button only offers an ally). Pause and speed are
  still votes of everyone taking part. A player who is away at the start,
  drops, leaves or is continued without: their units go to a player of
  their own side taking part (the one the server named, if they are on
  that side), otherwise the battle AI takes their side over
  (`sim.ai_sides`, hashed in `Lockstep.state_hash` with `ai_take`;
  mid-battle on a field map it advances from where the army stands rather
  than deploying again) and hands it back when that player is admitted
  again. Results are per side (the result panel: your army / enemy).
- **Telemetry:** `custom_room` (create / join with a setup summary),
  `custom_start`, `custom_battle` at the end (setup summary, winner, my
  side, online, per-side totals), `deploy_ready`, `battle_start`.

### Distribution (agreed and built 2026-10-17)

The game ships on itch.io as a web build (HTTPS, any origin) and as desktop builds (Windows, Linux, macOS) that carry the game server (`scserver`) beside the game. The game server is also a standalone Docker image anyone can run (API and live relay, no web build); There is no public relay: the default server (built into the client so a fresh install works) is one self-host among many. Online campaigns and live battles always go through a game server: the default one, a friend's by address, or one the player hosts from the desktop build ("Host a server"). The server holds no rules (see SERVER.md); the client refuses a server built for another `CState.VERSION`, and a seat token goes only to the server it was issued by. Browsers can only call HTTPS servers (mixed content), so an itch.io player needs the default server or a self-hosted one behind a domain; desktop players can use plain HTTP on a LAN, a forwarded port or a tunnel such as Tailscale. A server serves other sites only when its owner lists their origins (`SC_ALLOWED_ORIGINS`); by default it answers its own origin.
