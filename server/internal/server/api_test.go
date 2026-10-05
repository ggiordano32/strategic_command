package server

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func TestCreateJoinAndTokens(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	if len(c.code) != joinCodeLen || len(c.tokA) < 40 {
		t.Fatalf("bad code or token: %q %q", c.code, c.tokA)
	}
	sum := e.must2(e.call("GET", "/api/c/"+c.id, c.tokA, nil))
	if num64(sum["me"]) != 0 || sum["join_code"] != nil {
		t.Fatalf("summary: me %v, join code %v (should be gone once both seats are claimed)", sum["me"], sum["join_code"])
	}
	seats := sum["seats"].([]any)
	if len(seats) != 2 || seats[1].(map[string]any)["claimed"] != true {
		t.Fatalf("seats: %v", seats)
	}
	// The join code no longer works; a wrong code is a 404.
	st, _ := e.call("POST", "/api/join/preview", "", map[string]any{"code": c.code})
	if st != 404 {
		t.Fatalf("used join code: %d", st)
	}
	// Tokens: unknown, wrong campaign, none.
	if st, _ := e.call("GET", "/api/c/"+c.id, "nope", nil); st != 401 {
		t.Fatalf("bad token: %d", st)
	}
	c2 := e.newCampaign(0, false)
	if st, _ := e.call("GET", "/api/c/"+c.id, c2.tokA, nil); st != 401 {
		t.Fatalf("token of another campaign: %d", st)
	}
	if st, _ := e.call("GET", "/api/c/"+c.id, "", nil); st != 401 {
		t.Fatalf("no token: %d", st)
	}
	// Tokens are stored hashed, never in clear.
	var n int
	e.srv.db.QueryRow("SELECT COUNT(*) FROM tokens WHERE hash = ?", c.tokA).Scan(&n)
	var h string
	e.srv.db.QueryRow("SELECT hash FROM tokens WHERE campaign_id = ? AND f = 0", c.id).Scan(&h)
	if n != 0 || h != tokenHash(c.tokA) {
		t.Fatal("token not stored as its hash")
	}
}

func TestJoinPreviewAndCodes(t *testing.T) {
	e := newEnv(t, nil)
	text := tstate{Humans: []int{2, 5}}.text()
	out := e.must2(e.call("POST", "/api/campaigns", "", map[string]any{"format_version": 1, "seat": 5,
		"state_gz": gz64(text), "hash": StateHash(text)}))
	code := out["join_code"].(string)
	// Case-insensitive, dashes and spaces ignored.
	typed := strings.ToLower(code[:3]) + "- " + code[3:]
	pv := e.must2(e.call("POST", "/api/join/preview", "", map[string]any{"code": typed}))
	if num64(pv["turn"]) != 0 || len(pv["seats"].([]any)) != 2 {
		t.Fatalf("preview: %v", pv)
	}
	if st, _ := e.call("POST", "/api/join", "", map[string]any{"code": code, "f": 5}); st != 409 {
		t.Fatalf("taken seat: %d", st)
	}
	if st, _ := e.call("POST", "/api/join", "", map[string]any{"code": code, "f": 3}); st != 400 {
		t.Fatalf("not a seat: %d", st)
	}
	e.must2(e.call("POST", "/api/join", "", map[string]any{"code": code, "f": 2}))
	// Wrong codes are rate limited per address.
	limited := false
	for i := 0; i < 15; i++ {
		st, _ := e.call("POST", "/api/join/preview", "", map[string]any{"code": "ZZZZZZ"})
		if st == 429 {
			limited = true
			break
		}
		if st != 404 {
			t.Fatalf("wrong code: %d", st)
		}
	}
	if !limited {
		t.Fatal("wrong codes were not rate limited")
	}
}

func TestInviteKey(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.InviteKey = "sesame" })
	text := tstate{Humans: []int{0}}.text()
	body := map[string]any{"format_version": 1, "seat": 0, "state_gz": gz64(text), "hash": StateHash(text)}
	if st, _ := e.call("POST", "/api/campaigns", "", body); st != 403 {
		t.Fatalf("no invite: %d", st)
	}
	body["invite"] = "sesame"
	out := e.must2(e.call("POST", "/api/campaigns", "", body))
	if out["join_code"] != nil {
		t.Fatal("a one-seat campaign has no join code")
	}
	info := e.must2(e.call("GET", "/api/info", "", nil))
	if info["invite_required"] != true || !strings.Contains(info["build"].(string), "rules:") {
		t.Fatalf("info: %v", info)
	}
}

