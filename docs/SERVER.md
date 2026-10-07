# Server (milestones 4 and 5) — as built

Built 2026-10-05 (milestone 5, the live battle relay: section 17). The campaign server for online co-op, the web build's file
server and the playtest telemetry endpoint, in one Go binary with SQLite.
Code: `server/` (Go module), client side in `game/net/` and
`game/campaign/online_ui.gd`.

**The rule:** the server never runs game rules. Clients run `campaign/`
(resolve turns, apply battle results) and upload the resulting state; the
server stores versions, enforces who may write what and when
(compare-and-swap on versions, battle leases, deadlines), and sends
notifications. It reads a few top-level facts out of each state blob (turn,
phase, winner, which human factions are alive, which humans have armies in
each pending battle) for bookkeeping, and checks that an upload's MD5-based
hash matches its content. It does not validate orders or results.

## Contents

1. Stack and layout
2. Running it (and how Go was installed)
3. Switching port 8060 to the Go server, and back
4. API reference
5. Data model
6. Concurrency: what happens in each race
7. Turns, deadlines, battles
8. Notifications (Discord)
9. Live updates: long-poll, WebSocket
10. Versions and compatibility
11. Determinism safety net
12. Web build serving and telemetry
13. Security and known limits
14. Backups, history, rollback, space
15. Deployment (Docker, Proxmox, Caddy, moving the data)
16. Tests
17. Live battle rooms (milestone 5): the lockstep relay
18. Custom battle rooms

## 1. Stack and layout

- Go 1.27.1, `modernc.org/sqlite` (pure Go: the binary is static, no cgo),
  `github.com/coder/websocket`, `github.com/andybalholm/brotli`. 13 MB
  binary.
- `server/cmd/scserver` main (flags and env); `server/internal/server` HTTP
  handlers, campaign logic, hub (long-poll), WebSocket, static files,
  telemetry, rate limits; `server/internal/store` SQLite (WAL, one
  connection, backups, gzip); `server/internal/notify` Discord webhook
  queue. `server/cmd/webcheck` drives the web export in headless Chromium
  (test tool, not in the image).
- `server/Dockerfile`, `server/deploy/` (compose, systemd unit, Caddyfile).
- `tools/build_server.sh` (builds `build/server/scserver`; `--test` also
  runs vet and tests), `tools/run_server.sh [port]`.
