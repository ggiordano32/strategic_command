package server

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"

	"strategiccommand/server/internal/notify"
	"strategiccommand/server/internal/store"
)

type queryer interface {
	QueryRowContext(ctx context.Context, q string, args ...any) *sql.Row
	QueryContext(ctx context.Context, q string, args ...any) (*sql.Rows, error)
	ExecContext(ctx context.Context, q string, args ...any) (sql.Result, error)
}

type labels struct {
	Factions []string `json:"factions"`
	Regions  []string `json:"regions"`
}

type campRow struct {
	ID            string
	Name          string
	Created       int64
	FormatVersion int
	Rules, Build  string
	Humans        []int
	Labels        labels
	JoinCode      string
	JoinExpires   int64
	Version       int
	Hash          string
	Turn          int
	Phase         string
	Winner        int
	Alive         []int
	Battles       []Battle
	TimeoutH      int
	SubsRev       int
	Deadline      int64
	Seq           int64
	Webhook       string
}

func (c *campRow) faction(f int) string {
	if f >= 0 && f < len(c.Labels.Factions) && c.Labels.Factions[f] != "" {
		return c.Labels.Factions[f]
	}
	return fmt.Sprintf("Faction %d", f)
}

func (c *campRow) region(r int) string {
	if r >= 0 && r < len(c.Labels.Regions) && c.Labels.Regions[r] != "" {
		return c.Labels.Regions[r]
	}
	return fmt.Sprintf("region %d", r)
}

func (c *campRow) battle(id int) *Battle {
	for i := range c.Battles {
		if c.Battles[i].ID == id {
			return &c.Battles[i]
		}
	}
	return nil
}

const campCols = `id, name, created_at, format_version, rules, build, humans, labels, join_code, join_expires,
	version, hash, turn, phase, winner, alive, battles, timeout_h, subs_rev, deadline, seq, webhook_url`

func loadCamp(ctx context.Context, q queryer, id string) (*campRow, error) {
	var c campRow
	var humans, lab, alive, battles string
	var jc sql.NullString
	err := q.QueryRowContext(ctx, "SELECT "+campCols+" FROM campaigns WHERE id = ?", id).Scan(
		&c.ID, &c.Name, &c.Created, &c.FormatVersion, &c.Rules, &c.Build, &humans, &lab, &jc, &c.JoinExpires,
		&c.Version, &c.Hash, &c.Turn, &c.Phase, &c.Winner, &alive, &battles, &c.TimeoutH, &c.SubsRev,
		&c.Deadline, &c.Seq, &c.Webhook)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errf(http.StatusNotFound, "not_found", "no such campaign")
	}
	if err != nil {
		return nil, err
	}
	c.JoinCode = nullStr(jc)
	c.Humans = parseInts(humans)
	c.Alive = parseInts(alive)
	json.Unmarshal([]byte(lab), &c.Labels)
	json.Unmarshal([]byte(battles), &c.Battles)
	return &c, nil
}

type seatRow struct {
	F        int
	Claimed  bool
	LastSeen int64
	Discord  string
}