func TestBadInput(t *testing.T) {
	e := newEnv(t, nil)
	text := tstate{Humans: []int{0, 1}}.text()
	cases := []map[string]any{
		{"format_version": 1, "seat": 0, "state_gz": gz64(text), "hash": "deadbeef"},           // wrong hash
		{"format_version": 2, "seat": 0, "state_gz": gz64(text), "hash": StateHash(text)},      // wrong format version
		{"format_version": 1, "seat": 4, "state_gz": gz64(text), "hash": StateHash(text)},      // not a human seat
		{"format_version": 1, "seat": 0, "state_gz": "!!!", "hash": StateHash(text)},           // not base64
		{"format_version": 1, "seat": 0, "state_gz": gz64([]byte("{}")), "hash": StateHash([]byte("{}"))}, // not a state
		{"format_version": 1, "seat": 0, "state_gz": gz64(text), "hash": StateHash(text), "webhook_url": "https://evil.example/x"},
		{"format_version": 1, "seat": 0, "state_gz": gz64(text), "hash": StateHash(text), "turn_timeout_h": 5},
	}
	e.srv.cfg.TestMode = false // real webhook validation
	for i, b := range cases {
		if st, out := e.call("POST", "/api/campaigns", "", b); st != 400 {
			t.Errorf("case %d: %d %v", i, st, out)
		}
	}
	e.srv.cfg.TestMode = true
	// Not JSON at all.
	resp, _ := http.Post(e.ts.URL+"/api/campaigns", "application/json", strings.NewReader("{nope"))
	if resp.StatusCode != 400 {
		t.Fatalf("bad json: %d", resp.StatusCode)
	}
	// Too big.
	big := strings.Repeat("x", maxStateBody+10)
	resp, _ = http.Post(e.ts.URL+"/api/campaigns", "application/json", strings.NewReader(`{"name":"`+big+`"}`))
	if resp.StatusCode != 413 {
		t.Fatalf("too big: %d", resp.StatusCode)
	}
	// Cross-origin mutation.
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/join/preview", strings.NewReader("{}"))
	req.Header.Set("Origin", "https://evil.example")
	resp, _ = http.DefaultClient.Do(req)
	if resp.StatusCode != 403 {
		t.Fatalf("cross origin: %d", resp.StatusCode)
	}
	// A gzip bomb is refused.
	bomb := gz64([]byte(strings.Repeat("a", maxStateRaw+100)))
	if st, _ := e.call("POST", "/api/campaigns", "", map[string]any{"format_version": 1, "seat": 0, "state_gz": bomb, "hash": "0"}); st != 400 {
		t.Fatalf("bomb: %d", st)
	}
	if st, _ := e.call("GET", "/api/nothing", "", nil); st != 404 {
		t.Fatalf("unknown endpoint: %d", st)
	}
}

