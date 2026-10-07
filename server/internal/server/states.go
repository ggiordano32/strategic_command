package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"strategiccommand/server/internal/store"
)

type stateRow struct {
	Version, Parent int
	Kind            string
	Turn            int
	Phase           string
	Hash            string
	Blob            []byte
	RawSize         int
	Inputs          []byte
	By              int
	Rules, Build    string
	At              int64
}

func loadState(ctx context.Context, q queryer, id string, v int, withBlob bool) (*stateRow, error) {
	var r stateRow
	cols := "version, parent, kind, turn, phase, hash, raw_size, by_f, rules, build, created_at, inputs"
	if withBlob {
		cols += ", blob"
	}
	dst := []any{&r.Version, &r.Parent, &r.Kind, &r.Turn, &r.Phase, &r.Hash, &r.RawSize, &r.By, &r.Rules, &r.Build, &r.At, &r.Inputs}
	if withBlob {
		dst = append(dst, &r.Blob)
	}
	err := q.QueryRowContext(ctx, "SELECT "+cols+" FROM states WHERE campaign_id = ? AND version = ?", id, v).Scan(dst...)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errf(http.StatusNotFound, "no_version", "no such state version")
	}
	return &r, err
}

func (r *stateRow) text() ([]byte, error) { return store.Gunzip(r.Blob, maxStateRaw) }

func (r *stateRow) inputsJSON() json.RawMessage {
	if len(r.Inputs) == 0 {
		return json.RawMessage("null")
	}
	b, err := store.Gunzip(r.Inputs, maxStateRaw)
	if err != nil {
		return json.RawMessage("null")
	}
	return b
}

// GET /api/c/{id}/state[?version=N]
func (s *Server) getState(w http.ResponseWriter, r *http.Request, seat Seat) {
	ctx := r.Context()
	v := 0
	if q := r.URL.Query().Get("version"); q != "" {
		v, _ = strconv.Atoi(q)
	}
	if v <= 0 {
		if err := s.db.QueryRowContext(ctx, "SELECT version FROM campaigns WHERE id = ?", seat.Campaign).Scan(&v); err != nil {
			s.failErr(w, err)
			return
		}
	}
	row, err := loadState(ctx, s.db, seat.Campaign, v, true)
	if err != nil {
		s.failErr(w, err)
		return
	}
	text, err := row.text()
	if err != nil {
		s.failErr(w, err)
		return
	}
	var buf bytes.Buffer
	head, _ := json.Marshal(map[string]any{"version": row.Version, "parent": row.Parent, "kind": row.Kind,
		"hash": row.Hash, "turn": row.Turn, "phase": row.Phase, "by": row.By, "rules": row.Rules, "build": row.Build,
		"at": row.At})
	buf.Write(head[:len(head)-1])
	buf.WriteString(`,"state":`)
	buf.Write(text)
	buf.WriteString("}")
	writeJSONBytes(w, r, buf.Bytes())
}

// writeJSONBytes sends a JSON body, gzip-compressed when the client takes it.
func writeJSONBytes(w http.ResponseWriter, r *http.Request, b []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Vary", "Accept-Encoding")
	if len(b) > 2048 && strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
		w.Header().Set("Content-Encoding", "gzip")
		gz := store.Gzip(b)
		w.Header().Set("Content-Length", strconv.Itoa(len(gz)))
		w.WriteHeader(200)
		w.Write(gz)
		return
	}
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	w.WriteHeader(200)
	w.Write(b)
}

type putReq struct {
	BaseVersion int             `json:"base_version"`
	Kind        string          `json:"kind"`
	Hash        string          `json:"hash"`
	StateGz     string          `json:"state_gz"`
	SubsRev     int             `json:"subs_rev"`
	Forced      bool            `json:"forced"`
	BattleID    int             `json:"battle_id"`
	Outcome     json.RawMessage `json:"outcome"`
	Rules       string          `json:"rules"`
	Build       string          `json:"build"`
}