func loadSeats(ctx context.Context, q queryer, id string) ([]seatRow, error) {
	rows, err := q.QueryContext(ctx, "SELECT f, claimed, last_seen, discord_user FROM seats WHERE campaign_id = ? ORDER BY f", id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []seatRow
	for rows.Next() {
		var s seatRow
		var cl int
		if err := rows.Scan(&s.F, &cl, &s.LastSeen, &s.Discord); err != nil {
			return nil, err
		}
		s.Claimed = cl != 0
		out = append(out, s)
	}
	return out, rows.Err()
}

func bumpSeq(ctx context.Context, tx queryer, id string) (int64, error) {
	var seq int64
	err := tx.QueryRowContext(ctx, "UPDATE campaigns SET seq = seq + 1 WHERE id = ? RETURNING seq", id).Scan(&seq)
	return seq, err
}

func addActivity(ctx context.Context, tx queryer, id string, at int64, f int, kind string, data map[string]any) {
	b, _ := json.Marshal(data)
	if data == nil {
		b = []byte("{}")
	}
	tx.ExecContext(ctx, "INSERT INTO activity (campaign_id, at, f, kind, data) VALUES (?, ?, ?, ?, ?)", id, at, f, kind, string(b))
	tx.ExecContext(ctx, `DELETE FROM activity WHERE campaign_id = ? AND id <= (SELECT id FROM activity WHERE campaign_id = ?
		ORDER BY id DESC LIMIT 1 OFFSET ?)`, id, id, activityKeep)
}

func newToken(ctx context.Context, tx queryer, id string, f int, now int64, device string) (string, error) {
	tok := randomToken()
	_, err := tx.ExecContext(ctx, "INSERT INTO tokens (campaign_id, f, hash, created_at, device) VALUES (?, ?, ?, ?, ?)",
		id, f, tokenHash(tok), now, clip(device, 80))
	return tok, err
}

func clip(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

// ------------------------------------------------------- notifications ---

// outbox collects messages decided inside a transaction; they are queued
// only after it commits.
type outbox struct{ msgs []notify.Message }

// note records dedupe key `key` and, if it is new and the campaign has a
// webhook, queues a message. Returns whether the key was new.
func (s *Server) note(ctx context.Context, tx queryer, ob *outbox, c *campRow, seats []seatRow, key, kind, text string, mention []int) bool {
	res, err := tx.ExecContext(ctx, "INSERT OR IGNORE INTO notif_sent (campaign_id, key, at) VALUES (?, ?, ?)", c.ID, key, ms(s.clock.Now()))
	if err != nil {
		return false
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return false
	}
	if c.Webhook == "" || ob == nil {
		return true
	}
	content := "**" + c.Name + "**: " + text
	var users []string
	for _, f := range mention {
		for _, st := range seats {
			if st.F == f && st.Discord != "" {
				content += " <@" + st.Discord + ">"
				users = append(users, st.Discord)
			}
		}
	}
	ob.msgs = append(ob.msgs, notify.Message{Campaign: c.ID, URL: c.Webhook, Kind: kind, Content: content, Users: users})
	return true
}

func (s *Server) flush(ob *outbox) {
	for _, m := range ob.msgs {
		s.notifier.Enqueue(m)
	}
}

func (s *Server) names(c *campRow, fs []int) string {
	var out []string
	for _, f := range fs {
		out = append(out, c.faction(f))
	}
	if len(out) == 0 {
		return "nobody"
	}
	return strings.Join(out, " and ")
}

// ------------------------------------------------------------- create ---

func decodeState(b64, hash string) ([]byte, *StateMeta, error) {
	if len(b64) == 0 {
		return nil, nil, errf(http.StatusBadRequest, "bad_request", "state_gz missing")
	}
	gz, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, nil, errf(http.StatusBadRequest, "bad_request", "state_gz is not base64")
	}
	text, err := store.Gunzip(gz, maxStateRaw)
	if err != nil {
		return nil, nil, errf(http.StatusBadRequest, "bad_request", "state_gz does not decompress: %v", err)
	}
	if got := StateHash(text); got != strings.ToLower(hash) {
		return nil, nil, errf(http.StatusBadRequest, "bad_hash", "state hash %s does not match the claimed %s", got, hash)
	}
	meta, err := ParseState(text)
	if err != nil {
		return nil, nil, errf(http.StatusBadRequest, "bad_state", "%v", err)
	}
	return text, meta, nil
}

func validTimeout(h int) bool {
	switch h {
	case 0, 12, 24, 48, 72:
		return true
	}
	return false
}

func (s *Server) createCampaign(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name          string          `json:"name"`
		Invite        string          `json:"invite"`
		FormatVersion int             `json:"format_version"`
		Rules         string          `json:"rules"`
		Build         string          `json:"build"`
		Seat          int             `json:"seat"`
		StateGz       string          `json:"state_gz"`
		Hash          string          `json:"hash"`
		Labels        json.RawMessage `json:"labels"`
		WebhookURL    string          `json:"webhook_url"`
		DiscordUser   string          `json:"discord_user"`
		TimeoutH      *int            `json:"turn_timeout_h"`
		Device        string          `json:"device"`
	}
	if err := readJSON(w, r, maxStateBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if s.cfg.InviteKey != "" && subtle.ConstantTimeCompare([]byte(req.Invite), []byte(s.cfg.InviteKey)) != 1 {
		s.codeFail.Take("invite:" + ipOf(r))
		fail(w, http.StatusForbidden, "invite_required", "this server needs an invite key to create campaigns")
		return
	}
	if !s.createLimit.Allow(ipOf(r)) {
		fail(w, http.StatusTooManyRequests, "rate_limited", "too many campaigns created from this address")
		return
	}
	text, meta, err := decodeState(req.StateGz, req.Hash)
	if err != nil {
		s.failErr(w, err)
		return
	}
	if meta.FormatVersion != req.FormatVersion || req.FormatVersion <= 0 {
		fail(w, http.StatusBadRequest, "bad_state", "format_version does not match the state")
		return
	}
	if len(meta.Humans) == 0 || len(meta.Humans) > 8 || !hasInt(meta.Humans, req.Seat) {
		fail(w, http.StatusBadRequest, "bad_request", "seat must be one of the state's human factions")
		return
	}
	var lab labels
	if len(req.Labels) > 0 {
		if len(req.Labels) > 16<<10 || json.Unmarshal(req.Labels, &lab) != nil {
			fail(w, http.StatusBadRequest, "bad_request", "labels must be {factions:[...], regions:[...]}")
			return
		}
	}
	labJSON, _ := json.Marshal(lab)
	if req.WebhookURL != "" && !notify.ValidWebhook(req.WebhookURL, s.cfg.TestMode) {
		fail(w, http.StatusBadRequest, "bad_webhook", "not a Discord webhook URL (https://discord.com/api/webhooks/...)")
		return
	}
	if req.DiscordUser != "" && !notify.ValidUserID(req.DiscordUser) {
		fail(w, http.StatusBadRequest, "bad_discord_user", "a Discord user id is a 17-20 digit number")
		return
	}
	timeout := meta.TimeoutH
	if req.TimeoutH != nil {
		timeout = *req.TimeoutH
	}
	if !validTimeout(timeout) {
		fail(w, http.StatusBadRequest, "bad_request", "turn_timeout_h must be 0, 12, 24, 48 or 72")
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = meta.Name
	}
	name = clip(name, 60)
	now := ms(s.clock.Now())
	id := randomID()
	var tok, code string
	err = s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		var jc any
		if len(meta.Humans) > 1 {
			for i := 0; i < 5; i++ {
				code = randomCode(joinCodeLen)
				var n int
				tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM campaigns WHERE join_code = ?", code).Scan(&n)
				if n == 0 {
					break
				}
			}
			jc = code
		}
		battles, _ := json.Marshal(meta.Battles)
		if meta.Battles == nil {
			battles = []byte("[]")
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO campaigns (id, name, created_at, format_version, rules, build, humans, labels,
			join_code, join_expires, version, hash, turn, phase, winner, alive, battles, timeout_h, webhook_url, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			id, name, now, req.FormatVersion, clip(req.Rules, 40), clip(req.Build, 120), intsJSON(meta.Humans), string(labJSON),
			jc, now+joinCodeTTL.Milliseconds(), strings.ToLower(req.Hash), meta.Turn, meta.Phase, meta.Winner,
			intsJSON(meta.Alive), string(battles), timeout, req.WebhookURL, now)
		if err != nil {
			return err
		}
		for _, f := range meta.Humans {
			claimed, at, du := 0, int64(0), ""
			if f == req.Seat {
				claimed, at, du = 1, now, req.DiscordUser
			}
			if _, err := tx.ExecContext(ctx, "INSERT INTO seats (campaign_id, f, claimed, claimed_at, last_seen, discord_user) VALUES (?, ?, ?, ?, ?, ?)",
				id, f, claimed, at, at, du); err != nil {
				return err
			}
		}
		if tok, err = newToken(ctx, tx, id, req.Seat, now, req.Device); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO states (campaign_id, version, parent, kind, turn, phase, hash, blob, raw_size, by_f, rules, build, created_at)
			VALUES (?, 1, 0, 'create', ?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, meta.Turn, meta.Phase, strings.ToLower(req.Hash),
			store.Gzip(text), len(text), req.Seat, clip(req.Rules, 40), clip(req.Build, 120), now); err != nil {
			return err
		}
		addActivity(ctx, tx, id, now, req.Seat, "created", nil)
		return nil
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.log.Info("campaign created", "campaign", id, "humans", meta.Humans, "seat", req.Seat, "ip", ipOf(r))
	out := map[string]any{"id": id, "token": tok, "seat": req.Seat, "version": 1, "hash": strings.ToLower(req.Hash)}
	if code != "" {
		out["join_code"] = code
		out["join_expires"] = now + joinCodeTTL.Milliseconds()
	}
	reply(w, 200, out)
}

// --------------------------------------------------------------- join ---

func (s *Server) codeGuard(w http.ResponseWriter, r *http.Request) bool {
	if !s.codeFail.Has("code:" + ipOf(r)) {
		w.Header().Set("Retry-After", "60")
		fail(w, http.StatusTooManyRequests, "rate_limited", "too many wrong codes; wait a few minutes")
		return false
	}
	return true
}

func (s *Server) findJoin(ctx context.Context, q queryer, code string) (*campRow, error) {
	code = NormCode(code)
	if len(code) != joinCodeLen {
		return nil, errf(http.StatusNotFound, "bad_code", "no open campaign with that code")
	}
	var id string
	err := q.QueryRowContext(ctx, "SELECT id FROM campaigns WHERE join_code = ? AND join_expires > ?", code, ms(s.clock.Now())).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errf(http.StatusNotFound, "bad_code", "no open campaign with that code")
	}
	if err != nil {
		return nil, err
	}
	return loadCamp(ctx, q, id)
}

func (s *Server) joinPreview(w http.ResponseWriter, r *http.Request) {
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
	c, err := s.findJoin(r.Context(), s.db, req.Code)
	if err != nil {
		s.codeFail.Take("code:" + ipOf(r))
		s.failErr(w, err)
		return
	}
	seats, err := loadSeats(r.Context(), s.db, c.ID)
	if err != nil {
		s.failErr(w, err)
		return
	}
	var list []map[string]any
	for _, st := range seats {
		list = append(list, map[string]any{"f": st.F, "name": c.faction(st.F), "claimed": st.Claimed})
	}
	reply(w, 200, map[string]any{"id": c.ID, "name": c.Name, "turn": c.Turn, "humans": c.Humans,
		"format_version": c.FormatVersion, "rules": c.Rules, "seats": list})
}

func (s *Server) join(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code        string `json:"code"`
		F           int    `json:"f"`
		DiscordUser string `json:"discord_user"`
		Device      string `json:"device"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if !s.codeGuard(w, r) {
		return
	}
	if req.DiscordUser != "" && !notify.ValidUserID(req.DiscordUser) {
		fail(w, http.StatusBadRequest, "bad_discord_user", "a Discord user id is a 17-20 digit number")
		return
	}
	var tok string
	var c *campRow
	ob := &outbox{}
	var seq int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		var err error
		c, err = s.findJoin(ctx, tx, req.Code)
		if err != nil {
			s.codeFail.Take("code:" + ipOf(r))
			return err
		}
		var claimed int
		err = tx.QueryRowContext(ctx, "SELECT claimed FROM seats WHERE campaign_id = ? AND f = ?", c.ID, req.F).Scan(&claimed)
		if errors.Is(err, sql.ErrNoRows) {
			return errf(http.StatusBadRequest, "bad_seat", "that faction is not a player seat in this campaign")
		}
		if err != nil {
			return err
		}
		if claimed != 0 {
			return errf(http.StatusConflict, "seat_taken", "that seat is already taken")
		}
		now := ms(s.clock.Now())
		if _, err := tx.ExecContext(ctx, "UPDATE seats SET claimed = 1, claimed_at = ?, last_seen = ?, discord_user = ? WHERE campaign_id = ? AND f = ?",
			now, now, req.DiscordUser, c.ID, req.F); err != nil {
			return err
		}
		if tok, err = newToken(ctx, tx, c.ID, req.F, now, req.Device); err != nil {
			return err
		}
		var open int
		tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM seats WHERE campaign_id = ? AND claimed = 0", c.ID).Scan(&open)
		if open == 0 {
			tx.ExecContext(ctx, "UPDATE campaigns SET join_code = NULL WHERE id = ?", c.ID)
		}
		addActivity(ctx, tx, c.ID, now, req.F, "joined", nil)
		seats, _ := loadSeats(ctx, tx, c.ID)
		s.note(ctx, tx, ob, c, seats, fmt.Sprintf("joined:%d", req.F), "joined",
			fmt.Sprintf("%s joined the campaign. Turn %d is ready to plan.", c.faction(req.F), c.Turn+1), nil)
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(c.ID, seq)
	s.flush(ob)
	s.log.Info("seat claimed", "campaign", c.ID, "f", req.F, "ip", ipOf(r))
	reply(w, 200, map[string]any{"id": c.ID, "token": tok, "seat": req.F, "name": c.Name})
}

// ---------------------------------------------------------- device links ---

func (s *Server) makeLink(w http.ResponseWriter, r *http.Request, seat Seat) {
	now := s.clock.Now()
	exp := ms(now.Add(linkCodeTTL))
	var code string
	for i := 0; i < 5; i++ {
		code = randomCode(linkCodeLen)
		_, err := s.db.ExecContext(r.Context(), "INSERT INTO link_codes (code, campaign_id, f, expires) VALUES (?, ?, ?, ?)",
			code, seat.Campaign, seat.F, exp)
		if err == nil {
			reply(w, 200, map[string]any{"code": code, "expires_at": exp})
			return
		}
	}
	fail(w, 500, "internal", "could not make a code")
}

func (s *Server) claimLink(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code   string `json:"code"`
		Device string `json:"device"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if !s.codeGuard(w, r) {
		return
	}
	code := NormCode(req.Code)
	var id string
	var f int
	var tok string
	var name string
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		now := ms(s.clock.Now())
		err := tx.QueryRowContext(ctx, "SELECT campaign_id, f FROM link_codes WHERE code = ? AND expires > ?", code, now).Scan(&id, &f)
		if errors.Is(err, sql.ErrNoRows) || len(code) != linkCodeLen {
			s.codeFail.Take("code:" + ipOf(r))
			return errf(http.StatusNotFound, "bad_code", "that device code is unknown or expired")
		}
		if err != nil {
			return err
		}
		tx.ExecContext(ctx, "DELETE FROM link_codes WHERE code = ?", code)
		tx.QueryRowContext(ctx, "SELECT name FROM campaigns WHERE id = ?", id).Scan(&name)
		tok, err = newToken(ctx, tx, id, f, now, req.Device)
		if err != nil {
			return err
		}
		addActivity(ctx, tx, id, now, f, "device_linked", nil)
		return nil
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.log.Info("device linked", "campaign", id, "f", f, "ip", ipOf(r))
	reply(w, 200, map[string]any{"id": id, "token": tok, "seat": f, "name": name})
}

// ------------------------------------------------------------- summary ---

func (s *Server) summary(w http.ResponseWriter, r *http.Request, seat Seat) {
	ctx := r.Context()
	out, err := s.buildSummary(ctx, seat)
	if err != nil {
		s.failErr(w, err)
		return
	}
	reply(w, 200, out)
}

func (s *Server) buildSummary(ctx context.Context, seat Seat) (map[string]any, error) {
	c, err := loadCamp(ctx, s.db, seat.Campaign)
	if err != nil {
		return nil, err
	}
	seats, err := loadSeats(ctx, s.db, c.ID)
	if err != nil {
		return nil, err
	}
	now := s.clock.Now()
	subs := map[int]int64{}
	rows, err := s.db.QueryContext(ctx, "SELECT f, submitted_at FROM submissions WHERE campaign_id = ? AND version = ?", c.ID, c.Version)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var f int
		var at int64
		rows.Scan(&f, &at)
		subs[f] = at
	}
	rows.Close()
	var seatList []map[string]any
	var submitted, missing []int
	for _, st := range seats {
		_, did := subs[st.F]
		seatList = append(seatList, map[string]any{"f": st.F, "name": c.faction(st.F), "claimed": st.Claimed,
			"last_seen": st.LastSeen, "online": st.LastSeen > 0 && now.Sub(time.UnixMilli(st.LastSeen)) < onlineWindow,
			"submitted": did, "discord": st.Discord != "", "alive": hasInt(c.Alive, st.F)})
	}
	for _, f := range c.Alive {
		if _, did := subs[f]; did {
			submitted = append(submitted, f)
		} else {
			missing = append(missing, f)
		}
	}
	// Battles, claims and flags.
	claims := map[int]map[string]any{}
	rows, err = s.db.QueryContext(ctx, "SELECT battle_id, f, token_id, mode, lease_until, claimed_at FROM battle_claims WHERE campaign_id = ?", c.ID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var bid, f int
		var tid, until, at int64
		var mode string
		rows.Scan(&bid, &f, &tid, &mode, &until, &at)
		if until > ms(now) {
			claims[bid] = map[string]any{"f": f, "mode": mode, "until": until, "since": at, "mine": tid == seat.TokenID}
		}
	}
	rows.Close()
	flags := map[int][2]int{}
	rows, err = s.db.QueryContext(ctx, "SELECT battle_id, wait_by, command_by FROM battle_flags WHERE campaign_id = ?", c.ID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var bid, wb, cb int
		rows.Scan(&bid, &wb, &cb)
		flags[bid] = [2]int{wb, cb}
	}
	rows.Close()
	var battles []map[string]any
	for _, b := range c.Battles {
		fl, ok := flags[b.ID]
		if !ok {
			fl = [2]int{-1, -1}
		}
		var claim any
		if cl, ok := claims[b.ID]; ok {
			claim = cl
		}
		var live any
		if li := s.liveInfo(c.ID, b.ID); li != nil {
			live = li
		}
		battles = append(battles, map[string]any{"id": b.ID, "r": b.R, "region": c.region(b.R), "humans": b.Humans,
			"claim": claim, "wait_by": fl[0], "command_by": fl[1], "live": live})
	}
	var acts []map[string]any
	rows, err = s.db.QueryContext(ctx, "SELECT at, f, kind, data FROM activity WHERE campaign_id = ? ORDER BY id DESC LIMIT 20", c.ID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var at int64
		var f int
		var kind, data string
		rows.Scan(&at, &f, &kind, &data)
		acts = append(acts, map[string]any{"at": at, "f": f, "kind": kind, "data": json.RawMessage(data)})
	}
	rows.Close()
	var last struct {
		Kind   string
		By     int
		Rules  string
		Build  string
		Parent int
		At     int64
	}
	s.db.QueryRowContext(ctx, "SELECT kind, by_f, rules, build, parent, created_at FROM states WHERE campaign_id = ? AND version = ?",
		c.ID, c.Version).Scan(&last.Kind, &last.By, &last.Rules, &last.Build, &last.Parent, &last.At)
	out := map[string]any{
		"id": c.ID, "name": c.Name, "version": c.Version, "hash": c.Hash, "turn": c.Turn, "phase": c.Phase,
		"winner": c.Winner, "format_version": c.FormatVersion, "rules": c.Rules, "humans": c.Humans, "alive": c.Alive,
		"me": seat.F, "seq": c.Seq, "seats": seatList, "submitted": orEmpty(submitted), "missing": orEmpty(missing),
		"all_in": len(missing) == 0 && len(c.Alive) > 0, "subs_rev": c.SubsRev, "deadline": c.Deadline,
		"deadline_expired": c.Deadline > 0 && ms(now) >= c.Deadline, "timeout_h": c.TimeoutH,
		"battles": orEmptyMaps(battles), "activity": orEmptyMaps(acts), "webhook": notify.Mask(c.Webhook),
		"server_time": ms(now),
		"last": map[string]any{"kind": last.Kind, "by": last.By, "rules": last.Rules, "build": last.Build,
			"parent": last.Parent, "at": last.At},
	}
	if c.JoinCode != "" && c.JoinExpires > ms(now) {
		out["join_code"] = c.JoinCode
		out["join_expires"] = c.JoinExpires
	}
	sort.Ints(c.Humans)
	return out, nil
}

