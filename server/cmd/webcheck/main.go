// Command webcheck drives the game's web export in headless Chromium against
// a running server, to prove online play works through the browser's fetch
// and WebSocket (Godot's HTTPRequest and WebSocketPeer on the web). It
// opens two isolated browser contexts (separate storage, like two devices):
// A creates a campaign (?nettest=a), B joins it with the code
// (?nettest=b&join=CODE); both submit, B resolves, A sees the result through
// the long-poll; A also checks the WebSocket echo. See game/net/net_selftest.gd.
//
//	go run ./cmd/webcheck -url http://127.0.0.1:8073 [-shots DIR]
//	go run ./cmd/webcheck -url https://strategiccommand.ggior32.dev   (after the switch;
//	    creates a campaign named "nettest" there)
//	go run ./cmd/webcheck -url http://127.0.0.1:8073 -live
//	    a live co-op battle instead (milestone 5): A opens the room, B joins in
//	    the lobby, 600 frames in lockstep with every frame's hash compared over
//	    the relay, then B leaves and joins again mid-battle (snapshot)
//	go run ./cmd/webcheck -url http://127.0.0.1:8092 -soldiers [-shots DIR]
//	    only the 3D battle check (the default flow's battle part; works against tools/serve_web.py too). -v3d is the same
//	    check, kept as a flag so older scripts work (the 3D view is the default flow's battle view since 2026-11-09)
//	go run ./cmd/webcheck -url http://127.0.0.1:8092 -ghost [-shots DIR]
//	    only the ghost check: the 3D ghost pass (stencil test) on the GPU path with the web context's stencil attributes
//	    logged; our men in the open must not be ghosted over (see checkGhost)
//	go run ./cmd/webcheck -url http://127.0.0.1:8092 -oblique [-shots DIR]
//	    only the one-download check: the oblique sheets are in index.pck, so a battle fetches no second pack
//	    (see checkOblique; works against tools/serve_web.py too)
//	go run ./cmd/webcheck -url http://127.0.0.1:8092 -audio [-audio-autoplay] [-audio-query '&audio-exp=master']
//	    only the sound check (see audio.go; works against tools/serve_web.py too)
//	go run ./cmd/webcheck -url http://127.0.0.1:8092 -audio-loop
//	    only the ambient bed loop check: 54 s of bed_map, no gap at the seam (checkAudioLoop)
//
// After the turn flow, A loads a battle in the 3D view (?battle-view=3d) and
// its self-check (game/view3d.gd, console "V3D_PROBE") must report soldiers
// drawn in WebGL: the sim can run perfectly with nothing on screen, which no
// other check notices. Both rendering paths are checked (vertex texture reads,
// "v3d-gpu", and the compatible shaders, "v3d-cpu", ?soldiers=cpu), and the
// automatic switch between them (?v3d-probe-fail, see checkSoldiers). Last, sound: in a
// browser without the autoplay flag, one click (desktop) and one tap
// (phone) must start the page's AudioContext and a test clip that plays
// (?audio-debug=1, see checkAudio).
//
// Exit code 0 when everything passed.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/chromedp/cdproto/cdp"
	"github.com/chromedp/cdproto/emulation"
	"github.com/chromedp/cdproto/page"
	"github.com/chromedp/cdproto/runtime"
	"github.com/chromedp/chromedp"
)

var verbose bool

type console struct {
	mu    sync.Mutex
	lines []string
	who   string
	all   []string
}

func (c *console) add(s string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.all = append(c.all, s)
	if verbose || strings.Contains(s, "NETTEST") || strings.Contains(strings.ToLower(s), "error") {
		fmt.Printf("  [%s] %s\n", c.who, strings.TrimSpace(s))
	}
	c.lines = append(c.lines, s)
}

// reset forgets the lines seen so far (find / wait look at later ones only).
func (c *console) reset() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.lines = nil
}

func (c *console) find(re *regexp.Regexp) []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, l := range c.lines {
		if m := re.FindStringSubmatch(l); m != nil {
			return m
		}
	}
	return nil
}

func (c *console) wait(re *regexp.Regexp, d time.Duration) []string {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		if m := c.find(re); m != nil {
			return m
		}
		time.Sleep(100 * time.Millisecond)
	}
	return nil
}