- Client: `game/net/api.gd` (HTTP with timeouts and retries),
  `game/net/accounts.gd` (this device's seats and tokens),
  `game/net/online_campaign.gd` (one seat: sync, submit, resolve, battle
  outbox, verification, long-poll), `game/net/net.gd` (autoload `Net`:
  server info, create / join / device codes, Continue badges),
  `game/campaign/online_ui.gd` (the online turn flow on the campaign screen),
  `game/net/net_selftest.gd` (browser self-test, `?nettest=`).

## 2. Running it

**Go toolchain (installed 2026-10-05):** Go 1.27.1 for linux-amd64 from the
official tarball `https://go.dev/dl/go1.27.1.linux-amd64.tar.gz`, SHA-256
`63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445` checked
with `sha256sum -c`, unpacked into `~/.local/go` (user level, no sudo, no
system paths touched). Use it with `export PATH=$HOME/.local/go/bin:$PATH`;
`tools/build_server.sh` finds it there by itself. Module downloads go to
`~/go/pkg/mod`.

```sh
tools/build_server.sh --test      # vet + unit/HTTP tests + build build/server/scserver
tools/run_server.sh 8070          # serve build/web, data in ./data, telemetry in playtest_logs/
```

Configuration: flags, or the environment variable in brackets (flags win).

| Flag | Env | Default | Meaning |
|---|---|---|---|
| `-addr` | `SC_ADDR` | `:8060` | listen address |
| `-data` | `SC_DATA_DIR` | `./data` | `campaigns.db`, `backups/`, `webcache/` |
| `-web` | `SC_WEB_DIR` | `./build/web` | the Godot web export |
| `-log-dir` | `SC_LOG_DIR` | `./playtest_logs` | telemetry JSONL |
| `-invite-key` | `SC_INVITE_KEY` | empty | if set, needed to create campaigns |
| `-trusted-proxy` | `SC_TRUSTED_PROXY` | loopback + private ranges | peers whose `X-Forwarded-For` is believed |
| `-backup-every` | `SC_BACKUP_EVERY` | `6h` | SQLite backup interval (0 = off) |
| `-backup-keep` | `SC_BACKUP_KEEP` | `12` | backups kept |
| `-compress` | `SC_COMPRESS` | `true` | precompress the web build |
| `-brotli-max` | `SC_BROTLI_MAX` | `true` | also brotli quality 11 in the background |
| `-lease` | `SC_LEASE` | `120s` | battle lease length |
| `-room-grace` | `SC_ROOM_GRACE` | `90s` | an empty, started live battle room is kept this long for reconnects |
| `-log-level` | `SC_LOG_LEVEL` | `info` | `debug` also logs static file requests |
| `-test-mode` | `SC_TEST_MODE` | `false` | `/api/test/clock`, any webhook URL: tests only |
| `-backup-now` | | | write one backup and exit |

Logs are JSON lines on stderr (`slog`): every API request (method, path,
status, bytes, ms, client IP), campaign events, notifier results.
`GET /healthz` answers `{"ok":true,...}` with the notifier's counters when the
database answers. SIGINT / SIGTERM: long-polls and WebSockets are woken,
in-flight requests finish (20 s), the notifier drains (5 s), the database
closes.

## 3. Switching port 8060 to the Go server, and back

The Python server (`tools/serve_web.py`) and the Go server serve the same
`build/web`, write telemetry to the same `playtest_logs/` in the same format
(`tools/playtest_report.py` is unchanged), and both listen on plain HTTP for
Caddy. Leave the self-signed LAN server on 8443 as it is.

Switch (from the repository root):

```sh
tools/build_server.sh --test                       # once: build and test
pkill -f '^python3 tools/serve_web.py 8060'        # stop only the 8060 Python server
tools/run_server.sh 8060                           # start (run it in the background; logs on stderr)
```

Check (from this machine):

```sh
curl -s http://127.0.0.1:8060/healthz
curl -s https://strategiccommand.ggior32.dev/api/info
# WebSocket upgrade through Caddy (expect "HTTP/1.1 101 Switching Protocols"):
curl -si --http1.1 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Origin: https://strategiccommand.ggior32.dev" \
  https://strategiccommand.ggior32.dev/api/c/none/ws --max-time 5 | head -1
# The whole online flow in two headless Chromium browsers through Caddy
# (creates a campaign named "nettest" on the server):
cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url https://strategiccommand.ggior32.dev
```

The first start compresses the 39 MB wasm in the background (gzip and
brotli-9 in about 4 s, brotli-11 in about 100 s, cached in `data/webcache/`
by content hash); until then it is sent uncompressed.

Roll back:

```sh
pkill -f '^build/server/scserver -addr :8060'
python3 tools/serve_web.py 8060
```

The campaigns stay in `data/campaigns.db` for the next switch. With the
Python server running, online features report "The game server is not
available" and local play is unaffected.

## 4. API reference

JSON over HTTP(S), same origin only. Requests with a body send
`Content-Type: application/json`. Seat calls send
`Authorization: Bearer <seat token>`; the campaign id is in the path.
Errors: `{"error": code, "message": text, ...}` with HTTP status 400
(`bad_request`, `bad_state`, `bad_hash`, `bad_webhook`, `confirm`...), 401
(`unauthorized`), 403 (`invite_required`, `wrong_seat`, `need_command`,
`cross_origin`), 404 (`not_found`, `bad_code`, `no_version`), 409
(`conflict`, `not_ready`, `claimed`, `lost_lease`, `seat_taken`), 413
(`too_large`), 429 (`rate_limited`, with `Retry-After`). A 409 `conflict`
carries the current `version`, `hash`, `phase`, `turn` and pending battle
ids. Turn numbers in the API are the state's (0 = the first turn);
notifications show them from 1.

| Call | Body / query | Answer |
|---|---|---|
| `GET /healthz` | | `{ok, version, notify{queued,sent,failed,dropped,pending}}` |
| `GET /api/info` | | `{server, version, api (3: custom battles), build (web build stamp), invite_required, time}` |
| `POST /api/campaigns` | `{name, format_version, rules, build, seat, state_gz, hash, labels{factions[],regions[]}, turn_timeout_h, webhook_url?, discord_user?, invite?, device?}` | `{id, token, seat, version: 1, hash, join_code?, join_expires?}` |
| `POST /api/join/preview` | `{code}` | `{id, name, turn, humans, format_version, rules, seats[{f, name, claimed}]}` |
| `POST /api/join` | `{code, f, discord_user?, device?}` | `{id, token, seat, name}` |
| `POST /api/link` | `{code, device?}` (device code) | `{id, token, seat, name}` (a new token for that seat) |
| `GET /api/c/{id}` | | summary (below) |
| `GET /api/c/{id}/state` | `?version=N` | `{version, parent, kind, hash, turn, phase, by, rules, build, at, state}` (gzip on the wire) |
| `POST /api/c/{id}/state` | `{base_version, kind: turn\|battle, hash, state_gz, rules, build, subs_rev, forced}` or battle: `{..., battle_id, outcome}` | `{ok, version, already?}` |
| `GET /api/c/{id}/history` | | `{versions[{version, parent, kind, turn, phase, hash, raw_size, stored_size, by, rules, at}], stored_bytes}` |
| `GET /api/c/{id}/history/{v}` | `?parent=1&state=0` | `{version, parent, kind, hash, ..., inputs, state?, parent_hash?, parent_state?}` |
| `POST /api/c/{id}/rollback` | `{to_version, confirm: "rollback"}` | `{ok, version}` |
| `POST /api/c/{id}/submit` | `{base_version, submission{turn, f, base, orders}}` | `{ok, all_in, subs_rev, deadline}` |
| `POST /api/c/{id}/unsubmit` | `{turn}` | `{ok}` |
| `GET /api/c/{id}/resolve-input` | | `{base_version, base_hash, turn, phase, subs_rev, submissions[], missing[], all_in, deadline, expired, can_resolve}` |
| `POST /api/c/{id}/battles/{bid}/claim` | `{mode: fight\|auto}` | `{ok, until, lease_ms}` |
| `POST /api/c/{id}/battles/{bid}/heartbeat` | | `{ok, until}` |
| `POST /api/c/{id}/battles/{bid}/release` | | `{ok}` |
| `POST /api/c/{id}/battles/{bid}/choice` | `{choice: wait\|command\|ask}` | `{ok}` |
| `POST /api/c/{id}/ping` | `{battle_id?}` | `{ok, sent}` |
| `GET /api/c/{id}/session` | | `{rev, data}` |
| `POST /api/c/{id}/session` | `{data, rev?}` | `{ok, rev}` |
| `POST /api/c/{id}/settings` | `{webhook_url?, discord_user?, turn_timeout_h?}` | `{ok, webhook (masked)}` |
| `POST /api/c/{id}/test-notify` | | `{ok, queued}` |
| `POST /api/c/{id}/link` | | `{code, expires_at}` (device code, 30 min, single use) |
| `POST /api/c/{id}/verify` | `{version, ok, local_hash, ms}` | `{ok}` |
| `GET /api/c/{id}/wait` | `?since=SEQ&timeout=S` (max 25) | `{seq, server_time}` |
| `GET /api/c/{id}/ws` | WebSocket; first message `{"t":"auth","token":...}` | `hello`, then `ping`→`pong`, `echo`, and `room` (live battles, section 17) |
| `POST /api/custom` | `{setup (JSON object, <= 64 KB), rules, build, invite?, name?}` | `{code, token, seat: 0, rev: 1}` (custom battles, section 18) |
| `POST /api/custom/join` | `{code}` | `{code, token, seat: 1, rev, setup, rules, build, name}` |
| `GET /api/custom/{code}/ws` | WebSocket; first message `{"t":"auth","token":...}` | as `/api/c/{id}/ws`, the room is the custom battle (section 18) |
| `POST /api/test/clock` | `{advance_ms}` (test mode only) | `{ok, time}` |
| `GET` / `POST /telemetry` | as `tools/serve_web.py` | `{ok, stored}` / status |
| `GET /*` | static files from the web build | |

`state_gz` is the base64 of the gzip of the canonical state text
(`CState.to_json`); `hash` is `CState.hash_text` (first 4 bytes of its MD5,
little-endian, hex). The server recomputes the hash and refuses a mismatch.
`labels` are the faction and settlement names, so notifications can say
"the battle at Capua" without the server knowing the map.

Summary (`GET /api/c/{id}`): `id, name, version, hash, turn, phase, winner,
format_version, rules, humans, alive, me, seq, seats[{f, name, claimed,
last_seen, online, submitted, discord, alive}], submitted[], missing[],
all_in, subs_rev, deadline, deadline_expired, timeout_h, battles[{id, r,
region, humans, claim{f, mode, until, since, mine}|null, wait_by,
command_by, ask_by[], live{state: lobby|live, host, since, version, players[{f, on, in,
dropped, joining, keep, silent_ms}]}|null}], activity[{at, f, kind, data}] (last 20), webhook (masked),
server_time, last{kind, by, rules, build, parent, at}, join_code?`.

## 5. Data model

One SQLite file `data/campaigns.db`, WAL, `busy_timeout` 10 s, foreign keys,
one connection (every transaction is serialised).

| Table | Holds |
|---|---|
| `campaigns` | id, name, format version, creator's rules hash and build, humans, labels, join code (+ expiry; NULL once all seats are claimed), current version / hash / turn / phase / winner / alive humans / pending battles with their humans, timeout, `subs_rev` (bumps on every submit / unsubmit), deadline, `seq` (change counter), webhook URL |
| `seats` | per human faction: claimed, last seen, Discord user id, session blob (gzip) + rev |
| `tokens` | SHA-256 of each seat token (one per device), last used, revoked flag |
| `link_codes` | device codes: campaign, seat, expiry (single use) |
| `states` | every version: parent, kind (`create`, `turn`, `battle`, `rollback`), turn, phase, hash, the state (gzip), inputs (gzip: the submissions used, or battle id + outcome, or the rollback target), who, rules hash, build, time |
| `submissions` | per plan-phase version and faction: the submission JSON, time |
| `battle_claims` | per pending battle: holder seat, holder device (token id), mode, lease expiry |
| `battle_flags` | per pending battle: who chose "wait" and who "took command" |
| `battle_live` | per pending battle: the seats that took part in it live (each may upload its result); added by milestone 5 with `CREATE TABLE IF NOT EXISTS`, so an existing database gains it at start |
| `activity` | the last 200 events per campaign (joined, submitted, battle claimed, desync...) |
| `notif_sent` | notification dedupe keys |

## 6. Concurrency: what happens in each race

Every write is one transaction that re-reads the campaign row and checks
before writing. On a single connection the transactions cannot interleave,
so "read, check, write" is atomic.

| Race | Outcome |
|---|---|
| Two clients resolve the same turn and upload | The first upload whose `base_version` equals the current version wins and becomes version N+1. The second sees `base_version != current`: if its hash equals the winner's (deterministic rules: the normal case) it gets `200 {already: true}` and adopts it; otherwise `409 conflict` and refetches (and reports a determinism mismatch, see 11). Tested both ways. |
| A submission changes while someone resolves | The resolver uploads with the `subs_rev` it resolved from; any submit / unsubmit in between bumped it: `409 conflict`, refetch, resolve again if still all in. The stored inputs are the server's own copy of the submissions, so they are exactly what was resolved. |
| Upload answer lost (connection drops after commit) | The client retries the same body; the server finds a version with that parent and hash and answers `200 already`. |
| Resubmission | Replaces the seat's submission (upsert); `subs_rev` bumps. Unsubmit deletes it until the turn is resolved. |
| Two devices / players claim one battle | Exactly one lease (`claimed` 409 for the other, naming the holder). Tested with 20 parallel rounds. |
| Lease holder disappears (page closed) | No heartbeat: the lease expires after 120 s and anyone allowed may claim. A late upload by the old holder after someone else claimed is refused (`claimed`); its client keeps the result and drops it only if the battle stops being pending. |
| Two battle results at once | Each is applied to the state it was computed on; the second upload gets `conflict`, refetches, re-applies its outcome to the newer state (the battle is still pending) and uploads again. |
| Rollback while someone plays | Rollback makes a new version; everyone's next request sees the new version (long-poll wakes them), submissions of the old version no longer count, all claims and flags are cleared. |
| Same seat on two devices | Separate tokens; plans in the session blob are last-writer-wins (by save time); battle leases are per device. |

## 7. Turns, deadlines, battles

- Submitting is allowed in phase `plan` for the current turn by an alive
  human seat, also before the ally has joined.
- **The last submitter's client resolves at once**; any other open client
  resolves after a grace period (4 s) if nobody has, which covers a closed
  page. A client that resolves runs `CTurn.resolve_turn(state,
  submissions)` and uploads.
- **Turn timeout (decided):** the deadline starts when the turn's **first
  submission** arrives (`deadline = first submit + timeout`) and clears when
  every submission is withdrawn or the turn is resolved. The alternative,
  "from when the turn became plannable", would start the clock while nobody
  is waiting, so a player could be timed out by their ally's absence too.
  After the deadline the waiting player may resolve with `forced: true`; the
  missing seats submit nothing ("a faction that submits nothing holds").
  The 2-hour warning and the "deadline passed" note are sent by a scanner
  every 30 s. The timeout is set at creation (from the new-campaign screen)
  and can be changed in the Online dialog; the server's value is the one
  enforced (`state.settings.turn_timeout_h` is only the initial value).
- **Battles:** a seat may claim (fight or auto-resolve) a pending battle when
  its own faction is the only human in it, or after choosing `command`
  (the card's **Fight it for X**) for a battle with the ally's army in it
  (the ally is told). Choices (`POST .../choice`): `wait` (**Leave it to
  X**) records `wait_by` and pings the ally; `command` records
  `command_by`; `ask` (**Ask to join**, any alive human seat, army in the
  battle or not) adds the seat to the battle's `ask_by` (table
  `battle_asks`, cleared when the battle leaves the pending list or on a
  rollback) and pings the battle's humans when a webhook is set ("X asks
  to join the battle at R: open it with Fight together"). The owner's
  client shows the request on its battle card on its next poll and offers
  Fight together first; the request needs no Discord. A choice on a battle
  where the seat's own army is the only human one is refused
  (`not_needed`). Claims are leases (120 s) renewed by heartbeats every
  30 s, released by the result upload, by release, or by expiring.
- Battle results go through a local **outbox** on the client: saved to the
  device before the upload, retried with backoff (also after the page is
  closed and reopened), re-applied on a newer state after a conflict,
  dropped only when the battle is no longer pending (and then the client
  first checks whether its own earlier attempt was the one that won).

## 8. Notifications (Discord)

Per campaign webhook URL (set at creation or in the Online dialog), and an
optional Discord user id per seat for @mentions. Messages (with the
campaign name in bold):

| Kind | When | Mentions |
|---|---|---|
| joined | the ally claims their seat | — |
| submitted | "X has submitted turn N, waiting for Y" | the missing seats |
| turn resolved | "Turn N resolved: K battles pending involving your army: Capua (Rome), ..." | humans with armies in them |
| your turn | "Turn N resolved. Turn N+1 is ready to plan." (or after the last battle) | alive seats |
| ping | "X is waiting for you (turn N)" (button on the waiting panel) | the missing seats |
| ping battle | "X is asking you to join the battle at R now" (a live room opened, or the battle card's ping) | the ally (every other alive human for a room) |
| ask | "X asks to join the battle at R: open it with Fight together" | the battle's humans |
| wait | "X is waiting for you to fight the battle at R" | the ally |
| took command | "X took command of your army at R" | the ally |
| deadline soon | "Turn N deadline in about 2 hours: Y has not submitted" | the missing seats |
| deadline passed | "... X may resolve the turn now without Y" | all |
| forced | "Turn N resolved after the timeout without Y" (in the turn message) | |
| won / lost | at the end | all |
| rollback | "X rolled the campaign back to version V" | — |
| test | "Send test message" in the Online dialog | the sender |

"Battle pending involving your army" is part of the "turn resolved" message
(battles only appear when a turn resolves), to keep the channel quiet.
Delivery: never inside an API call (a bounded queue of 500 drained by one
worker, so a campaign's messages arrive in order); per campaign at least
1.5 s apart and at most 40 an hour; Discord's 429 is honoured once
(`retry_after`), 5xx and network errors are retried twice with backoff,
other errors are logged and dropped. Dedupe: each message has a key
(`submitted:<version>:<seat>`, `turn:<turn>:<version>`, `ping:...:<2-minute
bucket>`...) recorded in `notif_sent` in the same transaction as the change.
The webhook URL must be `https://discord.com/api/webhooks/...` (or
discordapp / ptb / canary), is never returned to clients after being set
(only `https://discord.com/...XXXX`), and is redacted from logs.
`allowed_mentions` only lets the listed user ids ping.

## 9. Live updates: long-poll, WebSocket

- **Long-poll** (`GET /wait?since=SEQ`) is the change channel. Every change
  to a campaign bumps its `seq`; an open client keeps one request waiting
  (up to 25 s; answered at once when `seq` moves) and refetches the summary
  (and the state if the version moved). It is a plain request, so it passes
  Caddy and works in iOS Safari and in Godot's `HTTPRequest` (which on the
  web is `fetch`). When the server cannot be reached the client retries with
  backoff (2 s doubling to 60 s), shows "Offline", and keeps working on its
  local copy. **Not SSE:** Godot's `HTTPRequest` delivers a response only
  when it is complete, and the browser's `EventSource` cannot send the
  Authorization header; long-poll gets the same latency without either
  problem.
- **WebSocket** `GET /api/c/{id}/ws`: authenticated by the first message
  (browsers cannot set headers on a WebSocket), then `ping`/`pong` and
  `echo`. It exists to prove WebSockets pass the proxy (checked from the
  browser by the self-test). Milestone 5's battle relay goes here: a "join
  room" message (room = campaign + battle id), the server fans messages out
  to the room's members in arrival order (`server.Room` is the placeholder).
  Nothing in the long-poll path needs to change for that.

## 10. Versions and compatibility

- **State format version** (`CState.VERSION`, now 1) must match exactly:
  the server stores the creator's, refuses uploads of another, and a client
  of another format refuses to open the campaign ("update the game").
- **Rules hash** (`rules:xxxxxxxx`): SHA-1 of `campaign/*.gd` + `sim/*.gd`
  (sorted paths), written into `build_stamp.txt` by `tools/export_web.sh`
  (`game/net/net.gd` computes the same from the sources when there is no
  stamp; checked equal). Sent with every upload and stored per version. If
  the latest version was made by a different rules hash the client shows a
  warning (reload both devices); actual divergence is caught by the
  determinism check.
- **Build stamp**: `tools/export_web.sh` copies `build_stamp.txt` next to the
  export; `/api/info` returns it, and the home page says "A newer version of
  the game is on the server: reload the page" when it differs from the
  running build.
- Policy for deploying a new build mid-campaign: rules changes that keep the
  format are fine between turns (both players reload); a format change needs
  `CState.VERSION` bumped and a migration (none exists yet), else the
  campaign is refused until both run a matching build.

## 11. Determinism safety net

When a client adopts a version made by another device (kind `turn` or
`battle`), it fetches that version's parent state and inputs
(`/history/{v}?parent=1&state=0`), re-runs the step (`resolve_turn` or
`apply_battle`), compares hashes, and posts the result to `/verify`. A
mismatch is logged on the server (`DETERMINISM MISMATCH`), recorded in the
campaign activity, sent to telemetry (`online_desync`) and shown to the
player; the server's copy stays authoritative. A resolve race checks for
free: the loser compares its own result with the winner's. On by default;
costs one download (about 15 KB, gzipped on the wire) and one turn
resolution (~10-20 ms desktop) per new version. Togglable per device in the
Online dialog.

## 12. Web build serving and telemetry

- Static files from `build/web` with explicit MIME types (`.wasm`
  `application/wasm`, `.js`, `.pck`, `.html`...), `Cache-Control: no-cache`
  plus a content-hash `ETag`: every load revalidates (never a stale build)
  and an unchanged 39 MB wasm costs a 304.
- Compression: `index.wasm` 39.5 MB -> **7.1 MB brotli-11** (8.0 MB
  brotli-9, 10.1 MB gzip-9), so a phone downloads about a fifth. Made in the
  background once per build (gzip + brotli-9 in about 4 s, then brotli-11 in
  about 100 s), cached in `data/webcache/` by content hash, chosen by
  `Accept-Encoding`. `index.pck` gains little (0.6 MB -> 0.58 MB).
- `/telemetry` behaves like `serve_web.py`: one record or `{"records": [...]}`
  (max 512 KB, 2,000 records, 64 KB per record), one JSON line per record in
  `<log dir>/YYYY-MM-DD.jsonl` with `recv` (UTC, ms) and `ip` first (the
  socket peer, or `<first X-Forwarded-For> via <peer>`); `GET` returns the
  status object. Rate limited per IP (5/s, burst 30).

## 13. Security and known limits

- No accounts. A **seat token** (32 random bytes, base64url) is the only
  credential; it lives in the browser's storage (`user://online/`, i.e.
  IndexedDB). Stored on the server as SHA-256; compared in constant time.
  Each device has its own token (device codes mint a new one), so a lost
  device's token could be revoked (a `revoked` column exists; there is no UI
  for it yet).
