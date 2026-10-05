package server

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type env struct {
	t     *testing.T
	srv   *Server
	ts    *httptest.Server
	clock *OffsetClock
	hook  *fakeHook
}

type fakeHook struct {
	mu   sync.Mutex
	msgs []map[string]any
	ts   *httptest.Server
}

func (h *fakeHook) contents() []string {
	h.mu.Lock()
	defer h.mu.Unlock()
	var out []string
	for _, m := range h.msgs {
		out = append(out, fmt.Sprint(m["content"]))
	}
	return out
}

func newEnv(t *testing.T, mod func(*Config)) *env {
	t.Helper()
	dir := t.TempDir()
	web := filepath.Join(dir, "web")
	os.MkdirAll(web, 0o755)
	os.WriteFile(filepath.Join(web, "index.html"), []byte("<html>"+string(bytes.Repeat([]byte("hello world "), 300))+"</html>"), 0o644)
	os.WriteFile(filepath.Join(web, "build_stamp.txt"), []byte("20261005T000000Z src:abc sim:def rules:12345678\n"), 0o644)
	cfg := Config{DataDir: filepath.Join(dir, "data"), WebDir: web, LogDir: filepath.Join(dir, "logs"),
		TestMode: true, CompressWeb: true, LeaseDuration: 120 * time.Second, BackupKeep: 3}
	if mod != nil {
		mod(&cfg)
	}
	clock := &OffsetClock{}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if os.Getenv("SC_TEST_LOG") != "" {
		log = slog.New(slog.NewTextHandler(os.Stderr, nil))
	}
	srv, err := New(cfg, log, clock)
	if err != nil {
		t.Fatal(err)
	}
	srv.ipLimit = NewLimiter(clock, 10000, time.Second, 10000)
	srv.tokLimit = NewLimiter(clock, 10000, time.Second, 10000)
	srv.createLimit = NewLimiter(clock, 10000, time.Second, 10000)
	srv.notifier.MinGap = 5 * time.Millisecond
	srv.notifier.Retry = 10 * time.Millisecond
	srv.Start()
	e := &env{t: t, srv: srv, clock: clock}
	e.ts = httptest.NewServer(srv.Handler())
	h := &fakeHook{}
	h.ts = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var m map[string]any
		json.NewDecoder(r.Body).Decode(&m)
		h.mu.Lock()
		h.msgs = append(h.msgs, m)
		h.mu.Unlock()
		w.WriteHeader(204)
	}))
	e.hook = h
	t.Cleanup(func() {
		e.ts.Close()
		h.ts.Close()
		srv.Drain()
		srv.Close()
	})
	return e
}

