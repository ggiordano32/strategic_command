# Strategic Command game server

The game server for Strategic Command: campaign storage and turn
bookkeeping, the live co-op battle relay, optional Discord notifications.
One Go binary (`scserver`) with SQLite, no other services. It never runs
game rules; the game clients do. Full reference: `docs/SERVER.md`.

You need your own server only to host games for friends yourself. The
default server is built into the game as the default.

## Run it

```sh
docker run -d --name sc --restart unless-stopped -p 8060:8060 -v sc-data:/data \
  ghcr.io/ggiordano32/strategic-command-server:latest
curl http://localhost:8060/api/info
```

Or with compose (`server/deploy/selfhost/`, copy `.env.example` to `.env`):

```sh
docker compose --profile scserver up -d   # plain HTTP on port 8060
docker compose --profile caddy up -d      # HTTPS on your domain (SC_DOMAIN)
```

The image has no web build: players use the game from itch.io or the
desktop version, and point it at your address.

## Settings (environment variables)

| Variable | Meaning |
|---|---|
| `SC_INVITE_KEY` | If set, players need this key to create a campaign (joining needs none). |
| `SC_ALLOWED_ORIGINS` | Web pages allowed to use this server from another site: comma list of origins, or `*`. Needed for browser players on itch.io. The desktop game needs nothing. Default: none. |
| `SC_GAME_URL` | Shown on the server's front page ("the game is at ..."). |
| `SC_DOMAIN` | Compose `caddy` profile only: the domain to get a certificate for. |

For the game on itch.io, set `SC_ALLOWED_ORIGINS=https://html-classic.itch.zone,https://*.itch.zone`.
itch.io serves HTML5 uploads from `html-classic.itch.zone` (itch staff say it
is stable and advise allowing `itch.zone` generally, hence the wildcard).
An entry like `https://*.itch.zone` matches any subdomain with that scheme
and port, not the bare `itch.zone`.
`*` allows any site; it is safe for the API (players authenticate with a
token, not cookies) but lets any web page talk to your server.
Other options (ports, backup interval, ...) are in `docs/SERVER.md` section 2.

## Reaching your server

- **Friends on the desktop game** join by address, plain HTTP is fine:
  `http://<your address>:8060`. On your own network use the LAN address.
  Over the internet, forward TCP port 8060 on your router to the machine,
  or use a tunnel such as Tailscale (nothing to forward).
- **Browser players** can only join **HTTPS** servers (the browser refuses
  plain HTTP from an HTTPS page). You need a domain pointing at your
  machine and a reverse proxy with a certificate: the compose `caddy`
  profile does this (ports 80 and 443 must be reachable; set `SC_DOMAIN`).
  Without a domain, browser friends cannot join; use the desktop version.

## Data and backups

Everything is in the `/data` volume: `campaigns.db` (SQLite), `backups/`,
`playtest_logs/`. A backup is written every 6 hours (12 kept). Take one now:

```sh
docker exec sc /usr/local/bin/scserver -backup-now
docker run --rm -v sc-data:/data -v "$PWD":/out alpine sh -c 'cp /data/backups/* /out/'
```

(The server image has no shell; the second command copies from the volume
with a helper container.) To restore, stop the server and put a backup
file at `/data/campaigns.db`, owned by uid 65532.

## Updating

```sh
docker pull ghcr.io/ggiordano32/strategic-command-server:latest
docker rm -f sc && docker run ...        # same -v sc-data:/data, data is kept
# compose: docker compose pull && docker compose --profile scserver up -d
```

Update between turns: live battles in progress are lost on restart. The
game and the server must be for the same version of the game:
`/api/info` reports `state_version`, and the game warns when it differs.

## Build it yourself

From the repository root:

```sh
docker build -f server/Dockerfile --target server -t strategic-command-server .
cd server && go test ./... && CGO_ENABLED=0 go build ./cmd/scserver
```