- **Join codes**: 6 characters from 29 (no 0/O, 1/I/L, U/V): 594 million
  codes; wrong codes are limited to 10 per 15 minutes per IP; a code stops
  working once both seats are taken, or after 14 days. **Device codes**: 8
  characters, 30 minutes, single use.
- **Invite key** (`SC_INVITE_KEY`): if set, creating a campaign needs it, so
  strangers cannot fill the disk. Creating is also limited to 6 per hour per
  IP. Recommended once the domain is shared beyond the two players.
  Players enter it once per device: the client remembers the last key that
  worked (`invite` in `user://online/accounts.json`) and prefills it. On
  phones and tablets a tap on the field opens the browser's text box (paste
  works there); on desktop browsers use Ctrl+V or the Paste button beside
  the field. Spaces around a pasted key are dropped.
- Limits: 64 KB per ordinary request, 4 MB per state upload (8 MB
  decompressed), 512 KB session blobs, 256 KB per submission; per IP 20
  requests/s (burst 60); per token 10/s (burst 40); failed auth counts
  towards the code limit.
- **Same origin only**: no CORS headers; non-GET requests with a foreign
  `Origin` (or `Sec-Fetch-Site: cross-site`) are refused; the WebSocket
  checks Origin against Host.
- Client IP for rate limits: the right-most `X-Forwarded-For` address that is
  not a trusted proxy, believed only when the socket peer is a trusted proxy
  (default: loopback and private ranges, which suits Caddy on the LAN).
