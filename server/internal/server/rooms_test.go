package server

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// wsc is a test WebSocket client: every message it receives is kept.
type wsc struct {
	t    *testing.T
	c    *websocket.Conn
	ctx  context.Context
	stop context.CancelFunc
	mu   sync.Mutex
	msgs []map[string]any
	read int // messages already returned by next()
	done chan struct{}
}

func (e *env) dial(cid, tok string) *wsc {
	e.t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	url := "ws" + strings.TrimPrefix(e.ts.URL, "http") + "/api/c/" + cid + "/ws"
	c, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		e.t.Fatal(err)
	}
	c.SetReadLimit(4 << 20)
	w := &wsc{t: e.t, c: c, ctx: ctx, stop: cancel, done: make(chan struct{})}
	go func() {
		defer close(w.done)
		for {
			_, b, err := c.Read(ctx)
			if err != nil {
				return
			}
			var m map[string]any
			json.Unmarshal(b, &m)
			w.mu.Lock()
			w.msgs = append(w.msgs, m)
			w.mu.Unlock()
		}
	}()
	w.send(map[string]any{"t": "auth", "token": tok})
	w.next("hello")
	e.t.Cleanup(func() { w.close() })
	return w
}

func (w *wsc) send(v any) {
	w.t.Helper()
	b, _ := json.Marshal(v)
	if err := w.c.Write(w.ctx, websocket.MessageText, b); err != nil {
		w.t.Fatalf("write: %v", err)
	}
}

func (w *wsc) close() {
	w.c.Close(websocket.StatusNormalClosure, "")
	w.stop()
}

// next returns the next unread message of type typ (skipping others).
func (w *wsc) next(typ string) map[string]any {
	w.t.Helper()
	end := time.Now().Add(5 * time.Second)
	for time.Now().Before(end) {
		w.mu.Lock()
		for w.read < len(w.msgs) {
			m := w.msgs[w.read]
			w.read++
			if m["t"] == typ {
				w.mu.Unlock()
				return m
			}
		}
		w.mu.Unlock()
		time.Sleep(5 * time.Millisecond)
	}
	w.t.Fatalf("no %q message; got %v", typ, w.all())
	return nil
}

// stream returns every stream item (start, in, drop) received, in order.
func (w *wsc) stream() []map[string]any {
	w.mu.Lock()
	defer w.mu.Unlock()
	var out []map[string]any
	for _, m := range w.msgs {
		if m["t"] == "start" || m["t"] == "in" || m["t"] == "drop" {
			out = append(out, m)
		}
	}
	return out
}

func (w *wsc) all() []map[string]any {
	w.mu.Lock()
	defer w.mu.Unlock()
	return append([]map[string]any{}, w.msgs...)
}

func (w *wsc) waitStream(n int) []map[string]any {
	w.t.Helper()
	end := time.Now().Add(5 * time.Second)
	for time.Now().Before(end) {
		if s := w.stream(); len(s) >= n {
			return s
		}
		time.Sleep(5 * time.Millisecond)
	}
	w.t.Fatalf("stream has %d items, want %d", len(w.stream()), n)
	return nil
}

// battleCampaign: a campaign in the battles phase with battle 1 holding
// both humans' armies and battle 2 Rome's alone; version 2.
func (e *env) battleCampaign() camp {
	e.t.Helper()
	c := e.newCampaign(0, true)
	p := "/api/c/" + c.id
	e.submit(c, c.tokA, 1, 0, 0)
	e.submit(c, c.tokB, 1, 0, 1)
	ri := e.must2(e.call("GET", p+"/resolve-input", c.tokA, nil))
	b1 := tbattle{ID: 1, R: 1, Armies: map[int]int{1: 0, 100001: 1}, DefF: 4}
	b2 := tbattle{ID: 2, R: 2, Armies: map[int]int{2: 0}, DefF: 5}
	e.must2(e.upload(c, c.tokB, 1, "turn", battleState(1, b1, b2), map[string]any{"subs_rev": ri["subs_rev"]}))
	return c
}