func orEmpty(v []int) []int {
	if v == nil {
		return []int{}
	}
	return v
}

func orEmptyMaps(v []map[string]any) []map[string]any {
	if v == nil {
		return []map[string]any{}
	}
	return v
}

// ------------------------------------------------------------ settings ---

func (s *Server) settings(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		WebhookURL  *string `json:"webhook_url"`
		DiscordUser *string `json:"discord_user"`
		TimeoutH    *int    `json:"turn_timeout_h"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if req.WebhookURL != nil && *req.WebhookURL != "" && !notify.ValidWebhook(*req.WebhookURL, s.cfg.TestMode) {
		fail(w, http.StatusBadRequest, "bad_webhook", "not a Discord webhook URL (https://discord.com/api/webhooks/...)")
		return
	}
	if req.DiscordUser != nil && *req.DiscordUser != "" && !notify.ValidUserID(*req.DiscordUser) {
		fail(w, http.StatusBadRequest, "bad_discord_user", "a Discord user id is a 17-20 digit number")
		return
	}
	if req.TimeoutH != nil && !validTimeout(*req.TimeoutH) {
		fail(w, http.StatusBadRequest, "bad_request", "turn_timeout_h must be 0, 12, 24, 48 or 72")
		return
	}
	var seq int64
	var mask string
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, err := loadCamp(ctx, tx, seat.Campaign)
		if err != nil {
			return err
		}
		now := ms(s.clock.Now())
		if req.WebhookURL != nil {
			tx.ExecContext(ctx, "UPDATE campaigns SET webhook_url = ? WHERE id = ?", *req.WebhookURL, c.ID)
			c.Webhook = *req.WebhookURL
			addActivity(ctx, tx, c.ID, now, seat.F, "webhook", map[string]any{"set": *req.WebhookURL != ""})
		}
		if req.DiscordUser != nil {
			tx.ExecContext(ctx, "UPDATE seats SET discord_user = ? WHERE campaign_id = ? AND f = ?", *req.DiscordUser, c.ID, seat.F)
		}
		if req.TimeoutH != nil && *req.TimeoutH != c.TimeoutH {
			dl := int64(0)
			if *req.TimeoutH > 0 && c.Deadline > 0 {
				var first int64
				tx.QueryRowContext(ctx, "SELECT COALESCE(MIN(submitted_at), 0) FROM submissions WHERE campaign_id = ? AND version = ?", c.ID, c.Version).Scan(&first)
				if first > 0 {
					dl = first + int64(*req.TimeoutH)*3600_000
				}
			}
			tx.ExecContext(ctx, "UPDATE campaigns SET timeout_h = ?, deadline = ? WHERE id = ?", *req.TimeoutH, dl, c.ID)
			addActivity(ctx, tx, c.ID, now, seat.F, "timeout", map[string]any{"hours": *req.TimeoutH})
		}
		mask = notify.Mask(c.Webhook)
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	reply(w, 200, map[string]any{"ok": true, "webhook": mask})
}

func (s *Server) testNotify(w http.ResponseWriter, r *http.Request, seat Seat) {
	c, err := loadCamp(r.Context(), s.db, seat.Campaign)
	if err != nil {
		s.failErr(w, err)
		return
	}
	if c.Webhook == "" {
		fail(w, http.StatusBadRequest, "no_webhook", "set a Discord webhook URL first")
		return
	}
	if !s.codeFail.Allow("test-notify:" + c.ID) {
		fail(w, http.StatusTooManyRequests, "rate_limited", "wait a little before sending another test")
		return
	}
	seats, _ := loadSeats(r.Context(), s.db, c.ID)
	content := fmt.Sprintf("**%s**: test message from %s. Notifications for this campaign work.", c.Name, c.faction(seat.F))
	var users []string
	for _, st := range seats {
		if st.F == seat.F && st.Discord != "" {
			content += " <@" + st.Discord + ">"
			users = append(users, st.Discord)
		}
	}
	ok := s.notifier.Enqueue(notify.Message{Campaign: c.ID, URL: c.Webhook, Kind: "test", Content: content, Users: users})
	reply(w, 200, map[string]any{"ok": ok, "queued": ok})
}

// ping: "X is asking you to join the battle at R now" (battle_id set) or
// "X is waiting for you to plan turn T".
func (s *Server) ping(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		BattleID *int `json:"battle_id"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	ob := &outbox{}
	sent := false
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, err := loadCamp(ctx, tx, seat.Campaign)
		if err != nil {
			return err
		}
		seats, _ := loadSeats(ctx, tx, c.ID)
		now := s.clock.Now()
		var others []int
		for _, f := range c.Humans {
			if f != seat.F {
				others = append(others, f)
			}
		}
		if req.BattleID != nil {
			b := c.battle(*req.BattleID)
			if b == nil {
				return errf(http.StatusNotFound, "no_battle", "no such pending battle")
			}
			key := fmt.Sprintf("ping:b%d:%d:%d", b.ID, seat.F, now.UnixMilli()/pingBucket.Milliseconds())
			sent = s.note(ctx, tx, ob, c, seats, key, "ping_battle",
				fmt.Sprintf("%s is asking you to join the battle at %s now.", c.faction(seat.F), c.region(b.R)), others)
			addActivity(ctx, tx, c.ID, ms(now), seat.F, "ping_battle", map[string]any{"battle": b.ID})
			return nil
		}
		var missing []int
		rows, _ := tx.QueryContext(ctx, "SELECT f FROM submissions WHERE campaign_id = ? AND version = ?", c.ID, c.Version)
		done := map[int]bool{}
		for rows != nil && rows.Next() {
			var f int
			rows.Scan(&f)
			done[f] = true
		}
		if rows != nil {
			rows.Close()
		}
		for _, f := range c.Alive {
			if !done[f] && f != seat.F {
				missing = append(missing, f)
			}
		}
		if len(missing) == 0 {
			missing = others
		}
		key := fmt.Sprintf("ping:t%d:%d:%d", c.Version, seat.F, now.UnixMilli()/pingBucket.Milliseconds())
		sent = s.note(ctx, tx, ob, c, seats, key, "ping_turn",
			fmt.Sprintf("%s is waiting for you (turn %d).", c.faction(seat.F), c.Turn+1), missing)
		addActivity(ctx, tx, c.ID, ms(now), seat.F, "ping", nil)
		return nil
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.flush(ob)
	reply(w, 200, map[string]any{"ok": true, "sent": sent})
}

// ---------------------------------------------------------------- misc ---

func (s *Server) telemetryPost(w http.ResponseWriter, r *http.Request) {
	if !s.teleLimit.Allow(ipOf(r)) {
		fail(w, http.StatusTooManyRequests, "rate_limited", "too many telemetry posts")
		return
	}
	s.tele.Post(w, r)
}
