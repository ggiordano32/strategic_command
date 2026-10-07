// Package server is the Strategic Command campaign server: it serves the
// web build, collects playtest telemetry, and stores co-op campaigns
// (state versions, turn submissions, battle leases, per-seat session
// blobs) for clients that run all the game rules themselves.
package server

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"strategiccommand/server/internal/notify"
	"strategiccommand/server/internal/store"
)

// Version is the server build version reported by /api/info.
const Version = "1.0.0"

// APIVersion is bumped on incompatible API changes.
const APIVersion = 3

// Limits.
const (
	maxBody        = 64 << 10  // ordinary API requests
	maxStateBody   = 4 << 20   // state uploads (gzip + base64)
	maxStateRaw    = 8 << 20   // a decompressed state
	maxSessionRaw  = 512 << 10 // a seat's session blob
	maxOutcomeRaw  = 256 << 10
	joinCodeLen    = 6
	linkCodeLen    = 8
	joinCodeTTL    = 14 * 24 * time.Hour
	linkCodeTTL    = 30 * time.Minute
	onlineWindow   = 75 * time.Second
	longPollMax    = 25 * time.Second
	seenThrottle   = 15 * time.Second
	activityKeep   = 200
	maxSubmission  = 256 << 10
	deadlineWarn   = 2 * time.Hour
	pingBucket     = 2 * time.Minute
	waitPingBucket = 10 * time.Minute
)