func TestSubmitResubmitUnsubmit(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	p := "/api/c/" + c.id
	if st, _ := e.call("POST", p+"/submit", c.tokA, map[string]any{"submission": sub(0, 1)}); st != 403 {
		t.Fatalf("submit for the other faction: %d", st)
	}
	if st, _ := e.call("POST", p+"/submit", c.tokA, map[string]any{"submission": sub(3, 0)}); st != 409 {
		t.Fatalf("wrong turn: %d", st)
	}
	if st, _ := e.call("POST", p+"/submit", c.tokA, map[string]any{"submission": map[string]any{"f": 0}}); st != 400 {
		t.Fatalf("malformed: %d", st)
	}
	e.must2(e.call("POST", p+"/submit", c.tokA, map[string]any{"submission": sub(0, 0, "first")}))
	out := e.must2(e.call("POST", p+"/submit", c.tokA, map[string]any{"submission": sub(0, 0, "second")}))
	if out["all_in"] != false {
		t.Fatal("all in with one of two")
	}
	ri := e.must2(e.call("GET", p+"/resolve-input", c.tokB, nil))
	subs := ri["submissions"].([]any)
	if len(subs) != 1 || subs[0].(map[string]any)["orders"].([]any)[0] != "second" {
		t.Fatalf("resubmission did not replace: %v", subs)
	}
	if ri["can_resolve"] != false {
		t.Fatal("can resolve with a missing seat")
	}
	// Uploading now is refused (not all in, no timeout).
	if st, out := e.upload(c, c.tokA, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}}, map[string]any{"subs_rev": ri["subs_rev"], "forced": true}); st != 409 || out["error"] != "not_ready" {
		t.Fatalf("early resolve: %d %v", st, out)
	}
	e.must2(e.call("POST", p+"/unsubmit", c.tokA, map[string]any{"turn": 0}))
	ri = e.must2(e.call("GET", p+"/resolve-input", c.tokB, nil))
	if len(ri["submissions"].([]any)) != 0 {
		t.Fatal("unsubmit did not withdraw")
	}
	e.submit(c, c.tokA, 1, 0, 0)
	e.submit(c, c.tokB, 1, 0, 1)
	ri = e.must2(e.call("GET", p+"/resolve-input", c.tokB, nil))
	if ri["all_in"] != true || ri["can_resolve"] != true {
		t.Fatalf("all in: %v", ri)
	}
	// Stale subs_rev (a submission changed while resolving) is refused.
	if st, _ := e.upload(c, c.tokB, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}}, map[string]any{"subs_rev": 1}); st != 409 {
		t.Fatalf("stale subs_rev: %d", st)
	}
	e.must2(e.upload(c, c.tokB, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}}, map[string]any{"subs_rev": ri["subs_rev"]}))
	// After resolution the turn cannot be unsubmitted or resubmitted.
	if st, _ := e.call("POST", p+"/unsubmit", c.tokA, map[string]any{"turn": 0}); st != 409 {
		t.Fatalf("unsubmit after resolution: %d", st)
	}
	h := e.must2(e.call("GET", p+"/history/2", c.tokA, nil))
	in := h["inputs"].(map[string]any)
	if len(in["submissions"].([]any)) != 2 || in["forced"] != false {
		t.Fatalf("inputs: %v", in)
	}
}

// Two clients resolve the same turn at once. Identical results: one write
// wins, the other is told it already happened (200, already). Different
// results: one wins, the other gets 409. Exactly one new version either way.
func TestResolveRace(t *testing.T) {
	for _, same := range []bool{true, false} {
		e := newEnv(t, nil)
		c := e.newCampaign(0, false)
		e.submit(c, c.tokA, 1, 0, 0)
		e.submit(c, c.tokB, 1, 0, 1)
		ri := e.must2(e.call("GET", "/api/c/"+c.id+"/resolve-input", c.tokA, nil))
		var wg sync.WaitGroup
		res := make([]int, 2)
		already := make([]bool, 2)
		for i, tok := range []string{c.tokA, c.tokB} {
			wg.Add(1)
			go func(i int, tok string) {
				defer wg.Done()
				salt := 0
				if !same {
					salt = i
				}
				st, out := e.upload(c, tok, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}, Salt: salt}, map[string]any{"subs_rev": ri["subs_rev"]})
				res[i] = st
				already[i] = out["already"] == true
			}(i, tok)
		}
		wg.Wait()
		hist := e.must2(e.call("GET", "/api/c/"+c.id+"/history", c.tokA, nil))
		if n := len(hist["versions"].([]any)); n != 2 {
			t.Fatalf("same=%v: %d versions", same, n)
		}
		if same {
			if res[0] != 200 || res[1] != 200 || already[0] == already[1] {
				t.Fatalf("same result race: %v %v", res, already)
			}
		} else if !((res[0] == 200 && res[1] == 409) || (res[0] == 409 && res[1] == 200)) {
			t.Fatalf("different result race: %v", res)
		}
	}
}

