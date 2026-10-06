package server

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

type croom struct {
	code, tokA, tokB string
}

var testSetup = map[string]any{"map": "plains", "armies": []any{map[string]any{"side": 0, "units": 12}}}

// newCustom creates a custom room (and joins seat 1 if join).
func (e *env) newCustom(join bool) croom {
	e.t.Helper()
	out := e.must2(e.call("POST", "/api/custom", "", map[string]any{"setup": testSetup, "rules": "r1", "build": "b1", "name": "Test"}))
	c := croom{code: out["code"].(string), tokA: out["token"].(string)}
	if join {
		j := e.must2(e.call("POST", "/api/custom/join", "", map[string]any{"code": c.code}))
		c.tokB = j["token"].(string)
	}
	return c
}

func (e *env) customURL(code string) string {
	return "ws" + strings.TrimPrefix(e.ts.URL, "http") + "/api/custom/" + code + "/ws"
}

// dialCustom connects to a custom room's WebSocket and authenticates.
func (e *env) dialCustom(code, tok string) *wsc {
	e.t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	c, _, err := websocket.Dial(ctx, e.customURL(code), nil)
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
	e.t.Cleanup(func() { w.close() })
	return w
}

// enterCustom dials, checks the hello and enters the room.
func (e *env) enterCustom(code, tok string, wantF int) (*wsc, map[string]any) {
	e.t.Helper()
	w := e.dialCustom(code, tok)
	if h := w.next("hello"); num64(h["f"]) != wantF || num64(h["api"]) != 3 {
		e.t.Fatalf("hello: %v", h)
	}
	w.send(map[string]any{"t": "room", "b": 0, "v": 0, "create": false, "scen": "", "keep": false})
	return w, w.next("room")
}

// customRefused: the auth is answered by a policy-violation close.
func (e *env) customRefused(code, tok string) {
	e.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, e.customURL(code), nil)
	if err != nil {
		e.t.Fatal(err)
	}
	defer conn.CloseNow()
	conn.Write(ctx, websocket.MessageText, []byte(`{"t":"auth","token":"`+tok+`"}`))
	if _, _, err := conn.Read(ctx); websocket.CloseStatus(err) != websocket.StatusPolicyViolation {
		e.t.Fatalf("token %q on %s: %v", tok, code, err)
	}
}

// waitRoster returns the next roster that satisfies ok.
func (w *wsc) waitRoster(ok func(r map[string]any, ps map[int]map[string]any) bool) map[string]any {
	w.t.Helper()
	for {
		r := w.next("roster")
		ps := map[int]map[string]any{}
		for _, p := range r["players"].([]any) {
			pm := p.(map[string]any)
			ps[num64(pm["f"])] = pm
		}
		if ok(r, ps) {
			return r
		}
	}
}

func lobby(ready bool, rev int, scen string) map[string]any {
	return map[string]any{"t": "lobby", "ready": ready, "rev": rev, "scen": scen}
}

func errCode(w *wsc, want string) map[string]any {
	w.t.Helper()
	m := w.next("error")
	if m["code"] != want {
		w.t.Fatalf("error %v, want %s", m, want)
	}
	return m
}

func TestCustomCreate(t *testing.T) {
	e := newEnv(t, nil)
	out := e.must2(e.call("POST", "/api/custom", "", map[string]any{"setup": testSetup, "rules": "r1", "build": "b1"}))
	code := out["code"].(string)
	if len(code) != 6 || strings.Trim(code, codeAlphabet) != "" || out["token"] == "" || num64(out["seat"]) != 0 || num64(out["rev"]) != 1 {
		t.Fatalf("create: %v", out)
	}
	if info := e.must2(e.call("GET", "/api/info", "", nil)); num64(info["api"]) != 3 {
		t.Fatalf("api version: %v", info)
	}
	for _, bad := range []any{nil, []any{1}, "x", 3} {
		body := map[string]any{"rules": "r1"}
		if bad != nil {
			body["setup"] = bad
		}
		if st, out := e.call("POST", "/api/custom", "", body); st != 400 || out["error"] != "bad_request" {
			t.Fatalf("setup %v: %d %v", bad, st, out)
		}
	}
	// Over 64 KB: inside the body limit, and beyond it.
	for _, n := range []int{65 << 10, 200 << 10} {
		big := map[string]any{"pad": strings.Repeat("x", n)}
		if st, out := e.call("POST", "/api/custom", "", map[string]any{"setup": big}); st != 413 || out["error"] != "too_large" {
			t.Fatalf("large setup %d: %d %v", n, st, out)
		}
	}
	// Rate limit (the campaign creation limiter).
	e.srv.createLimit = NewLimiter(e.clock, 6, time.Hour, 6)
	for i := 0; i < 6; i++ {
		e.must2(e.call("POST", "/api/custom", "", map[string]any{"setup": testSetup}))
	}
	if st, out := e.call("POST", "/api/custom", "", map[string]any{"setup": testSetup}); st != 429 || out["error"] != "rate_limited" {
		t.Fatalf("create rate limit: %d %v", st, out)
	}
}