// Server holds everything.
type Server struct {
	cfg      Config
	db       *store.DB
	log      *slog.Logger
	clock    Clock
	notifier *notify.Notifier
	hub      *Hub
	rooms    *Rooms
	web      *Web
	tele     *Telemetry
	mux      *http.ServeMux

	ipLimit     *Limiter
	tokLimit    *Limiter
	createLimit *Limiter
	codeFail    *Limiter
	teleLimit   *Limiter

	seenMu sync.Mutex
	seen   map[int64]time.Time // token id -> last time last_seen was written

	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

// New opens the database and builds the handler.
func New(cfg Config, log *slog.Logger, clock Clock) (*Server, error) {
	if clock == nil {
		clock = &OffsetClock{}
	}
	if cfg.LeaseDuration == 0 {
		cfg.LeaseDuration = 120 * time.Second
	}
	if cfg.RoomGrace == 0 {
		cfg.RoomGrace = 90 * time.Second
	}
	if cfg.CustomTTL == 0 {
		cfg.CustomTTL = 10 * time.Minute
	}
	db, err := store.Open(filepath.Join(cfg.DataDir, "campaigns.db"))
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &Server{
		cfg: cfg, db: db, log: log, clock: clock,
		notifier:    notify.New(log),
		hub:         NewHub(),
		rooms:       newRooms(),
		ipLimit:     NewLimiter(clock, 20, time.Second, 60),
		tokLimit:    NewLimiter(clock, 10, time.Second, 40),
		createLimit: NewLimiter(clock, 6, time.Hour, 6),
		codeFail:    NewLimiter(clock, 10, 15*time.Minute, 10),
		teleLimit:   NewLimiter(clock, 5, time.Second, 30),
		seen:        map[int64]time.Time{},
		ctx:         ctx, cancel: cancel,
	}
	s.web = NewWeb(cfg.WebDir, filepath.Join(cfg.DataDir, "webcache"), cfg.CompressWeb, cfg.BrotliMax, log)
	s.tele = NewTelemetry(cfg.LogDir, clock)
	s.routes()
	return s, nil
}

// Notifier exposes the notifier (tests tune its timing).
func (s *Server) Notifier() *notify.Notifier { return s.notifier }

// DB exposes the database (tests).
func (s *Server) DB() *store.DB { return s.db }

// Start launches the background workers (notifier, deadline scanner,
// backups, web precompression).
func (s *Server) Start() {
	s.wg.Add(1)
	go func() { defer s.wg.Done(); s.notifier.Run(s.ctx) }()
	s.wg.Add(1)
	go func() { defer s.wg.Done(); s.background() }()
	s.wg.Add(1)
	go func() { defer s.wg.Done(); s.roomLoop() }()
	s.web.Warm()
}

// Drain wakes every long-poll and closes WebSockets (before http.Server.Shutdown).
func (s *Server) Drain() { s.hub.CloseAll() }

// Close stops background work and closes the database.
func (s *Server) Close() {
	s.hub.CloseAll()
	s.cancel()
	s.wg.Wait()
	s.web.Stop()
	if s.db != nil {
		s.db.Close()
	}
}

// Handler is the root HTTP handler.
func (s *Server) Handler() http.Handler { return s.middleware(s.mux) }

func (s *Server) routes() {
	m := http.NewServeMux()
	m.HandleFunc("GET /healthz", s.healthz)
	m.HandleFunc("GET /api/info", s.info)
	m.HandleFunc("POST /api/campaigns", s.createCampaign)
	m.HandleFunc("POST /api/join/preview", s.joinPreview)
	m.HandleFunc("POST /api/join", s.join)
	m.HandleFunc("POST /api/link", s.claimLink)
	m.HandleFunc("GET /api/c/{id}", s.auth(s.summary))
	m.HandleFunc("GET /api/c/{id}/state", s.auth(s.getState))
	m.HandleFunc("POST /api/c/{id}/state", s.auth(s.putState))
	m.HandleFunc("GET /api/c/{id}/history", s.auth(s.history))
	m.HandleFunc("GET /api/c/{id}/history/{v}", s.auth(s.historyVersion))
	m.HandleFunc("POST /api/c/{id}/rollback", s.auth(s.rollback))
	m.HandleFunc("POST /api/c/{id}/submit", s.auth(s.submit))
	m.HandleFunc("POST /api/c/{id}/unsubmit", s.auth(s.unsubmit))
	m.HandleFunc("GET /api/c/{id}/resolve-input", s.auth(s.resolveInput))
	m.HandleFunc("POST /api/c/{id}/battles/{bid}/claim", s.auth(s.claimBattle))
	m.HandleFunc("POST /api/c/{id}/battles/{bid}/heartbeat", s.auth(s.heartbeatBattle))
	m.HandleFunc("POST /api/c/{id}/battles/{bid}/release", s.auth(s.releaseBattle))
	m.HandleFunc("POST /api/c/{id}/battles/{bid}/choice", s.auth(s.battleChoice))
	m.HandleFunc("POST /api/c/{id}/ping", s.auth(s.ping))
	m.HandleFunc("GET /api/c/{id}/session", s.auth(s.getSession))
	m.HandleFunc("POST /api/c/{id}/session", s.auth(s.putSession))
	m.HandleFunc("POST /api/c/{id}/settings", s.auth(s.settings))
	m.HandleFunc("POST /api/c/{id}/test-notify", s.auth(s.testNotify))
	m.HandleFunc("POST /api/c/{id}/link", s.auth(s.makeLink))
	m.HandleFunc("POST /api/c/{id}/verify", s.auth(s.verifyReport))
	m.HandleFunc("GET /api/c/{id}/wait", s.auth(s.wait))
	m.HandleFunc("GET /api/c/{id}/ws", s.ws)
	m.HandleFunc("POST /api/custom", s.createCustom)
	m.HandleFunc("POST /api/custom/join", s.joinCustom)
	m.HandleFunc("GET /api/custom/{code}/ws", s.wsCustom)
	if s.cfg.TestMode {
		m.HandleFunc("POST /api/test/clock", s.testClock)
	}
	m.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		fail(w, http.StatusNotFound, "not_found", "no such API endpoint")
	})
	m.HandleFunc("GET /telemetry", s.tele.Status)
	m.HandleFunc("POST /telemetry", s.telemetryPost)
	m.Handle("/", s.web)
	s.mux = m
}

// ------------------------------------------------------------ middleware ---

type statusWriter struct {
	http.ResponseWriter
	status int
	bytes  int64
}

func (w *statusWriter) WriteHeader(c int) {
	if w.status == 0 {
		w.status = c
	}
	w.ResponseWriter.WriteHeader(c)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = 200
	}
	n, err := w.ResponseWriter.Write(b)
	w.bytes += int64(n)
	return n, err
}

func (w *statusWriter) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

type ctxKey int

const ipKey ctxKey = 1