// POST /api/c/{id}/state: a client uploads the state it computed from the
// current version (base_version) by resolving the turn or applying one
// battle's outcome. Exactly one upload per base version wins (checked and
// written in one transaction); the rest get 409 and refetch. Replaying an
// upload that already won (same base, same hash) answers 200 again, so a
// client whose connection dropped after the server committed can retry.
func (s *Server) putState(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req putReq
	if err := readJSON(w, r, maxStateBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	req.Hash = strings.ToLower(req.Hash)
	if req.Kind != "turn" && req.Kind != "battle" {
		fail(w, http.StatusBadRequest, "bad_request", "kind must be turn or battle")
		return
	}
	text, meta, err := decodeState(req.StateGz, req.Hash)
	if err != nil {
		s.failErr(w, err)
		return
	}
	if req.Kind == "battle" && (len(req.Outcome) == 0 || len(req.Outcome) > maxOutcomeRaw || !json.Valid(req.Outcome)) {
		fail(w, http.StatusBadRequest, "bad_request", "a battle upload needs its outcome (JSON)")
		return
	}
	ob := &outbox{}
	var newV int
	var seq int64
	already := false
	err = s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, err := loadCamp(ctx, tx, seat.Campaign)
		if err != nil {
			return err
		}
		if req.BaseVersion != c.Version {
			var v int
			err := tx.QueryRowContext(ctx, "SELECT version FROM states WHERE campaign_id = ? AND parent = ? AND hash = ? ORDER BY version DESC LIMIT 1",
				c.ID, req.BaseVersion, req.Hash).Scan(&v)
			if err == nil {
				newV, already = v, true
				return nil
			}
			return conflict(c, "the campaign has moved on (version %d, you sent %d)", c.Version, req.BaseVersion)
		}
		if meta.FormatVersion != c.FormatVersion {
			return errf(http.StatusBadRequest, "bad_state", "state format %d, campaign uses %d", meta.FormatVersion, c.FormatVersion)
		}
		if intsJSON(meta.Humans) != intsJSON(c.Humans) {
			return errf(http.StatusBadRequest, "bad_state", "the state's human factions changed")
		}
		now := ms(s.clock.Now())
		seats, _ := loadSeats(ctx, tx, c.ID)
		var inputs any
		switch req.Kind {
		case "turn":
			if c.Phase != "plan" {
				return conflict(c, "the turn cannot be resolved in phase %s", c.Phase)
			}
			if meta.Turn != c.Turn+1 {
				return errf(http.StatusBadRequest, "bad_state", "a resolved turn must be turn %d, got %d", c.Turn+1, meta.Turn)
			}
			if req.SubsRev != c.SubsRev {
				return conflict(c, "the submissions changed while you were resolving")
			}
			subs, missing, err := s.loadSubs(ctx, tx, c)
			if err != nil {
				return err
			}
			if len(missing) > 0 {
				if !(req.Forced && c.Deadline > 0 && now >= c.Deadline) {
					e := errf(http.StatusConflict, "not_ready", "waiting for %s", s.names(c, missing))
					e.extra = map[string]any{"missing": missing, "version": c.Version}
					return e
				}
			}
			raw := make([]json.RawMessage, 0, len(subs))
			for _, sb := range subs {
				raw = append(raw, json.RawMessage(sb.Body))
			}
			inputs = map[string]any{"submissions": raw, "forced": len(missing) > 0, "missing": orEmpty(missing), "turn": c.Turn}
		case "battle":
			if c.Phase != "battles" {
				return conflict(c, "no battles are pending")
			}
			b := c.battle(req.BattleID)
			if b == nil {
				return conflict(c, "battle %d is no longer pending", req.BattleID)
			}
			if hasInt(meta.AllBattleIDs, req.BattleID) {
				return errf(http.StatusBadRequest, "bad_state", "the uploaded state still has battle %d pending", req.BattleID)
			}
			if meta.Turn != c.Turn {
				return errf(http.StatusBadRequest, "bad_state", "a battle result cannot change the turn")
			}
			var holder int64
			var hf int
			var until int64
			var mode string
			err := tx.QueryRowContext(ctx, "SELECT token_id, f, lease_until, mode FROM battle_claims WHERE campaign_id = ? AND battle_id = ?",
				c.ID, b.ID).Scan(&holder, &hf, &until, &mode)
			if err := s.mayCommand(ctx, tx, c, b, seat); err != nil {
				return err
			}
			// A live battle's result may come from any seat that took part
			// (mayCommand checked that); the room holds the claim meanwhile.
			if err == nil && until > now && holder != seat.TokenID && mode != "live" {
				e := errf(http.StatusConflict, "claimed", "%s holds this battle", c.faction(hf))
				e.extra = map[string]any{"held_by": hf, "version": c.Version}
				return e
			}
			inputs = map[string]any{"battle_id": b.ID, "outcome": req.Outcome}
		}
		inb, _ := json.Marshal(inputs)
		newV = c.Version + 1
		if _, err := tx.ExecContext(ctx, `INSERT INTO states (campaign_id, version, parent, kind, turn, phase, hash, blob, raw_size,
			inputs, by_f, rules, build, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			c.ID, newV, c.Version, req.Kind, meta.Turn, meta.Phase, req.Hash, store.Gzip(text), len(text),
			store.Gzip(inb), seat.F, clip(req.Rules, 40), clip(req.Build, 120), now); err != nil {
			return err
		}
		if err := s.applyMeta(ctx, tx, c, meta, req.Hash, newV, now); err != nil {
			return err
		}
		ad := map[string]any{"version": newV, "turn": meta.Turn, "phase": meta.Phase}
		if req.Kind == "battle" {
			ad["battle"] = req.BattleID
			ad["region"] = c.battle(req.BattleID).R
		} else if m, ok := inputs.(map[string]any); ok && m["forced"] == true {
			ad["forced"] = true
		}
		addActivity(ctx, tx, c.ID, now, seat.F, req.Kind, ad)
		s.afterNewState(ctx, tx, ob, c, seats, meta, newV, req.Kind, inputs)
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	if already {
		reply(w, 200, map[string]any{"ok": true, "version": newV, "already": true})
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	s.flush(ob)
	keep := map[int]bool{}
	for _, id := range meta.AllBattleIDs {
		keep[id] = true
	}
	if req.Kind == "battle" {
		s.battleResolved(seat.Campaign, req.BattleID)
	}
	s.closeRoomsOf(seat.Campaign, keep)
	s.log.Info("state uploaded", "campaign", seat.Campaign, "version", newV, "kind", req.Kind, "f", seat.F,
		"turn", meta.Turn, "phase", meta.Phase, "hash", req.Hash)
	reply(w, 200, map[string]any{"ok": true, "version": newV})
}

func conflict(c *campRow, f string, a ...any) *apiError {
	e := errf(http.StatusConflict, "conflict", f, a...)
	ids := []int{}
	for _, b := range c.Battles {
		ids = append(ids, b.ID)
	}
	e.extra = map[string]any{"version": c.Version, "hash": c.Hash, "phase": c.Phase, "turn": c.Turn, "battles": ids}
	return e
}

// applyMeta moves the campaign row to a new current state.
func (s *Server) applyMeta(ctx context.Context, tx queryer, c *campRow, meta *StateMeta, hash string, v int, now int64) error {
	battles, _ := json.Marshal(meta.Battles)
	if meta.Battles == nil {
		battles = []byte("[]")
	}
	_, err := tx.ExecContext(ctx, `UPDATE campaigns SET version = ?, hash = ?, turn = ?, phase = ?, winner = ?, alive = ?,
		battles = ?, deadline = 0, subs_rev = subs_rev + 1, updated_at = ? WHERE id = ?`,
		v, hash, meta.Turn, meta.Phase, meta.Winner, intsJSON(meta.Alive), string(battles), now, c.ID)
	if err != nil {
		return err
	}
	// Leases and flags of battles that are gone.
	keep := map[int]bool{}
	for _, b := range meta.Battles {
		keep[b.ID] = true
	}
	for _, b := range c.Battles {
		if !keep[b.ID] {
			tx.ExecContext(ctx, "DELETE FROM battle_claims WHERE campaign_id = ? AND battle_id = ?", c.ID, b.ID)
			tx.ExecContext(ctx, "DELETE FROM battle_flags WHERE campaign_id = ? AND battle_id = ?", c.ID, b.ID)
			tx.ExecContext(ctx, "DELETE FROM battle_live WHERE campaign_id = ? AND battle_id = ?", c.ID, b.ID)
			tx.ExecContext(ctx, "DELETE FROM battle_asks WHERE campaign_id = ? AND battle_id = ?", c.ID, b.ID)
		}
	}
	return nil
}

// afterNewState decides the notifications for a new current state.
func (s *Server) afterNewState(ctx context.Context, tx queryer, ob *outbox, c *campRow, seats []seatRow, meta *StateMeta, v int, kind string, inputs any) {
	all := meta.Humans
	cc := *c
	if meta.Phase == "over" {
		if meta.Winner == 1 {
			s.note(ctx, tx, ob, &cc, seats, "over", "won", "Victory! The campaign is won.", all)
		} else {
			s.note(ctx, tx, ob, &cc, seats, "over", "lost", "Defeat. The campaign is lost.", all)
		}
		return
	}
	forced := ""
	if m, ok := inputs.(map[string]any); ok && m["forced"] == true {
		forced = fmt.Sprintf(" after the timeout without %s", s.names(c, m["missing"].([]int)))
	}
	if kind == "turn" && len(meta.Battles) > 0 {
		var parts []string
		involved := map[int]bool{}
		for _, b := range meta.Battles {
			parts = append(parts, fmt.Sprintf("%s (%s)", c.region(b.R), s.names(c, b.Humans)))
			for _, f := range b.Humans {
				involved[f] = true
			}
		}
		var who []int
		for _, f := range all {
			if involved[f] {
				who = append(who, f)
			}
		}
		n := len(meta.Battles)
		pl := "s"
		if n == 1 {
			pl = ""
		}
		s.note(ctx, tx, ob, &cc, seats, fmt.Sprintf("resolved:%d", v), "turn_resolved",
			fmt.Sprintf("Turn %d resolved%s: %d battle%s pending involving your army: %s.", c.Turn+1, forced, n, pl, strings.Join(parts, ", ")), who)
		return
	}
	if meta.Phase == "plan" {
		text := fmt.Sprintf("Turn %d is ready to plan.", meta.Turn+1)
		if kind == "turn" {
			text = fmt.Sprintf("Turn %d resolved%s. Turn %d is ready to plan.", c.Turn+1, forced, meta.Turn+1)
		} else {
			text = fmt.Sprintf("All battles are resolved. Turn %d is ready to plan.", meta.Turn+1)
		}
		s.note(ctx, tx, ob, &cc, seats, fmt.Sprintf("turn:%d:%d", meta.Turn, v), "your_turn", text, meta.Alive)
	}
}

// --------------------------------------------------------------- history ---

func (s *Server) history(w http.ResponseWriter, r *http.Request, seat Seat) {
	rows, err := s.db.QueryContext(r.Context(), `SELECT version, parent, kind, turn, phase, hash, raw_size, length(blob),
		COALESCE(length(inputs), 0), by_f, rules, created_at FROM states WHERE campaign_id = ? ORDER BY version`, seat.Campaign)
	if err != nil {
		s.failErr(w, err)
		return
	}
	defer rows.Close()
	var list []map[string]any
	total := 0
	for rows.Next() {
		var v, p, turn, raw, stored, inl, by int
		var kind, phase, hash, rules string
		var at int64
		rows.Scan(&v, &p, &kind, &turn, &phase, &hash, &raw, &stored, &inl, &by, &rules, &at)
		total += stored + inl
		list = append(list, map[string]any{"version": v, "parent": p, "kind": kind, "turn": turn, "phase": phase,
			"hash": hash, "raw_size": raw, "stored_size": stored + inl, "by": by, "rules": rules, "at": at})
	}
	reply(w, 200, map[string]any{"versions": orEmptyMaps(list), "stored_bytes": total})
}

// GET /api/c/{id}/history/{v}?parent=1&state=0: one version with its inputs,
// optionally its parent's state (for re-running the resolution locally).
func (s *Server) historyVersion(w http.ResponseWriter, r *http.Request, seat Seat) {
	ctx := r.Context()
	v, _ := strconv.Atoi(r.PathValue("v"))
	row, err := loadState(ctx, s.db, seat.Campaign, v, true)
	if err != nil {
		s.failErr(w, err)
		return
	}
	head, _ := json.Marshal(map[string]any{"version": row.Version, "parent": row.Parent, "kind": row.Kind,
		"hash": row.Hash, "turn": row.Turn, "phase": row.Phase, "by": row.By, "rules": row.Rules, "at": row.At})
	var buf bytes.Buffer
	buf.Write(head[:len(head)-1])
	buf.WriteString(`,"inputs":`)
	buf.Write(row.inputsJSON())
	if r.URL.Query().Get("state") != "0" {
		text, err := row.text()
		if err != nil {
			s.failErr(w, err)
			return
		}
		buf.WriteString(`,"state":`)
		buf.Write(text)
	}
	if r.URL.Query().Get("parent") == "1" && row.Parent > 0 {
		pr, err := loadState(ctx, s.db, seat.Campaign, row.Parent, true)
		if err != nil {
			s.failErr(w, err)
			return
		}
		ptext, err := pr.text()
		if err != nil {
			s.failErr(w, err)
			return
		}
		buf.WriteString(`,"parent_hash":"` + pr.Hash + `","parent_state":`)
		buf.Write(ptext)
	}
	buf.WriteString("}")
	writeJSONBytes(w, r, buf.Bytes())
}

// POST /api/c/{id}/rollback {to_version, confirm: "rollback"}: the state of
// an older version becomes a new version (history is never rewritten).
func (s *Server) rollback(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		ToVersion int    `json:"to_version"`
		Confirm   string `json:"confirm"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if req.Confirm != "rollback" {
		fail(w, http.StatusBadRequest, "confirm", `send "confirm": "rollback" to roll the campaign back`)
		return
	}
	ob := &outbox{}
	var newV int
	var seq int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, err := loadCamp(ctx, tx, seat.Campaign)
		if err != nil {
			return err
		}
		if req.ToVersion <= 0 || req.ToVersion >= c.Version {
			return errf(http.StatusBadRequest, "bad_request", "to_version must be an earlier version (1-%d)", c.Version-1)
		}
		old, err := loadState(ctx, tx, c.ID, req.ToVersion, true)
		if err != nil {
			return err
		}
		text, err := old.text()
		if err != nil {
			return err
		}
		meta, err := ParseState(text)
		if err != nil {
			return err
		}
		now := ms(s.clock.Now())
		newV = c.Version + 1
		inb, _ := json.Marshal(map[string]any{"to_version": req.ToVersion, "from_version": c.Version})
		if _, err := tx.ExecContext(ctx, `INSERT INTO states (campaign_id, version, parent, kind, turn, phase, hash, blob, raw_size,
			inputs, by_f, rules, build, created_at) VALUES (?, ?, ?, 'rollback', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			c.ID, newV, c.Version, meta.Turn, meta.Phase, old.Hash, old.Blob, old.RawSize, store.Gzip(inb), seat.F,
			old.Rules, old.Build, now); err != nil {
			return err
		}
		if err := s.applyMeta(ctx, tx, c, meta, old.Hash, newV, now); err != nil {
			return err
		}
		tx.ExecContext(ctx, "DELETE FROM battle_claims WHERE campaign_id = ?", c.ID)
		tx.ExecContext(ctx, "DELETE FROM battle_flags WHERE campaign_id = ?", c.ID)
		tx.ExecContext(ctx, "DELETE FROM battle_live WHERE campaign_id = ?", c.ID)
		tx.ExecContext(ctx, "DELETE FROM battle_asks WHERE campaign_id = ?", c.ID)
		addActivity(ctx, tx, c.ID, now, seat.F, "rollback", map[string]any{"to": req.ToVersion, "version": newV})
		seats, _ := loadSeats(ctx, tx, c.ID)
		s.note(ctx, tx, ob, c, seats, fmt.Sprintf("rollback:%d", newV), "rollback",
			fmt.Sprintf("%s rolled the campaign back to version %d (turn %d).", c.faction(seat.F), req.ToVersion, meta.Turn+1), nil)
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	s.flush(ob)
	s.closeRoomsOf(seat.Campaign, nil)
	s.log.Warn("campaign rolled back", "campaign", seat.Campaign, "to", req.ToVersion, "version", newV, "f", seat.F)
	reply(w, 200, map[string]any{"ok": true, "version": newV})
}

// POST /api/c/{id}/verify: a client re-ran a version's resolution and
// reports whether it got the same hash (the cross-device determinism check).
func (s *Server) verifyReport(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		Version   int    `json:"version"`
		OK        bool   `json:"ok"`
		LocalHash string `json:"local_hash"`
		Ms        int    `json:"ms"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if req.OK {
		s.log.Info("determinism check passed", "campaign", seat.Campaign, "version", req.Version, "f", seat.F, "ms", req.Ms)
		reply(w, 200, map[string]any{"ok": true})
		return
	}
	s.log.Warn("DETERMINISM MISMATCH", "campaign", seat.Campaign, "version", req.Version, "f", seat.F, "local_hash", req.LocalHash)
	var seq int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		addActivity(r.Context(), tx, seat.Campaign, ms(s.clock.Now()), seat.F, "desync",
			map[string]any{"version": req.Version, "local_hash": clip(req.LocalHash, 16)})
		var err error
		seq, err = bumpSeq(r.Context(), tx, seat.Campaign)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	reply(w, 200, map[string]any{"ok": true})
}
