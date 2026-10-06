package server

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"time"
)

// Custom battle rooms: a live lockstep room that is not tied to a campaign.
// A host creates it from a setup (an opaque JSON object the clients build
// the battle from) and gets a 6-character code; the friend joins by code;
// both see and edit the setup in a lobby (compare-and-swap on its revision),
// say ready, the host starts, and from then on it is the ordinary live room
// relay (rooms.go). Memory only: no database rows, no Discord. The server
// never reads the setup. Seats: 0 = the creator (Player 1), 1 = the joiner
// (Player 2); they double as the lockstep player ids. Documented in
// docs/SERVER.md section 18.

const (
	customSeats    = 2
	customSetupMax = 64 << 10
	customMaxAge   = 6 * time.Hour
	customMaxRooms = 1000
)

func customKey(code string) string { return "custom/" + code }

// cleanSetup checks a setup (a JSON object of at most 64 KB) and compacts it.
func cleanSetup(raw json.RawMessage) (json.RawMessage, *apiError) {
	if len(raw) > customSetupMax {
		return nil, errf(http.StatusRequestEntityTooLarge, "too_large", "the setup is larger than 64 KB")
	}
	t := bytes.TrimSpace(raw)
	if len(t) == 0 || t[0] != '{' || !json.Valid(t) {
		return nil, errf(http.StatusBadRequest, "bad_request", "setup must be a JSON object")
	}
	var buf bytes.Buffer
	if err := json.Compact(&buf, t); err != nil {
		return nil, errf(http.StatusBadRequest, "bad_request", "setup must be a JSON object")
	}
	return buf.Bytes(), nil
}

// customRoom finds an open custom room by typed code (nil: none).
func (s *Server) customRoom(code string) *Room {
	code = NormCode(code)
	if len(code) != joinCodeLen {
		return nil
	}
	s.rooms.mu.Lock()
	r := s.rooms.m[customKey(code)]
	s.rooms.mu.Unlock()
	if r == nil || !r.custom {
		return nil
	}
	return r
}

// POST /api/custom {setup, rules, build, invite?, name?} -> {code, token, seat: 0, rev: 1}
func (s *Server) createCustom(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Setup  json.RawMessage `json:"setup"`
		Rules  string          `json:"rules"`
		Build  string          `json:"build"`
		Invite string          `json:"invite"`
		Name   string          `json:"name"`
	}
	if err := readJSON(w, r, customSetupMax+8<<10, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if s.cfg.InviteKey != "" && subtle.ConstantTimeCompare([]byte(req.Invite), []byte(s.cfg.InviteKey)) != 1 {
		s.codeFail.Take("invite:" + ipOf(r))
		fail(w, http.StatusForbidden, "invite_required", "this server needs an invite key to create battles")
		return
	}
	if !s.createLimit.Allow(ipOf(r)) {
		fail(w, http.StatusTooManyRequests, "rate_limited", "too many rooms created from this address")
		return
	}
	setup, ae := cleanSetup(req.Setup)
	if ae != nil {
		s.failErr(w, ae)
		return
	}
	tok := randomToken()
	now := s.clock.Now()
	rm := &Room{s: s, custom: true, setup: setup, rev: 1, name: clip(req.Name, 64), rules: clip(req.Rules, 64),
		build: clip(req.Build, 128), host: 0, created: now, emptyAt: now, members: map[int]*member{},
		parts: map[int]*part{}, hashes: map[int64]map[int]string{}, lobbyReady: map[int]int{}, scens: map[int]string{}}
	rm.toks[0] = tokenHash(tok)
	s.rooms.mu.Lock()
	n := 0
	for _, o := range s.rooms.m {
		if o.custom {
			n++
		}
	}
	if n >= customMaxRooms {
		s.rooms.mu.Unlock()
		fail(w, http.StatusServiceUnavailable, "busy", "too many custom battles open on this server")
		return
	}
	for {
		rm.code = randomCode(joinCodeLen)
		rm.key = customKey(rm.code)
		if s.rooms.m[rm.key] == nil {
			break
		}
	}
	s.rooms.m[rm.key] = rm
	s.rooms.mu.Unlock()
	s.log.Info("custom room created", "code", rm.code, "bytes", len(setup), "rules", rm.rules, "ip", ipOf(r))
	reply(w, 200, map[string]any{"code": rm.code, "token": tok, "seat": 0, "rev": 1})
}