func TestTimeoutForceResolve(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(12, true)
	p := "/api/c/" + c.id
	sum := e.must2(e.call("GET", p, c.tokA, nil))
	if num64(sum["deadline"]) != 0 {
		t.Fatal("deadline before any submission")
	}
	e.submit(c, c.tokA, 1, 0, 0)
	sum = e.must2(e.call("GET", p, c.tokA, nil))
	dl := num64(sum["deadline"])
	if dl == 0 || sum["deadline_expired"] != false {
		t.Fatalf("deadline: %v", sum)
	}
	ri := e.must2(e.call("GET", p+"/resolve-input", c.tokA, nil))
	if st, _ := e.upload(c, c.tokA, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}}, map[string]any{"subs_rev": ri["subs_rev"], "forced": true}); st != 409 {
		t.Fatalf("forced before the deadline: %d", st)
	}
	// 10 h later: the 2-hour warning.
	e.must2(e.call("POST", "/api/test/clock", "", map[string]any{"advance_ms": 10*3600_000 + 60_000}))
	got := e.waitSeq("has submitted turn 1, waiting for Carthage", "deadline in about 2 hours")
	if !strings.Contains(find(got, "deadline in"), "<@222222222222222222>") {
		t.Fatalf("warning: %v", got)
	}
	// Past the deadline.
	e.must2(e.call("POST", "/api/test/clock", "", map[string]any{"advance_ms": 2 * 3600_000}))
	e.waitSeq("deadline in", "deadline passed")
	ri = e.must2(e.call("GET", p+"/resolve-input", c.tokA, nil))
	if ri["expired"] != true || ri["can_resolve"] != true {
		t.Fatalf("resolve input after the deadline: %v", ri)
	}
	if st, _ := e.upload(c, c.tokA, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}}, map[string]any{"subs_rev": ri["subs_rev"]}); st != 409 {
		t.Fatalf("not forced: %d", st)
	}
	e.must2(e.upload(c, c.tokA, 1, "turn", tstate{Turn: 1, Humans: []int{0, 1}}, map[string]any{"subs_rev": ri["subs_rev"], "forced": true}))
	h := e.must2(e.call("GET", p+"/history/2", c.tokA, nil))
	in := h["inputs"].(map[string]any)
	if in["forced"] != true || num64(in["missing"].([]any)[0]) != 1 {
		t.Fatalf("inputs: %v", in)
	}
	e.waitSeq("deadline passed", "Turn 1 resolved after the timeout without Carthage. Turn 2 is ready")
	sum = e.must2(e.call("GET", p, c.tokA, nil))
	if num64(sum["deadline"]) != 0 || num64(sum["turn"]) != 1 {
		t.Fatalf("after force: %v", sum)
	}
}

func battleState(turn int, battles ...tbattle) tstate {
	ph := "plan"
	if len(battles) > 0 {
		ph = "battles"
	}
	return tstate{Turn: turn, Phase: ph, Humans: []int{0, 1}, Battles: battles}
}