func listen(ctx context.Context, c *console) {
	logs := chromedp.Events(ctx, runtime.ConsoleAPICalled)
	go func() {
		for e, err := range logs {
			if err != nil {
				return
			}
			var parts []string
			for _, a := range e.Args {
				parts = append(parts, strings.Trim(string(a.Value), `"`))
			}
			c.add(strings.Join(parts, " "))
		}
	}()
	exc := chromedp.Events(ctx, runtime.ExceptionThrown)
	go func() {
		for e, err := range exc {
			if err != nil {
				return
			}
			c.add("EXCEPTION " + e.ExceptionDetails.Text)
		}
	}()
}

func main() {
	url := flag.String("url", "http://127.0.0.1:8073", "server base URL")
	chrome := flag.String("chrome", "/usr/bin/chromium", "Chromium binary")
	shots := flag.String("shots", "", "directory for phone-size screenshots (optional)")
	invite := flag.String("invite", "", "invite key if the server needs one")
	timeout := flag.Duration("timeout", 4*time.Minute, "overall timeout")
	flag.BoolVar(&verbose, "v", false, "print every console line")
	live := flag.Bool("live", false, "check a live co-op battle instead of the turn flow")
	soldiersOnly := flag.Bool("soldiers", false, "only check that a 3D battle draws its soldiers (both paths, the automatic switch)")
	obliqueOnly := flag.Bool("oblique", false, "only check that the oblique sheets ride in the main download (no second pack)")
	v3dOnly := flag.Bool("v3d", false, "the same as -soldiers (the 3D view is the default flow's battle view; kept so older scripts work)")
	ghostOnly := flag.Bool("ghost", false, "only check that the 3D ghost pass's stencil test works in WebGL (see checkGhost)")
	audioOnly := flag.Bool("audio", false, "only check that sound plays after the first input")
	audioAutoplay := flag.Bool("audio-autoplay", false, "also run the sound check with --autoplay-policy=no-user-gesture-required")
	audioLoop := flag.Bool("audio-loop", false, "only check that the ambient bed loops without a gap (plays bed_map for 54 s)")
	audioQuery := flag.String("audio-query", "", "extra URL query for the sound check (diagnosis, e.g. '&audio-exp=master')")
	flag.Parse()

	// Two browser processes: separate storage, like two devices, and each
	// tab is the visible one (a hidden tab gets no animation frames, and
	// Godot's main loop runs on them).
	// autoplay: --autoplay-policy=no-user-gesture-required (every check but
	// the sound one, which needs the browser's real gesture rule).
	newBrowserWith := func(autoplay bool) (context.Context, context.CancelFunc) {
		opts := append(chromedp.DefaultExecAllocatorOptions[:],
			chromedp.ExecPath(*chrome),
			chromedp.Flag("headless", "new"),
			chromedp.Flag("use-angle", "swiftshader"),
			chromedp.Flag("enable-unsafe-swiftshader", true),
			chromedp.Flag("ignore-gpu-blocklist", true),
			chromedp.Flag("disable-background-timer-throttling", true),
			chromedp.Flag("disable-backgrounding-occluded-windows", true),
			chromedp.Flag("disable-renderer-backgrounding", true),
		)
		if autoplay {
			opts = append(opts, chromedp.Flag("autoplay-policy", "no-user-gesture-required"))
		}
		alloc, cancelAlloc := chromedp.NewExecAllocator(context.Background(), opts...)
		ctx, cancel := chromedp.NewContext(alloc)
		return ctx, func() { cancel(); cancelAlloc() }
	}
	newBrowser := func() (context.Context, context.CancelFunc) { return newBrowserWith(true) }
	front := func(ctx context.Context) {
		chromedp.Call(ctx, page.BringToFront, cdp.Empty{})
		chromedp.Call(ctx, emulation.SetFocusEmulationEnabled, emulation.SetFocusEmulationEnabledParams{Enabled: true})
	}
	deadline := time.AfterFunc(*timeout, func() { fmt.Println("timeout"); os.Exit(1) })
	defer deadline.Stop()
	fails := 0
	check := func(ok bool, what string) {
		if ok {
			fmt.Println("  ok   " + what)
		} else {
			fmt.Println("  FAIL " + what)
			fails++
		}
	}
	audio := func() {
		checkAudio(newBrowserWith, front, *url, *audioQuery, *shots, false, false, check)
		checkAudio(newBrowserWith, front, *url, *audioQuery, *shots, false, true, check)
		if *audioAutoplay {
			checkAudio(newBrowserWith, front, *url, *audioQuery, *shots, true, false, check)
			checkAudio(newBrowserWith, front, *url, *audioQuery, *shots, true, true, check)
		}
	}
	if *audioLoop {
		checkAudioLoop(newBrowserWith, front, *url, *audioQuery, check)
		if fails == 0 {
			fmt.Println("RESULT: PASS")
			return
		}
		fmt.Printf("RESULT: FAIL (%d)\n", fails)
		os.Exit(1)
	}
	if *audioOnly {
		audio()
		if fails == 0 {
			fmt.Println("RESULT: PASS")
			return
		}
		fmt.Printf("RESULT: FAIL (%d)\n", fails)
		os.Exit(1)
	}
	ctxA, cancelA := newBrowser()
	defer cancelA()
	ca := &console{who: "A"}
	listen(ctxA, ca)
	phone := chromedp.EmulateViewport(780, 360, chromedp.EmulateScale(2), chromedp.EmulateMobile, chromedp.EmulateTouch)
	inv := ""
	if *invite != "" {
		inv = "&invite=" + *invite
	}
	// The page names its own server: the origin probe (6 s) loses to a slow first frame on a loaded machine and the page
	// then falls back to the default server (a failure seen at HEAD too, 2026-11-09).
	srv := "&server=" + *url
	t0 := time.Now()
	front(ctxA)
	if *live {
		os.Exit(runLive(ctxA, ca, newBrowser, front, phone, *url, inv, check, &fails))
	}
	if *v3dOnly || *soldiersOnly {
		checkSoldiers(ctxA, ca, phone, *url, *shots, check)
		if fails == 0 {
			fmt.Println("RESULT: PASS")
			return
		}
		fmt.Printf("RESULT: FAIL (%d)\n", fails)
		os.Exit(1)
	}
	if *ghostOnly {
		checkGhost(ctxA, ca, phone, *url, *shots, check)
		if fails == 0 {
			fmt.Println("RESULT: PASS")
			return
		}
		fmt.Printf("RESULT: FAIL (%d)\n", fails)
		os.Exit(1)
	}
	if *obliqueOnly {
		checkOblique(ctxA, ca, phone, *url, *shots, check)
		if fails == 0 {
			fmt.Println("RESULT: PASS")
			return
		}
		fmt.Printf("RESULT: FAIL (%d)\n", fails)
		os.Exit(1)
	}
	if err := chromedp.Do(ctxA, phone, chromedp.Navigate(*url+"/?nettest=a"+inv+srv)); err != nil {
		fmt.Println("navigate A:", err)
		os.Exit(1)
	}
	code := ca.wait(regexp.MustCompile(`NETTEST A CODE (\w+) ID (\w+)`), 150*time.Second)
	if code == nil {
		fmt.Println("A never created a campaign; console tail:")
		for _, l := range tail(ca.all, 30) {
			fmt.Println("   ", l)
		}
		os.Exit(1)
	}
	fmt.Printf("A created campaign %s (code %s) after %.1f s (page load + wasm)\n", code[2], code[1], time.Since(t0).Seconds())
	ctxB, cancelB := newBrowser()
	defer cancelB()
	cb := &console{who: "B"}
	listen(ctxB, cb)
	front(ctxB)
	if err := chromedp.Do(ctxB, phone, chromedp.Navigate(*url+"/?nettest=b&join="+code[1]+srv)); err != nil {
		fmt.Println("navigate B:", err)
		os.Exit(1)
	}
	ws := ca.wait(regexp.MustCompile(`NETTEST A WS (OK rtt_ms \d+|FAIL.*)`), 60*time.Second)
	check(ws != nil && strings.HasPrefix(ws[1], "OK"), fmt.Sprintf("WebSocket echo from the browser: %v", ws))
	doneB := cb.wait(regexp.MustCompile(`NETTEST B DONE v(\d+) (\w+) turn (\d+) waited_ms (\d+) resolve (\w+)`), 150*time.Second)
	doneA := ca.wait(regexp.MustCompile(`NETTEST A DONE v(\d+) (\w+) turn (\d+) waited_ms (\d+) resolve (\S+)`), 60*time.Second)
	check(cb.find(regexp.MustCompile(`NETTEST B JOINED`)) != nil, "B joined with the code in a separate browser context")
	check(doneB != nil, fmt.Sprintf("B submitted and the turn resolved: %v", doneB))
	check(doneA != nil, fmt.Sprintf("A saw the resolved turn (long-poll): %v", doneA))
	if doneA != nil && doneB != nil {
		check(doneA[1] == doneB[1] && doneA[2] == doneB[2], "both browsers on the same version and state hash "+doneA[2])
		check(doneB[5] == "won" || doneA[5] == "won", "one of them resolved the turn and uploaded it")
	}
	h := ca.wait(regexp.MustCompile(`NETTEST A HISTORY (\d+) versions`), 20*time.Second)
	check(h != nil && h[1] == "2", fmt.Sprintf("history has 2 versions: %v", h))
	if *shots != "" {
		if ca.wait(regexp.MustCompile(`NETTEST A SCREEN open`), 30*time.Second) != nil {
			time.Sleep(2 * time.Second)
			if png, err := chromedp.Run(ctxA, chromedp.CaptureScreenshot()); err == nil {
				p := filepath.Join(*shots, "online_web_phone_campaign.png")
				os.WriteFile(p, png, 0o644)
				fmt.Println("  screenshot", p)
			}
		}
	}
	cancelB()
	checkSoldiers(ctxA, ca, phone, *url, *shots, check)
	cancelA()
	audio()
	for _, c := range []*console{ca, cb} {
		for _, l := range c.all {
			if strings.Contains(l, "EXCEPTION") || strings.Contains(l, "SCRIPT ERROR") {
				check(false, c.who+" console error: "+l)
			}
		}
	}
	if fails == 0 {
		fmt.Println("RESULT: PASS")
		return
	}
	fmt.Printf("RESULT: FAIL (%d)\n", fails)
	os.Exit(1)
}