- Discord webhook URLs are secrets: host-checked, never returned, redacted
  from logs.
- The server does not validate game rules, so a modified client can upload
  any state. Accepted (co-op between friends; DESIGN.md "No anti-cheat").
- Known limits: one SQLite connection (plenty for a few campaigns; it would
  need a read pool for hundreds of active players); in-memory rate limiters
  (reset on restart); no campaign deletion endpoint (delete rows with
  `sqlite3` if needed); no token revocation UI; webhook messages are lost
  if the process dies with a non-empty queue (they are notifications only).

## 14. Backups, history, rollback, space

- Every version is kept (`states`), with its inputs, so any version can be
  inspected (`/history/{v}`), replayed, or made current again with
  `POST /rollback {to_version, confirm: "rollback"}` (also in the game:
  Online > History and rollback, two taps). A rollback is a new version;
  nothing is deleted.
- Space: a state is 10-15 KB of JSON, about 1.8 KB gzipped. A 60-turn
  campaign measured 74 versions = 129 KB of states (two players with the
  test policy; with more player battles, up to ~150 versions, about 350 KB
  including inputs). Sessions and activity add a few KB.
- Backups: `VACUUM INTO data/backups/sc-YYYYMMDD-HHMMSS.db` every 6 h (first
  one 2 minutes after start), keeping 12; `scserver -backup-now` writes one
  and exits. Restore: stop the server, copy a backup over
  `data/campaigns.db` (remove `campaigns.db-wal` and `-shm`), start it.

