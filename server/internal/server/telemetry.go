package server

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// Telemetry is the playtest log endpoint, behaving like tools/serve_web.py
// so tools/playtest_report.py reads its files unchanged: POST /telemetry
// takes one record object or {"records": [...]}; each record becomes one
// JSON line in <log dir>/YYYY-MM-DD.jsonl (UTC date) with "recv" (server
// UTC time, ISO 8601 with milliseconds) and "ip" first; GET returns a
// small status object.
type Telemetry struct {
	dir   string
	clock Clock
	mu    sync.Mutex
	stats struct {
		Records, Posts, Rejected int
		Started                  string
	}
}

const (
	teleMaxBody    = 512 * 1024
	teleMaxRecords = 2000
	teleMaxRecord  = 64 * 1024
)

func NewTelemetry(dir string, clock Clock) *Telemetry {
	t := &Telemetry{dir: dir, clock: clock}
	t.stats.Started = clock.Now().UTC().Format("2006-01-02T15:04:05+00:00")
	return t
}

func (t *Telemetry) logPath() string {
	return filepath.Join(t.dir, t.clock.Now().UTC().Format("2006-01-02")+".jsonl")
}

func (t *Telemetry) Status(w http.ResponseWriter, r *http.Request) {
	t.mu.Lock()
	out := map[string]any{"records": t.stats.Records, "posts": t.stats.Posts, "rejected": t.stats.Rejected,
		"started": t.stats.Started, "ok": true, "log_file": t.logPath()}
	t.mu.Unlock()
	w.Header().Set("Cache-Control", "no-store")
	reply(w, 200, out)
}

func (t *Telemetry) reject(w http.ResponseWriter, code int, msg string) {
	t.mu.Lock()
	t.stats.Rejected++
	t.mu.Unlock()
	w.Header().Set("Cache-Control", "no-store")
	reply(w, code, map[string]any{"ok": false, "error": msg})
}

func (t *Telemetry) Post(w http.ResponseWriter, r *http.Request) {
	if r.ContentLength > teleMaxBody {
		t.reject(w, http.StatusRequestEntityTooLarge, "body too large or bad length")
		return
	}
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, teleMaxBody))
	if err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			t.reject(w, http.StatusRequestEntityTooLarge, "body too large or bad length")
			return
		}
		t.reject(w, http.StatusBadRequest, "invalid json")
		return
	}
	var top any
	if json.Unmarshal(raw, &top) != nil {
		t.reject(w, http.StatusBadRequest, "invalid json")
		return
	}
	var records []json.RawMessage
	switch v := top.(type) {
	case map[string]any:
		if _, ok := v["records"].([]any); ok {
			var env struct {
				Records []json.RawMessage `json:"records"`
			}
			json.Unmarshal(raw, &env)
			records = env.Records
			if len(records) > teleMaxRecords {
				records = records[:teleMaxRecords]
			}
		} else {
			records = []json.RawMessage{raw}
		}
	default:
		t.reject(w, http.StatusBadRequest, "expected an object")
		return
	}
	now := t.clock.Now().UTC()
	recv := now.Format("2006-01-02T15:04:05.000+00:00")
	// Like serve_web.py: the socket peer, and with X-Forwarded-For (behind
	// Caddy) "<first forwarded address> via <peer>" (not trusted; for
	// grouping devices in the report only).
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		ip = r.RemoteAddr
	}
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		first := strings.TrimSpace(strings.Split(fwd, ",")[0])
		if len(first) > 64 {
			first = first[:64]
		}
		ip = first + " via " + ip
	}
	var lines [][]byte
	for _, rec := range records {
		line, ok := stampRecord(rec, recv, ip)
		if ok && len(line) <= teleMaxRecord {
			lines = append(lines, line)
		}
	}
	if len(lines) > 0 {
		t.mu.Lock()
		err := t.write(lines)
		if err == nil {
			t.stats.Records += len(lines)
			t.stats.Posts++
		}
		t.mu.Unlock()
		if err != nil {
			reply(w, 500, map[string]any{"ok": false, "error": "OSError"})
			return
		}
	}
	w.Header().Set("Cache-Control", "no-store")
	reply(w, 200, map[string]any{"ok": true, "stored": len(lines)})
}

func (t *Telemetry) write(lines [][]byte) error {
	if err := os.MkdirAll(t.dir, 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(t.logPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	var buf bytes.Buffer
	for _, l := range lines {
		buf.Write(l)
		buf.WriteByte('\n')
	}
	_, err = f.Write(buf.Bytes())
	return err
}

// stampRecord writes {"recv":..,"ip":..,<the record's other keys in order>}
// compactly; records that are not objects are skipped.
func stampRecord(rec json.RawMessage, recv, ip string) ([]byte, bool) {
	dec := json.NewDecoder(bytes.NewReader(rec))
	dec.UseNumber()
	tok, err := dec.Token()
	if err != nil {
		return nil, false
	}
	if d, ok := tok.(json.Delim); !ok || d != '{' {
		return nil, false
	}
	var out bytes.Buffer
	out.WriteString(`{"recv":`)
	rb, _ := json.Marshal(recv)
	out.Write(rb)
	out.WriteString(`,"ip":`)
	ib, _ := json.Marshal(ip)
	out.Write(ib)
	seen := map[string]bool{}
	for dec.More() {
		kt, err := dec.Token()
		if err != nil {
			return nil, false
		}
		key, _ := kt.(string)
		var val json.RawMessage
		if err := dec.Decode(&val); err != nil {
			return nil, false
		}
		if key == "recv" || key == "ip" || seen[key] {
			continue
		}
		seen[key] = true
		var cv bytes.Buffer
		if json.Compact(&cv, val) != nil {
			return nil, false
		}
		kb, _ := json.Marshal(key)
		out.WriteByte(',')
		out.Write(kb)
		out.WriteByte(':')
		out.Write(cv.Bytes())
	}
	out.WriteByte('}')
	return out.Bytes(), true
}