func (s *Server) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ip := s.clientIP(r)
		r = r.WithContext(context.WithValue(r.Context(), ipKey, ip))
		sw := &statusWriter{ResponseWriter: w}
		api := strings.HasPrefix(r.URL.Path, "/api/")
		if api {
			sw.Header().Set("Cache-Control", "no-store")
			sw.Header().Set("X-Content-Type-Options", "nosniff")
			// Same origin only: no CORS headers are ever sent, and
			// cross-site mutations are refused outright.
			if r.Method != "GET" && r.Method != "HEAD" && !sameOrigin(r) {
				fail(sw, http.StatusForbidden, "cross_origin", "cross-origin requests are not allowed")
				s.access(r, sw, ip, start)
				return
			}
			if !s.ipLimit.Allow(ip) {
				sw.Header().Set("Retry-After", "2")
				fail(sw, http.StatusTooManyRequests, "rate_limited", "too many requests")
				s.access(r, sw, ip, start)
				return
			}
		}
		defer func() {
			if rec := recover(); rec != nil {
				s.log.Error("panic", "path", r.URL.Path, "err", fmt.Sprint(rec))
				if sw.status == 0 {
					fail(sw, http.StatusInternalServerError, "internal", "internal error")
				}
			}
			s.access(r, sw, ip, start)
		}()
		next.ServeHTTP(sw, r)
	})
}

func (s *Server) access(r *http.Request, sw *statusWriter, ip string, start time.Time) {
	if r.URL.Path == "/telemetry" && sw.status < 400 {
		return
	}
	lvl := slog.LevelInfo
	if !strings.HasPrefix(r.URL.Path, "/api/") && sw.status < 400 {
		lvl = slog.LevelDebug
	}
	s.log.Log(r.Context(), lvl, "http", "method", r.Method, "path", r.URL.Path, "status", sw.status,
		"bytes", sw.bytes, "ms", time.Since(start).Milliseconds(), "ip", ip)
}

// sameOrigin: requests without an Origin header (native clients, curl) are
// fine; with one, its host must be the request's host.
func sameOrigin(r *http.Request) bool {
	o := r.Header.Get("Origin")
	if o == "" {
		sf := r.Header.Get("Sec-Fetch-Site")
		return sf == "" || sf == "same-origin" || sf == "none"
	}
	i := strings.Index(o, "://")
	if i < 0 {
		return false
	}
	return strings.EqualFold(o[i+3:], r.Host)
}

// clientIP: the socket peer, or (when the peer is a trusted proxy) the
// right-most address in X-Forwarded-For that is not a trusted proxy.
func (s *Server) clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	peer, err := netip.ParseAddr(host)
	if err != nil || !s.trusted(peer) {
		return host
	}
	xff := r.Header.Values("X-Forwarded-For")
	parts := strings.Split(strings.Join(xff, ","), ",")
	for i := len(parts) - 1; i >= 0; i-- {
		p := strings.TrimSpace(parts[i])
		a, err := netip.ParseAddr(p)
		if err != nil {
			break
		}
		a = a.Unmap()
		if !s.trusted(a) || i == 0 {
			return a.String()
		}
	}
	return host
}

func (s *Server) trusted(a netip.Addr) bool {
	a = a.Unmap()
	for _, p := range s.cfg.TrustedProxy {
		if p.Contains(a) {
			return true
		}
	}
	return false
}

func ipOf(r *http.Request) string {
	if v, ok := r.Context().Value(ipKey).(string); ok {
		return v
	}
	return ""
}

// ---------------------------------------------------------------- replies ---

type apiError struct {
	status int
	code   string
	msg    string
	extra  map[string]any
}

func (e *apiError) Error() string { return e.code + ": " + e.msg }

func errf(status int, code, f string, a ...any) *apiError {
	return &apiError{status: status, code: code, msg: fmt.Sprintf(f, a...)}
}

func reply(w http.ResponseWriter, status int, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		status, b = 500, []byte(`{"error":"internal","message":"encode"}`)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write(b)
}

func fail(w http.ResponseWriter, status int, code, msg string) {
	reply(w, status, map[string]any{"error": code, "message": msg})
}