func TestCustomInviteKey(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.InviteKey = "sesame" })
	for _, inv := range []string{"", "wrong"} {
		if st, out := e.call("POST", "/api/custom", "", map[string]any{"setup": testSetup, "invite": inv}); st != 403 || out["error"] != "invite_required" {
			t.Fatalf("invite %q: %d %v", inv, st, out)
		}
	}
	e.must2(e.call("POST", "/api/custom", "", map[string]any{"setup": testSetup, "invite": "sesame"}))
}

func TestCustomJoin(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCustom(false)
	typed := strings.ToLower(c.code[:3]) + "-" + strings.ToLower(c.code[3:])
	j := e.must2(e.call("POST", "/api/custom/join", "", map[string]any{"code": typed}))
	sj, _ := json.Marshal(j["setup"])
	ss, _ := json.Marshal(testSetup)
	if j["code"] != c.code || j["token"] == "" || num64(j["seat"]) != 1 || num64(j["rev"]) != 1 || string(sj) != string(ss) ||
		j["rules"] != "r1" || j["build"] != "b1" || j["name"] != "Test" {
		t.Fatalf("join: %v", j)
	}
	if st, out := e.call("POST", "/api/custom/join", "", map[string]any{"code": c.code}); st != 409 || out["error"] != "seat_taken" {
		t.Fatalf("second join: %d %v", st, out)
	}
	if st, out := e.call("POST", "/api/custom/join", "", map[string]any{"code": "ZZZZZZ"}); st != 404 || out["error"] != "bad_code" {
		t.Fatalf("bad code: %d %v", st, out)
	}
	// A room started alone cannot be joined.
	c2 := e.newCustom(false)
	a, _ := e.enterCustom(c2.code, c2.tokA, 0)
	a.send(lobby(true, 1, "h"))
	a.send(map[string]any{"t": "start"})
	a.next("start")
	if st, out := e.call("POST", "/api/custom/join", "", map[string]any{"code": c2.code}); st != 409 || out["error"] != "started" {
		t.Fatalf("join after start: %d %v", st, out)
	}
	// Wrong codes count against the code-guess limiter (10 per 15 min; one used above).
	for i := 0; i < 9; i++ {
		e.call("POST", "/api/custom/join", "", map[string]any{"code": fmt.Sprintf("ZZZZZ%d", i+2)})
	}
	if st, out := e.call("POST", "/api/custom/join", "", map[string]any{"code": "ZZZZZZ"}); st != 429 || out["error"] != "rate_limited" {
		t.Fatalf("code limiter: %d %v", st, out)
	}
}

func TestCustomWSAuth(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCustom(true)
	c2 := e.newCustom(true)
	a := e.dialCustom(strings.ToLower(c.code), c.tokA)
	if h := a.next("hello"); num64(h["f"]) != 0 {
		t.Fatalf("hello A: %v", h)
	}
	b := e.dialCustom(c.code, c.tokB)
	if h := b.next("hello"); num64(h["f"]) != 1 {
		t.Fatalf("hello B: %v", h)
	}
	e.customRefused(c.code, c.tokA+"x")
	e.customRefused(c.code, c2.tokA)
	e.customRefused("ZZZZZZ", c.tokA)
	// Lobby messages are custom-only: a campaign room calls them unknown.
	cc := e.battleCampaign()
	w := e.dial(cc.id, cc.tokA)
	w.send(map[string]any{"t": "room", "b": 1, "v": 2, "create": true})
	if r := w.next("room"); r["custom"] != nil || r["setup"] != nil {
		t.Fatalf("campaign room reply: %v", r)
	}
	w.send(lobby(true, 1, "x"))
	errCode(w, "unknown")
}

