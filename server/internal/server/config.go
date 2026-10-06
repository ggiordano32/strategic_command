package server

import (
	"net/netip"
	"strings"
	"sync/atomic"
	"time"
)

// Config is everything the server needs; filled from flags / env by main.
type Config struct {
	Addr          string         // listen address, e.g. ":8060"
	DataDir       string         // SQLite file, backups, compressed-file cache
	WebDir        string         // the Godot web export (build/web)
	LogDir        string         // playtest telemetry JSONL files
	InviteKey     string         // if set, required to create a campaign
	TrustedProxy  []netip.Prefix // peers whose X-Forwarded-For is believed
	BackupEvery   time.Duration  // 0 = no periodic backups
	BackupKeep    int
	TestMode      bool // enables /api/test/* and any webhook URL (never in production)
	PublicURL     string
	CompressWeb   bool // precompress the web build (gzip + brotli)
	BrotliMax     bool // also make a quality-11 brotli copy in the background
	LeaseDuration time.Duration
	RoomGrace     time.Duration // an empty live room is kept this long for reconnects
	CustomTTL     time.Duration // an empty custom battle lobby is kept this long
}

// DefaultTrusted is the default trusted-proxy list: loopback and private
// ranges (Caddy on the LAN or on the same host).
const DefaultTrusted = "127.0.0.0/8,::1/128,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fc00::/7"

// ParsePrefixes parses a comma-separated list of CIDRs or addresses.
func ParsePrefixes(s string) ([]netip.Prefix, error) {
	var out []netip.Prefix
	for _, p := range strings.Split(s, ",") {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if !strings.Contains(p, "/") {
			a, err := netip.ParseAddr(p)
			if err != nil {
				return nil, err
			}
			out = append(out, netip.PrefixFrom(a, a.BitLen()))
			continue
		}
		pr, err := netip.ParsePrefix(p)
		if err != nil {
			return nil, err
		}
		out = append(out, pr.Masked())
	}
	return out, nil
}

// Clock is the server's time source; tests and test mode shift it.
type Clock interface {
	Now() time.Time
}

// OffsetClock is the real time plus an adjustable offset.
type OffsetClock struct{ off atomic.Int64 }

func (c *OffsetClock) Now() time.Time { return time.Now().Add(time.Duration(c.off.Load())) }

// Advance moves the clock forward by d.
func (c *OffsetClock) Advance(d time.Duration) { c.off.Add(int64(d)) }

func ms(t time.Time) int64 { return t.UnixMilli() }