func (s *Server) failErr(w http.ResponseWriter, err error) {
	var ae *apiError
	if errors.As(err, &ae) {
		body := map[string]any{"error": ae.code, "message": ae.msg}
		for k, v := range ae.extra {
			body[k] = v
		}
		reply(w, ae.status, body)
		return
	}
	s.log.Error("internal error", "err", err)
	fail(w, http.StatusInternalServerError, "internal", "internal error")
}

// readJSON decodes the request body (at most limit bytes) into v.
func readJSON(w http.ResponseWriter, r *http.Request, limit int64, v any) error {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	b, err := io.ReadAll(r.Body)
	if err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			return errf(http.StatusRequestEntityTooLarge, "too_large", "request body too large")
		}
		return errf(http.StatusBadRequest, "bad_request", "could not read body")
	}
	if len(b) == 0 {
		b = []byte("{}")
	}
	if err := json.Unmarshal(b, v); err != nil {
		return errf(http.StatusBadRequest, "bad_request", "invalid JSON: %v", err)
	}
	return nil
}

// ------------------------------------------------------------------ auth ---

// Seat is an authenticated request's identity.
type Seat struct {
	Campaign string
	F        int
	TokenID  int64
}

type authed func(w http.ResponseWriter, r *http.Request, seat Seat)

func tokenHash(tok string) string {
	h := sha256.Sum256([]byte(tok))
	return hex.EncodeToString(h[:])
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}

// checkToken finds the seat a token belongs to in campaign id. Tokens are
// stored as SHA-256 hashes and compared in constant time.
func (s *Server) checkToken(ctx context.Context, id, tok string) (Seat, bool) {
	if tok == "" || len(tok) > 200 || id == "" || len(id) > 40 {
		return Seat{}, false
	}
	want := tokenHash(tok)
	rows, err := s.db.QueryContext(ctx, "SELECT id, f, hash FROM tokens WHERE campaign_id = ? AND revoked = 0", id)
	if err != nil {
		return Seat{}, false
	}
	defer rows.Close()
	found := Seat{}
	ok := false
	for rows.Next() {
		var tid int64
		var f int
		var h string
		if rows.Scan(&tid, &f, &h) != nil {
			continue
		}
		if subtle.ConstantTimeCompare([]byte(h), []byte(want)) == 1 {
			found, ok = Seat{Campaign: id, F: f, TokenID: tid}, true
		}
	}
	return found, ok
}

func (s *Server) auth(h authed) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		seat, ok := s.checkToken(r.Context(), id, bearer(r))
		if !ok {
			s.codeFail.Take("auth:" + ipOf(r))
			if !s.codeFail.Has("auth:" + ipOf(r)) {
				fail(w, http.StatusTooManyRequests, "rate_limited", "too many failed attempts")
				return
			}
			fail(w, http.StatusUnauthorized, "unauthorized", "unknown campaign or seat token")
			return
		}
		if !s.tokLimit.Allow(fmt.Sprint(seat.TokenID)) {
			w.Header().Set("Retry-After", "2")
			fail(w, http.StatusTooManyRequests, "rate_limited", "too many requests")
			return
		}
		s.markSeen(seat)
		h(w, r, seat)
	}
}

// markSeen updates the seat's last-seen time (at most every 15 s per token).
func (s *Server) markSeen(seat Seat) {
	now := s.clock.Now()
	s.seenMu.Lock()
	last := s.seen[seat.TokenID]
	if now.Sub(last) < seenThrottle && now.After(last) {
		s.seenMu.Unlock()
		return
	}
	s.seen[seat.TokenID] = now
	s.seenMu.Unlock()
	_, err := s.db.Exec("UPDATE seats SET last_seen = ? WHERE campaign_id = ? AND f = ?", ms(now), seat.Campaign, seat.F)
	if err == nil {
		s.db.Exec("UPDATE tokens SET last_used = ? WHERE id = ?", ms(now), seat.TokenID)
	}
}

// ----------------------------------------------------------------- codes ---

// codeAlphabet has no 0/O, 1/I/L or U/V lookalikes: codes are typed on phones.
const codeAlphabet = "23456789ABCDEFGHJKMNPQRSTWXYZ"