func TestCustomLobby(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCustom(true)
	a, ra := e.enterCustom(c.code, c.tokA, 0)
	if ra["custom"] != true || ra["code"] != c.code || num64(ra["rev"]) != 1 || num64(ra["v"]) != 1 || num64(ra["host"]) != 0 ||
		ra["started"] != false || ra["setup"] == nil || ra["rules"] != "r1" || num64(ra["k"]) != -1 {
		t.Fatalf("room reply: %v", ra)
	}
	// Seat 1 is claimed but not connected: it is in the roster, off.
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool {
		return ps[1] != nil && ps[1]["on"] == false && ps[0]["on"] == true && ps[0]["ready"] == false
	})
	b, rb := e.enterCustom(c.code, c.tokB, 1)
	if num64(rb["you"]) != 1 || num64(rb["host"]) != 0 {
		t.Fatalf("room reply B: %v", rb)
	}
	// Setup: success broadcasts to both; a stale base gets conflict + setup.
	a.send(map[string]any{"t": "setup", "rev": 1, "setup": map[string]any{"map": "hills"}})
	for _, w := range []*wsc{a, b} {
		if s := w.next("setup"); num64(s["rev"]) != 2 || num64(s["by"]) != 0 || s["setup"].(map[string]any)["map"] != "hills" {
			t.Fatalf("setup broadcast: %v", s)
		}
	}
	b.send(map[string]any{"t": "setup", "rev": 1, "setup": map[string]any{"map": "swamp"}})
	if m := errCode(b, "conflict"); num64(m["rev"]) != 2 {
		t.Fatalf("conflict: %v", m)
	}
	if s := b.next("setup"); num64(s["rev"]) != 2 || s["setup"].(map[string]any)["map"] != "hills" {
		t.Fatalf("setup after conflict: %v", s)
	}
	b.send(map[string]any{"t": "setup", "rev": 2, "setup": []any{1}})
	errCode(b, "bad_request")
	b.send(map[string]any{"t": "setup", "rev": 2, "setup": map[string]any{"pad": strings.Repeat("x", 65<<10)}})
	errCode(b, "too_large")
	// Ready at the current rev / at a stale rev.
	a.send(lobby(true, 2, "h1"))
	b.send(lobby(true, 1, "h1"))
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool {
		return ps[0]["ready"] == true && ps[1]["ready"] == false && ps[1]["scen"] == "h1" && num64(r["rev"]) == 2
	})
	b.send(map[string]any{"t": "start"})
	errCode(b, "not_host")
	a.send(map[string]any{"t": "start"})
	errCode(a, "not_ready")
	b.send(lobby(true, 2, "h2"))
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool { return ps[1]["ready"] == true })
	a.send(map[string]any{"t": "start"})
	errCode(a, "scen_mismatch")
	// A setup change clears every ready flag.
	b.send(lobby(true, 2, "h1"))
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool { return ps[1]["scen"] == "h1" })
	b.send(map[string]any{"t": "setup", "rev": 2, "setup": map[string]any{"map": "coast"}})
	if s := a.next("setup"); num64(s["by"]) != 1 || num64(s["rev"]) != 3 {
		t.Fatalf("setup by B: %v", s)
	}
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool {
		return ps[0]["ready"] == false && ps[1]["ready"] == false && ps[0]["scen"] == "" && num64(r["rev"]) == 3
	})
	a.send(map[string]any{"t": "start"})
	errCode(a, "not_ready")
	a.send(lobby(true, 3, "h3"))
	b.send(lobby(true, 3, "h3"))
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool {
		return ps[0]["ready"] == true && ps[1]["ready"] == true
	})
	a.send(map[string]any{"t": "start"})
	sa, sb := a.next("start"), b.next("start")
	if num64(sa["s"]) != 1 || num64(sa["rev"]) != 3 || len(sa["players"].([]any)) != 2 || num64(sb["s"]) != 1 {
		t.Fatalf("start: %v %v", sa, sb)
	}
	b.send(map[string]any{"t": "setup", "rev": 3, "setup": map[string]any{}})
	errCode(b, "started")
	b.send(lobby(false, 3, ""))
	errCode(b, "started")
}

func TestCustomRelay(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCustom(true)
	a, _ := e.enterCustom(c.code, c.tokA, 0)
	b, _ := e.enterCustom(c.code, c.tokB, 1)
	a.send(lobby(true, 1, "s"))
	b.send(lobby(true, 1, "s"))
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool {
		return ps[0]["ready"] == true && ps[1]["ready"] == true
	})
	a.send(map[string]any{"t": "start"})
	b.next("start")
	for i := 1; i <= 20; i++ {
		a.send(in(i, i+3, map[string]any{"type": 1, "f": i + 3}))
		b.send(in(i, i+2))
	}
	sa, sb := a.waitStream(41), b.waitStream(41)
	for i := range sa {
		ja, _ := json.Marshal(sa[i])
		jb, _ := json.Marshal(sb[i])
		if string(ja) != string(jb) || num64(sa[i]["s"]) != i+1 {
			t.Fatalf("item %d differs: %s vs %s", i, ja, jb)
		}
	}
	a.send(in(22, 30))
	errCode(a, "out_of_order")
	b.send(map[string]any{"t": "hash", "fr": 7, "h": "cafe"})
	if m := a.next("hash"); m["h"] != "cafe" || num64(m["p"]) != 1 {
		t.Fatalf("hash relay: %v", m)
	}
	b.send(map[string]any{"t": "replay", "from": 30})
	if rp := b.next("replay"); num64(rp["from"]) != 30 || num64(rp["to"]) != 41 || len(rp["items"].([]any)) != 12 {
		t.Fatalf("replay: %v", rp)
	}
	a.send(map[string]any{"t": "res", "fr": 100, "h": "beef"})
	if m := b.next("res"); num64(m["p"]) != 0 || m["h"] != "beef" {
		t.Fatalf("res relay: %v", m)
	}
	a.send(map[string]any{"t": "leave"})
	if d := b.next("drop"); num64(d["who"]) != 0 || num64(d["to"]) != 1 || d["why"] != "leave" || num64(d["after"]) != 23 {
		t.Fatalf("leave drop: %v", d)
	}
	b.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool { return num64(r["host"]) == 1 })
}