// checkSoldiers: a battle in the browser, in the 3D view (the only battle view the web needs since 2026-11-09), draws its
// soldiers, on both rendering paths (game/view3d.gd). The view's self-check renders only the men around the biggest unit
// into a small offscreen viewport ~30 frames in and prints the pixels drawn and the path ("V3D_PROBE drawn=N men=M path=P"):
//   - a West town first (its kit pieces are meshes from the main pack's kit3d.res, the scene builds), the default path
//     (vertex texture reads, "v3d-gpu");
//   - the compatible shaders, forced with ?soldiers=cpu ("v3d-cpu");
//   - the automatic switch: ?v3d-probe-fail makes the gpu path's probe report nothing drawn, as on the devices it fails
//     on; the view must switch to the compatible shaders and draw there;
//   - the next battle starts on the compatible path (remembered in user://settings.cfg, the browser's storage).
func checkSoldiers(ctx context.Context, c *console, phone chromedp.Action[chromedp.Void], url, shots string, check func(bool, string)) {
	probe := regexp.MustCompile(`V3D_PROBE drawn=(\d+) men=(\d+) path=(\S+)`)
	built := regexp.MustCompile(`view3d: built in ([\d.]+) ms \(board (\d+) verts, (\d+) trees, (\d+) kit meshes, shadows (\w+)\)`)
	run := func(scenario, query, what string, wantPath string, shot string) {
		c.reset()
		t0 := time.Now()
		if err := chromedp.Do(ctx, phone, chromedp.Navigate(url+"/?scenario="+scenario+"&speed=3&battle-view=3d"+query)); err != nil {
			check(false, what+": navigate: "+err.Error())
			return
		}
		b := c.wait(built, 240*time.Second)
		check(b != nil, fmt.Sprintf("%s: the 3D scene builds: %v ms, board %v verts, %v kit meshes, shadows %v (%.1f s)",
			what, idx(b, 1), idx(b, 2), idx(b, 4), idx(b, 5), time.Since(t0).Seconds()))
		if scenario == "west_town" {
			check(b != nil && atoi(b[4]) > 50, fmt.Sprintf("%s: the town's kit pieces are meshes: %v", what, idx(b, 4)))
		}
		m := c.wait(probe, 120*time.Second)
		check(m != nil && atoi(m[1]) >= 50 && m[3] == wantPath, fmt.Sprintf(
			"%s: %v pixels around a unit of %v men on the %v path (want %s; %.1f s)",
			what, idx(m, 1), idx(m, 2), idx(m, 3), wantPath, time.Since(t0).Seconds()))
		if shots != "" && shot != "" && m != nil {
			if png, err := chromedp.Run(ctx, chromedp.CaptureScreenshot()); err == nil {
				p := filepath.Join(shots, shot)
				os.WriteFile(p, png, 0o644)
				fmt.Println("  screenshot", p)
			}
		}
	}
	run("west_town", "", "a 3D battle draws its soldiers in WebGL (vertex texture path)", "v3d-gpu", "web_v3d.png")
	run("skirmish", "&soldiers=cpu", "a 3D battle draws its soldiers in WebGL (compatible path, forced)", "v3d-cpu", "web_v3d_cpu.png")
	// The automatic switch.
	c.reset()
	t0 := time.Now()
	if err := chromedp.Do(ctx, phone, chromedp.Navigate(url+"/?scenario=skirmish&speed=3&battle-view=3d&v3d-probe-fail=1")); err != nil {
		check(false, "automatic switch: navigate: "+err.Error())
	} else {
		first := c.wait(probe, 120*time.Second)
		check(first != nil && first[1] == "0" && first[3] == "v3d-gpu", fmt.Sprintf(
			"a failing vertex texture path is seen: %v pixels on the %v path", idx(first, 1), idx(first, 3)))
		second := c.wait(regexp.MustCompile(`V3D_PROBE drawn=(\d+) men=(\d+) path=v3d-cpu`), 60*time.Second)
		check(second != nil && atoi(second[1]) >= 50, fmt.Sprintf(
			"... and the view switches to the compatible shaders, which draw: %v pixels (%.1f s)",
			idx(second, 1), time.Since(t0).Seconds()))
		time.Sleep(2 * time.Second) // let user:// reach the browser's storage
	}
	run("skirmish", "", "the next battle starts on the remembered compatible path", "v3d-cpu", "")
	for _, l := range c.all {
		if strings.Contains(l, "SHADER ERROR") || strings.Contains(l, "Shader compilation failed") {
			check(false, "shader error: "+strings.TrimSpace(l))
			break
		}
	}
}