// POST /api/custom/join {code} -> {code, token, seat: 1, rev, setup, rules, build, name}
func (s *Server) joinCustom(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code string `json:"code"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if !s.codeGuard(w, r) {
		return
	}
	rm := s.customRoom(req.Code)
	badCode := func() {
		s.codeFail.Take("code:" + ipOf(r))
		fail(w, http.StatusNotFound, "bad_code", "no open battle with that code")
	}
	if rm == nil {
		badCode()
		return
	}
	rm.mu.Lock()
	if rm.closed {
		rm.mu.Unlock()
		badCode()
		return
	}
	if rm.toks[1] != "" {
		rm.mu.Unlock()
		fail(w, http.StatusConflict, "seat_taken", "somebody already joined this battle")
		return
	}
	if rm.started {
		rm.mu.Unlock()
		fail(w, http.StatusConflict, "started", "this battle has already started")
		return
	}
	tok := randomToken()
	rm.toks[1] = tokenHash(tok)
	out := map[string]any{"code": rm.code, "token": tok, "seat": 1, "rev": rm.rev, "setup": rm.setup,
		"rules": rm.rules, "build": rm.build, "name": rm.name}
	rm.roster()
	rm.mu.Unlock()
	s.log.Info("custom room joined", "code", rm.code, "ip", ipOf(r))
	reply(w, 200, out)
}

// checkCustomToken: the room and seat a token belongs to.
func (s *Server) checkCustomToken(code, tok string) (*Room, int, bool) {
	if tok == "" || len(tok) > 200 {
		return nil, 0, false
	}
	rm := s.customRoom(code)
	if rm == nil {
		return nil, 0, false
	}
	want := []byte(tokenHash(tok))
	rm.mu.Lock()
	defer rm.mu.Unlock()
	if rm.closed {
		return nil, 0, false
	}
	f, ok := 0, false
	for i, h := range rm.toks {
		if h != "" && subtle.ConstantTimeCompare([]byte(h), want) == 1 {
			f, ok = i, true
		}
	}
	return rm, f, ok
}

// GET /api/custom/{code}/ws: the same WebSocket as /api/c/{id}/ws, the seat
// token of the custom room authenticates.
func (s *Server) wsCustom(w http.ResponseWriter, r *http.Request) {
	code := NormCode(r.PathValue("code"))
	s.serveWS(w, r, "code:", func(ctx context.Context, tok string) (*wsPeer, bool) {
		rm, f, ok := s.checkCustomToken(code, tok)
		if !ok {
			return nil, false
		}
		return &wsPeer{f: f, logKV: []any{"custom", code, "f", f},
			enter: func(ctx context.Context, m *member, req roomMsg) (*Room, error) {
				return rm.enterCustom(m, req)
			}}, true
	})
}

// enterCustom handles {"t":"room",...} on a custom room's WebSocket (b, v,
// create and scen are ignored; keep is kept).
func (r *Room) enterCustom(m *member, req roomMsg) (*Room, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		return nil, errf(http.StatusConflict, "closed", "the room closed")
	}
	f := m.f
	if old := r.members[f]; old != nil {
		old.kill()
	}
	m.keep = req.Keep
	r.members[f] = m
	r.emptyAt = time.Time{}
	if !r.started {
		// In the lobby Player 1 hosts whenever connected.
		if _, ok := r.members[r.host]; !ok || f == 0 {
			r.host = f
		}
	}
	p := r.parts[f]
	reply := map[string]any{"t": "room", "b": 0, "v": r.rev, "scen": "", "host": r.host, "started": r.started,
		"you": f, "seq": r.seq, "region": 0, "custom": true, "code": r.code, "setup": r.setup, "rev": r.rev,
		"name": r.name, "rules": r.rules, "build": r.build}
	if p != nil {
		reply["n"] = p.lastN
		reply["k"] = p.lastK
		reply["in"] = p.in
		reply["dropped"] = p.dropped
	} else {
		reply["n"] = 0
		reply["k"] = -1
		reply["in"] = false
		reply["dropped"] = false
	}
	if r.startItem != nil {
		reply["start"] = json.RawMessage(r.startItem)
	}
	r.sendTo(m, jsonb(reply))
	r.roster()
	return r, nil
}

// customSetup (locked): {"t":"setup","rev":BASE,"setup":{...}}.
func (r *Room) customSetup(m *member, req roomMsg) {
	if r.started {
		r.errorTo(m, "started", "the battle has started")
		return
	}
	if req.Rev == nil || *req.Rev != r.rev {
		r.sendTo(m, jsonb(map[string]any{"t": "error", "code": "conflict", "rev": r.rev,
			"message": "the setup was changed meanwhile"}))
		r.sendTo(m, jsonb(map[string]any{"t": "setup", "rev": r.rev, "setup": r.setup, "by": -1}))
		return
	}
	setup, ae := cleanSetup(req.Setup)
	if ae != nil {
		r.errorTo(m, ae.code, ae.msg)
		return
	}
	r.setup = setup
	r.rev++
	r.lobbyReady = map[int]int{}
	r.scens = map[int]string{}
	r.broadcast(jsonb(map[string]any{"t": "setup", "rev": r.rev, "setup": r.setup, "by": m.f}), -1)
	r.roster()
}

// customLobby (locked): {"t":"lobby","ready":bool,"rev":N,"scen":HASH}.
func (r *Room) customLobby(m *member, req roomMsg) {
	if r.started {
		r.errorTo(m, "started", "the battle has started")
		return
	}
	if req.Ready && req.Rev != nil && *req.Rev == r.rev {
		r.lobbyReady[m.f] = r.rev
	} else {
		delete(r.lobbyReady, m.f)
	}
	r.scens[m.f] = clip(req.Scen, 64)
	r.roster()
}

// customCanStart (locked): every connected member is ready at the current
// revision and reported the same scenario hash.
func (r *Room) customCanStart(m *member) bool {
	scen, first := "", true
	for f := range r.members {
		if rv, ok := r.lobbyReady[f]; !ok || rv != r.rev {
			r.errorTo(m, "not_ready", "every player must be ready with the current setup")
			return false
		}
	}
	for f := range r.members {
		if first {
			scen, first = r.scens[f], false
		} else if r.scens[f] != scen {
			r.errorTo(m, "scen_mismatch", "the players built different battles from the setup")
			return false
		}
	}
	return true
}

// customSweep closes a custom room that has been empty too long (lobby:
// CustomTTL, started: RoomGrace) or is older than 6 hours.
func (s *Server) customSweep(r *Room, now time.Time) {
	r.mu.Lock()
	ttl := s.cfg.CustomTTL
	if r.started {
		ttl = s.cfg.RoomGrace
	}
	why := ""
	switch {
	case now.Sub(r.created) >= customMaxAge:
		why = "max_age"
	case len(r.members) == 0 && !r.emptyAt.IsZero() && now.Sub(r.emptyAt) >= ttl:
		why = "empty"
	}
	r.mu.Unlock()
	if why == "" {
		return
	}
	s.rooms.mu.Lock()
	if s.rooms.m[r.key] == r {
		delete(s.rooms.m, r.key)
	}
	s.rooms.mu.Unlock()
	r.close(why)
}
