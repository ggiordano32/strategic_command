package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type subRow struct {
	F    int
	Body string
	At   int64
}

// loadSubs: the current version's submissions (by faction) and the alive
// humans who have not submitted.
func (s *Server) loadSubs(ctx context.Context, q queryer, c *campRow) ([]subRow, []int, error) {
	rows, err := q.QueryContext(ctx, "SELECT f, body, submitted_at FROM submissions WHERE campaign_id = ? AND version = ? ORDER BY f", c.ID, c.Version)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var subs []subRow
	done := map[int]bool{}
	for rows.Next() {
		var sr subRow
		if err := rows.Scan(&sr.F, &sr.Body, &sr.At); err != nil {
			return nil, nil, err
		}
		subs = append(subs, sr)
		done[sr.F] = true
	}
	var missing []int
	for _, f := range c.Alive {
		if !done[f] {
			missing = append(missing, f)
		}
	}
	return subs, missing, rows.Err()
}

// POST /api/c/{id}/submit {submission: {turn, f, base, orders}, base_version}
// Replaces this seat's earlier submission for the turn. The turn deadline
// (if the campaign has a timeout) starts at the turn's first submission.
func (s *Server) submit(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		BaseVersion int             `json:"base_version"`
		Submission  json.RawMessage `json:"submission"`
	}
	if err := readJSON(w, r, maxSubmission+4096, &req); err != nil {
		s.failErr(w, err)
		return
	}
	var sub struct {
		Turn   *num            `json:"turn"`
		F      *num            `json:"f"`
		Base   string          `json:"base"`
		Orders json.RawMessage `json:"orders"`
	}
	if len(req.Submission) == 0 || json.Unmarshal(req.Submission, &sub) != nil || sub.Turn == nil || sub.F == nil {
		fail(w, http.StatusBadRequest, "bad_request", "submission must be {turn, f, base, orders}")
		return
	}
	var orders []json.RawMessage
	if json.Unmarshal(sub.Orders, &orders) != nil {
		fail(w, http.StatusBadRequest, "bad_request", "orders must be an array")
		return
	}
	if int(*sub.F) != seat.F {
		fail(w, http.StatusForbidden, "wrong_seat", "you can only submit for your own faction")
		return
	}
	ob := &outbox{}
	var seq int64
	var allIn bool
	var subsRev int
	var deadline int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, err := loadCamp(ctx, tx, seat.Campaign)
		if err != nil {
			return err
		}
		if req.BaseVersion != 0 && req.BaseVersion != c.Version {
			return conflict(c, "the campaign has moved on (version %d)", c.Version)
		}
		if c.Phase != "plan" {
			return conflict(c, "turns cannot be submitted in phase %s", c.Phase)
		}
		if int(*sub.Turn) != c.Turn {
			return conflict(c, "this is turn %d, not %d", c.Turn, int(*sub.Turn))
		}
		if !hasInt(c.Alive, seat.F) {
			return errf(http.StatusForbidden, "eliminated", "your faction has been eliminated")
		}
		now := ms(s.clock.Now())
		var had int
		tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM submissions WHERE campaign_id = ? AND version = ? AND f = ?", c.ID, c.Version, seat.F).Scan(&had)
		if _, err := tx.ExecContext(ctx, `INSERT INTO submissions (campaign_id, version, f, turn, body, submitted_at) VALUES (?, ?, ?, ?, ?, ?)
			ON CONFLICT (campaign_id, version, f) DO UPDATE SET body = excluded.body, submitted_at = excluded.submitted_at`,
			c.ID, c.Version, seat.F, c.Turn, string(req.Submission), now); err != nil {
			return err
		}
		deadline = c.Deadline
		if deadline == 0 && c.TimeoutH > 0 {
			deadline = now + int64(c.TimeoutH)*3600_000
		}
		if _, err := tx.ExecContext(ctx, "UPDATE campaigns SET subs_rev = subs_rev + 1, deadline = ? WHERE id = ?", deadline, c.ID); err != nil {
			return err
		}
		subsRev = c.SubsRev + 1
		c.SubsRev = subsRev
		_, missing, err := s.loadSubs(ctx, tx, c)
		if err != nil {
			return err
		}
		allIn = len(missing) == 0
		kind := "submitted"
		if had > 0 {
			kind = "resubmitted"
		}
		addActivity(ctx, tx, c.ID, now, seat.F, kind, map[string]any{"turn": c.Turn, "orders": len(orders)})
		if !allIn {
			seats, _ := loadSeats(ctx, tx, c.ID)
			s.note(ctx, tx, ob, c, seats, fmt.Sprintf("submitted:%d:%d", c.Version, seat.F), "submitted",
				fmt.Sprintf("%s has submitted turn %d, waiting for %s.", c.faction(seat.F), c.Turn+1, s.names(c, missing)), missing)
		}
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	s.flush(ob)
	reply(w, 200, map[string]any{"ok": true, "all_in": allIn, "subs_rev": subsRev, "deadline": deadline})
}