// call makes a request; body may be nil. Returns status and decoded JSON.
func (e *env) call(method, path, token string, body any) (int, map[string]any) {
	e.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, e.ts.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("X-Forwarded-For", "203.0.113.7")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func (e *env) must(status int, out map[string]any, want int) map[string]any {
	e.t.Helper()
	if status != want {
		e.t.Fatalf("status %d, want %d: %v", status, want, out)
	}
	return out
}

// A minimal state with the fields the server reads.
type tstate struct {
	Turn    int
	Phase   string
	Humans  []int
	Alive   []int // factions alive (default all)
	Battles []tbattle
	Winner  int
	Salt    int
}

type tbattle struct {
	ID, R  int
	Armies map[int]int // army id -> faction (attackers)
	DefF   int
}

func (s tstate) text() []byte {
	factions := []map[string]any{}
	for f := 0; f < 8; f++ {
		alive := 1
		if s.Alive != nil {
			alive = 0
			for _, a := range s.Alive {
				if a == f {
					alive = 1
				}
			}
		}
		factions = append(factions, map[string]any{"alive": alive})
	}
	armies := []map[string]any{}
	battles := []map[string]any{}
	for _, b := range s.Battles {
		att := []int{}
		for id, f := range b.Armies {
			armies = append(armies, map[string]any{"id": id, "f": f})
			att = append(att, id)
		}
		battles = append(battles, map[string]any{"id": b.ID, "r": b.R, "att": att, "def": []int{}, "reinf": []int{},
			"att_f": b.Armies[att[0]], "def_f": b.DefF})
	}
	phase := s.Phase
	if phase == "" {
		phase = "plan"
	}
	st := map[string]any{"format": "strategic_command_campaign", "version": 1, "name": "Test", "turn": s.Turn,
		"phase": phase, "winner": s.Winner, "humans": s.Humans, "settings": map[string]any{"turn_timeout_h": 0},
		"factions": factions, "armies": armies, "battles": battles, "salt": s.Salt}
	b, _ := json.Marshal(st)
	return b
}

func gz64(b []byte) string {
	var buf bytes.Buffer
	w := gzip.NewWriter(&buf)
	w.Write(b)
	w.Close()
	return base64.StdEncoding.EncodeToString(buf.Bytes())
}

type camp struct {
	id, tokA, tokB, code string
}

// newCampaign creates a 2-seat campaign (factions 0 and 1) and joins seat 1.
func (e *env) newCampaign(timeout int, webhook bool) camp {
	e.t.Helper()
	text := tstate{Humans: []int{0, 1}}.text()
	body := map[string]any{"name": "Test", "format_version": 1, "rules": "r1", "seat": 0, "state_gz": gz64(text),
		"hash": StateHash(text), "turn_timeout_h": timeout,
		"labels": map[string]any{"factions": []string{"Rome", "Carthage"}, "regions": []string{"Latium", "Etruria", "Campania"}}}
	if webhook {
		body["webhook_url"] = e.hook.ts.URL + "/hook"
		body["discord_user"] = "111111111111111111"
	}
	out := e.must2(e.call("POST", "/api/campaigns", "", body))
	c := camp{id: out["id"].(string), tokA: out["token"].(string), code: out["join_code"].(string)}
	j := e.must2(e.call("POST", "/api/join", "", map[string]any{"code": c.code, "f": 1, "discord_user": "222222222222222222"}))
	c.tokB = j["token"].(string)
	return c
}

func (e *env) must2(status int, out map[string]any) map[string]any {
	e.t.Helper()
	return e.must(status, out, 200)
}

func sub(turn, f int, orders ...any) map[string]any {
	if orders == nil {
		orders = []any{}
	}
	return map[string]any{"turn": turn, "f": f, "base": "00000000", "orders": orders}
}

func (e *env) submit(c camp, tok string, version, turn, f int) {
	e.t.Helper()
	e.must2(e.call("POST", "/api/c/"+c.id+"/submit", tok, map[string]any{"base_version": version, "submission": sub(turn, f, map[string]any{"t": "move", "army": 1, "to": 2})}))
}

func (e *env) upload(c camp, tok string, base int, kind string, st tstate, extra map[string]any) (int, map[string]any) {
	e.t.Helper()
	text := st.text()
	body := map[string]any{"base_version": base, "kind": kind, "hash": StateHash(text), "state_gz": gz64(text)}
	for k, v := range extra {
		body[k] = v
	}
	return e.call("POST", "/api/c/"+c.id+"/state", tok, body)
}

func (e *env) waitHook(n int) []string {
	e.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if got := e.hook.contents(); len(got) >= n {
			return got
		}
		time.Sleep(10 * time.Millisecond)
	}
	e.t.Fatalf("webhook got %d messages, want %d: %v", len(e.hook.contents()), n, e.hook.contents())
	return nil
}

// waitSeq waits until the webhook has received messages containing each
// of want, in that order (other messages may come between).
func (e *env) waitSeq(want ...string) []string {
	e.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	var got []string
	for time.Now().Before(deadline) {
		got = e.hook.contents()
		i := 0
		for _, g := range got {
			if i < len(want) && strings.Contains(g, want[i]) {
				i++
			}
		}
		if i == len(want) {
			return got
		}
		time.Sleep(10 * time.Millisecond)
	}
	e.t.Fatalf("webhook messages %q do not contain %q in order", got, want)
	return nil
}

// find returns the first message containing s.
func find(msgs []string, s string) string {
	for _, m := range msgs {
		if strings.Contains(m, s) {
			return m
		}
	}
	return ""
}

func num64(v any) int {
	switch x := v.(type) {
	case float64:
		return int(x)
	case int:
		return x
	}
	return -999
}
