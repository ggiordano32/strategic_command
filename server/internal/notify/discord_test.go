package notify

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type fake struct {
	mu     sync.Mutex
	bodies []map[string]any
	status []int // status to answer per call (then 204)
	calls  int
}

func (f *fake) handler(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	st := 204
	if len(f.status) > 0 {
		st = f.status[0]
		f.status = f.status[1:]
	}
	if st == 429 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(429)
		w.Write([]byte(`{"retry_after": 0.05, "global": false}`))
		return
	}
	if st < 300 {
		var m map[string]any
		json.NewDecoder(r.Body).Decode(&m)
		f.bodies = append(f.bodies, m)
	}
	w.WriteHeader(st)
}

func setup(t *testing.T, status ...int) (*Notifier, *fake, string, func()) {
	f := &fake{status: status}
	ts := httptest.NewServer(http.HandlerFunc(f.handler))
	n := New(slog.New(slog.NewTextHandler(io.Discard, nil)))
	n.MinGap = time.Millisecond
	n.Retry = 5 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	go n.Run(ctx)
	return n, f, ts.URL + "/api/webhooks/1/x", func() { cancel(); n.Wait(); ts.Close() }
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	end := time.Now().Add(3 * time.Second)
	for !cond() {
		if time.Now().After(end) {
			t.Fatal("timed out")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestOrderAndMentions(t *testing.T) {
	n, f, url, stop := setup(t)
	defer stop()
	for i, txt := range []string{"one", "two", "three"} {
		n.Enqueue(Message{Campaign: "c", URL: url, Content: txt + " <@123456789012345678>", Users: []string{"123456789012345678"}, Kind: string(rune('a' + i))})
	}
	waitFor(t, func() bool { return n.Stats().Sent == 3 })
	f.mu.Lock()
	defer f.mu.Unlock()
	for i, want := range []string{"one", "two", "three"} {
		if !strings.HasPrefix(f.bodies[i]["content"].(string), want) {
			t.Fatalf("order: %v", f.bodies)
		}
	}
	am := f.bodies[0]["allowed_mentions"].(map[string]any)
	if len(am["parse"].([]any)) != 0 || am["users"].([]any)[0] != "123456789012345678" {
		t.Fatalf("allowed_mentions: %v", am)
	}
}

func TestRetries(t *testing.T) {
	cases := []struct {
		status []int
		sent   bool
		calls  int
	}{
		{[]int{429}, true, 2},           // rate limited, then ok after retry_after
		{[]int{500, 503}, true, 3},      // two server errors, then ok
		{[]int{500, 500, 500}, false, 3}, // gives up after three tries
		{[]int{404}, false, 1},          // rejected: dropped at once
	}
	for i, c := range cases {
		n, f, url, stop := setup(t, c.status...)
		n.Enqueue(Message{Campaign: "c", URL: url, Content: "a"})
		waitFor(t, func() bool { s := n.Stats(); return s.Sent+s.Failed == 1 })
		s := n.Stats()
		f.mu.Lock()
		calls := f.calls
		f.mu.Unlock()
		if (s.Sent == 1) != c.sent || calls != c.calls {
			t.Errorf("case %d: %+v, %d calls", i, s, calls)
		}
		stop()
	}
}

func TestUnreachableIsNotFatal(t *testing.T) {
	n := New(slog.New(slog.NewTextHandler(io.Discard, nil)))
	n.Retry = time.Millisecond
	n.Client.Timeout = 200 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	go n.Run(ctx)
	n.Enqueue(Message{Campaign: "c", URL: "http://127.0.0.1:1/x", Content: "a"})
	waitFor(t, func() bool { return n.Stats().Failed == 1 })
	cancel()
	n.Wait()
}

func TestHourlyCapAndQueueFull(t *testing.T) {
	n, _, url, stop := setup(t)
	defer stop()
	n.PerHour = 3
	for i := 0; i < 5; i++ {
		n.Enqueue(Message{Campaign: "c", URL: url, Content: "x"})
	}
	waitFor(t, func() bool { s := n.Stats(); return s.Sent+s.Dropped == 5 })
	if s := n.Stats(); s.Sent != 3 || s.Dropped != 2 {
		t.Fatalf("cap: %+v", s)
	}
	// Enqueue never blocks, even with no worker.
	m := New(slog.New(slog.NewTextHandler(io.Discard, nil)))
	t0 := time.Now()
	for i := 0; i < 600; i++ {
		m.Enqueue(Message{Campaign: "c", URL: url, Content: "x"})
	}
	if time.Since(t0) > time.Second || m.Stats().Dropped != 100 {
		t.Fatalf("queue full: %+v", m.Stats())
	}
}

func TestValidation(t *testing.T) {
	good := []string{"https://discord.com/api/webhooks/123/abc", "https://discordapp.com/api/webhooks/1/x", "https://discord.com/api/webhooks/1/x?thread_id=5"}
	bad := []string{"http://discord.com/api/webhooks/1/x", "https://discord.com.evil.io/api/webhooks/1/x", "https://evil.io/api/webhooks/1",
		"https://discord.com/other", "https://user@discord.com/api/webhooks/1/x", "https://discord.com:8443/api/webhooks/1/x", "nonsense"}
	for _, u := range good {
		if !ValidWebhook(u, false) {
			t.Errorf("rejected %s", u)
		}
	}
	for _, u := range bad {
		if ValidWebhook(u, false) {
			t.Errorf("accepted %s", u)
		}
	}
	if m := Mask("https://discord.com/api/webhooks/123/secretABCD"); strings.Contains(m, "secret") || !strings.HasSuffix(m, "ABCD") {
		t.Errorf("mask: %s", m)
	}
	if !ValidUserID("123456789012345678") || ValidUserID("12ab") {
		t.Error("user id")
	}
}
