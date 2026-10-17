package server

import (
	"context"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func (e *env) do(method, path, origin string, hdr map[string]string, body string) *http.Response {
	e.t.Helper()
	req, _ := http.NewRequest(method, e.ts.URL+path, strings.NewReader(body))
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	resp.Body.Close()
	return resp
}

func (e *env) wsOrigin(origin string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	u := "ws" + strings.TrimPrefix(e.ts.URL, "http") + "/api/c/nope/ws"
	c, _, err := websocket.Dial(ctx, u, &websocket.DialOptions{HTTPHeader: http.Header{"Origin": {origin}}})
	if err == nil {
		c.CloseNow()
	}
	return err
}

func TestAllowedOrigins(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.AllowedOrigins = ParseOrigins("https://game.example/, http://127.0.0.1:9") })
	pre := map[string]string{"Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type,authorization"}
	r := e.do("OPTIONS", "/api/campaigns", "https://game.example", pre, "")
	if r.StatusCode != 204 || r.Header.Get("Access-Control-Allow-Origin") != "https://game.example" ||
		!strings.Contains(r.Header.Get("Access-Control-Allow-Headers"), "Authorization") ||
		r.Header.Get("Access-Control-Max-Age") == "" || !strings.Contains(r.Header.Get("Vary"), "Origin") {
		t.Fatalf("preflight: %d %v", r.StatusCode, r.Header)
	}
	r = e.do("POST", "/api/join/preview", "https://game.example", nil, "{}")
	if r.StatusCode == 403 || r.Header.Get("Access-Control-Allow-Origin") != "https://game.example" {
		t.Fatalf("allowed POST: %d %v", r.StatusCode, r.Header)
	}
	r = e.do("GET", "/api/info", "https://game.example", nil, "")
	if r.StatusCode != 200 || r.Header.Get("Access-Control-Allow-Origin") == "" {
		t.Fatalf("allowed GET: %d", r.StatusCode)
	}
	// A foreign origin: preflight and POST refused, no allow header.
	r = e.do("OPTIONS", "/api/campaigns", "https://evil.example", pre, "")
	if r.StatusCode != 403 || r.Header.Get("Access-Control-Allow-Origin") != "" {
		t.Fatalf("foreign preflight: %d", r.StatusCode)
	}
	r = e.do("POST", "/api/join/preview", "https://evil.example", nil, "{}")
	if r.StatusCode != 403 || r.Header.Get("Access-Control-Allow-Origin") != "" {
		t.Fatalf("foreign POST: %d", r.StatusCode)
	}
	// No Origin (native client) still works.
	if r = e.do("POST", "/api/join/preview", "", nil, "{}"); r.StatusCode == 403 {
		t.Fatalf("native POST refused")
	}
	// WebSocket.
	if err := e.wsOrigin("https://game.example"); err != nil {
		t.Fatalf("allowed ws: %v", err)
	}
	if err := e.wsOrigin("https://evil.example"); err == nil {
		t.Fatalf("foreign ws accepted")
	}
	// Telemetry / healthz preflight too.
	if r = e.do("OPTIONS", "/telemetry", "https://game.example", pre, ""); r.StatusCode != 204 {
		t.Fatalf("telemetry preflight: %d", r.StatusCode)
	}
}

func TestAllowedOriginsStar(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.AllowedOrigins = ParseOrigins("*") })
	pre := map[string]string{"Access-Control-Request-Method": "POST"}
	if r := e.do("OPTIONS", "/api/campaigns", "https://anything.example", pre, ""); r.StatusCode != 204 {
		t.Fatalf("star preflight: %d", r.StatusCode)
	}
	if r := e.do("POST", "/api/join/preview", "https://anything.example", nil, "{}"); r.StatusCode == 403 {
		t.Fatalf("star POST refused")
	}
	if err := e.wsOrigin("https://anything.example"); err != nil {
		t.Fatalf("star ws: %v", err)
	}
}

func TestNoAllowedOriginsUnchanged(t *testing.T) {
	e := newEnv(t, nil)
	r := e.do("GET", "/api/info", "https://game.example", nil, "")
	if r.Header.Get("Access-Control-Allow-Origin") != "" || r.Header.Get("Vary") != "" {
		t.Fatalf("CORS headers with no allow-list: %v", r.Header)
	}
	if r = e.do("OPTIONS", "/api/campaigns", "https://game.example", map[string]string{"Access-Control-Request-Method": "POST"}, ""); r.StatusCode != 403 {
		t.Fatalf("preflight: %d", r.StatusCode)
	}
	if err := e.wsOrigin("https://game.example"); err == nil {
		t.Fatalf("foreign ws accepted by default")
	}
	// Same-origin Origin header on the WebSocket still works.
	u, _ := url.Parse(e.ts.URL)
	if err := e.wsOrigin("http://" + u.Host); err != nil {
		t.Fatalf("same-origin ws: %v", err)
	}
}

func TestNoWebDir(t *testing.T) {
	for _, web := range []string{"", "missing"} {
		e := newEnv(t, func(c *Config) {
			if web == "" {
				c.WebDir = ""
			} else {
				c.WebDir = filepath.Join(os.TempDir(), "sc-no-such-web-dir")
			}
			c.GameURL = "https://game.example/play"
		})
		resp, err := http.Get(e.ts.URL + "/")
		if err != nil {
			t.Fatal(err)
		}
		buf := make([]byte, 400)
		n, _ := resp.Body.Read(buf)
		resp.Body.Close()
		got := string(buf[:n])
		if resp.StatusCode != 200 || !strings.Contains(got, "Strategic Command game server "+Version) ||
			!strings.Contains(got, "the game is at https://game.example/play") {
			t.Fatalf("root %q: %d %q", web, resp.StatusCode, got)
		}
		if st, info := e.call("GET", "/api/info", "", nil); st != 200 || info["state_version"] != float64(StateVersion) {
			t.Fatalf("info: %d %v", st, info)
		}
		if st, _ := e.call("GET", "/index.html", "", nil); st != 404 {
			t.Fatalf("index.html: %d", st)
		}
	}
}

func TestAllowedOriginsWildcard(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.AllowedOrigins = ParseOrigins("https://*.itch.zone, https://*.port.test:8443") })
	pre := map[string]string{"Access-Control-Request-Method": "POST"}
	for origin, want := range map[string]int{
		"https://html-classic.itch.zone":      204,
		"https://A.B.Itch.Zone":               204,
		"https://itch.zone":                   403, // bare apex
		"http://html-classic.itch.zone":       403, // other scheme
		"https://html-classic.itch.zone:8443": 403, // port not listed
		"https://evilitch.zone":               403,
		"https://itch.zone.evil.test":         403,
		"https://x.port.test:8443":            204,
		"https://x.port.test":                 403, // port mismatch
		"https://x.port.test:9":               403,
	} {
		if r := e.do("OPTIONS", "/api/campaigns", origin, pre, ""); r.StatusCode != want {
			t.Errorf("%s: %d want %d", origin, r.StatusCode, want)
		}
	}
	if err := e.wsOrigin("https://html-classic.itch.zone"); err != nil {
		t.Fatalf("wildcard ws: %v", err)
	}
	if err := e.wsOrigin("https://itch.zone"); err == nil {
		t.Fatalf("apex ws accepted")
	}
}