// The host starts alone; Player 2 joins the running battle afterwards.
func TestCustomStartAloneLateJoin(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCustom(true)
	a, _ := e.enterCustom(c.code, c.tokA, 0)
	a.send(lobby(true, 1, "s"))
	a.waitRoster(func(r map[string]any, ps map[int]map[string]any) bool { return ps[0]["ready"] == true })
	a.send(map[string]any{"t": "start"})
	if s := a.next("start"); len(s["players"].([]any)) != 1 {
		t.Fatalf("start alone: %v", s)
	}
	a.send(in(1, 5))
	a.waitStream(2)
	b, rb := e.enterCustom(c.code, c.tokB, 1)
	if rb["started"] != true || rb["start"] == nil || rb["in"] != false || num64(rb["seq"]) != 2 {
		t.Fatalf("late room reply: %v", rb)
	}
	b.send(map[string]any{"t": "ready"})
	if m := a.next("ready"); num64(m["p"]) != 1 {
		t.Fatalf("ready relay: %v", m)
	}
	b.send(in(1, 6))
	got := a.waitStream(3)
	if l := got[2]; l["t"] != "in" || num64(l["p"]) != 1 {
		t.Fatalf("late input: %v", l)
	}
}

func TestCustomExpiry(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.RoomGrace = 5 * time.Second })
	gone := func(code string) bool { return e.srv.customRoom(code) == nil }
	// A lobby nobody entered: closed after the TTL (10 min).
	c := e.newCustom(false)
	e.clock.Advance(9 * time.Minute)
	e.srv.roomSweep()
	if gone(c.code) {
		t.Fatal("lobby closed before its TTL")
	}
	e.clock.Advance(2 * time.Minute)
	e.srv.roomSweep()
	if !gone(c.code) {
		t.Fatal("lobby not closed after its TTL")
	}
	if st, out := e.call("POST", "/api/custom/join", "", map[string]any{"code": c.code}); st != 404 || out["error"] != "bad_code" {
		t.Fatalf("join an expired room: %d %v", st, out)
	}
	e.customRefused(c.code, c.tokA)
	// A lobby with a member stays; emptied, the TTL counts from then.
	c = e.newCustom(false)
	a, _ := e.enterCustom(c.code, c.tokA, 0)
	e.clock.Advance(20 * time.Minute)
	e.srv.roomSweep()
	if gone(c.code) {
		t.Fatal("occupied lobby closed")
	}
	a.close()
	<-a.done
	time.Sleep(50 * time.Millisecond)
	e.clock.Advance(9 * time.Minute)
	e.srv.roomSweep()
	if gone(c.code) {
		t.Fatal("lobby closed before the TTL since it emptied")
	}
	e.clock.Advance(2 * time.Minute)
	e.srv.roomSweep()
	if !gone(c.code) {
		t.Fatal("emptied lobby not closed")
	}
	// A started room: the room grace once empty.
	c = e.newCustom(false)
	a, _ = e.enterCustom(c.code, c.tokA, 0)
	a.send(lobby(true, 1, ""))
	a.send(map[string]any{"t": "start"})
	a.next("start")
	a.close()
	<-a.done
	time.Sleep(50 * time.Millisecond)
	e.clock.Advance(4 * time.Second)
	e.srv.roomSweep()
	if gone(c.code) {
		t.Fatal("started room closed before the grace")
	}
	e.clock.Advance(2 * time.Second)
	e.srv.roomSweep()
	if !gone(c.code) {
		t.Fatal("empty started room not closed")
	}
	// Six hours at most, members or not.
	c = e.newCustom(false)
	a, _ = e.enterCustom(c.code, c.tokA, 0)
	for i := 0; i < 5; i++ {
		e.clock.Advance(time.Hour)
		a.send(map[string]any{"t": "ping", "n": i})
		a.next("pong")
		e.srv.roomSweep()
		if gone(c.code) {
			t.Fatalf("occupied room closed after %d h", i+1)
		}
	}
	e.clock.Advance(time.Hour)
	e.srv.roomSweep()
	if !gone(c.code) {
		t.Fatal("room older than 6 h not closed")
	}
	select {
	case <-a.done:
	case <-time.After(5 * time.Second):
		t.Fatal("member of a closed room still connected")
	}
}
