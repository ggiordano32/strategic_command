// Package store keeps the campaign server's data in one SQLite file
// (pure-Go driver, WAL mode). All access goes through one connection, so
// every transaction is serialised: the compare-and-swap on state versions,
// battle leases and submissions are plain "read, check, write" inside a
// transaction with no further locking.
package store

import (
	"bytes"
	"compress/gzip"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// DB wraps the SQLite handle.
type DB struct {
	*sql.DB
	Path string
}

const schema = `
CREATE TABLE IF NOT EXISTS campaigns (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	created_at INTEGER NOT NULL,
	format_version INTEGER NOT NULL,
	rules TEXT NOT NULL DEFAULT '',
	build TEXT NOT NULL DEFAULT '',
	humans TEXT NOT NULL,          -- JSON array of faction indices
	labels TEXT NOT NULL DEFAULT '{}', -- JSON {factions:[names], regions:[names]}
	join_code TEXT UNIQUE,         -- NULL once every seat is claimed or expired
	join_expires INTEGER NOT NULL DEFAULT 0,
	version INTEGER NOT NULL,      -- current state version
	hash TEXT NOT NULL,
	turn INTEGER NOT NULL,
	phase TEXT NOT NULL,
	winner INTEGER NOT NULL DEFAULT -1,
	alive TEXT NOT NULL DEFAULT '[]', -- JSON array: human factions still alive
	battles TEXT NOT NULL DEFAULT '[]', -- JSON [{id, r, humans:[f]}] pending battles with a human
	timeout_h INTEGER NOT NULL DEFAULT 0,
	subs_rev INTEGER NOT NULL DEFAULT 0, -- bumps on every submit / unsubmit
	deadline INTEGER NOT NULL DEFAULT 0, -- unix ms, 0 = none
	seq INTEGER NOT NULL DEFAULT 1,      -- change counter for long-polling clients
	webhook_url TEXT NOT NULL DEFAULT '',
	updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS seats (
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	f INTEGER NOT NULL,
	claimed INTEGER NOT NULL DEFAULT 0,
	claimed_at INTEGER NOT NULL DEFAULT 0,
	last_seen INTEGER NOT NULL DEFAULT 0,
	discord_user TEXT NOT NULL DEFAULT '',
	session BLOB,                  -- opaque per-seat blob (gzip)
	session_rev INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (campaign_id, f)
);
CREATE TABLE IF NOT EXISTS tokens (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	f INTEGER NOT NULL,
	hash TEXT NOT NULL UNIQUE,     -- sha256 hex of the token
	created_at INTEGER NOT NULL,
	last_used INTEGER NOT NULL DEFAULT 0,
	device TEXT NOT NULL DEFAULT '',
	revoked INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS tokens_campaign ON tokens(campaign_id);
CREATE TABLE IF NOT EXISTS link_codes (
	code TEXT PRIMARY KEY,
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	f INTEGER NOT NULL,
	expires INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS states (
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	version INTEGER NOT NULL,
	parent INTEGER NOT NULL,       -- 0 for the first
	kind TEXT NOT NULL,            -- create | turn | battle | rollback
	turn INTEGER NOT NULL,
	phase TEXT NOT NULL,
	hash TEXT NOT NULL,
	blob BLOB NOT NULL,            -- gzip of the canonical state JSON
	raw_size INTEGER NOT NULL,
	inputs BLOB,                   -- gzip JSON: what produced it from parent
	by_f INTEGER NOT NULL DEFAULT -1,
	rules TEXT NOT NULL DEFAULT '',
	build TEXT NOT NULL DEFAULT '',
	created_at INTEGER NOT NULL,
	PRIMARY KEY (campaign_id, version)
);
CREATE TABLE IF NOT EXISTS submissions (
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	version INTEGER NOT NULL,      -- the plan-phase state version it is for
	f INTEGER NOT NULL,
	turn INTEGER NOT NULL,
	body TEXT NOT NULL,            -- the submission JSON {turn, f, base, orders}
	submitted_at INTEGER NOT NULL,
	PRIMARY KEY (campaign_id, version, f)
);
CREATE TABLE IF NOT EXISTS battle_claims (
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	battle_id INTEGER NOT NULL,
	f INTEGER NOT NULL,            -- seat holding the lease
	token_id INTEGER NOT NULL,     -- device holding it
	mode TEXT NOT NULL,            -- fight | auto
	claimed_at INTEGER NOT NULL,
	lease_until INTEGER NOT NULL,
	PRIMARY KEY (campaign_id, battle_id)
);
CREATE TABLE IF NOT EXISTS battle_flags (
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	battle_id INTEGER NOT NULL,
	wait_by INTEGER NOT NULL DEFAULT -1,    -- seat that chose to wait for the ally
	wait_at INTEGER NOT NULL DEFAULT 0,
	command_by INTEGER NOT NULL DEFAULT -1, -- seat that took command of the ally's army
	command_at INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (campaign_id, battle_id)
);
-- Seats that took part in a live co-op battle (milestone 5): each may
-- upload its result, whoever's armies are in it.
CREATE TABLE IF NOT EXISTS battle_live (
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	battle_id INTEGER NOT NULL,
	f INTEGER NOT NULL,
	PRIMARY KEY (campaign_id, battle_id, f)
);
CREATE TABLE IF NOT EXISTS activity (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
	at INTEGER NOT NULL,
	f INTEGER NOT NULL DEFAULT -1,
	kind TEXT NOT NULL,
	data TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS activity_campaign ON activity(campaign_id, id);
CREATE TABLE IF NOT EXISTS notif_sent (
	campaign_id TEXT NOT NULL,
	key TEXT NOT NULL,
	at INTEGER NOT NULL,
	PRIMARY KEY (campaign_id, key)
);
`

// Open opens (creating if needed) the database at path.
func Open(path string) (*DB, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	dsn := "file:" + path + "?_pragma=busy_timeout(10000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)&_pragma=synchronous(NORMAL)&_txlock=immediate"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// One connection: transactions never interleave (see package comment).
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(0)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("schema: %w", err)
	}
	_ = os.Chmod(path, 0o600)
	return &DB{DB: db, Path: path}, nil
}

