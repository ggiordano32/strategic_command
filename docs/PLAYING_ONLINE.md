# Playing online (for players)

How to play Strategic Command online co-op, choose or host a game server, and what browsers can and cannot join.

**Official server.** Online co-op and live battles use the official server
by default; you do not need to do anything. Create a campaign with Online
co-op, send the join code or link to your ally.

**Your own or a friend's server.** Main menu > Game server > Change, type or
paste the address (`https://games.example.com`, or `192.168.1.20:8060`
on a local network), Test, then Use this server. Use official goes back. A
join link from someone on another server (`...?join=ABC123&server=...`)
switches you to their server when you open it or paste it in Join.

**Hosting from your PC (desktop version only).** Main menu > Game server >
Host a server: choose a port (default 8060) and, if you like, an invite key,
then Start. Your game uses it at once. Give friends who also run the desktop
version the address shown (same network: the 192.168... address; other
networks: the public address, after forwarding the port on your router, or use
a tunnel like Tailscale). They enter it under Game server > Change. The
server stops when you close the game, and its data (campaigns) lives in the
game's user folder under `host/`.

**The HTTPS rule.** A browser (including the game on itch.io) can only join
servers with an `https://` address. A server started with Host a server is plain
HTTP, so browser players cannot join it: use the desktop version, or put the
server behind a domain with HTTPS (see the server README), or use the
official server.

## Running your own server

The game server also runs without the game, as a Docker image:
`ghcr.io/ggiordano32/strategic-command-server` (API and live relay only).
`server/README.md` explains it; a compose file is in `server/deploy/selfhost`
(profiles `scserver`, and `caddy` for HTTPS). Set `SC_ALLOWED_ORIGINS` so the
itch.io web build may call it (for example
`https://html-classic.itch.zone,https://*.itch.zone`), and give the server a
domain so Caddy can get it a certificate: browser players need HTTPS.
