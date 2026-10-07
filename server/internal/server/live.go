package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/coder/websocket"

	"strategiccommand/server/internal/store"
)

// ------------------------------------------------------------------ hub ---

// Hub tells long-polling clients when a campaign's change counter (seq)
// moves. One entry per campaign: the latest seq and a channel that is
// closed (and replaced) on every change.
type Hub struct {
	mu     sync.Mutex
	m      map[string]*hubEntry
	closed bool
	done   chan struct{}
}

type hubEntry struct {
	seq int64
	ch  chan struct{}
}

func NewHub() *Hub { return &Hub{m: map[string]*hubEntry{}, done: make(chan struct{})} }

// Notify records seq for campaign id and wakes its waiters.
func (h *Hub) Notify(id string, seq int64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	e := h.m[id]
	if e == nil {
		e = &hubEntry{ch: make(chan struct{})}
		h.m[id] = e
	}
	if seq > e.seq {
		e.seq = seq
	}
	close(e.ch)
	e.ch = make(chan struct{})
}

// watch returns the known seq (0 if unknown) and the channel to wait on.
func (h *Hub) watch(id string) (int64, chan struct{}) {
	h.mu.Lock()
	defer h.mu.Unlock()
	e := h.m[id]
	if e == nil {
		e = &hubEntry{ch: make(chan struct{})}
		h.m[id] = e
	}
	return e.seq, e.ch
}

func (h *Hub) setIfUnknown(id string, seq int64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if e := h.m[id]; e != nil && e.seq < seq {
		e.seq = seq
	}
}

// CloseAll wakes every waiter (shutdown).
func (h *Hub) CloseAll() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.closed {
		h.closed = true
		close(h.done)
	}
}

// GET /api/c/{id}/wait?since=N[&timeout=S]: long-poll. Answers at once if
// the campaign's change counter is above `since`, else when it changes or
// after `timeout` seconds (max 25), with {"seq": current}. Works through
// any proxy and in every browser (it is one ordinary request); clients loop.
func (s *Server) wait(w http.ResponseWriter, r *http.Request, seat Seat) {
	since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
	tmo := longPollMax
	if t, err := strconv.Atoi(r.URL.Query().Get("timeout")); err == nil && t >= 0 && time.Duration(t)*time.Second < tmo {
		tmo = time.Duration(t) * time.Second
	}
	cur, ch := s.hub.watch(seat.Campaign)
	if cur == 0 {
		var seq int64
		if err := s.db.QueryRowContext(r.Context(), "SELECT seq FROM campaigns WHERE id = ?", seat.Campaign).Scan(&seq); err != nil {
			s.failErr(w, err)
			return
		}
		s.hub.setIfUnknown(seat.Campaign, seq)
		cur, ch = s.hub.watch(seat.Campaign)
		if cur == 0 {
			cur = seq
		}
	}
	if cur <= since {
		t := time.NewTimer(tmo)
		select {
		case <-ch:
		case <-t.C:
		case <-r.Context().Done():
		case <-s.hub.done:
		}
		t.Stop()
		cur, _ = s.hub.watch(seat.Campaign)
	}
	reply(w, 200, map[string]any{"seq": cur, "server_time": ms(s.clock.Now())})
}

// ------------------------------------------------------------ websocket ---

// GET /api/c/{id}/ws: WebSocket. Browsers cannot set headers on a
// WebSocket, so the first message authenticates: {"t":"auth","token":...}
// -> {"t":"hello", f, server_time}. Then {"t":"ping","n":N} ->
// {"t":"pong","n":N,"server_time":ms} and {"t":"echo",...} -> the same
// message back (the browser self-test), and {"t":"room", b, v, create,
// scen, keep} enters the live room of battle b (rooms.go); every later
// message on the connection goes to that room. Text frames of JSON only.
// A connection that sends nothing for 25 s is closed (clients ping every
// second or two), so a phone that went to the background drops out of a
// room promptly.
func (s *Server) ws(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.serveWS(w, r, "auth:", func(ctx context.Context, tok string) (*wsPeer, bool) {
		seat, ok := s.checkToken(ctx, id, tok)
		if !ok {
			return nil, false
		}
		return &wsPeer{f: seat.F, tok: seat.TokenID, logKV: []any{"campaign", id, "f", seat.F},
			seen: func() { s.markSeen(seat) },
			enter: func(ctx context.Context, m *member, req roomMsg) (*Room, error) {
				return s.enterRoom(ctx, seat, m, req)
			}}, true
	})
}

// wsPeer is an authenticated WebSocket: its seat (the lockstep player id),
// how to mark it seen and how its {"t":"room"} message enters a room.
type wsPeer struct {
	f     int
	tok   int64
	logKV []any
	seen  func() // nil: nothing to record
	enter func(ctx context.Context, m *member, req roomMsg) (*Room, error)
}