// Tx runs fn in a transaction, committing if it returns nil.
func (d *DB) Tx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := d.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

// Backup writes a consistent copy of the database to dir with VACUUM INTO
// and keeps the newest `keep` copies. Returns the new file's path.
func (d *DB) Backup(ctx context.Context, dir string, now time.Time, keep int) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	name := "sc-" + now.UTC().Format("20060102-150405") + ".db"
	path := filepath.Join(dir, name)
	if _, err := os.Stat(path); err == nil {
		return path, nil
	}
	if _, err := d.ExecContext(ctx, "VACUUM INTO ?", path); err != nil {
		return "", err
	}
	_ = os.Chmod(path, 0o600)
	ents, err := os.ReadDir(dir)
	if err != nil {
		return path, nil
	}
	var olds []string
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), "sc-") && strings.HasSuffix(e.Name(), ".db") {
			olds = append(olds, e.Name())
		}
	}
	sort.Strings(olds)
	for len(olds) > keep && keep > 0 {
		os.Remove(filepath.Join(dir, olds[0]))
		olds = olds[1:]
	}
	return path, nil
}

// Gzip compresses b.
func Gzip(b []byte) []byte {
	var buf bytes.Buffer
	w, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	w.Write(b)
	w.Close()
	return buf.Bytes()
}

// ErrTooLarge is returned by Gunzip when the output exceeds the limit.
var ErrTooLarge = errors.New("decompressed data too large")

// Gunzip decompresses b, refusing more than max bytes of output.
func Gunzip(b []byte, max int64) ([]byte, error) {
	r, err := gzip.NewReader(bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	defer r.Close()
	out, err := io.ReadAll(io.LimitReader(r, max+1))
	if err != nil {
		return nil, err
	}
	if int64(len(out)) > max {
		return nil, ErrTooLarge
	}
	return out, nil
}