func in(n, k int, orders ...map[string]any) map[string]any {
	if orders == nil {
		orders = []map[string]any{}
	}
	return map[string]any{"t": "in", "n": n, "k": k, "o": orders}
}

func TestRoomEntryAndAuth(t *testing.T) {
	e := newEnv(t, nil)
	c := e.battleCampaign()
	a := e.dial(c.id, c.tokA)
	// No room yet, not creating.
	a.send(map[string]any{"t": "room", "b": 1, "v": 2})
	if m := a.next("error"); m["code"] != "no_room" {
		t.Fatalf("join without a room: %v", m)
	}
	// Stale version.
	a.send(map[string]any{"t": "room", "b": 1, "v": 1, "create": true})
	if m := a.next("error"); m["code"] != "stale" {
		t.Fatalf("stale version: %v", m)
	}
	// Not pending.
	a.send(map[string]any{"t": "room", "b": 9, "v": 2, "create": true})
	if m := a.next("error"); m["code"] != "not_pending" {
		t.Fatalf("battle not pending: %v", m)
	}
	// Carthage's army is not in battle 2.
	b := e.dial(c.id, c.tokB)
	b.send(map[string]any{"t": "room", "b": 2, "v": 2, "create": true})
	if m := b.next("error"); m["code"] != "not_in_battle" {
		t.Fatalf("not in battle: %v", m)
	}
	// A bad token never gets a hello.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	url := "ws" + strings.TrimPrefix(e.ts.URL, "http") + "/api/c/" + c.id + "/ws"
	conn, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	conn.Write(ctx, websocket.MessageText, []byte(`{"t":"auth","token":"`+c.tokA+`x"}`))
	if _, _, err := conn.Read(ctx); websocket.CloseStatus(err) != websocket.StatusPolicyViolation {
		t.Fatalf("bad token: %v", err)
	}
	// A battle claimed by an ordinary (auto-resolve) claim cannot go live.
	e.must2(e.call("POST", "/api/c/"+c.id+"/battles/2/claim", c.tokA, map[string]any{"mode": "auto"}))
	a2 := e.dial(c.id, c.tokA)
	// (Same device: its own claim may be turned into a live room.)
	a2.send(map[string]any{"t": "room", "b": 2, "v": 2, "create": true})
	if m := a2.next("room"); m["host"] == nil {
		t.Fatalf("own claim -> room: %v", m)
	}
}

