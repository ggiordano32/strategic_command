package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"sync"
	"time"
)

// Live co-op battle rooms (milestone 5): a relay for deterministic lockstep.
// Both clients run the battle sim; only their inputs travel. A room is one
// pending battle of one campaign, opened over the campaign's WebSocket by a
// human seat whose army is in the battle (the host), joined by the other.
//
// The server never runs the sim and trusts clients only as far as auth: it
// checks who may be in the room, that each player's input messages are
// numbered without gaps and their marks never go back, sizes and rates. It
// stamps a room sequence number on every stream item (start, inputs, drop
// events), sends every item to every member (the sender included), keeps
// the last items for reconnects (replay), caches the latest snapshot sent
// by a client, decides roles (host, who is dropped) and relays the rest
// (hashes, snapshot requests and chunks, ready, results) without keeping
// it. A room holds the battle's claim (mode "live") for as long as any
// member is connected (the lease is renewed here, no client heartbeats);
// when the room empties for good it is closed and the battle is an ordinary
// pending battle again. The protocol is described in docs/SERVER.md.

const (
	roomReadLimit   = 256 << 10 // one WebSocket message in a room (snapshot chunks)
	roomInMax       = 16 << 10  // one input message
	roomOrdersMax   = 128       // inputs in one message
	roomBufItems    = 20000     // stream items kept for replay ...
	roomBufBytes    = 8 << 20   // ... and at most this many bytes
	roomSnapMax     = 12 << 20  // one snapshot (base64 chunks)
	roomChunkMax    = 200 << 10 // one snapshot chunk
	roomReplayBatch = 400       // stream items per replay message
	roomSilent      = 8 * time.Second
	roomReadTimeout = 25 * time.Second
	roomRenewEvery  = 30 * time.Second
	roomHashKeep    = 256
	roomLobbyGrace  = 8 * time.Second
)

// Rooms is every open room, by "campaign/battle".
type Rooms struct {
	mu sync.Mutex
	m  map[string]*Room
}

func newRooms() *Rooms { return &Rooms{m: map[string]*Room{}} }

func roomKey(cid string, bid int) string { return cid + "/" + strconv.Itoa(bid) }

// Room is one live battle.
type Room struct {
	s        *Server
	key      string
	campaign string
	battle   int
	region   int
	version  int    // campaign state version the battle is built from
	scen     string // the opener's hash of the built scenario (clients compare)

	mu        sync.Mutex
	host      int
	started   bool
	created   time.Time
	startedAt time.Time
	seq       int64
	members   map[int]*member
	parts     map[int]*part
	buf       []bufItem
	bufBytes  int
	startItem []byte
	snap      *snapCache
	building  *snapCache
	hashes    map[int64]map[int]string
	desyncs   int
	closed    bool
	emptyAt   time.Time
	renewedAt time.Time

	// Custom battle rooms (custom.go): not tied to a campaign, memory only.
	custom     bool
	code       string
	setup      json.RawMessage
	rev        int
	name       string
	rules      string
	build      string
	toks       [customSeats]string // SHA-256 of each seat's token ("": unclaimed)
	lobbyReady map[int]int         // seat -> rev it is ready at (absent: not ready)
	scens      map[int]string      // seat -> scenario hash it reported
}

type member struct {
	f       int
	tok     int64
	out     chan []byte
	kill    func()
	joined  time.Time
	lastMsg time.Time
	keep    bool
	limit   *connBucket
}

type part struct {
	lastN   int64
	lastK   int64
	in      bool // takes part (not dropped, or admitted again)
	dropped bool
	joining bool // said ready after a drop or a mid-battle join
	lastIn  time.Time
}

type bufItem struct {
	s int64
	b []byte
}

type snapCache struct {
	id     string
	from   int
	fr, ls int64
	cnt    int
	chunks [][]byte
	size   int
	at     time.Time
}

// bucket is a small token bucket (per connection; no locking needed: one
// reader goroutine per connection).
type connBucket struct {
	tokens, max, rate float64
	last              time.Time
}