// serveWS is the WebSocket loop shared by campaign and custom rooms: auth
// (failures count under failKey+IP in the code limiter), hello, the writer
// goroutine, rate bucket, read timeout, ping/echo, room entry, then every
// message to the room.
func (s *Server) serveWS(w http.ResponseWriter, r *http.Request, failKey string,
	auth func(ctx context.Context, tok string) (*wsPeer, bool)) {
	c, err := websocket.Accept(w, r, nil) // checks Origin against Host
	if err != nil {
		return
	}
	c.SetReadLimit(roomReadLimit)
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	go func() {
		select {
		case <-s.ctx.Done():
		case <-s.hub.done:
		case <-ctx.Done():
		}
		cancel()
	}()
	actx, acancel := context.WithTimeout(ctx, 10*time.Second)
	_, msg, err := c.Read(actx)
	acancel()
	if err != nil {
		c.Close(websocket.StatusPolicyViolation, "auth expected")
		return
	}
	var hello struct {
		T     string `json:"t"`
		Token string `json:"token"`
	}
	json.Unmarshal(msg, &hello)
	peer, ok := auth(ctx, hello.Token)
	if hello.T != "auth" || !ok {
		s.codeFail.Take(failKey + ipOf(r))
		c.Close(websocket.StatusPolicyViolation, "unauthorized")
		return
	}
	if peer.seen != nil {
		peer.seen()
	}
	// One writer goroutine per connection; everything else queues into out.
	now := s.clock.Now()
	// A live battle sends ~12 messages a second (an input per frame, a hash
	// a second, a ping); tests run frames 5x faster and hash every frame.
	rate := 60.0
	if s.cfg.TestMode {
		rate = 400
	}
	m := &member{f: peer.f, tok: peer.tok, out: make(chan []byte, 4096), kill: cancel, joined: now, lastMsg: now,
		limit: &connBucket{tokens: 300, max: 300, rate: rate, last: time.Now()}}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case b := <-m.out:
				wctx, wc := context.WithTimeout(ctx, 10*time.Second)
				err := c.Write(wctx, websocket.MessageText, b)
				wc()
				if err != nil {
					cancel()
					return
				}
			}
		}
	}()
	send := func(v any) {
		select {
		case m.out <- jsonb(v):
		default:
			cancel()
		}
	}
	send(map[string]any{"t": "hello", "f": peer.f, "server_time": ms(s.clock.Now()), "api": APIVersion})
	s.log.Info("ws connected", append(append([]any{}, peer.logKV...), "ip", ipOf(r))...)
	var room *Room
	defer func() {
		if room != nil {
			room.disconnected(m)
		}
		c.Close(websocket.StatusNormalClosure, "")
	}()
	lastSeen := time.Now()
	for {
		rctx, rc := context.WithTimeout(ctx, roomReadTimeout)
		typ, msg, err := c.Read(rctx)
		rc()
		if err != nil {
			return
		}
		if typ != websocket.MessageText {
			continue
		}
		if !m.limit.take(time.Now()) {
			send(map[string]any{"t": "error", "code": "rate_limited", "message": "too many messages"})
			continue
		}
		if peer.seen != nil && time.Since(lastSeen) > seenThrottle {
			lastSeen = time.Now()
			peer.seen()
		}
		var req roomMsg
		if json.Unmarshal(msg, &req) != nil {
			continue
		}
		if room != nil {
			room.handle(m, msg, req)
			continue
		}
		switch req.T {
		case "ping":
			send(map[string]any{"t": "pong", "n": req.N, "server_time": ms(s.clock.Now())})
		case "echo":
			if len(msg) <= 64<<10 {
				select {
				case m.out <- msg:
				default:
				}
			}
		case "room":
			rm, err := peer.enter(ctx, m, req)
			if err != nil {
				var ae *apiError
				if errors.As(err, &ae) {
					e := map[string]any{"t": "error", "code": ae.code, "message": ae.msg}
					for k, v := range ae.extra {
						e[k] = v
					}
					send(e)
				} else {
					s.log.Error("room entry", "err", err)
					send(map[string]any{"t": "error", "code": "internal", "message": "internal error"})
				}
				continue
			}
			room = rm
		default:
			send(map[string]any{"t": "error", "code": "unknown", "message": "unknown message type"})
		}
	}
}

// ------------------------------------------------------------- sessions ---

// GET /api/c/{id}/session: this seat's opaque session blob.
func (s *Server) getSession(w http.ResponseWriter, r *http.Request, seat Seat) {
	var blob []byte
	var rev int
	err := s.db.QueryRowContext(r.Context(), "SELECT session, session_rev FROM seats WHERE campaign_id = ? AND f = ?",
		seat.Campaign, seat.F).Scan(&blob, &rev)
	if err != nil {
		s.failErr(w, err)
		return
	}
	data := []byte("null")
	if len(blob) > 0 {
		if d, err := store.Gunzip(blob, maxSessionRaw); err == nil {
			data = d
		}
	}
	b := append([]byte(`{"rev":`+strconv.Itoa(rev)+`,"data":`), data...)
	b = append(b, '}')
	writeJSONBytes(w, r, b)
}

// POST /api/c/{id}/session {data, rev?}: replace it (last writer wins; if
// rev is given it must match the stored revision, else 409).
func (s *Server) putSession(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		Data json.RawMessage `json:"data"`
		Rev  *int            `json:"rev"`
	}
	if err := readJSON(w, r, maxSessionRaw+1024, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if len(req.Data) == 0 {
		req.Data = json.RawMessage("null")
	}
	var rev int
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		var cur int
		if err := tx.QueryRowContext(ctx, "SELECT session_rev FROM seats WHERE campaign_id = ? AND f = ?", seat.Campaign, seat.F).Scan(&cur); err != nil {
			return err
		}
		if req.Rev != nil && *req.Rev != cur {
			e := errf(http.StatusConflict, "conflict", "the session was changed on another device")
			e.extra = map[string]any{"rev": cur}
			return e
		}
		rev = cur + 1
		_, err := tx.ExecContext(ctx, "UPDATE seats SET session = ?, session_rev = ? WHERE campaign_id = ? AND f = ?",
			store.Gzip(req.Data), rev, seat.Campaign, seat.F)
		return err
	})
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			fail(w, http.StatusNotFound, "not_found", "no such seat")
			return
		}
		s.failErr(w, err)
		return
	}
	reply(w, 200, map[string]any{"ok": true, "rev": rev})
}