func TestRoomTwoPeersOrdering(t *testing.T) {
	e := newEnv(t, nil)
	c := e.battleCampaign()
	p := "/api/c/" + c.id
	a := e.dial(c.id, c.tokA)
	a.send(map[string]any{"t": "room", "b": 1, "v": 2, "create": true, "scen": "abc"})
	ra := a.next("room")
	if num64(ra["host"]) != 0 || ra["started"] != false || ra["scen"] != "abc" {
		t.Fatalf("room reply: %v", ra)
	}
	// The room holds the claim; an HTTP claim is refused; the summary shows it.
	if st, out := e.call("POST", p+"/battles/1/choice", c.tokB, map[string]any{"choice": "command"}); st != 200 {
		t.Fatalf("choice: %d %v", st, out)
	}
	if st, out := e.call("POST", p+"/battles/1/claim", c.tokB, map[string]any{"mode": "fight"}); st != 409 {
		t.Fatalf("claim of a live battle: %d %v", st, out)
	}
	sum := e.must2(e.call("GET", p, c.tokB, nil))
	live := sum["battles"].([]any)[0].(map[string]any)["live"].(map[string]any)
	if live["state"] != "lobby" || num64(live["host"]) != 0 {
		t.Fatalf("summary live: %v", live)
	}
	// Ally pinged ("asking you to join").
	e.waitSeq("Rome is asking you to join the battle at Etruria now")
	b := e.dial(c.id, c.tokB)
	b.send(map[string]any{"t": "room", "b": 1, "v": 2})
	rb := b.next("room")
	if num64(rb["host"]) != 0 || num64(rb["you"]) != 1 {
		t.Fatalf("peer room reply: %v", rb)
	}
	ros := a.next("roster")
	_ = ros
	// Input before the start, and a start by the non-host: refused.
	b.send(in(1, 3))
	if m := b.next("error"); m["code"] != "not_playing" {
		t.Fatalf("input before start: %v", m)
	}
	b.send(map[string]any{"t": "start"})
	if m := b.next("error"); m["code"] != "not_host" {
		t.Fatalf("start by the peer: %v", m)
	}
	a.send(map[string]any{"t": "start"})
	sa := a.next("start")
	sb := b.next("start")
	if num64(sa["s"]) != 1 || num64(sb["s"]) != 1 || len(sa["players"].([]any)) != 2 {
		t.Fatalf("start items: %v %v", sa, sb)
	}
	// Interleaved inputs from both: both see one identical sequence.
	for i := 1; i <= 40; i++ {
		a.send(in(i, i+3, map[string]any{"type": 1, "unit": i % 5, "x": 1000 * i, "f": i + 3}))
		b.send(in(i, i+2))
	}
	sa2 := a.waitStream(81)
	sb2 := b.waitStream(81)
	for i := range sa2 {
		ja, _ := json.Marshal(sa2[i])
		jb, _ := json.Marshal(sb2[i])
		if string(ja) != string(jb) || num64(sa2[i]["s"]) != i+1 {
			t.Fatalf("item %d differs: %s vs %s", i, ja, jb)
		}
	}
	// Gaps, marks going back and non-integer inputs are refused.
	a.send(in(42, 50))
	if m := a.next("error"); m["code"] != "out_of_order" {
		t.Fatalf("gap: %v", m)
	}
	a.send(in(41, 10))
	if m := a.next("error"); m["code"] != "out_of_order" {
		t.Fatalf("mark back: %v", m)
	}
	a.send(map[string]any{"t": "in", "n": 41, "k": 50, "o": []any{map[string]any{"type": 1.5}}})
	if m := a.next("error"); m["code"] != "bad_input" {
		t.Fatalf("float input: %v", m)
	}
	a.send(map[string]any{"t": "in", "n": 41, "k": 50, "o": []any{map[string]any{"type": "x"}}})
	if m := a.next("error"); m["code"] != "bad_input" {
		t.Fatalf("string input: %v", m)
	}
	// Hashes are relayed to the other player only.
	a.send(map[string]any{"t": "hash", "fr": 10, "h": "deadbeef"})
	if m := b.next("hash"); m["h"] != "deadbeef" || num64(m["p"]) != 0 {
		t.Fatalf("hash relay: %v", m)
	}
	// The summary says live with both in.
	sum = e.must2(e.call("GET", p, c.tokB, nil))
	live = sum["battles"].([]any)[0].(map[string]any)["live"].(map[string]any)
	if live["state"] != "live" || len(live["players"].([]any)) != 2 {
		t.Fatalf("summary live after start: %v", live)
	}
	// The host uploads the result (it holds the live claim, so no "take
	// command" is needed); the room is told and closes; the claim is gone.
	e.must2(e.upload(c, c.tokA, 2, "battle", battleState(1, tbattle{ID: 2, R: 2, Armies: map[int]int{2: 0}, DefF: 5}),
		map[string]any{"battle_id": 1, "outcome": map[string]any{"winner": 0}}))
	b.next("resolved")
	var n int
	time.Sleep(2500 * time.Millisecond)
	e.srv.db.QueryRow("SELECT COUNT(*) FROM battle_claims WHERE campaign_id = ? AND battle_id = 1", c.id).Scan(&n)
	if n != 0 || e.srv.hasRoom(c.id, 1) {
		t.Fatalf("room / claim left after the result: claims %d room %v", n, e.srv.hasRoom(c.id, 1))
	}
}