func tail(s []string, n int) []string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

// runLive: the live co-op battle check (see the package comment).
func runLive(ctxA context.Context, ca *console, newBrowser func() (context.Context, context.CancelFunc),
	front func(context.Context), phone chromedp.Action[chromedp.Void], url, inv string, check func(bool, string), fails *int) int {
	t0 := time.Now()
	if err := chromedp.Do(ctxA, phone, chromedp.Navigate(url+"/?nettest=livea"+inv)); err != nil {
		fmt.Println("navigate A:", err)
		return 1
	}
	code := ca.wait(regexp.MustCompile(`NETTEST LIVEA CODE (\w+) ID (\w+)`), 150*time.Second)
	if code == nil {
		fmt.Println("A never created a campaign; console tail:")
		for _, l := range tail(ca.all, 30) {
			fmt.Println("   ", l)
		}
		return 1
	}
	fmt.Printf("A created campaign %s (code %s) after %.1f s\n", code[2], code[1], time.Since(t0).Seconds())
	ctxB, cancelB := newBrowser()
	defer cancelB()
	cb := &console{who: "B"}
	listen(ctxB, cb)
	front(ctxB)
	if err := chromedp.Do(ctxB, phone, chromedp.Navigate(url+"/?nettest=liveb&join="+code[1])); err != nil {
		fmt.Println("navigate B:", err)
		return 1
	}
	re1 := regexp.MustCompile(`NETTEST LIVEB LIVE frames (\d+) checks (\d+) desyncs (\d+) rtt_ms (\d+) waits (\d+) wait_ms_max (\d+)`)
	l1 := cb.wait(re1, 180*time.Second)
	check(l1 != nil && l1[3] == "0" && atoi(l1[2]) >= 550,
		fmt.Sprintf("joined in the lobby, %v frames in lockstep, every frame's hash compared over the relay: %v checks, %v desyncs (rtt %v ms, %v waits, longest %v ms)",
			idx(l1, 1), idx(l1, 2), idx(l1, 3), idx(l1, 4), idx(l1, 5), idx(l1, 6)))
	re2 := regexp.MustCompile(`NETTEST LIVEB REJOIN frame (\d+) snapshot_bytes (\d+) restore_ms ([\d.]+) catchup_frames (\d+) catchup_ms (\d+) join_ms (\d+)`)
	l2 := cb.wait(re2, 90*time.Second)
	check(l2 != nil && atoi(l2[2]) > 0, fmt.Sprintf("left and joined again mid-battle at frame %v from a %v-byte snapshot (restore %v ms, caught up %v frames in %v ms, %v ms from joining to commanding)",
		idx(l2, 1), idx(l2, 2), idx(l2, 3), idx(l2, 4), idx(l2, 5), idx(l2, 6)))
	re3 := regexp.MustCompile(`NETTEST LIVEB DONE frames (\d+) tick (\d+) checks (\d+) desyncs (\d+)`)
	l3 := cb.wait(re3, 90*time.Second)
	check(l3 != nil && l3[4] == "0" && atoi(l3[3]) >= 250, fmt.Sprintf("after the rejoin: to frame %v, %v hash checks, %v desyncs", idx(l3, 1), idx(l3, 3), idx(l3, 4)))
	re4 := regexp.MustCompile(`NETTEST LIVEA DONE frames (\d+) tick (\d+) checks (\d+) desyncs (\d+)`)
	l4 := ca.wait(re4, 90*time.Second)
	check(l4 != nil && l4[4] == "0" && atoi(l4[3]) >= 800, fmt.Sprintf("the host: to frame %v, %v hash checks, %v desyncs", idx(l4, 1), idx(l4, 3), idx(l4, 4)))
	for _, c := range []*console{ca, cb} {
		for _, l := range c.all {
			if strings.Contains(l, "EXCEPTION") || strings.Contains(l, "SCRIPT ERROR") || strings.Contains(l, "NETTEST LIVEA FAIL") ||
				strings.Contains(l, "NETTEST LIVEB FAIL") {
				check(false, c.who+" console: "+l)
			}
		}
	}
	if *fails == 0 {
		fmt.Println("RESULT: PASS")
		return 0
	}
	fmt.Printf("RESULT: FAIL (%d)\n", *fails)
	return 1
}

