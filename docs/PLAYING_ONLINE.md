# Playing online (for players)

How to play Strategic Command online co-op, choose or host a game server, and what browsers can and cannot join.

**The default server.** A fresh install has a game server address built in,
so online co-op and live battles work without any setup. It is one person's
own server (the game's author's), like any you could host: there is no public
relay. Create a campaign with Online co-op and send the join code or link to
your ally.

**A friend's server.** Main menu > Game server > Join a friend's server >
Change, type or paste the address (`https://games.example.com`, or
`192.168.1.20:8060` on a local network), Test, then Use this server. Use
default goes back to the built-in address. A join link from someone on another
server (`...?join=ABC123&server=...`) switches you to their server when you
open it or paste it in Join.

**Hosting from your PC (desktop version only).** Main menu > Game server >
Host a server: choose a port (default 8060) and, if you like, an invite key,
then Start. Your game uses it at once, and friends on the same network can join
with the 192.168... address shown. For friends elsewhere the game first asks
your router to open the port (UPnP; the "Open port with UPnP" box, on by
default). When that works the panel says "Port opened on your router (UPnP)"
and shows the address to give friends. If the router refuses (many do, or have
UPnP off), the panel says so with a Try again button: forward TCP port 8060 to
your PC on the router yourself, or use a tunnel like Tailscale and give friends
its address. Friends enter the address under Game server > Change. The server
stops when you close the game (the router mapping is removed), and its data
(campaigns) lives in the game's user folder under `host/`.

**The HTTPS rule.** A browser (including the game on itch.io) can only join
servers with an `https://` address. A server started with Host a server is plain
HTTP, so browser players cannot join it: use the desktop version, or put the
server behind a domain with HTTPS (see the server README), or use the
default server.

## Running your own server

The game server also runs without the game, as a Docker image:
`ghcr.io/ggiordano32/strategic-command-server` (API and live relay only).
`server/README.md` explains it; a compose file is in `server/deploy/selfhost`
(profiles `scserver`, and `caddy` for HTTPS). Set `SC_ALLOWED_ORIGINS` so the
itch.io web build may call it (for example
`https://html-classic.itch.zone,https://*.itch.zone`), and give the server a
domain so Caddy can get it a certificate: browser players need HTTPS.