func TestBattleClaimsAndCommand(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, true)
	p := "/api/c/" + c.id
	e.submit(c, c.tokA, 1, 0, 0)
	e.submit(c, c.tokB, 1, 0, 1)
	ri := e.must2(e.call("GET", p+"/resolve-input", c.tokA, nil))
	b1 := tbattle{ID: 1, R: 1, Armies: map[int]int{1: 0}, DefF: -1}         // Rome only
	b2 := tbattle{ID: 2, R: 2, Armies: map[int]int{100001: 1}, DefF: 4}     // Carthage only
	e.must2(e.upload(c, c.tokB, 1, "turn", battleState(1, b1, b2), map[string]any{"subs_rev": ri["subs_rev"]}))
	sum := e.must2(e.call("GET", p, c.tokA, nil))
	if sum["phase"] != "battles" || len(sum["battles"].([]any)) != 2 {
		t.Fatalf("battles: %v", sum)
	}
	// Submitting is refused while battles are pending.
	if st, _ := e.call("POST", p+"/submit", c.tokA, map[string]any{"submission": sub(1, 0)}); st != 409 {
		t.Fatalf("submit in battles phase: %d", st)
	}
	// Rome claims its own battle; Carthage may not (needs command).
	e.must2(e.call("POST", p+"/battles/1/claim", c.tokA, map[string]any{"mode": "auto"}))
	if st, out := e.call("POST", p+"/battles/1/claim", c.tokB, map[string]any{"mode": "auto"}); st != 403 || out["error"] != "need_command" {
		t.Fatalf("claim without command: %d %v", st, out)
	}
	// Carthage takes command of Rome's army there (Rome is told), but Rome holds the lease.
	e.must2(e.call("POST", p+"/battles/1/choice", c.tokB, map[string]any{"choice": "command"}))
	if st, out := e.call("POST", p+"/battles/1/claim", c.tokB, map[string]any{"mode": "fight"}); st != 409 || num64(out["held_by"]) != 0 {
		t.Fatalf("claim of a held battle: %d %v", st, out)
	}
	// Heartbeats keep the lease; after it expires Carthage can claim it.
	e.must2(e.call("POST", p+"/battles/1/heartbeat", c.tokA, nil))
	e.clock.Advance(121 * time.Second)
	e.must2(e.call("POST", p+"/battles/1/claim", c.tokB, map[string]any{"mode": "fight"}))
	if st, _ := e.call("POST", p+"/battles/1/heartbeat", c.tokA, nil); st != 409 {
		t.Fatalf("heartbeat of a lost lease: %d", st)
	}
	// Rome's late upload is refused (Carthage holds it); Carthage's goes in.
	after1 := battleState(1, b2)
	if st, out := e.upload(c, c.tokA, 2, "battle", after1, map[string]any{"battle_id": 1, "outcome": map[string]any{"winner": 0}}); st != 409 || out["error"] != "claimed" {
		t.Fatalf("upload by the non-holder: %d %v", st, out)
	}
	e.must2(e.upload(c, c.tokB, 2, "battle", after1, map[string]any{"battle_id": 1, "outcome": map[string]any{"winner": 0}}))
	// A battle upload whose state still lists the battle is refused.
	if st, _ := e.upload(c, c.tokB, 3, "battle", after1, map[string]any{"battle_id": 2, "outcome": map[string]any{"winner": 1}}); st != 400 {
		t.Fatalf("battle still pending in upload: %d", st)
	}
	// Rome waits for Carthage on battle 2 (Carthage is pinged)... no: battle 2
	// is Carthage's alone, so Rome needs command; "wait" is for battles with both.
	if st, _ := e.call("POST", p+"/battles/2/choice", c.tokB, map[string]any{"choice": "wait"}); st != 400 {
		t.Fatalf("wait on own battle: %d", st)
	}
	e.must2(e.call("POST", p+"/battles/2/choice", c.tokA, map[string]any{"choice": "wait"}))
	e.must2(e.call("POST", p+"/ping", c.tokA, map[string]any{"battle_id": 2}))
	e.must2(e.upload(c, c.tokB, 3, "battle", battleState(1), map[string]any{"battle_id": 2, "outcome": map[string]any{"winner": 1}}))
	sum = e.must2(e.call("GET", p, c.tokA, nil))
	if sum["phase"] != "plan" || num64(sum["version"]) != 4 {
		t.Fatalf("after battles: %v", sum)
	}
	var n int
	e.srv.db.QueryRow("SELECT COUNT(*) FROM battle_claims WHERE campaign_id = ?", c.id).Scan(&n)
	if n != 0 {
		t.Fatal("claims left behind")
	}
	got := e.waitSeq("Turn 1 resolved: 2 battles pending", "took command of your army at Etruria", "waiting for you to fight the battle at Campania",
		"asking you to join the battle at Campania now", "All battles are resolved. Turn 2 is ready")
	tc := find(got, "took command")
	if !strings.Contains(tc, "<@111111111111111111>") || strings.Contains(tc, "<@222222222222222222>") {
		t.Fatalf("took command should mention Rome only: %q", tc)
	}
}

// Two devices of one seat race for the same battle: exactly one lease.
func TestBattleClaimRace(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	p := "/api/c/" + c.id
	link := e.must2(e.call("POST", p+"/link", c.tokA, nil))
	dev2 := e.must2(e.call("POST", "/api/link", "", map[string]any{"code": strings.ToLower(link["code"].(string))}))
	tok2 := dev2["token"].(string)
	if st, _ := e.call("POST", "/api/link", "", map[string]any{"code": link["code"]}); st != 404 {
		t.Fatal("a device code works twice")
	}
	e.submit(c, c.tokA, 1, 0, 0)
	e.submit(c, c.tokB, 1, 0, 1)
	ri := e.must2(e.call("GET", p+"/resolve-input", c.tokA, nil))
	e.must2(e.upload(c, c.tokA, 1, "turn", battleState(1, tbattle{ID: 1, R: 0, Armies: map[int]int{1: 0}, DefF: -1}), map[string]any{"subs_rev": ri["subs_rev"]}))
	for round := 0; round < 20; round++ {
		var wg sync.WaitGroup
		res := make([]int, 2)
		for i, tok := range []string{c.tokA, tok2} {
			wg.Add(1)
			go func(i int, tok string) {
				defer wg.Done()
				res[i], _ = e.call("POST", p+"/battles/1/claim", tok, map[string]any{"mode": "auto"})
			}(i, tok)
		}
		wg.Wait()
		if !((res[0] == 200 && res[1] == 409) || (res[0] == 409 && res[1] == 200)) {
			t.Fatalf("round %d: %v", round, res)
		}
		// Release whichever holds it.
		e.call("POST", p+"/battles/1/release", c.tokA, nil)
		e.call("POST", p+"/battles/1/release", tok2, nil)
	}
}

