// Package notify posts campaign notifications to Discord webhooks.
//
// Enqueue never blocks: messages go into a bounded queue that one worker
// drains in order (so a campaign's messages arrive in the order they were
// queued). Per campaign the worker keeps a minimum gap between posts and an
// hourly cap; Discord's 429 answers are honoured (one retry after
// retry_after), 5xx and network errors are retried twice with backoff, and
// anything else is logged and dropped. Nothing here is ever fatal.
// Deduplication is the caller's job (the server records a key per message
// in the database before queueing).
package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Message is one webhook post.
type Message struct {
	Campaign string
	URL      string
	Kind     string
	Content  string
	Users    []string // Discord user ids to @mention (must also appear in Content)
}

// Notifier is the queue and its worker.
type Notifier struct {
	Log      *slog.Logger
	Client   *http.Client
	MinGap   time.Duration // between two posts of one campaign
	PerHour  int           // posts per campaign per hour
	Retry    time.Duration // base backoff for 5xx / network errors
	ch       chan Message
	mu       sync.Mutex
	sent     map[string][]time.Time
	last     map[string]time.Time
	stats    Stats
	wg       sync.WaitGroup
	stopOnce sync.Once
	stop     chan struct{}
}

// Stats counts what happened (for /healthz and tests).
type Stats struct {
	Queued, Sent, Failed, Dropped int
}

// New makes a notifier; call Run to start the worker.
func New(log *slog.Logger) *Notifier {
	return &Notifier{
		Log:     log,
		Client:  &http.Client{Timeout: 10 * time.Second},
		MinGap:  1500 * time.Millisecond,
		PerHour: 40,
		Retry:   2 * time.Second,
		ch:      make(chan Message, 500),
		sent:    map[string][]time.Time{},
		last:    map[string]time.Time{},
		stop:    make(chan struct{}),
	}
}

// Enqueue queues m; returns false (and logs) if the queue is full or m has
// no URL.
func (n *Notifier) Enqueue(m Message) bool {
	if m.URL == "" {
		return false
	}
	select {
	case n.ch <- m:
		n.mu.Lock()
		n.stats.Queued++
		n.mu.Unlock()
		return true
	default:
		n.mu.Lock()
		n.stats.Dropped++
		n.mu.Unlock()
		n.Log.Warn("notify queue full, message dropped", "campaign", m.Campaign, "kind", m.Kind)
		return false
	}
}

// Stats returns a copy of the counters.
func (n *Notifier) Stats() Stats {
	n.mu.Lock()
	defer n.mu.Unlock()
	return n.stats
}

// Pending is the number of queued messages.
func (n *Notifier) Pending() int { return len(n.ch) }

// Run drains the queue until ctx ends (then posts what is left, briefly).
func (n *Notifier) Run(ctx context.Context) {
	n.wg.Add(1)
	defer n.wg.Done()
	for {
		select {
		case m := <-n.ch:
			n.deliver(ctx, m)
		case <-ctx.Done():
			// Drain for up to 5 s so a shutdown does not lose fresh news.
			end := time.After(5 * time.Second)
			for {
				select {
				case m := <-n.ch:
					n.deliver(context.Background(), m)
				case <-end:
					return
				default:
					return
				}
			}
		}
	}
}

// Wait blocks until Run has returned.
func (n *Notifier) Wait() { n.wg.Wait() }

func (n *Notifier) deliver(ctx context.Context, m Message) {
	// Rate limit per campaign: hourly cap, then a minimum gap.
	n.mu.Lock()
	now := time.Now()
	keep := n.sent[m.Campaign][:0]
	for _, t := range n.sent[m.Campaign] {
		if now.Sub(t) < time.Hour {
			keep = append(keep, t)
		}
	}
	n.sent[m.Campaign] = keep
	if n.PerHour > 0 && len(keep) >= n.PerHour {
		n.stats.Dropped++
		n.mu.Unlock()
		n.Log.Warn("notify hourly cap reached, message dropped", "campaign", m.Campaign, "kind", m.Kind)
		return
	}
	wait := n.MinGap - now.Sub(n.last[m.Campaign])
	n.mu.Unlock()
	if wait > 0 {
		select {
		case <-time.After(wait):
		case <-ctx.Done():
		}
	}
	ok := n.post(ctx, m)
	n.mu.Lock()
	n.last[m.Campaign] = time.Now()
	n.sent[m.Campaign] = append(n.sent[m.Campaign], time.Now())
	if ok {
		n.stats.Sent++
	} else {
		n.stats.Failed++
	}
	n.mu.Unlock()
}

type payload struct {
	Content         string          `json:"content"`
	Username        string          `json:"username"`
	AllowedMentions allowedMentions `json:"allowed_mentions"`
}

