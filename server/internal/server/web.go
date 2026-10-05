package server

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"log/slog"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/andybalholm/brotli"
)

// Web serves the Godot web export. Every response says "no-cache" with an
// ETag, so browsers revalidate on each load (a stale build is never used)
// but get a cheap 304 when nothing changed. Large compressible files
// (the 39 MB .wasm, .pck, .js) are compressed once per build in the
// background (gzip-9 and brotli-9, then brotli-11) and cached on disk by
// content hash; until a variant is ready the file is sent as is.
type Web struct {
	dir      string
	cacheDir string
	compress bool
	brMax    bool
	log      *slog.Logger
	mu       sync.Mutex
	files    map[string]*webFile
	stop     chan struct{}
	wg       sync.WaitGroup
}

type webFile struct {
	mu      sync.Mutex
	size    int64
	mtime   time.Time
	etag    string
	sum     string
	data    []byte
	gz      []byte
	br      []byte
	brLevel int
	working bool
}

var mimeTypes = map[string]string{
	".html":        "text/html; charset=utf-8",
	".js":          "application/javascript",
	".wasm":        "application/wasm",
	".pck":         "application/octet-stream",
	".png":         "image/png",
	".svg":         "image/svg+xml",
	".ico":         "image/x-icon",
	".json":        "application/json",
	".webmanifest": "application/manifest+json",
	".txt":         "text/plain; charset=utf-8",
	".css":         "text/css; charset=utf-8",
}

var compressible = map[string]bool{".html": true, ".js": true, ".wasm": true, ".pck": true, ".json": true,
	".svg": true, ".txt": true, ".css": true, ".webmanifest": true}

func NewWeb(dir, cacheDir string, compress, brMax bool, log *slog.Logger) *Web {
	return &Web{dir: dir, cacheDir: cacheDir, compress: compress, brMax: brMax, log: log,
		files: map[string]*webFile{}, stop: make(chan struct{})}
}

// Warm loads and starts compressing the main files of the build.
func (wb *Web) Warm() {
	for _, n := range []string{"index.html", "index.js", "index.wasm", "index.pck"} {
		if f := wb.file(n); f != nil {
			wb.maybeCompress(f, n)
		}
	}
}

// Stop tells background compression not to start new work. It does not
// wait: a brotli-11 pass over the wasm takes about 100 s and cannot be
// interrupted, and its cache file is written atomically (rename), so a
// shutdown in the middle loses nothing.
func (wb *Web) Stop() {
	select {
	case <-wb.stop:
	default:
		close(wb.stop)
	}
}