func TestRollbackAndHistory(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	p := "/api/c/" + c.id
	for v := 1; v <= 3; v++ {
		e.submit(c, c.tokA, v, v-1, 0)
		e.submit(c, c.tokB, v, v-1, 1)
		ri := e.must2(e.call("GET", p+"/resolve-input", c.tokA, nil))
		e.must2(e.upload(c, c.tokA, v, "turn", tstate{Turn: v, Humans: []int{0, 1}}, map[string]any{"subs_rev": ri["subs_rev"]}))
	}
	if st, _ := e.call("POST", p+"/rollback", c.tokA, map[string]any{"to_version": 2}); st != 400 {
		t.Fatalf("rollback without confirmation: %d", st)
	}
	if st, _ := e.call("POST", p+"/rollback", c.tokA, map[string]any{"to_version": 4, "confirm": "rollback"}); st != 400 {
		t.Fatalf("rollback to current: %d", st)
	}
	e.must2(e.call("POST", p+"/rollback", c.tokA, map[string]any{"to_version": 2, "confirm": "rollback"}))
	sum := e.must2(e.call("GET", p, c.tokB, nil))
	v2 := e.must2(e.call("GET", p+"/state?version=2", c.tokB, nil))
	if num64(sum["version"]) != 5 || num64(sum["turn"]) != 1 || sum["hash"] != v2["hash"] {
		t.Fatalf("after rollback: %v", sum)
	}
	cur := e.must2(e.call("GET", p+"/state", c.tokB, nil))
	if num64(cur["version"]) != 5 || cur["kind"] != "rollback" || cur["state"].(map[string]any)["turn"].(float64) != 1 {
		t.Fatalf("state after rollback: %v", cur["version"])
	}
	hist := e.must2(e.call("GET", p+"/history", c.tokA, nil))
	vs := hist["versions"].([]any)
	for i, v := range vs {
		m := v.(map[string]any)
		if num64(m["version"]) != i+1 || num64(m["parent"]) != i {
			t.Fatalf("history not contiguous: %v", vs)
		}
	}
	// The turn can be played again from the rolled-back state.
	e.submit(c, c.tokA, 5, 1, 0)
	hv := e.must2(e.call("GET", p+"/history/3?parent=1", c.tokA, nil))
	if hv["parent_state"] == nil || hv["inputs"] == nil || hv["parent_hash"] == nil {
		t.Fatalf("history version with parent: %v", hv)
	}
}

func TestSessionBlob(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	p := "/api/c/" + c.id + "/session"
	got := e.must2(e.call("GET", p, c.tokA, nil))
	if got["data"] != nil || num64(got["rev"]) != 0 {
		t.Fatalf("empty session: %v", got)
	}
	e.must2(e.call("POST", p, c.tokA, map[string]any{"data": map[string]any{"plans": []int{1, 2}}}))
	out := e.must2(e.call("POST", p, c.tokA, map[string]any{"data": map[string]any{"plans": []int{3}}, "rev": 1}))
	if num64(out["rev"]) != 2 {
		t.Fatalf("rev: %v", out)
	}
	if st, _ := e.call("POST", p, c.tokA, map[string]any{"data": 1, "rev": 1}); st != 409 {
		t.Fatalf("stale rev: %d", st)
	}
	got = e.must2(e.call("GET", p, c.tokA, nil))
	if num64(got["data"].(map[string]any)["plans"].([]any)[0]) != 3 {
		t.Fatalf("session: %v", got)
	}
	// Per seat: the ally's is separate.
	other := e.must2(e.call("GET", p, c.tokB, nil))
	if other["data"] != nil {
		t.Fatal("session leaked to the other seat")
	}
}