func TestRoomReconnectDropSnapshot(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.RoomGrace = 5 * time.Second })
	c := e.battleCampaign()
	a := e.dial(c.id, c.tokA)
	a.send(map[string]any{"t": "room", "b": 1, "v": 2, "create": true})
	a.next("room")
	b := e.dial(c.id, c.tokB)
	b.send(map[string]any{"t": "room", "b": 1, "v": 2})
	b.next("room")
	a.send(map[string]any{"t": "start"})
	b.next("start")
	for i := 1; i <= 5; i++ {
		a.send(in(i, i+3))
		b.send(in(i, i+3))
	}
	b.waitStream(11)
	// B's connection goes; A keeps sending; A sees B offline in the roster.
	b.close()
	<-b.done
	for i := 6; i <= 10; i++ {
		a.send(in(i, i+3))
	}
	a.waitStream(16)
	// Continue while B is merely quiet but connected is refused: here B is
	// gone, so it is accepted.
	a.send(map[string]any{"t": "continue", "who": 1})
	drop := a.next("drop")
	if num64(drop["who"]) != 1 || num64(drop["after"]) != 8 || num64(drop["to"]) != 0 {
		t.Fatalf("drop event: %v", drop)
	}
	// B comes back: told its counters; replay brings every missed item.
	b2 := e.dial(c.id, c.tokB)
	b2.send(map[string]any{"t": "room", "b": 1, "v": 2})
	rb := b2.next("room")
	if num64(rb["n"]) != 5 || num64(rb["k"]) != 8 || rb["in"] != false || rb["dropped"] != true || rb["start"] == nil {
		t.Fatalf("reconnect reply: %v", rb)
	}
	b2.send(map[string]any{"t": "replay", "from": 12})
	rp := b2.next("replay")
	items := rp["items"].([]any)
	if num64(rp["from"]) != 12 || len(items) != 6 || num64(items[5].(map[string]any)["s"]) != 17 {
		t.Fatalf("replay: from %v, %d items: %v", rp["from"], len(items), rp)
	}
	// Dropped: inputs refused until ready.
	b2.send(in(6, 20))
	if m := b2.next("error"); m["code"] != "not_playing" {
		t.Fatalf("input while dropped: %v", m)
	}
	// Snapshot: B asks, A is asked, A sends two chunks, B gets them.
	b2.send(map[string]any{"t": "snapreq"})
	if m := a.next("snapreq"); num64(m["to"]) != 1 {
		t.Fatalf("snapreq to host: %v", m)
	}
	for i := 0; i < 2; i++ {
		a.send(map[string]any{"t": "snap", "id": "s1", "to": 1, "i": i, "cnt": 2, "fr": 30, "ls": 17, "d": fmt.Sprintf("chunk%d", i)})
	}
	s0 := b2.next("snap")
	s1 := b2.next("snap")
	if s0["d"] != "chunk0" || s1["d"] != "chunk1" || num64(s1["ls"]) != 17 {
		t.Fatalf("snapshot chunks: %v %v", s0, s1)
	}
	b2.send(map[string]any{"t": "ready"})
	if m := a.next("ready"); num64(m["p"]) != 1 {
		t.Fatalf("ready relay: %v", m)
	}
	b2.send(in(6, 40))
	got := b2.waitStream(1)
	last := got[len(got)-1]
	if last["t"] != "in" || num64(last["p"]) != 1 || num64(last["n"]) != 6 {
		t.Fatalf("input after ready: %v", last)
	}
	// A leaves: its units go to B, B becomes host; the cached snapshot
	// serves the next request.
	a.send(map[string]any{"t": "leave"})
	d2 := b2.next("drop")
	if num64(d2["who"]) != 0 || num64(d2["to"]) != 1 {
		t.Fatalf("leave drop: %v", d2)
	}
	ros := b2.next("roster")
	for num64(ros["host"]) != 1 {
		ros = b2.next("roster")
	}
	b3 := e.dial(c.id, c.tokA)
	b3.send(map[string]any{"t": "room", "b": 1, "v": 2})
	b3.next("room")
	b3.send(map[string]any{"t": "snapreq"})
	// B is in the battle and connected: B is asked.
	if m := b2.next("snapreq"); num64(m["to"]) != 0 {
		t.Fatalf("snapreq to the new host: %v", m)
	}
	b2.close()
	<-b2.done
	time.Sleep(50 * time.Millisecond)
	b3.send(map[string]any{"t": "snapreq"})
	c0 := b3.next("snap")
	if c0["d"] != "chunk0" {
		t.Fatalf("cached snapshot: %v", c0)
	}
	// Empty room: closed after the grace, claim released.
	b3.close()
	<-b3.done
	time.Sleep(50 * time.Millisecond)
	e.clock.Advance(6 * time.Second)
	e.srv.roomSweep()
	time.Sleep(100 * time.Millisecond)
	if e.srv.hasRoom(c.id, 1) {
		t.Fatal("empty room not closed")
	}
	var n int
	e.srv.db.QueryRow("SELECT COUNT(*) FROM battle_claims WHERE campaign_id = ? AND battle_id = 1", c.id).Scan(&n)
	if n != 0 {
		t.Fatal("claim left after the room closed")
	}
}