## 15. Deployment

**Docker / Podman** (image: Go build stage, then
`gcr.io/distroless/static-debian12:nonroot`: CA certificates, no shell,
user 65532; the web build is copied in; data in the `/data` volume):

```sh
tools/export_web.sh
docker build -f server/Dockerfile -t strategic-command:latest .      # from the repo root
docker run -d --name sc --restart unless-stopped -p 8060:8060 -v sc-data:/data \
  -e SC_INVITE_KEY=... strategic-command:latest
# or: docker compose -f server/deploy/docker-compose.yml up -d --build
```

A new web build needs a new image, or mount it read-only over `/srv/web`
(commented line in the compose file).

**Proxmox:** either an LXC with Docker (or Podman) running the image, or a
small Debian LXC / VM running the static binary under systemd
(`server/deploy/scserver.service`: own user, `ProtectSystem=strict`, data in
`/var/lib/scserver`). 256 MB RAM is plenty (the compressed wasm variants
are held in memory, ~20 MB). Point Caddy at it:

```
strategiccommand.ggior32.dev {
	reverse_proxy <container or VM address>:8060
}
```

Nothing else is needed for long-polling or WebSockets with Caddy.
If Caddy is not on a private address, set `SC_TRUSTED_PROXY` to its address.

**Moving the data** (from this machine to the Proxmox host): stop the server
(or take a consistent copy with `scserver -backup-now -data ./data`), copy
`data/campaigns.db` (and `playtest_logs/` if wanted) into the new data
volume (`docker cp` or a bind mount; for the named volume:
`docker run --rm -v sc-data:/data -v $PWD:/from alpine cp /from/campaigns.db /data/`
then `chown 65532:65532`), start the new server, switch Caddy, stop the old
one. `webcache/` need not be copied. Tokens, codes and history move with
the file; clients only know the domain, so nothing changes for them.