func (b *connBucket) take(now time.Time) bool {
	b.tokens += now.Sub(b.last).Seconds() * b.rate
	if b.tokens > b.max {
		b.tokens = b.max
	}
	b.last = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// roomMsg is every field a client message to a room may carry.
type roomMsg struct {
	T      string          `json:"t"`
	B      int             `json:"b"`
	V      int             `json:"v"`
	Create bool            `json:"create"`
	Scen   string          `json:"scen"`
	Keep   bool            `json:"keep"`
	N      int64           `json:"n"`
	K      *int64          `json:"k"`
	O      json.RawMessage `json:"o"`
	Fr     int64           `json:"fr"`
	H      string          `json:"h"`
	ID     string          `json:"id"`
	To     *int            `json:"to"`
	I      int             `json:"i"`
	Cnt    int             `json:"cnt"`
	LS     int64           `json:"ls"`
	D      string          `json:"d"`
	From   int64           `json:"from"`
	Who    *int            `json:"who"`
	Ms     int             `json:"ms"`
	Rev    *int            `json:"rev"`
	Setup  json.RawMessage `json:"setup"`
	Ready  bool            `json:"ready"`
}

func jsonb(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

// ----------------------------------------------------------------- entry ---

// enterRoom handles {"t":"room", b, v, create, scen, keep}: the seat must be
// a human whose army is in pending battle b of the campaign, at state
// version v. create opens the room if there is none (the claim must be
// free, or this device's own, or another live claim of this room). Any
// other alive human seat may join a room that is open (a guest: no army of
// its own there, it commands the units it is given) but never opens one.
func (s *Server) enterRoom(ctx context.Context, seat Seat, m *member, req roomMsg) (*Room, error) {
	c, err := loadCamp(ctx, s.db, seat.Campaign)
	if err != nil {
		return nil, err
	}
	b := c.battle(req.B)
	if b == nil {
		return nil, errf(http.StatusConflict, "not_pending", "battle %d is not pending", req.B)
	}
	inBattle := hasInt(b.Humans, seat.F)
	if !inBattle && !hasInt(c.Alive, seat.F) {
		return nil, errf(http.StatusForbidden, "not_in_battle", "your army is not in this battle")
	}
	// Lock order: never take a room lock while holding the database (the
	// one SQLite connection), so the claim is taken with no lock held.
	key := roomKey(seat.Campaign, req.B)
	s.rooms.mu.Lock()
	r := s.rooms.m[key]
	if r != nil && r.version != c.Version {
		// The campaign moved on under an empty or stale room.
		r.mu.Lock()
		empty := len(r.members) == 0
		r.mu.Unlock()
		if empty {
			delete(s.rooms.m, key)
			go r.close("stale")
			r = nil
		}
	}
	s.rooms.mu.Unlock()
	if r == nil {
		if !inBattle {
			if req.Create {
				return nil, errf(http.StatusForbidden, "not_in_battle", "your army is not in this battle: join when your ally opens it")
			}
			return nil, errf(http.StatusNotFound, "no_room", "nobody is fighting this battle live")
		}
		if !req.Create {
			return nil, errf(http.StatusNotFound, "no_room", "nobody is fighting this battle live")
		}
		if req.V != c.Version {
			return nil, errf(http.StatusConflict, "stale", "the campaign is at version %d", c.Version)
		}
		if err := s.claimLive(ctx, c, b, seat); err != nil {
			return nil, err
		}
		now := s.clock.Now()
		nr := &Room{s: s, key: key, campaign: seat.Campaign, battle: req.B, region: b.R, version: c.Version,
			scen: clip(req.Scen, 64), host: seat.F, created: now, members: map[int]*member{}, parts: map[int]*part{},
			hashes: map[int64]map[int]string{}, renewedAt: now}
		s.rooms.mu.Lock()
		if r = s.rooms.m[key]; r == nil {
			// (Two openers at once: the first one's room is used.)
			r = nr
			s.rooms.m[key] = r
			s.log.Info("room opened", "room", key, "host", seat.F, "version", c.Version)
			go s.roomOpened(c, b, seat)
		}
		s.rooms.mu.Unlock()
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		return nil, errf(http.StatusConflict, "closed", "the room closed; try again")
	}
	if old := r.members[seat.F]; old != nil {
		// The same seat again (reconnect, or another device): the newest wins.
		old.kill()
	}
	m.f = seat.F
	m.tok = seat.TokenID
	m.keep = req.Keep
	r.members[seat.F] = m
	r.emptyAt = time.Time{}
	if _, ok := r.members[r.host]; !ok && !r.started && inBattle {
		r.host = seat.F
	}
	p := r.parts[seat.F]
	reply := map[string]any{"t": "room", "b": r.battle, "v": r.version, "scen": r.scen, "host": r.host,
		"started": r.started, "you": seat.F, "seq": r.seq, "region": r.region}
	if p != nil {
		reply["n"] = p.lastN
		reply["k"] = p.lastK
		reply["in"] = p.in
		reply["dropped"] = p.dropped
	} else {
		reply["n"] = 0
		reply["k"] = -1
		reply["in"] = false
	}
	if r.startItem != nil {
		reply["start"] = json.RawMessage(r.startItem)
	}
	r.sendTo(m, jsonb(reply))
	r.roster()
	go s.roomChanged(r.campaign)
	return r, nil
}

// claimLive takes the battle's claim for the room (mode "live"): refused if
// another device holds an ordinary claim on it.
func (s *Server) claimLive(ctx context.Context, c *campRow, b *Battle, seat Seat) error {
	return s.db.Tx(ctx, func(tx *sql.Tx) error {
		now := ms(s.clock.Now())
		var holder int64
		var hf int
		var hu int64
		var hmode string
		err := tx.QueryRowContext(ctx, "SELECT token_id, f, lease_until, mode FROM battle_claims WHERE campaign_id = ? AND battle_id = ?",
			c.ID, b.ID).Scan(&holder, &hf, &hu, &hmode)
		if err == nil && hu > now && holder != seat.TokenID && hmode != "live" {
			e := errf(http.StatusConflict, "claimed", "%s is already resolving this battle", c.faction(hf))
			e.extra = map[string]any{"held_by": hf, "mode": hmode}
			return e
		}
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO battle_claims (campaign_id, battle_id, f, token_id, mode, claimed_at, lease_until)
			VALUES (?, ?, ?, ?, 'live', ?, ?) ON CONFLICT (campaign_id, battle_id) DO UPDATE SET f = excluded.f,
			token_id = excluded.token_id, mode = 'live', claimed_at = excluded.claimed_at, lease_until = excluded.lease_until`,
			c.ID, b.ID, seat.F, seat.TokenID, now, now+s.cfg.LeaseDuration.Milliseconds())
		return err
	})
}

// roomOpened: activity, the allies' Discord ping (every other alive human:
// anyone may join, army in the battle or not), the long-poll bump.
func (s *Server) roomOpened(c *campRow, b *Battle, seat Seat) {
	ctx := s.ctx
	ob := &outbox{}
	var seq int64
	s.db.Tx(ctx, func(tx *sql.Tx) error {
		now := s.clock.Now()
		seats, _ := loadSeats(ctx, tx, c.ID)
		var others []int
		for _, f := range c.Alive {
			if f != seat.F {
				others = append(others, f)
			}
		}
		if len(others) > 0 {
			key := fmt.Sprintf("ping:b%d:%d:%d", b.ID, seat.F, now.UnixMilli()/pingBucket.Milliseconds())
			s.note(ctx, tx, ob, c, seats, key, "ping_battle",
				fmt.Sprintf("%s is asking you to join the battle at %s now.", c.faction(seat.F), c.region(b.R)), others)
		}
		addActivity(ctx, tx, c.ID, ms(now), seat.F, "battle_live", map[string]any{"battle": b.ID, "region": b.R})
		var err error
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if seq > 0 {
		s.hub.Notify(c.ID, seq)
	}
	s.flush(ob)
}

// roomChanged bumps the campaign's change counter so long-polling clients
// refetch the summary (which shows who is in each live battle).
func (s *Server) roomChanged(cid string) {
	var seq int64
	s.db.Tx(s.ctx, func(tx *sql.Tx) error {
		var err error
		seq, err = bumpSeq(s.ctx, tx, cid)
		return err
	})
	if seq > 0 {
		s.hub.Notify(cid, seq)
	}
}

// liveInfo is the summary's view of battle bid's room (nil: none).
func (s *Server) liveInfo(cid string, bid int) map[string]any {
	s.rooms.mu.Lock()
	r := s.rooms.m[roomKey(cid, bid)]
	s.rooms.mu.Unlock()
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		return nil
	}
	state := "lobby"
	since := r.created
	if r.started {
		state = "live"
		since = r.startedAt
	}
	return map[string]any{"state": state, "host": r.host, "since": ms(since), "players": r.players(), "version": r.version}
}

// hasRoom: a live room exists for the battle (ordinary claims are refused).
func (s *Server) hasRoom(cid string, bid int) bool {
	s.rooms.mu.Lock()
	defer s.rooms.mu.Unlock()
	return s.rooms.m[roomKey(cid, bid)] != nil
}

// ----------------------------------------------------------- messages ---

// sendTo queues b for one member; a member that cannot keep up is cut off
// (it reconnects and catches up by replay or snapshot).
func (r *Room) sendTo(m *member, b []byte) {
	select {
	case m.out <- b:
	default:
		r.s.log.Warn("room member too slow, disconnecting", "room", r.key, "f", m.f)
		m.kill()
	}
}

func (r *Room) broadcast(b []byte, except int) {
	for f, m := range r.members {
		if f != except {
			r.sendTo(m, b)
		}
	}
}

// stream stamps, keeps and sends a stream item. fill is the item without
// "s"; the stamped bytes are returned.
func (r *Room) stream(item map[string]any) []byte {
	r.seq++
	item["s"] = r.seq
	b := jsonb(item)
	r.buf = append(r.buf, bufItem{s: r.seq, b: b})
	r.bufBytes += len(b)
	for len(r.buf) > roomBufItems || r.bufBytes > roomBufBytes {
		r.bufBytes -= len(r.buf[0].b)
		r.buf = r.buf[1:]
	}
	r.broadcast(b, -1)
	return b
}

func (r *Room) players() []map[string]any {
	fs := map[int]bool{}
	for f := range r.members {
		fs[f] = true
	}
	for f := range r.parts {
		fs[f] = true
	}
	if r.custom {
		for f, h := range r.toks {
			if h != "" {
				fs[f] = true
			}
		}
	}
	var list []int
	for f := range fs {
		list = append(list, f)
	}
	sort.Ints(list)
	now := r.s.clock.Now()
	out := []map[string]any{}
	for _, f := range list {
		m := r.members[f]
		p := r.parts[f]
		e := map[string]any{"f": f, "on": m != nil, "in": p != nil && p.in, "dropped": p != nil && p.dropped,
			"joining": p != nil && p.joining}
		if m != nil {
			e["keep"] = m.keep
			e["silent_ms"] = now.Sub(m.lastMsg).Milliseconds()
		}
		if r.custom {
			rv, ok := r.lobbyReady[f]
			e["ready"] = ok && rv == r.rev
			e["scen"] = r.scens[f]
		}
		out = append(out, e)
	}
	return out
}

func (r *Room) roster() {
	msg := map[string]any{"t": "roster", "host": r.host, "started": r.started, "players": r.players(), "seq": r.seq}
	if r.custom {
		msg["rev"] = r.rev
	}
	r.broadcast(jsonb(msg), -1)
}

func (r *Room) errorTo(m *member, code, msg string) {
	r.sendTo(m, jsonb(map[string]any{"t": "error", "code": code, "message": msg}))
}

// handle one message from member m (the connection's reader goroutine).
func (r *Room) handle(m *member, raw []byte, req roomMsg) {
	now := r.s.clock.Now()
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed || r.members[m.f] != m {
		return
	}
	m.lastMsg = now
	switch req.T {
	case "start":
		if r.started {
			return
		}
		if m.f != r.host {
			r.errorTo(m, "not_host", "only the host starts the battle")
			return
		}
		if r.custom && !r.customCanStart(m) {
			return
		}
		r.started = true
		r.startedAt = now
		var ps []int
		for f := range r.members {
			ps = append(ps, f)
			r.parts[f] = &part{lastK: -1, in: true, lastIn: now}
		}
		sort.Ints(ps)
		item := map[string]any{"t": "start", "players": ps, "host": r.host}
		if r.custom {
			item["rev"] = r.rev
		}
		r.startItem = r.stream(item)
		r.roster()
		if r.custom {
			r.s.log.Info("custom room started", "code", r.code, "players", ps, "rev", r.rev)
			return
		}
		r.s.log.Info("room started", "room", r.key, "players", ps)
		go r.s.tookPart(r.campaign, r.battle, ps...)
		go r.s.setHost(r.campaign, r.battle, r.host, m.tok)
		go r.s.roomChanged(r.campaign)
	case "in":
		p := r.parts[m.f]
		if !r.started || p == nil || !(p.in || p.joining) {
			r.errorTo(m, "not_playing", "you are not taking part in the battle")
			return
		}
		if len(raw) > roomInMax || req.K == nil {
			r.errorTo(m, "bad_input", "input message too large or without a mark")
			return
		}
		if req.N != p.lastN+1 || *req.K < p.lastK {
			// The client lost track (a message refused or never sent): it
			// continues from the relay's counters and resyncs.
			r.sendTo(m, jsonb(map[string]any{"t": "error", "code": "out_of_order", "n": p.lastN, "k": p.lastK,
				"message": fmt.Sprintf("expected message %d with mark >= %d", p.lastN+1, p.lastK)}))
			return
		}
		orders, ok := cleanOrders(req.O)
		if !ok {
			r.errorTo(m, "bad_input", "inputs must be a list of objects of integers")
			return
		}
		p.lastN = req.N
		p.lastK = *req.K
		p.lastIn = now
		if p.joining {
			// A (re)joining player sends inputs only once admitted.
			p.joining = false
			p.in = true
			p.dropped = false
			defer r.roster()
			if !r.custom {
				go r.s.tookPart(r.campaign, r.battle, m.f)
			}
		}
		r.stream(map[string]any{"t": "in", "p": m.f, "n": req.N, "k": *req.K, "o": orders})
	case "hash":
		r.checkHash(m.f, req.Fr, clip(req.H, 16))
		r.broadcast(jsonb(map[string]any{"t": "hash", "p": m.f, "fr": req.Fr, "h": clip(req.H, 16)}), m.f)
	case "res":
		r.broadcast(jsonb(map[string]any{"t": "res", "p": m.f, "fr": req.Fr, "h": clip(req.H, 16)}), m.f)
	case "ready":
		p := r.parts[m.f]
		if !r.started {
			return
		}
		if p == nil {
			p = &part{lastK: -1}
			r.parts[m.f] = p
		}
		if !p.in {
			p.joining = true
			p.dropped = false
		}
		r.broadcast(jsonb(map[string]any{"t": "ready", "p": m.f, "keep": m.keep}), -1)
		r.roster()
	case "snapreq":
		r.snapRequest(m)
	case "snap":
		r.snapChunk(m, raw, req)
	case "replay":
		r.replay(m, req.From)
	case "continue":
		if req.Who == nil {
			return
		}
		who := *req.Who
		p := r.parts[who]
		me := r.parts[m.f]
		if p == nil || !p.in || who == m.f || me == nil || !me.in {
			r.errorTo(m, "bad_continue", "that player is not in the battle")
			return
		}
		om := r.members[who]
		if om != nil && now.Sub(om.lastMsg) < roomSilent {
			r.errorTo(m, "still_here", "that player is still connected")
			return
		}
		r.drop(who, m.f, "continue")
	case "leave":
		p := r.parts[m.f]
		if r.started && p != nil && p.in {
			to := -1
			if r.host != m.f && r.parts[r.host] != nil && r.parts[r.host].in {
				to = r.host
			} else {
				for f, q := range r.parts {
					if f != m.f && q.in && (to < 0 || r.members[f] != nil) {
						to = f
					}
				}
			}
			r.drop(m.f, to, "leave")
		}
		delete(r.members, m.f)
		r.memberGone(m.f)
		m.kill()
	case "ping":
		r.sendTo(m, jsonb(map[string]any{"t": "pong", "n": req.N, "server_time": ms(now)}))
	case "setup":
		if !r.custom {
			r.errorTo(m, "unknown", "unknown message type")
			return
		}
		r.customSetup(m, req)
	case "lobby":
		if !r.custom {
			r.errorTo(m, "unknown", "unknown message type")
			return
		}
		r.customLobby(m, req)
	default:
		r.errorTo(m, "unknown", "unknown message type")
	}
}

// cleanOrders checks a list of inputs: objects with short keys and integer
// values only (the relay does not interpret them).
func cleanOrders(raw json.RawMessage) ([]map[string]int64, bool) {
	if len(raw) == 0 || string(raw) == "null" {
		return []map[string]int64{}, true
	}
	var list []map[string]json.Number
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if err := d.Decode(&list); err != nil || len(list) > roomOrdersMax {
		return nil, false
	}
	out := make([]map[string]int64, 0, len(list))
	for _, o := range list {
		if len(o) > 16 {
			return nil, false
		}
		c := make(map[string]int64, len(o))
		for k, v := range o {
			if len(k) > 12 {
				return nil, false
			}
			n, err := v.Int64()
			if err != nil {
				return nil, false
			}
			c[k] = n
		}
		out = append(out, c)
	}
	return out, true
}

// drop: player who no longer takes part after their last mark; their units
// go to player `to` (-1: nobody). Host moves to `to` if the host dropped.
func (r *Room) drop(who, to int, why string) {
	p := r.parts[who]
	if p == nil || !p.in {
		return
	}
	p.in = false
	p.dropped = true
	p.joining = false
	r.stream(map[string]any{"t": "drop", "who": who, "after": p.lastK, "to": to, "why": why})
	r.s.log.Info("room drop", "room", r.key, "who", who, "after", p.lastK, "to", to, "why", why)
	if r.host == who {
		r.pickHost(who)
	}
	r.roster()
}

// pickHost: a connected player who takes part, else any connected member.
func (r *Room) pickHost(not int) {
	best := -1
	for f, m := range r.members {
		if f == not || m == nil {
			continue
		}
		if p := r.parts[f]; p != nil && p.in {
			best = f
			break
		}
		if best < 0 {
			best = f
		}
	}
	if best >= 0 && best != r.host {
		r.host = best
		if m := r.members[best]; m != nil && r.started && !r.custom {
			go r.s.setHost(r.campaign, r.battle, best, m.tok)
		}
	}
}

// memberGone (locked): roster, host handover in the lobby, empty time.
func (r *Room) memberGone(f int) {
	if r.host == f && !r.started {
		r.pickHost(f)
	}
	if len(r.members) == 0 {
		r.emptyAt = r.s.clock.Now()
	}
	if r.custom {
		if !r.started {
			// Ready flags are for the members present; a returning member
			// says ready again.
			delete(r.lobbyReady, f)
			delete(r.scens, f)
		}
		r.roster()
		return
	}
	r.roster()
	go r.s.roomChanged(r.campaign)
}

// disconnected is called when a member's connection ends.
func (r *Room) disconnected(m *member) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.members[m.f] != m {
		return
	}
	delete(r.members, m.f)
	r.memberGone(m.f)
}

func (r *Room) checkHash(f int, fr int64, h string) {
	hs := r.hashes[fr]
	if hs == nil {
		hs = map[int]string{}
		r.hashes[fr] = hs
		if len(r.hashes) > roomHashKeep {
			for k := range r.hashes {
				if k < fr-roomHashKeep {
					delete(r.hashes, k)
				}
			}
		}
	}
	hs[f] = h
	for of, oh := range hs {
		if of != f && oh != h {
			r.desyncs++
			if r.desyncs <= 20 {
				r.s.log.Warn("LIVE DESYNC", "room", r.key, "frame", fr, "a", f, "ha", h, "b", of, "hb", oh)
			}
		}
	}
}

// ----------------------------------------------------------- snapshots ---

// snapRequest: ask a player who has the battle running (the host first) for
// a snapshot for m; without one, serve the cached snapshot.
func (r *Room) snapRequest(m *member) {
	ask := -1
	if hm := r.members[r.host]; hm != nil && r.host != m.f {
		if p := r.parts[r.host]; p != nil && p.in && r.s.clock.Now().Sub(hm.lastMsg) < roomSilent {
			ask = r.host
		}
	}
	if ask < 0 {
		for f, om := range r.members {
			if p := r.parts[f]; f != m.f && p != nil && p.in && r.s.clock.Now().Sub(om.lastMsg) < roomSilent {
				ask = f
				break
			}
		}
	}
	if ask >= 0 {
		r.sendTo(r.members[ask], jsonb(map[string]any{"t": "snapreq", "to": m.f}))
		return
	}
	if r.snap != nil {
		for _, c := range r.snap.chunks {
			r.sendTo(m, c)
		}
		return
	}
	r.errorTo(m, "no_snapshot", "nobody can send the battle right now")
}

// snapChunk relays one chunk {id, to, i, cnt, fr, ls, d} to its requester
// (to = -1: for the cache only) and caches complete snapshots.
func (r *Room) snapChunk(m *member, raw []byte, req roomMsg) {
	p := r.parts[m.f]
	if p == nil || !p.in || req.Cnt <= 0 || req.I < 0 || req.I >= req.Cnt || len(req.D) > roomChunkMax ||
		req.Cnt*roomChunkMax > roomSnapMax*2 || len(req.ID) > 40 {
		r.errorTo(m, "bad_snapshot", "bad snapshot chunk")
		return
	}
	to := -1
	if req.To != nil {
		to = *req.To
	}
	out := jsonb(map[string]any{"t": "snap", "from": m.f, "id": req.ID, "i": req.I, "cnt": req.Cnt, "fr": req.Fr,
		"ls": req.LS, "d": req.D})
	if to >= 0 {
		if tm := r.members[to]; tm != nil {
			r.sendTo(tm, out)
		}
	}
	if req.I == 0 {
		r.building = &snapCache{id: req.ID, from: m.f, fr: req.Fr, ls: req.LS, cnt: req.Cnt}
	}
	b := r.building
	if b == nil || b.id != req.ID || b.from != m.f || len(b.chunks) != req.I {
		return
	}
	b.chunks = append(b.chunks, out)
	b.size += len(req.D)
	if b.size > roomSnapMax {
		r.building = nil
		return
	}
	if len(b.chunks) == b.cnt {
		b.at = r.s.clock.Now()
		r.snap = b
		r.building = nil
	}
}

// replay sends the stream items from sequence `from` on, in batches; if
// the buffer no longer reaches back that far: error "replay_gone" (the
// client then asks for a snapshot).
func (r *Room) replay(m *member, from int64) {
	if from < 1 {
		from = 1
	}
	if from > r.seq {
		r.sendTo(m, jsonb(map[string]any{"t": "replay", "from": from, "to": r.seq, "items": []json.RawMessage{}}))
		return
	}
	if len(r.buf) == 0 || r.buf[0].s > from {
		r.errorTo(m, "replay_gone", "those messages are no longer kept")
		return
	}
	i := sort.Search(len(r.buf), func(i int) bool { return r.buf[i].s >= from })
	for i < len(r.buf) {
		j := i + roomReplayBatch
		if j > len(r.buf) {
			j = len(r.buf)
		}
		items := make([]json.RawMessage, 0, j-i)
		for _, it := range r.buf[i:j] {
			items = append(items, it.b)
		}
		r.sendTo(m, jsonb(map[string]any{"t": "replay", "from": r.buf[i].s, "to": r.buf[j-1].s, "items": items}))
		i = j
	}
}

// ---------------------------------------------------------- lifecycle ---

// close (rooms lock held or room removed): wake members, free the claim.
func (r *Room) close(why string) {
	r.mu.Lock()
	if r.closed {
		r.mu.Unlock()
		return
	}
	r.closed = true
	for _, m := range r.members {
		m.kill()
	}
	r.members = map[int]*member{}
	r.mu.Unlock()
	if r.custom {
		r.s.log.Info("custom room closed", "code", r.code, "why", why)
		return
	}
	r.s.log.Info("room closed", "room", r.key, "why", why)
	go func() {
		r.s.db.Exec("DELETE FROM battle_claims WHERE campaign_id = ? AND battle_id = ? AND mode = 'live'", r.campaign, r.battle)
		r.s.roomChanged(r.campaign)
	}()
}

// setHost moves the live claim to the host's device.
func (s *Server) setHost(cid string, bid, f int, tok int64) {
	now := ms(s.clock.Now())
	s.db.Exec("UPDATE battle_claims SET f = ?, token_id = ?, lease_until = ? WHERE campaign_id = ? AND battle_id = ? AND mode = 'live'",
		f, tok, now+s.cfg.LeaseDuration.Milliseconds(), cid, bid)
}

// tookPart records seats that played in a live battle: each may upload its
// result (mayCommand), also after the room has closed.
func (s *Server) tookPart(cid string, bid int, fs ...int) {
	for _, f := range fs {
		s.db.Exec("INSERT OR IGNORE INTO battle_live (campaign_id, battle_id, f) VALUES (?, ?, ?)", cid, bid, f)
	}
}

// roomLoop: renew the leases of rooms with members, close rooms that have
// been empty for the grace period (or whose battle is no longer pending).
func (s *Server) roomLoop() {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-t.C:
		}
		s.roomSweep()
	}
}

func (s *Server) roomSweep() {
	now := s.clock.Now()
	s.rooms.mu.Lock()
	var all []*Room
	for _, r := range s.rooms.m {
		all = append(all, r)
	}
	s.rooms.mu.Unlock()
	for _, r := range all {
		if r.custom {
			s.customSweep(r, now)
			continue
		}
		r.mu.Lock()
		empty := len(r.members) == 0
		grace := s.cfg.RoomGrace
		if !r.started && grace > roomLobbyGrace {
			grace = roomLobbyGrace // an abandoned lobby goes quickly
		}
		expired := empty && !r.emptyAt.IsZero() && now.Sub(r.emptyAt) >= grace
		renew := !empty && now.Sub(r.renewedAt) >= roomRenewEvery
		var hostTok int64
		if hm := r.members[r.host]; hm != nil {
			hostTok = hm.tok
		}
		host := r.host
		if renew {
			r.renewedAt = now
		}
		r.mu.Unlock()
		if !expired && !renew {
			// Battle resolved meanwhile (result uploaded): close.
			continue
		}
		if expired {
			s.rooms.mu.Lock()
			if s.rooms.m[r.key] == r {
				delete(s.rooms.m, r.key)
			}
			s.rooms.mu.Unlock()
			r.close("empty")
			continue
		}
		until := ms(now) + s.cfg.LeaseDuration.Milliseconds()
		if hostTok != 0 {
			s.db.Exec("UPDATE battle_claims SET lease_until = ?, f = ?, token_id = ? WHERE campaign_id = ? AND battle_id = ? AND mode = 'live'",
				until, host, hostTok, r.campaign, r.battle)
		} else {
			s.db.Exec("UPDATE battle_claims SET lease_until = ? WHERE campaign_id = ? AND battle_id = ? AND mode = 'live'",
				until, r.campaign, r.battle)
		}
	}
}

// battleResolved closes the battle's room once its result is in (called
// after a battle upload commits).
func (s *Server) battleResolved(cid string, bid int) {
	s.rooms.mu.Lock()
	r := s.rooms.m[roomKey(cid, bid)]
	if r != nil {
		delete(s.rooms.m, r.key)
	}
	s.rooms.mu.Unlock()
	if r != nil {
		r.mu.Lock()
		r.broadcast(jsonb(map[string]any{"t": "resolved", "b": bid}), -1)
		r.mu.Unlock()
		// Let the members read "resolved" before their sockets close.
		time.AfterFunc(2*time.Second, func() { r.close("resolved") })
	}
}

// closeRoomsOf closes every room of a campaign (rollback, stale states).
func (s *Server) closeRoomsOf(cid string, keep map[int]bool) {
	s.rooms.mu.Lock()
	var gone []*Room
	for k, r := range s.rooms.m {
		if r.campaign == cid && !keep[r.battle] {
			gone = append(gone, r)
			delete(s.rooms.m, k)
		}
	}
	s.rooms.mu.Unlock()
	for _, r := range gone {
		r.close("battle gone")
	}
}