func TestRoomLeaseRenewal(t *testing.T) {
	e := newEnv(t, nil)
	c := e.battleCampaign()
	a := e.dial(c.id, c.tokA)
	a.send(map[string]any{"t": "room", "b": 1, "v": 2, "create": true})
	a.next("room")
	var until0, until1 int64
	e.srv.db.QueryRow("SELECT lease_until FROM battle_claims WHERE campaign_id = ? AND battle_id = 1", c.id).Scan(&until0)
	for i := 0; i < 5; i++ {
		e.clock.Advance(40 * time.Second)
		e.srv.roomSweep()
	}
	e.srv.db.QueryRow("SELECT lease_until FROM battle_claims WHERE campaign_id = ? AND battle_id = 1", c.id).Scan(&until1)
	if until1 <= until0+150000 {
		t.Fatalf("lease not renewed while the room is in use: %d -> %d", until0, until1)
	}
	sum := e.must2(e.call("GET", "/api/c/"+c.id, c.tokB, nil))
	cl := sum["battles"].([]any)[0].(map[string]any)["claim"].(map[string]any)
	if cl["mode"] != "live" {
		t.Fatalf("claim mode: %v", cl)
	}
}

// A player who took part may upload the result even after leaving the room
// (the host role moved to the other); a seat that did not take part may not.
func TestRoomParticipantUpload(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.RoomGrace = 2 * time.Second })
	c := e.battleCampaign()
	a := e.dial(c.id, c.tokA)
	a.send(map[string]any{"t": "room", "b": 1, "v": 2, "create": true})
	a.next("room")
	b := e.dial(c.id, c.tokB)
	b.send(map[string]any{"t": "room", "b": 1, "v": 2})
	b.next("room")
	a.send(map[string]any{"t": "start"})
	b.next("start")
	time.Sleep(100 * time.Millisecond)
	// A leaves: B becomes host; A's late upload is still accepted.
	a.send(map[string]any{"t": "leave"})
	b.next("drop")
	<-a.done
	after := battleState(1, tbattle{ID: 2, R: 2, Armies: map[int]int{2: 0}, DefF: 5})
	e.must2(e.upload(c, c.tokA, 2, "battle", after, map[string]any{"battle_id": 1, "outcome": map[string]any{"winner": 0, "live": 1}}))
	b.next("resolved")
	var n int
	e.srv.db.QueryRow("SELECT COUNT(*) FROM battle_live WHERE campaign_id = ?", c.id).Scan(&n)
	if n != 0 {
		t.Fatalf("battle_live rows left after the battle: %d", n)
	}
}