func TestLongPoll(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	p := "/api/c/" + c.id
	sum := e.must2(e.call("GET", p, c.tokA, nil))
	seq := num64(sum["seq"])
	// Behind: answers at once.
	t0 := time.Now()
	out := e.must2(e.call("GET", p+"/wait?since=0", c.tokA, nil))
	if num64(out["seq"]) != seq || time.Since(t0) > time.Second {
		t.Fatalf("wait behind: %v", out)
	}
	// Up to date: blocks until a change.
	done := make(chan int)
	go func() {
		_, o := e.call("GET", p+"/wait?since="+itoa(seq), c.tokB, nil)
		done <- num64(o["seq"])
	}()
	time.Sleep(200 * time.Millisecond)
	select {
	case <-done:
		t.Fatal("wait returned without a change")
	default:
	}
	e.submit(c, c.tokA, 1, 0, 0)
	select {
	case got := <-done:
		if got <= seq {
			t.Fatalf("seq did not move: %d", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("wait did not wake")
	}
	// Timeout.
	t0 = time.Now()
	e.must2(e.call("GET", p+"/wait?since=999&timeout=1", c.tokA, nil))
	if d := time.Since(t0); d < 900*time.Millisecond || d > 3*time.Second {
		t.Fatalf("timeout took %v", d)
	}
}

func TestRateLimits(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	e.srv.tokLimit = NewLimiter(e.clock, 1, time.Second, 5)
	limited := false
	for i := 0; i < 10; i++ {
		if st, _ := e.call("GET", "/api/c/"+c.id, c.tokA, nil); st == 429 {
			limited = true
		}
	}
	if !limited {
		t.Fatal("per-token limit not applied")
	}
	e.srv.ipLimit = NewLimiter(e.clock, 1, time.Second, 5)
	limited = false
	for i := 0; i < 10; i++ {
		if st, _ := e.call("GET", "/api/info", "", nil); st == 429 {
			limited = true
		}
	}
	if !limited {
		t.Fatal("per-IP limit not applied")
	}
	e.srv.ipLimit = NewLimiter(e.clock, 1000, time.Second, 1000)
	e.srv.createLimit = NewLimiter(e.clock, 2, time.Hour, 2)
	text := tstate{Humans: []int{0}}.text()
	body := map[string]any{"format_version": 1, "seat": 0, "state_gz": gz64(text), "hash": StateHash(text)}
	e.must2(e.call("POST", "/api/campaigns", "", body))
	e.must2(e.call("POST", "/api/campaigns", "", body))
	if st, _ := e.call("POST", "/api/campaigns", "", body); st != 429 {
		t.Fatalf("create limit: %d", st)
	}
}

func TestClientIP(t *testing.T) {
	tp, _ := ParsePrefixes("10.0.0.0/8,127.0.0.1")
	s := &Server{cfg: Config{TrustedProxy: tp}}
	r, _ := http.NewRequest("GET", "/", nil)
	r.RemoteAddr = "10.1.2.3:5555"
	r.Header.Set("X-Forwarded-For", "198.51.100.9, 10.9.9.9")
	if ip := s.clientIP(r); ip != "198.51.100.9" {
		t.Fatalf("trusted proxy: %s", ip)
	}
	r.RemoteAddr = "203.0.113.5:1"
	if ip := s.clientIP(r); ip != "203.0.113.5" {
		t.Fatalf("untrusted peer must not be believed: %s", ip)
	}
	r.RemoteAddr = "10.1.2.3:5555"
	r.Header.Set("X-Forwarded-For", "1.1.1.1, 198.51.100.9")
	if ip := s.clientIP(r); ip != "198.51.100.9" {
		t.Fatalf("right-most untrusted: %s", ip)
	}
}

func TestTelemetry(t *testing.T) {
	e := newEnv(t, nil)
	req, _ := http.NewRequest("POST", e.ts.URL+"/telemetry", strings.NewReader(`{"records":[{"session":"s1","seq":0,"kind":"a","ip":"spoof"},{"kind":"b","n":1.5}, 3]}`))
	req.Header.Set("X-Forwarded-For", "198.51.100.1, 10.0.0.1")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]any
	json.NewDecoder(resp.Body).Decode(&out)
	if num64(out["stored"]) != 2 {
		t.Fatalf("stored: %v", out)
	}
	files, _ := filepath.Glob(filepath.Join(e.srv.cfg.LogDir, "*.jsonl"))
	if len(files) != 1 {
		t.Fatalf("log files: %v", files)
	}
	f, _ := os.Open(files[0])
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Scan()
	line := sc.Text()
	if !strings.HasPrefix(line, `{"recv":"`) || !strings.Contains(line, `"ip":"198.51.100.1 via 127.0.0.1","session":"s1","seq":0,"kind":"a"}`) {
		t.Fatalf("line: %s", line)
	}
	sc.Scan()
	if !strings.HasSuffix(sc.Text(), `"kind":"b","n":1.5}`) {
		t.Fatalf("line 2: %s", sc.Text())
	}
	st := e.must2(e.call("GET", "/telemetry", "", nil))
	if num64(st["records"]) != 2 || st["ok"] != true || st["log_file"] == nil {
		t.Fatalf("status: %v", st)
	}
	resp, _ = http.Post(e.ts.URL+"/telemetry", "text/plain", strings.NewReader("[1,2]"))
	if resp.StatusCode != 400 {
		t.Fatalf("array: %d", resp.StatusCode)
	}
}

func TestWebStatic(t *testing.T) {
	e := newEnv(t, nil)
	resp, err := http.Get(e.ts.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	io.ReadAll(resp.Body)
	etag := resp.Header.Get("ETag")
	if resp.StatusCode != 200 || resp.Header.Get("Cache-Control") != "no-cache" || etag == "" ||
		resp.Header.Get("Content-Type") != "text/html; charset=utf-8" {
		t.Fatalf("index: %d %v", resp.StatusCode, resp.Header)
	}
	req, _ := http.NewRequest("GET", e.ts.URL+"/index.html", nil)
	req.Header.Set("If-None-Match", etag)
	resp, _ = http.DefaultTransport.RoundTrip(req)
	if resp.StatusCode != 304 {
		t.Fatalf("revalidation: %d", resp.StatusCode)
	}
	// After background compression, brotli is served to clients that take it.
	deadline := time.Now().Add(5 * time.Second)
	for {
		req, _ = http.NewRequest("GET", e.ts.URL+"/index.html", nil)
		req.Header.Set("Accept-Encoding", "gzip, br")
		resp, _ = http.DefaultTransport.RoundTrip(req)
		resp.Body.Close()
		if resp.Header.Get("Content-Encoding") == "br" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("no brotli variant")
		}
		time.Sleep(20 * time.Millisecond)
	}
	for _, p := range []string{"/../etc/passwd", "/.hidden", "/nope.js"} {
		resp, _ = http.Get(e.ts.URL + p)
		if resp.StatusCode != 404 {
			t.Fatalf("%s: %d", p, resp.StatusCode)
		}
	}
	h := e.must2(e.call("GET", "/healthz", "", nil))
	if h["ok"] != true {
		t.Fatal("healthz")
	}
}

func TestWebSocket(t *testing.T) {
	e := newEnv(t, nil)
	c := e.newCampaign(0, false)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	url := "ws" + strings.TrimPrefix(e.ts.URL, "http") + "/api/c/" + c.id + "/ws"
	conn, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	conn.Write(ctx, websocket.MessageText, []byte(`{"t":"auth","token":"`+c.tokB+`"}`))
	_, msg, err := conn.Read(ctx)
	if err != nil || !strings.Contains(string(msg), `"hello"`) || !strings.Contains(string(msg), `"f":1`) {
		t.Fatalf("hello: %s %v", msg, err)
	}
	conn.Write(ctx, websocket.MessageText, []byte(`{"t":"ping","n":7}`))
	_, msg, _ = conn.Read(ctx)
	if !strings.Contains(string(msg), `"pong"`) || !strings.Contains(string(msg), `"n":7`) {
		t.Fatalf("pong: %s", msg)
	}
	conn.Write(ctx, websocket.MessageText, []byte(`{"t":"echo","x":"hi"}`))
	_, msg, _ = conn.Read(ctx)
	if !strings.Contains(string(msg), `"x":"hi"`) {
		t.Fatalf("echo: %s", msg)
	}
	conn.Close(websocket.StatusNormalClosure, "")
	// Bad token: closed.
	conn, _, err = websocket.Dial(ctx, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	conn.Write(ctx, websocket.MessageText, []byte(`{"t":"auth","token":"wrong"}`))
	if _, _, err := conn.Read(ctx); websocket.CloseStatus(err) != websocket.StatusPolicyViolation {
		t.Fatalf("bad token: %v", err)
	}
}

func TestBackupRotation(t *testing.T) {
	e := newEnv(t, nil)
	e.newCampaign(0, false)
	dir := filepath.Join(e.srv.cfg.DataDir, "backups")
	for i := 0; i < 5; i++ {
		if _, err := e.srv.db.Backup(context.Background(), dir, time.Now().Add(time.Duration(i)*time.Hour), 3); err != nil {
			t.Fatal(err)
		}
	}
	files, _ := filepath.Glob(filepath.Join(dir, "sc-*.db"))
	if len(files) != 3 {
		t.Fatalf("kept %d backups", len(files))
	}
}

func TestStateHashMatchesGodot(t *testing.T) {
	// CState.state_hash: MD5, first 4 bytes little-endian. md5("") = d41d8cd9...
	if h := StateHash([]byte("")); h != "d98c1dd4" {
		t.Fatalf("hash of empty: %s", h)
	}
}