func atoi(s string) int {
	n := 0
	fmt.Sscanf(s, "%d", &n)
	return n
}

func idx(m []string, i int) string {
	if m == nil || i >= len(m) {
		return "?"
	}
	return m[i]
}

// checkOblique: one download (game/oblique_pack.gd, docs/design/distribution.md "One download"). The oblique sheets and
// the 3D kit meshes are in index.pck, so a battle (opened here in the Oblique view, which draws the same sheets) must
// fetch no second pack: no "oblique pack:" console line, no request for oblique.pck, the soldiers drawn, neither loader's
// fallback notice (game/sprite_ob.gd, game/kit_ob.gd).
func checkOblique(ctx context.Context, c *console, phone chromedp.Action[chromedp.Void], url, shots string, check func(bool, string)) {
	c.reset()
	t0 := time.Now()
	if err := chromedp.Do(ctx, phone, chromedp.Navigate(url+"/?scenario=skirmish&speed=3&battle-view=oblique")); err != nil {
		check(false, "oblique: navigate: "+err.Error())
		return
	}
	m := c.wait(regexp.MustCompile(`SOLDIER_PROBE drawn=(\d+) men=(\d+) path=(\w+)`), 120*time.Second)
	check(m != nil && atoi(m[1]) >= 50, fmt.Sprintf("the oblique battle draws its soldiers from the main pack: %v pixels, %v men, %v path (%.1f s)",
		idx(m, 1), idx(m, 2), idx(m, 3), time.Since(t0).Seconds()))
	time.Sleep(2 * time.Second)
	for _, l := range c.all {
		if strings.Contains(l, "oblique view: no assets/") || strings.Contains(l, "oblique pack") || strings.Contains(l, "oblique.pck") {
			check(false, "a second pack or a loader fallback: "+strings.TrimSpace(l))
		}
	}
	if shots != "" && m != nil {
		if png, err := chromedp.Run(ctx, chromedp.CaptureScreenshot()); err == nil {
			p := filepath.Join(shots, "web_oblique.png")
			os.WriteFile(p, png, 0o644)
			fmt.Println("  screenshot", p)
		}
	}
}

