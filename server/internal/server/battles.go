package server

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
)

// Pending battles. A seat may command a battle when its own faction is the
// only human in it, or when it has taken command of the ally's army there
// (choice "command"). Fighting or auto-resolving needs a lease (claim) so
// two devices never resolve the same battle at once; the lease lasts
// cfg.LeaseDuration and is renewed by heartbeats, released by the result
// upload, by release, or by expiring (a closed page).

func (s *Server) mayCommand(ctx context.Context, q queryer, c *campRow, b *Battle, seat Seat) error {
	others := false
	for _, f := range b.Humans {
		if f != seat.F {
			others = true
		}
	}
	if hasInt(b.Humans, seat.F) && !others {
		return nil
	}
	var cmd int
	err := q.QueryRowContext(ctx, "SELECT command_by FROM battle_flags WHERE campaign_id = ? AND battle_id = ?", c.ID, b.ID).Scan(&cmd)
	if err == nil && cmd == seat.F {
		return nil
	}
	// A seat that took part in the battle fought live (rooms.go).
	var one int
	if q.QueryRowContext(ctx, "SELECT 1 FROM battle_live WHERE campaign_id = ? AND battle_id = ? AND f = ?", c.ID, b.ID, seat.F).Scan(&one) == nil {
		return nil
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	e := errf(http.StatusForbidden, "need_command", "the ally's army is in this battle: wait for them or take command first")
	e.extra = map[string]any{"humans": b.Humans}
	return e
}

func (s *Server) battleOf(ctx context.Context, q queryer, seat Seat, r *http.Request) (*campRow, *Battle, error) {
	bid, err := strconv.Atoi(r.PathValue("bid"))
	if err != nil {
		return nil, nil, errf(http.StatusBadRequest, "bad_request", "bad battle id")
	}
	c, err := loadCamp(ctx, q, seat.Campaign)
	if err != nil {
		return nil, nil, err
	}
	b := c.battle(bid)
	if b == nil {
		return c, nil, conflict(c, "battle %d is not pending", bid)
	}
	return c, b, nil
}

// POST /api/c/{id}/battles/{bid}/claim {mode: fight | auto}
func (s *Server) claimBattle(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		Mode string `json:"mode"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if req.Mode != "fight" && req.Mode != "auto" {
		fail(w, http.StatusBadRequest, "bad_request", "mode must be fight or auto")
		return
	}
	var until int64
	var seq int64
	// A battle fought live is held by its room (checked outside the
	// transaction: room locks are never taken while holding the database).
	if bid, err := strconv.Atoi(r.PathValue("bid")); err == nil {
		if li := s.liveInfo(seat.Campaign, bid); li != nil {
			e := errf(http.StatusConflict, "claimed", "this battle is being fought live")
			e.extra = map[string]any{"held_by": li["host"], "mode": "live"}
			s.failErr(w, e)
			return
		}
	}
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, b, err := s.battleOf(ctx, tx, seat, r)
		if err != nil {
			return err
		}
		if err := s.mayCommand(ctx, tx, c, b, seat); err != nil {
			return err
		}
		now := ms(s.clock.Now())
		var holder int64
		var hf int
		var hu int64
		var hmode string
		err = tx.QueryRowContext(ctx, "SELECT token_id, f, lease_until, mode FROM battle_claims WHERE campaign_id = ? AND battle_id = ?",
			c.ID, b.ID).Scan(&holder, &hf, &hu, &hmode)
		if err == nil && hu > now && holder != seat.TokenID {
			e := errf(http.StatusConflict, "claimed", "%s is already resolving this battle", c.faction(hf))
			e.extra = map[string]any{"held_by": hf, "mode": hmode, "until": hu}
			return e
		}
		until = now + s.cfg.LeaseDuration.Milliseconds()
		if _, err := tx.ExecContext(ctx, `INSERT INTO battle_claims (campaign_id, battle_id, f, token_id, mode, claimed_at, lease_until)
			VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (campaign_id, battle_id) DO UPDATE SET f = excluded.f,
			token_id = excluded.token_id, mode = excluded.mode, claimed_at = excluded.claimed_at, lease_until = excluded.lease_until`,
			c.ID, b.ID, seat.F, seat.TokenID, req.Mode, now, until); err != nil {
			return err
		}
		addActivity(ctx, tx, c.ID, now, seat.F, "battle_claimed", map[string]any{"battle": b.ID, "mode": req.Mode, "region": b.R})
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	reply(w, 200, map[string]any{"ok": true, "until": until, "lease_ms": s.cfg.LeaseDuration.Milliseconds()})
}

// POST /api/c/{id}/battles/{bid}/heartbeat: extend this device's lease.
func (s *Server) heartbeatBattle(w http.ResponseWriter, r *http.Request, seat Seat) {
	var until int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, b, err := s.battleOf(ctx, tx, seat, r)
		if err != nil {
			return err
		}
		now := ms(s.clock.Now())
		var holder, hu int64
		var hf int
		err = tx.QueryRowContext(ctx, "SELECT token_id, f, lease_until FROM battle_claims WHERE campaign_id = ? AND battle_id = ?",
			c.ID, b.ID).Scan(&holder, &hf, &hu)
		if errors.Is(err, sql.ErrNoRows) || (holder != seat.TokenID && hu > now) {
			e := errf(http.StatusConflict, "lost_lease", "you no longer hold this battle")
			if err == nil {
				e.extra = map[string]any{"held_by": hf}
			}
			return e
		}
		if err != nil {
			return err
		}
		if holder != seat.TokenID {
			// Expired and taken by nobody since: take it back.
			tx.ExecContext(ctx, "UPDATE battle_claims SET token_id = ?, f = ? WHERE campaign_id = ? AND battle_id = ?", seat.TokenID, seat.F, c.ID, b.ID)
		}
		until = now + s.cfg.LeaseDuration.Milliseconds()
		_, err = tx.ExecContext(ctx, "UPDATE battle_claims SET lease_until = ? WHERE campaign_id = ? AND battle_id = ?", until, c.ID, b.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	reply(w, 200, map[string]any{"ok": true, "until": until})
}

// POST /api/c/{id}/battles/{bid}/release
func (s *Server) releaseBattle(w http.ResponseWriter, r *http.Request, seat Seat) {
	var seq int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, b, err := s.battleOf(ctx, tx, seat, r)
		if err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, "DELETE FROM battle_claims WHERE campaign_id = ? AND battle_id = ? AND token_id = ?", c.ID, b.ID, seat.TokenID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n > 0 {
			addActivity(ctx, tx, c.ID, ms(s.clock.Now()), seat.F, "battle_released", map[string]any{"battle": b.ID})
			seq, err = bumpSeq(ctx, tx, c.ID)
		}
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

// POST /api/c/{id}/battles/{bid}/choice {choice: wait | command | ask}: when
// the ally's army is in the battle, wait for the ally (they are pinged) or
// take command of their army (they are told); or ask to join the battle
// live (any alive human seat, army in it or not: the battle's humans see it
// in the summary's ask_by and are pinged).
func (s *Server) battleChoice(w http.ResponseWriter, r *http.Request, seat Seat) {
	var req struct {
		Choice string `json:"choice"`
	}
	if err := readJSON(w, r, maxBody, &req); err != nil {
		s.failErr(w, err)
		return
	}
	if req.Choice != "wait" && req.Choice != "command" && req.Choice != "ask" {
		fail(w, http.StatusBadRequest, "bad_request", "choice must be wait, command or ask")
		return
	}
	ob := &outbox{}
	var seq int64
	err := s.db.Tx(r.Context(), func(tx *sql.Tx) error {
		ctx := r.Context()
		c, b, err := s.battleOf(ctx, tx, seat, r)
		if err != nil {
			return err
		}
		var others []int
		for _, f := range b.Humans {
			if f != seat.F {
				others = append(others, f)
			}
		}
		if len(others) == 0 {
			return errf(http.StatusBadRequest, "not_needed", "only your own army is in this battle")
		}
		now := s.clock.Now()
		tx.ExecContext(ctx, "INSERT OR IGNORE INTO battle_flags (campaign_id, battle_id) VALUES (?, ?)", c.ID, b.ID)
		seats, _ := loadSeats(ctx, tx, c.ID)
		if req.Choice == "ask" {
			if !hasInt(c.Alive, seat.F) {
				return errf(http.StatusForbidden, "not_alive", "your faction is out of the campaign")
			}
			tx.ExecContext(ctx, "INSERT OR IGNORE INTO battle_asks (campaign_id, battle_id, f, at) VALUES (?, ?, ?, ?)", c.ID, b.ID, seat.F, ms(now))
			s.note(ctx, tx, ob, c, seats, fmt.Sprintf("ask:%d:%d:%d", b.ID, seat.F, ms(now)/waitPingBucket.Milliseconds()), "ask",
				fmt.Sprintf("%s asks to join the battle at %s: open it with Fight together.", c.faction(seat.F), c.region(b.R)), others)
		} else if req.Choice == "wait" {
			tx.ExecContext(ctx, "UPDATE battle_flags SET wait_by = ?, wait_at = ? WHERE campaign_id = ? AND battle_id = ?", seat.F, ms(now), c.ID, b.ID)
			s.note(ctx, tx, ob, c, seats, fmt.Sprintf("wait:%d:%d:%d", b.ID, seat.F, ms(now)/waitPingBucket.Milliseconds()), "wait",
				fmt.Sprintf("%s is waiting for you to fight the battle at %s.", c.faction(seat.F), c.region(b.R)), others)
		} else {
			tx.ExecContext(ctx, "UPDATE battle_flags SET command_by = ?, command_at = ? WHERE campaign_id = ? AND battle_id = ?", seat.F, ms(now), c.ID, b.ID)
			s.note(ctx, tx, ob, c, seats, fmt.Sprintf("command:%d:%d", b.ID, seat.F), "took_command",
				fmt.Sprintf("%s took command of your army at %s.", c.faction(seat.F), c.region(b.R)), others)
		}
		addActivity(ctx, tx, c.ID, ms(now), seat.F, "battle_"+req.Choice, map[string]any{"battle": b.ID, "region": b.R})
		seq, err = bumpSeq(ctx, tx, c.ID)
		return err
	})
	if err != nil {
		s.failErr(w, err)
		return
	}
	s.hub.Notify(seat.Campaign, seq)
	s.flush(ob)
	reply(w, 200, map[string]any{"ok": true})
}
