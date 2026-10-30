// Drive the web export in headless Chromium by a script of steps.
// go run ./cmd/webprobe -url URL -out DIR step step ...   steps: wait:MS  click:X,Y  shot:NAME  log:N (print last N console lines)
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/chromedp/cdproto/runtime"
	"github.com/chromedp/chromedp"
)

func main() {
	url := flag.String("url", "http://127.0.0.1:8074/", "page")
	out := flag.String("out", ".", "shots dir")
	flag.Parse()
	opts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.Flag("headless", "new"),
		chromedp.Flag("use-angle", "swiftshader"),
		chromedp.Flag("enable-unsafe-swiftshader", true),
		chromedp.Flag("ignore-gpu-blocklist", true),
		chromedp.Flag("disable-background-timer-throttling", true),
		chromedp.Flag("disable-backgrounding-occluded-windows", true),
		chromedp.Flag("disable-renderer-backgrounding", true),
		chromedp.WindowSize(1280, 720),
		chromedp.ExecPath("/usr/bin/chromium"),
	)
	actx, acancel := chromedp.NewExecAllocator(context.Background(), opts...)
	defer acancel()
	ctx, cancel := chromedp.NewContext(actx)
	defer cancel()
	ctx, tcancel := context.WithTimeout(ctx, 6*time.Minute)
	defer tcancel()
	var logs []string
	evs := chromedp.Events(ctx, runtime.ConsoleAPICalled)
	go func() {
		for e, err := range evs {
			if err != nil {
				return
			}
			var parts []string
			for _, a := range e.Args {
				parts = append(parts, strings.Trim(string(a.Value), `"`))
			}
			logs = append(logs, strings.Join(parts, " "))
		}
	}()
	if err := chromedp.Do(ctx, chromedp.Navigate(*url)); err != nil {
		fmt.Println("navigate:", err)
		os.Exit(1)
	}
	for _, st := range flag.Args() {
		kv := strings.SplitN(st, ":", 2)
		switch kv[0] {
		case "wait":
			ms, _ := strconv.Atoi(kv[1])
			time.Sleep(time.Duration(ms) * time.Millisecond)
		case "click":
			xy := strings.Split(kv[1], ",")
			x, _ := strconv.ParseFloat(xy[0], 64)
			y, _ := strconv.ParseFloat(xy[1], 64)
			if err := chromedp.Do(ctx, chromedp.MouseClickXY(x, y)); err != nil {
				fmt.Println("click:", err)
			}
			time.Sleep(150 * time.Millisecond)
		case "shot":
			buf, err := chromedp.Run(ctx, chromedp.CaptureScreenshot())
			if err != nil {
				fmt.Println("shot:", err)
				continue
			}
			p := filepath.Join(*out, kv[1]+".png")
			os.WriteFile(p, buf, 0o644)
			fmt.Println("shot", p)
		case "log":
			n, _ := strconv.Atoi(kv[1])
			if n > len(logs) {
				n = len(logs)
			}
			for _, l := range logs[len(logs)-n:] {
				fmt.Println("console:", l)
			}
		}
	}
}