// checkGhost: the 3D ghost pass (game/soldiers3d_ghost.gdshader) draws our hidden men only where the stencil is not 1, which the
// men's pass writes. WebGL2 contexts from Godot's web template have no stencil in the default framebuffer unless the 3D scene
// renders into its own buffers; if the test failed there, the ghost would be drawn over every man. The game's own probe
// (game/view3d.gd _ghost_probe, ?ghost-probe) logs the context's stencil attributes and compares the frame with the ghost shown
// and hidden around each own unit in the open of the skirmish: "GHOST_PROBE units=N worst_frac=F changed=C control_changed=K" (F: share of a unit's
// patch that the ghost changed; 0 when the stencil works). ?soldiers=gpu forces the vertex texture path (swiftshader may fall to
// the compatible path, where the ghost is dropped and the probe prints nothing).
func checkGhost(ctx context.Context, c *console, phone chromedp.Action[chromedp.Void], url, shots string, check func(bool, string)) {
	for _, g := range []string{"1", "0"} {
		c.reset()
		t0 := time.Now()
		if err := chromedp.Do(ctx, phone, chromedp.Navigate(url+"/?scenario=skirmish&speed=3&battle-view=3d&soldiers=gpu&quality=high&ghost="+g+"&ghost-probe")); err != nil {
			check(false, "ghost="+g+": navigate: "+err.Error())
			return
		}
		pr := c.wait(regexp.MustCompile(`V3D_PROBE drawn=(\d+) men=(\d+) path=(\S+)`), 240*time.Second)
		check(pr != nil && pr[3] == "v3d-gpu" && atoi(pr[1]) >= 50, fmt.Sprintf("ghost=%s: the GPU soldier path draws: %v", g, pr))
		if g == "0" {
			time.Sleep(3 * time.Second)
			check(c.find(regexp.MustCompile(`GHOST_PROBE`)) == nil, "ghost=0: no ghost pass, no probe")
		} else {
			ctxl := c.wait(regexp.MustCompile(`GHOST_PROBE context (.*)`), 60*time.Second)
			fmt.Printf("  web context: %v\n", idx(ctxl, 1))
			m := c.wait(regexp.MustCompile(`GHOST_PROBE units=(\d+) worst_frac=([\d.]+) changed=(\d+) control_changed=(\d+)(?: men_px=(\d+))?`), 180*time.Second)
			check(m != nil && atoi(m[1]) >= 1, fmt.Sprintf("the ghost probe saw own units in the open: %v (%.1f s)", m, time.Since(t0).Seconds()))
			var f float64
			if m != nil {
				fmt.Sscanf(m[2], "%f", &f)
			}
			check(m != nil && f < 0.05, fmt.Sprintf("the ghost leaves our men in the open alone (worst share of a patch changed %v, %v pixels)", idx(m, 2), idx(m, 3)))
			check(m != nil && atoi(m[4]) >= 20, fmt.Sprintf("positive control: with the men's pass hidden the ghost does draw: %v pixels changed", idx(m, 4)))
		}
		if shots != "" {
			if png, err := chromedp.Run(ctx, chromedp.CaptureScreenshot()); err == nil {
				p := filepath.Join(shots, "web_ghost_"+g+".png")
				os.WriteFile(p, png, 0o644)
				fmt.Println("  screenshot", p)
			}
		}
	}
	for _, l := range c.all {
		if strings.Contains(l, "SHADER ERROR") || strings.Contains(l, "Shader compilation failed") {
			check(false, "shader error: "+strings.TrimSpace(l))
			break
		}
	}
}
