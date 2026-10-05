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
	flag.Parse()

	// Two browser processes: separate storage, like two devices, and each
	// tab is the visible one (a hidden tab gets no animation frames, and
	// Godot's main loop runs on them).
	newBrowser := func() (context.Context, context.CancelFunc) {
		opts := append(chromedp.DefaultExecAllocatorOptions[:],
			chromedp.ExecPath(*chrome),
			chromedp.Flag("headless", "new"),
			chromedp.Flag("use-angle", "swiftshader"),
			chromedp.Flag("enable-unsafe-swiftshader", true),
			chromedp.Flag("ignore-gpu-blocklist", true),
			chromedp.Flag("autoplay-policy", "no-user-gesture-required"),
			chromedp.Flag("disable-background-timer-throttling", true),
			chromedp.Flag("disable-backgrounding-occluded-windows", true),
			chromedp.Flag("disable-renderer-backgrounding", true),
		)
		alloc, cancelAlloc := chromedp.NewExecAllocator(context.Background(), opts...)
		ctx, cancel := chromedp.NewContext(alloc)
		return ctx, func() { cancel(); cancelAlloc() }
	}
	front := func(ctx context.Context) {
		chromedp.Call(ctx, page.BringToFront, cdp.Empty{})
		chromedp.Call(ctx, emulation.SetFocusEmulationEnabled, emulation.SetFocusEmulationEnabledParams{Enabled: true})
	}
	deadline := time.AfterFunc(*timeout, func() { fmt.Println("timeout"); os.Exit(1) })
	defer deadline.Stop()
	ctxA, cancelA := newBrowser()
	defer cancelA()
	ca := &console{who: "A"}
	listen(ctxA, ca)
	phone := chromedp.EmulateViewport(780, 360, chromedp.EmulateScale(2), chromedp.EmulateMobile, chromedp.EmulateTouch)
	inv := ""
	if *invite != "" {
		inv = "&invite=" + *invite
	}
	fails := 0
	check := func(ok bool, what string) {
		if ok {
			fmt.Println("  ok   " + what)
		} else {
			fmt.Println("  FAIL " + what)
			fails++
		}
	}
	t0 := time.Now()
	front(ctxA)
	if err := chromedp.Do(ctxA, phone, chromedp.Navigate(*url+"/?nettest=a"+inv)); err != nil {
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
	if err := chromedp.Do(ctxB, phone, chromedp.Navigate(*url+"/?nettest=b&join="+code[1])); err != nil {
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

func tail(s []string, n int) []string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}