// POST /api/c/{id}/unsubmit {turn}: withdraw this seat's submission (until
// the turn is resolved).
func (s *Server) unsubmit(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		Turn int `json:"turn"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	var seq int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, err := loadCamp(ctx, tx, seat.Campaign)
		if err != nil {
			return err
		}
		if c.Phase != "plan" || req.Turn != c.Turn {
			return conflict(c, "turn %d is already resolved", req.Turn)
		}
		res, err := tx.ExecContext(ctx, "DELETE FROM submissions WHERE campaign_id = ? AND version = ? AND f = ?", c.ID, c.Version, seat.F)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return nil
		}
		var left int
		tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM submissions WHERE campaign_id = ? AND version = ?", c.ID, c.Version).Scan(&left)
		dl := c.Deadline
		if left == 0 {
			dl = 0
		}
		tx.ExecContext(ctx, "UPDATE campaigns SET subs_rev = subs_rev + 1, deadline = ? WHERE id = ?", dl, c.ID)
		tx.ExecContext(ctx, "DELETE FROM notif_sent WHERE campaign_id = ? AND key = ?", c.ID, fmt.Sprintf("submitted:%d:%d", c.Version, seat.F))
		addActivity(ctx, tx, c.ID, ms(s.clock.Now()), seat.F, "unsubmitted", map[string]any{"turn": c.Turn})
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	if seq > 0 {
		s.hub.Notify(seat.Campaign, seq)
	}
	reply(w, 200, map[string]any{"ok": true})
}

// GET /api/c/{id}/resolve-input: everything a client needs to resolve the
// turn: the base version and hash, the submissions and their revision, and
// whether resolving is allowed now (all in, or the deadline has passed).
func (s *Server) resolveInput(w http.ResponseWriter, r *http.Request, seat Seat) {
	ctx := r.Context()
	c, err := loadCamp(ctx, s.db, seat.Campaign)
	if err != nil {
		s.failErr(w, err)
		return
	}
	subs, missing, err := s.loadSubs(ctx, s.db, c)
	if err != nil {
		s.failErr(w, err)
		return
	}
	raw := make([]json.RawMessage, 0, len(subs))
	for _, sb := range subs {
		raw = append(raw, json.RawMessage(sb.Body))
	}
	now := ms(s.clock.Now())
	expired := c.Deadline > 0 && now >= c.Deadline
	reply(w, 200, map[string]any{"base_version": c.Version, "base_hash": c.Hash, "turn": c.Turn, "phase": c.Phase,
		"subs_rev": c.SubsRev, "submissions": raw, "missing": orEmpty(missing), "all_in": len(missing) == 0,
		"deadline": c.Deadline, "expired": expired,
		"can_resolve": c.Phase == "plan" && (len(missing) == 0 || expired)})
}

// scanDeadlines sends "deadline in 2 hours" and "deadline passed" notes
// and wakes long-polling clients when a deadline passes.
func (s *Server) scanDeadlines(ctx context.Context) {
	now := s.clock.Now()
	rows, err := s.db.QueryContext(ctx, "SELECT id FROM campaigns WHERE deadline > 0 AND phase = 'plan' AND deadline - ? <= ?",
		deadlineWarn.Milliseconds(), ms(now))
	if err != nil {
		return
	}
	var ids []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		ids = append(ids, id)
	}
	rows.Close()
	for _, id := range ids {
		ob := &outbox{}
		var seq int64
		s.db.Tx(ctx, func(tx *sql.Tx) error {
			c, err := loadCamp(ctx, tx, id)
			if err != nil || c.Deadline == 0 || c.Phase != "plan" {
				return err
			}
			seats, _ := loadSeats(ctx, tx, c.ID)
			subs, missing, _ := s.loadSubs(ctx, tx, c)
			var waiting []int
			for _, sb := range subs {
				waiting = append(waiting, sb.F)
			}
			if ms(now) < c.Deadline {
				left := time.Duration(c.Deadline-ms(now)) * time.Millisecond
				s.note(ctx, tx, ob, c, seats, fmt.Sprintf("dl_soon:%d", c.Version), "deadline_soon",
					fmt.Sprintf("Turn %d deadline in %s: %s %s not submitted yet.", c.Turn+1, roundDur(left), s.names(c, missing), hasHave(len(missing))), missing)
				return nil
			}
			if s.note(ctx, tx, ob, c, seats, fmt.Sprintf("dl_passed:%d", c.Version), "deadline_passed",
				fmt.Sprintf("Turn %d deadline passed: %s may resolve the turn now without %s (a faction that submits nothing holds).",
					c.Turn+1, s.names(c, waiting), s.names(c, missing)), c.Humans) {
				addActivity(ctx, tx, c.ID, ms(now), -1, "deadline_passed", map[string]any{"turn": c.Turn})
				seq, err = bumpSeq(ctx, tx, c.ID)
			}
			return err
		})
		if seq > 0 {
			s.hub.Notify(id, seq)
		}
		s.flush(ob)
	}
}

func hasHave(n int) string {
	if n == 1 {
		return "has"
	}
	return "have"
}

func roundDur(d time.Duration) string {
	if d >= time.Hour {
		h := int((d + 30*time.Minute) / time.Hour)
		if h == 1 {
			return "about an hour"
		}
		return fmt.Sprintf("about %d hours", h)
	}
	return fmt.Sprintf("%d minutes", int(d/time.Minute)+1)
}