## 16. Tests

- `cd server && go test ./...` (or `tools/build_server.sh --test`): create /
  join / tokens (hashed, constant time, wrong campaign), join codes (case,
  dashes, taken seat, rate limit), invite key, bad input (wrong hash, wrong
  format, bad base64, gzip bomb, bad webhook, bad timeout, too large, bad
  JSON, cross-origin), submit / resubmit / unsubmit / stale `subs_rev`,
  resolve race (same and different results), timeout with an injected
  clock (2-hour warning, deadline passed, forced resolution and its inputs),
  battle claims (need command, held, heartbeat, expiry, upload by the
  non-holder, state still listing the battle), parallel claims from two
  devices of one seat (20 rounds), rollback and history continuity, session
  blobs (rev conflict, per seat), long-poll (immediate, wake, timeout), rate
  limits (token, IP, create), client IP behind proxies, telemetry lines,
  static files (no-cache, ETag 304, brotli, traversal), WebSocket (auth,
  ping, echo, bad token), backup rotation, the state hash against Godot's;
  the notifier against a fake webhook (order, mentions, 429 / 5xx retries,
  rejection, unreachable, hourly cap, never-blocking queue, URL checks).
- `python3 tests/online_e2e.py`: the Go server in test mode, a fake Discord
  webhook, two headless Godot clients (`tests/online_client.gd`, the game's
  own `game/net/` code) playing 10 turns as Rome and Carthage: creation and
  join by code, policies that attack, battles auto-resolved with the sim by
  the client whose army is in them (and by take-command), a forced resolve
  race, a device switch mid-turn through a device code, an absent player
  and a forced resolution after the (clock-shifted) deadline, battle uploads
  failing three times (A: before sending, then the page is closed and
  reopened; B: every answer lost after the server committed). It builds the
  server into `build/server-test/` (never over the binary a running server
  uses). Checks: both
  clients and the server on the same hash, contiguous history, every step
  re-run locally with no mismatch, the stored orders equal what was sent,
  one winner of the race with equal hashes, results delivered, Discord
  messages in order without duplicates. About 25 s.
- `server/cmd/webcheck`: the web export in two headless Chromium processes
  (`?nettest=a` / `?nettest=b&join=CODE`, `game/net/net_selftest.gd`):
  create, join, WebSocket echo from the browser, submit, resolution, the
  other browser picking it up by long-poll, equal hashes.

## 17. Live battle rooms (milestone 5)