type allowedMentions struct {
	Parse []string `json:"parse"`
	Users []string `json:"users"`
}

func (n *Notifier) post(ctx context.Context, m Message) bool {
	content := m.Content
	if len(content) > 1900 {
		content = content[:1900] + "..."
	}
	users := m.Users
	if users == nil {
		users = []string{}
	}
	body, _ := json.Marshal(payload{Content: content, Username: "Strategic Command",
		AllowedMentions: allowedMentions{Parse: []string{}, Users: users}})
	backoff := n.Retry
	for attempt := 0; attempt < 3; attempt++ {
		req, err := http.NewRequestWithContext(ctx, "POST", m.URL, bytes.NewReader(body))
		if err != nil {
			n.Log.Error("notify bad request", "campaign", m.Campaign, "err", err)
			return false
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := n.Client.Do(req)
		if err != nil {
			n.Log.Warn("notify post failed", "campaign", m.Campaign, "kind", m.Kind, "attempt", attempt, "err", redact(err.Error(), m.URL))
			if !sleep(ctx, backoff) {
				return false
			}
			backoff *= 2
			continue
		}
		rb, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		resp.Body.Close()
		switch {
		case resp.StatusCode >= 200 && resp.StatusCode < 300:
			n.Log.Info("notify sent", "campaign", m.Campaign, "kind", m.Kind)
			return true
		case resp.StatusCode == http.StatusTooManyRequests:
			d := retryAfter(resp.Header.Get("Retry-After"), rb)
			n.Log.Warn("notify rate limited by Discord", "campaign", m.Campaign, "retry_after", d)
			if attempt > 0 || !sleep(ctx, d) {
				return false
			}
		case resp.StatusCode >= 500:
			n.Log.Warn("notify server error", "campaign", m.Campaign, "status", resp.StatusCode, "attempt", attempt)
			if !sleep(ctx, backoff) {
				return false
			}
			backoff *= 2
		default:
			n.Log.Error("notify rejected", "campaign", m.Campaign, "kind", m.Kind, "status", resp.StatusCode, "body", strings.TrimSpace(string(rb)))
			return false
		}
	}
	return false
}

func sleep(ctx context.Context, d time.Duration) bool {
	select {
	case <-time.After(d):
		return true
	case <-ctx.Done():
		return false
	}
}

func retryAfter(h string, body []byte) time.Duration {
	var v struct {
		RetryAfter float64 `json:"retry_after"`
	}
	d := 2 * time.Second
	if json.Unmarshal(body, &v) == nil && v.RetryAfter > 0 {
		d = time.Duration(v.RetryAfter * float64(time.Second))
	} else if s, err := strconv.ParseFloat(h, 64); err == nil && s > 0 {
		d = time.Duration(s * float64(time.Second))
	}
	if d > 30*time.Second {
		d = 30 * time.Second
	}
	return d
}

// redact removes the webhook URL (a secret) from an error text.
func redact(s, u string) string {
	if u == "" {
		return s
	}
	s = strings.ReplaceAll(s, u, Mask(u))
	if pu, err := url.Parse(u); err == nil {
		s = strings.ReplaceAll(s, pu.Path, "/...")
	}
	return s
}

// Mask shows a webhook URL without its secret: host and the last 4 chars.
func Mask(u string) string {
	if u == "" {
		return ""
	}
	pu, err := url.Parse(u)
	if err != nil {
		return "(set)"
	}
	tail := u
	if len(tail) > 4 {
		tail = tail[len(tail)-4:]
	}
	return pu.Scheme + "://" + pu.Host + "/..." + tail
}

// ValidWebhook reports whether u is a Discord webhook URL (or, if any is
// true, any http(s) URL: test mode).
func ValidWebhook(u string, any bool) bool {
	pu, err := url.Parse(u)
	if err != nil || len(u) > 300 {
		return false
	}
	if any {
		return (pu.Scheme == "http" || pu.Scheme == "https") && pu.Host != ""
	}
	if pu.Scheme != "https" || pu.User != nil || pu.RawQuery != "" && !strings.HasPrefix(pu.RawQuery, "thread_id=") {
		return false
	}
	switch pu.Hostname() {
	case "discord.com", "discordapp.com", "ptb.discord.com", "canary.discord.com":
	default:
		return false
	}
	if pu.Port() != "" {
		return false
	}
	return strings.HasPrefix(pu.Path, "/api/webhooks/")
}

// ValidUserID reports whether s looks like a Discord user id (a snowflake).
func ValidUserID(s string) bool {
	if len(s) < 15 || len(s) > 21 {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