// BuildStamp is build_stamp.txt next to the export (written by
// tools/export_web.sh), so clients can tell a new deploy.
func (wb *Web) BuildStamp() string {
	b, err := os.ReadFile(filepath.Join(wb.dir, "build_stamp.txt"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// file returns the cached file, reloading it if it changed on disk.
func (wb *Web) file(name string) *webFile {
	full := filepath.Join(wb.dir, filepath.FromSlash(name))
	st, err := os.Stat(full)
	if err != nil || !st.Mode().IsRegular() {
		return nil
	}
	wb.mu.Lock()
	f := wb.files[name]
	if f == nil {
		f = &webFile{}
		wb.files[name] = f
	}
	wb.mu.Unlock()
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.data != nil && f.size == st.Size() && f.mtime.Equal(st.ModTime()) {
		return f
	}
	data, err := os.ReadFile(full)
	if err != nil {
		return nil
	}
	sum := sha256.Sum256(data)
	f.data, f.size, f.mtime = data, st.Size(), st.ModTime()
	f.sum = hex.EncodeToString(sum[:])
	f.etag = `"` + f.sum[:20] + `"`
	f.gz, f.br, f.brLevel = nil, nil, 0
	return f
}

func (wb *Web) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && r.Method != "HEAD" {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p := path.Clean("/" + r.URL.Path)
	if p == "/" {
		p = "/index.html"
	}
	name := strings.TrimPrefix(p, "/")
	for _, part := range strings.Split(name, "/") {
		if strings.HasPrefix(part, ".") {
			http.NotFound(w, r)
			return
		}
	}
	f := wb.file(name)
	if f == nil {
		http.NotFound(w, r)
		return
	}
	ext := strings.ToLower(path.Ext(name))
	ct := mimeTypes[ext]
	if ct == "" {
		ct = "application/octet-stream"
	}
	h := w.Header()
	h.Set("Content-Type", ct)
	h.Set("Cache-Control", "no-cache")
	h.Set("X-Content-Type-Options", "nosniff")
	if ext == ".html" {
		h.Set("Referrer-Policy", "same-origin")
	}
	f.mu.Lock()
	data, etag, gz, br := f.data, f.etag, f.gz, f.br
	f.mu.Unlock()
	if compressible[ext] {
		h.Set("Vary", "Accept-Encoding")
		wb.maybeCompress(f, name)
	}
	body := data
	ae := r.Header.Get("Accept-Encoding")
	switch {
	case br != nil && acceptsEnc(ae, "br"):
		body = br
		h.Set("Content-Encoding", "br")
		etag = etag[:len(etag)-1] + `-br"`
	case gz != nil && acceptsEnc(ae, "gzip"):
		body = gz
		h.Set("Content-Encoding", "gzip")
		etag = etag[:len(etag)-1] + `-gz"`
	}
	h.Set("ETag", etag)
	// ServeContent handles If-None-Match (304), HEAD and ranges.
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(body))
}

func acceptsEnc(header, enc string) bool {
	for _, part := range strings.Split(header, ",") {
		p := strings.TrimSpace(part)
		name, q, _ := strings.Cut(p, ";")
		if strings.TrimSpace(name) == enc {
			q = strings.TrimSpace(q)
			return q != "q=0" && q != "q=0.0"
		}
	}
	return false
}

// maybeCompress starts background compression of f if needed.
func (wb *Web) maybeCompress(f *webFile, name string) {
	if !wb.compress || !compressible[strings.ToLower(path.Ext(name))] {
		return
	}
	f.mu.Lock()
	need := (f.gz == nil || f.br == nil || (wb.brMax && f.brLevel < 11)) && len(f.data) > 1024 && !f.working
	if !need {
		f.mu.Unlock()
		return
	}
	f.working = true
	data, sum := f.data, f.sum
	f.mu.Unlock()
	wb.wg.Add(1)
	go func() {
		defer wb.wg.Done()
		defer func() { f.mu.Lock(); f.working = false; f.mu.Unlock() }()
		gz := wb.cached(sum, "gz", func() []byte {
			var b bytes.Buffer
			w, _ := gzip.NewWriterLevel(&b, gzip.BestCompression)
			w.Write(data)
			w.Close()
			return b.Bytes()
		})
		br9 := wb.cached(sum, "br9", func() []byte { return brotliBytes(data, 9) })
		if !wb.set(f, sum, gz, br9, 9) {
			return
		}
		if len(data) < 64<<10 || !wb.brMax {
			return
		}
		select {
		case <-wb.stop:
			return
		default:
		}
		t := time.Now()
		br11 := wb.cached(sum, "br11", func() []byte { return brotliBytes(data, 11) })
		if wb.set(f, sum, gz, br11, 11) {
			wb.log.Info("web file compressed (brotli 11)", "file", name, "raw", len(data), "br", len(br11), "gz", len(gz), "s", time.Since(t).Seconds())
		}
	}()
}

func (wb *Web) set(f *webFile, sum string, gz, br []byte, level int) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.sum != sum { // the file changed meanwhile
		return false
	}
	if gz != nil && len(gz) < len(f.data) {
		f.gz = gz
	}
	if br != nil && len(br) < len(f.data) && level >= f.brLevel {
		f.br, f.brLevel = br, level
	}
	return true
}

func brotliBytes(data []byte, q int) []byte {
	var b bytes.Buffer
	w := brotli.NewWriterLevel(&b, q)
	w.Write(data)
	w.Close()
	return b.Bytes()
}

// cached returns the compressed variant from the disk cache or makes it.
func (wb *Web) cached(sum, kind string, make func() []byte) []byte {
	p := filepath.Join(wb.cacheDir, sum[:32]+"."+kind)
	if b, err := os.ReadFile(p); err == nil && len(b) > 0 {
		return b
	}
	b := make()
	if err := os.MkdirAll(wb.cacheDir, 0o700); err == nil {
		tmp := p + ".tmp"
		if os.WriteFile(tmp, b, 0o600) == nil {
			os.Rename(tmp, p)
		}
	}
	wb.pruneCache()
	return b
}

// pruneCache keeps the cache from growing forever: files older than 3 days
// that are not the current build's are removed.
func (wb *Web) pruneCache() {
	ents, err := os.ReadDir(wb.cacheDir)
	if err != nil {
		return
	}
	wb.mu.Lock()
	cur := map[string]bool{}
	for _, f := range wb.files {
		if len(f.sum) >= 32 {
			cur[f.sum[:32]] = true
		}
	}
	wb.mu.Unlock()
	for _, e := range ents {
		n := e.Name()
		if len(n) < 32 || cur[n[:32]] {
			continue
		}
		if info, err := e.Info(); err == nil && time.Since(info.ModTime()) > 72*time.Hour {
			os.Remove(filepath.Join(wb.cacheDir, n))
		}
	}
}