The relay for live co-op battles (design: DESIGN.md section 5 "Live battles:
as built"). Code: `server/internal/server/rooms.go` (rooms), `live.go` (the
WebSocket); client `game/net/live_room.gd` (the connection),
`game/net/coop_session.gd` (the protocol's client side), `sim/lockstep.gd`
(the deterministic part). `/api/info` reports `api: 2` from this milestone
on; clients only offer live battles to servers with API 2.

**The rule stays:** the server never runs the sim. It relays inputs with a
sequence number, keeps the recent stream and the latest snapshot, decides
roles (host, who is dropped), and trusts clients only as far as auth: who
may be in the room, input messages numbered without gaps, marks that never
go back, sizes, rates.

### Room life

- A room is one pending battle of one campaign (key `campaign/battle`), in
  memory. It is opened over the campaign WebSocket by a human seat whose army
  is in the battle (`create`), at the campaign's current version (`v`): the
  battle is built from that version on every device, so a later joiner
  fetches that version (`GET /state?version=V`) if the campaign has moved on.
- Any other alive human seat may join an open room, army in the battle or
  not (a **guest**: it commands the units it is given; clients pass the
  campaign's other alive humans to `Lockstep.setup` as guests so they can be
  admitted and gifted units mid-battle). A guest cannot open a room
  (`not_in_battle` with `create`, `no_room` without) and never becomes the
  lobby host on entry.
- Opening takes the battle's claim in mode `live` (refused, `claimed`, if
  another device holds an ordinary claim; this device's own claim is turned
  into the live one). While the room has members the server renews the lease
  every 30 s (no client heartbeats); HTTP claims of the battle are refused
  (`claimed`, mode `live`). Opening pings the campaign's other alive humans
  on Discord ("X is asking you to join the battle at R now", deduplicated per 2
  minutes) and records `battle_live` activity.
- Lobby until the host sends `start`; the members present then take part from
  frame 0. Seats that took part are recorded in `battle_live`: each of them
  may upload the battle's result (`mayCommand`), also after the room closed,
  whoever's armies are in it; a live claim does not block their upload.
- Empty rooms are closed after a grace period (lobby 8 s; started
  `-room-grace` / `SC_ROOM_GRACE`, default 90 s), or 2 s after the
  battle's result was uploaded (members get `resolved` first), or when a turn
  upload or rollback removes the battle. Closing deletes the live claim, so
  the battle is an ordinary pending battle again; a half-played battle is
  not saved and restarts from the beginning.
- Roles: the host is the opener; if the host leaves or is dropped, the first
  connected member taking part becomes host (in the lobby, any connected
  member). "Host" only decides who is asked for snapshots and who uploads.
- One connection per seat: a second connection of the same seat (reconnect,
  other device) replaces the first.

### Messages

JSON text frames. After `auth` / `hello` the client sends
`{"t":"room","b":BATTLE,"v":VERSION,"create":bool,"scen":HASH,"keep":bool}`
(`scen`: the opener's hash of the built scenario, seed and command split,
which every joiner compares with its own build; `keep`: let the host keep
command of my army). Errors that end the attempt: `no_room`, `not_pending`,
`not_in_battle`, `stale`, `claimed`, `unauthorized`.

Server to client:

| Message | Fields | Meaning |
|---|---|---|
| `room` | `b, v, scen, host, started, you, seq, region, n, k, in, dropped, start?` | entered; `n`/`k` are this seat's last input number and mark the relay passed on (a reconnecting client continues from them), `start` the start item if started |
| `roster` | `host, started, seq, players[{f, on, in, dropped, joining, keep, silent_ms}]` | on every change of members or roles |
| `start` | `s, players[], host` | stream item: the battle starts; `players` take part from frame 0 |
| `in` | `s, p, n, k, o[]` | stream item: player `p`'s input message number `n`, mark `k` (no more inputs for frames `<= k`), inputs `o` (objects of integers, each with its frame `f`) |
| `drop` | `s, who, after, to, why` | stream item: `who` takes no part after frame `after` (their last relayed mark); their units go to `to` (-1: nobody); `why`: `continue` or `leave` |
| `replay` | `from, to, items[]` | stream items `from..to` (batches of 400), answering `replay` |
| `hash` | `p, fr, h` | player `p`'s lockstep hash at frame `fr` (not kept) |
| `snapreq` | `to` | please send a snapshot for player `to` |
| `snap` | `from, id, i, cnt, fr, ls, d` | snapshot chunk `i` of `cnt` (`d`: base64 piece, `fr`: frame, `ls`: last stream number in it) |
| `ready` | `p, keep` | player `p` has the battle running and asks to be admitted |
| `res` | `p, fr, h, up?` | player `p`'s result hash at the end; `up`: it is uploading the result |
| `resolved` | `b` | the result is in; the room closes |
| `pong` | `n, server_time` | answer to `ping` |
| `error` | `code, message, n?, k?` | `not_host`, `not_playing`, `out_of_order` (with the relay's `n`, `k`), `bad_input`, `bad_snapshot`, `replay_gone`, `no_snapshot`, `bad_continue`, `still_here`, `rate_limited`, `unknown` |

Client to server: `start` (host, lobby), `in {n, k, o}`, `hash {fr, h}`,
`res {fr, h, up?}`, `ready`, `snapreq`, `snap {id, to, i, cnt, fr, ls, d}`
(`to` -1: for the cache only), `replay {from}`, `continue {who}` (drop a
player who is disconnected or silent for 8 s; their units come to the
sender), `leave` (drop me, my units go to the host or another player taking
part), `ping {n}`.

**Stream:** `start`, `in` and `drop` carry the room's sequence number `s`
and go to every member, the sender included; clients apply them strictly in
`s` order and fill gaps with `replay`. Inputs are accepted only from players
taking part (or `joining`: said `ready` after a drop or a mid-battle join;
their first input marks them as taking part again), numbered `n = last + 1`,
with `k >= last k`. A refused input gets `out_of_order` with the relay's
counters; the client takes them and resyncs.

### Limits

256 KB per WebSocket message (snapshot chunks), 16 KB per input message, 128
inputs per message, 16 integer fields per input; 60 messages a second per
connection with a burst of 300 (400 a second in test mode, where frames run
5x faster and hash every frame); 4,096 queued outgoing messages per member
(a member that cannot keep up is disconnected and catches up after its
reconnect); stream buffer 20,000 items or 8 MB; snapshot 12 MB (base64);
a connection silent for 25 s is closed.

### Sizes and rates measured

A live battle at 1x sends about 12 messages a second per player (an input
message per 100 ms frame, a hash a second, a ping a second), each well under
200 bytes. A snapshot at 4,000 soldiers is about 86-89 KB (2,000: 36 KB; the
small test battles 15-30 KB), so 2-3 chunks; the host leaves one with the
relay every 30 s for reconnects when nobody else can send one.

## 18. Custom battle rooms

A live lockstep room (section 17) that is not tied to a campaign: two players
set up one battle together and fight it. Code:
`server/internal/server/custom.go` (endpoints, lobby, expiry), the relay is
`rooms.go`, the WebSocket loop `live.go` (shared with campaign rooms).
`/api/info` reports `api: 3` from here on (campaign live rooms still need
`>= 2`).

**The rule stays:** the server never reads the setup. It stores it as an
opaque JSON object, versions it (`rev`), and relays the lockstep exactly as
for a campaign room. Memory only: no database rows, no Discord, no claims,
no `battle_live`; a restart loses every custom room.

### Flow

1. Player 1 `POST /api/custom {setup, rules, build, invite?, name?}` ->
   `{code, token, seat: 0, rev: 1}`. The room exists, in the lobby, empty.
2. Player 2 `POST /api/custom/join {code}` -> `{code, token, seat: 1, rev,
   setup, rules, build, name}`. The code is typed like a campaign join code
   (any case, dashes and spaces ignored).
3. Both open `GET /api/custom/{code}/ws`: `{"t":"auth","token":...}` ->
   `{"t":"hello","f":SEAT,"server_time","api":3}`, then
   `{"t":"room","b":0,"v":0,"create":false,"scen":"","keep":bool}` (b, v,
   create, scen ignored) -> the room reply.
4. Lobby: either seat edits the setup (`setup`, compare-and-swap on `rev`),
   each says `lobby {ready, rev, scen}`; the host sends `start`.
5. From the `start` stream item on it is the section 17 relay unchanged
   (`in`, `hash`, `res`, `snapreq`/`snap`, `replay`, `ready` to join a
   running battle, `continue`, `leave`, `ping`; drops name `to`, the
   clients decide what happens to the units).

Seats: 0 = Player 1 (creator), 1 = Player 2 (joiner); they are the lockstep
player ids (`f`, `p`, `players`, `who`, `to`). In the lobby the host is seat
0 whenever it is connected, otherwise the connected seat; after the start the
section 17 handover applies. Tokens: 32 random bytes, only their SHA-256
kept, compared in constant time; one token per seat (no device codes).

### HTTP

| Call | Errors |
|---|---|
| `POST /api/custom` | 403 `invite_required` (as campaign creation), 429 `rate_limited` (the campaign creation limiter: 6 an hour per IP), 400 `bad_request` (setup missing or not a JSON object), 413 `too_large` (setup over 64 KB raw), 503 `busy` (1,000 custom rooms open) |
| `POST /api/custom/join` | 404 `bad_code` (no such room, or closed / expired; counts against the code-guess limiter, 10 per 15 min per IP), 409 `seat_taken` (seat 1 already claimed), 409 `started` (started without Player 2), 429 `rate_limited` |
| `GET /api/custom/{code}/ws` | bad token, unknown or closed code: closed with policy violation (counts against the code-guess limiter) |

### Messages (in addition to section 17)

| Message | Fields | Meaning |
|---|---|---|
| `room` (server) | section 17 fields (`b`: 0, `v`: rev, `scen`: "", `region`: 0) plus `custom: true, code, setup, rev, name, rules, build` | entered |
| `roster` (server) | section 17 fields plus `rev`; per player also `ready` (ready at the current rev), `scen` (the hash it reported) | both claimed seats always listed (`on: false` when not connected) |
| `setup` (client) | `rev` (the base), `setup{...}` | replace the setup if `rev` is current; lobby only |
| `setup` (server) | `rev, setup, by` | the new setup, to every member (the sender too); `by`: the seat that changed it, -1 when it is a resend after `conflict` |
| `lobby` (client) | `ready, rev, scen` | ready only counts if `rev` is current; `scen` (<= 64 chars): the client's hash of the battle it built; lobby only |
| `start` (stream) | `s, players[], host, rev` | `players`: the connected seats |
| `error` (server) | `conflict` (with the current `rev`, followed by a `setup` with the current setup), `started` (lobby message after the start), `too_large`, `bad_request`, `not_host`, `not_ready`, `scen_mismatch` | |

Lobby rules: a successful `setup` bumps `rev` and clears every seat's ready
flag and `scen`; a member that disconnects in the lobby loses its ready flag
and `scen` (it says `lobby` again after reconnecting). `start` (host only)
needs every connected member ready at the current `rev` with equal `scen`
hashes (`not_ready`, `scen_mismatch`); the host may start alone when the
other seat is not connected (Player 2 can still enter later and join the
running battle with `ready`, as a mid-battle join in section 17).

### Limits and expiry

| What | Value |
|---|---|
| setup | 64 KB raw (a JSON object), compacted when stored |
| empty lobby | closed after `-custom-ttl` / `SC_CUSTOM_TTL` (default 10 min) since it was last non-empty, or since creation if nobody entered |
| empty started room | closed after `-room-grace` / `SC_ROOM_GRACE` (default 90 s) |
| any room | closed 6 h after creation, members or not |
| rooms open | 1,000 custom rooms per server |
| WebSocket | as section 17 (sizes, rates, 25 s silence) |

A closed room is removed: its code answers `bad_code`, its tokens are
refused. Nothing about it is kept (logs only: `custom room created`,
`custom room joined`, `custom room started`, `custom room closed`, `ws
connected`).