func randomCode(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	out := make([]byte, n)
	for i := range b {
		// Rejection-free: 256 % 29 bias is negligible for this use, but
		// draw again to keep it uniform.
		for b[i] >= byte(256-256%len(codeAlphabet)) {
			var one [1]byte
			rand.Read(one[:])
			b[i] = one[0]
		}
		out[i] = codeAlphabet[int(b[i])%len(codeAlphabet)]
	}
	return string(out)
}

// NormCode upper-cases a typed code and drops spaces and dashes; common
// misreadings are mapped (O->0 is impossible, so O, I, L, U, V, 0, 1 are
// simply invalid).
func NormCode(s string) string {
	var b strings.Builder
	for _, c := range strings.ToUpper(s) {
		if c == ' ' || c == '-' || c == '_' || c == '.' {
			continue
		}
		b.WriteRune(c)
	}
	return b.String()
}

func randomToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return strings.TrimRight(base64url(b), "=")
}

func base64url(b []byte) string {
	const enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	var sb strings.Builder
	for i := 0; i < len(b); i += 3 {
		var v uint32
		n := len(b) - i
		if n > 3 {
			n = 3
		}
		for j := 0; j < 3; j++ {
			v <<= 8
			if j < n {
				v |= uint32(b[i+j])
			}
		}
		for j := 0; j < n+1; j++ {
			sb.WriteByte(enc[(v>>(18-6*j))&63])
		}
	}
	return sb.String()
}

func randomID() string {
	return strings.ToLower(randomCode(12))
}

// ----------------------------------------------------------------- misc ---

func (s *Server) healthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	var one int
	if err := s.db.QueryRowContext(ctx, "SELECT 1").Scan(&one); err != nil {
		fail(w, http.StatusServiceUnavailable, "db", "database unavailable")
		return
	}
	st := s.notifier.Stats()
	reply(w, 200, map[string]any{"ok": true, "version": Version, "notify": map[string]int{
		"queued": st.Queued, "sent": st.Sent, "failed": st.Failed, "dropped": st.Dropped, "pending": s.notifier.Pending()}})
}

func (s *Server) info(w http.ResponseWriter, r *http.Request) {
	reply(w, 200, map[string]any{"server": "strategic-command", "version": Version, "api": APIVersion,
		"build": s.web.BuildStamp(), "invite_required": s.cfg.InviteKey != "", "time": ms(s.clock.Now()),
		"test_mode": s.cfg.TestMode})
}

func (s *Server) testClock(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AdvanceMs int64 `json:"advance_ms"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if oc, ok := s.clock.(*OffsetClock); ok && req.AdvanceMs > 0 {
		oc.Advance(time.Duration(req.AdvanceMs) * time.Millisecond)
	}
	s.scanDeadlines(r.Context())
	reply(w, 200, map[string]any{"ok": true, "time": ms(s.clock.Now())})
}

// background: deadline warnings, backups, limiter sweeps, expired codes.
func (s *Server) background() {
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()
	nextBackup := time.Now().Add(2 * time.Minute)
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-tick.C:
		}
		s.scanDeadlines(s.ctx)
		for _, l := range []*Limiter{s.ipLimit, s.tokLimit, s.createLimit, s.codeFail, s.teleLimit} {
			l.Sweep()
		}
		now := ms(s.clock.Now())
		s.db.Exec("DELETE FROM link_codes WHERE expires < ?", now)
		s.db.Exec("UPDATE campaigns SET join_code = NULL WHERE join_code IS NOT NULL AND join_expires < ?", now)
		if s.cfg.BackupEvery > 0 && time.Now().After(nextBackup) {
			nextBackup = time.Now().Add(s.cfg.BackupEvery)
			if p, err := s.db.Backup(s.ctx, filepath.Join(s.cfg.DataDir, "backups"), time.Now(), s.cfg.BackupKeep); err != nil {
				s.log.Error("backup failed", "err", err)
			} else {
				s.log.Info("backup written", "path", p)
			}
		}
	}
}

// Backup writes a backup now (used by tests and the -backup-now flag).
func (s *Server) Backup() (string, error) {
	return s.db.Backup(context.Background(), filepath.Join(s.cfg.DataDir, "backups"), time.Now(), s.cfg.BackupKeep)
}

func nullStr(ns sql.NullString) string {
	if ns.Valid {
		return ns.String
	}
	return ""
}
