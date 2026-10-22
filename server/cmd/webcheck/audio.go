package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/chromedp/cdproto/input"
	"github.com/chromedp/cdproto/page"
	"github.com/chromedp/chromedp"
)

// audioHook runs before the page's own scripts: it keeps every AudioContext
// the page creates in window.__wcCtx, so the check can read the state of
// the context Godot plays through (GodotAudio itself is inside the
// engine's closure).
const audioHook = `(function(){
  var C = window.AudioContext || window.webkitAudioContext;
  if (!C || window.__wcCtx) return;
  window.__wcCtx = [];
  window.__wcPeak = 0;
  window.__wcSeries = []; window.__wcRec = false;  // -audio-loop: [context time, peak of the last ~40 ms]
  var W = function(o){ var x = new C(o); window.__wcCtx.push(x); return x; };
  W.prototype = C.prototype;
  window.AudioContext = W;
  if (window.webkitAudioContext) window.webkitAudioContext = W;
  // Everything bound for the speakers goes through one analyser per
  // context (an analyser passes its input on unchanged); a timer keeps
  // the loudest sample seen in window.__wcPeak.
  var oc = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(dst){
    if (typeof AudioDestinationNode !== 'undefined' && dst instanceof AudioDestinationNode) {
      var c = dst.context;
      if (!c.__wcTap) {
        var an = c.createAnalyser(); an.fftSize = 2048; oc.call(an, dst); c.__wcTap = an;
        var buf = new Float32Array(an.fftSize);
        setInterval(function(){ an.getFloatTimeDomainData(buf); var m = 0;
          for (var i = 0; i < buf.length; i++) { var v = Math.abs(buf[i]); if (v > m) m = v; }
          if (m > window.__wcPeak) window.__wcPeak = m;
        }, 20);
        // -audio-loop: every 1024-sample block's peak with its play time (a
        // timer misses blocks when the page is busy; a script processor does not).
        var sp = c.createScriptProcessor(1024, 1, 1);
        sp.onaudioprocess = function(e){ if (!window.__wcRec) return;
          var d = e.inputBuffer.getChannelData(0), m = 0;
          for (var i = 0; i < d.length; i++) { var v = Math.abs(d[i]); if (v > m) m = v; }
          window.__wcSeries.push([e.playbackTime, m]); };
        oc.call(an, sp); oc.call(sp, dst);
      }
      var args = Array.prototype.slice.call(arguments); args[0] = c.__wcTap;
      oc.apply(this, args);
      return dst;
    }
    return oc.apply(this, arguments);
  };
})()`

const audioState = `JSON.stringify((window.__wcCtx || []).map(function(x){
  return {state: x.state, rate: x.sampleRate, time: x.currentTime, peak: window.__wcPeak};
}))`

type ctxState struct {
	State string  `json:"state"`
	Rate  float64 `json:"rate"`
	Time  float64 `json:"time"`
	Peak  float64 `json:"peak"`
}

// checkAudio: sound in the browser (game/audio.gd, ?audio-debug=1). The
// page opens on the title screen; the context state is read before any
// input, then one click (desktop) or tap (phone) on an empty spot unlocks
// sound and the debug aid plays its test clip (horn_start, 1.5 s), printing
// "AUDIODEBUG play clip=horn_start ... playing=true pos0=.. pos200=..
// pos1400=.. playing200=true sample=true". Passes when:
//   - the page's AudioContext is "running" after the input and its clock
//     advances;
//   - sound reaches the speakers: every connection to the context's
//     destination goes through an analyser (audioHook), peak above 1 % of
//     full scale;
//   - the clip went through Sample playback, reports playing right after
//     play() and 200 ms later, and its position advances from 200 ms to
//     1.4 s (on the web the Sample path's position is held at the first
//     block for a second of the context's clock after the start).
//
// Run in a browser WITHOUT --autoplay-policy=no-user-gesture-required (the
// real case); -audio-autoplay also runs it with the flag (diagnosis).
func checkAudio(newB func(autoplay bool) (context.Context, context.CancelFunc), front func(context.Context),
	url, extra, shots string, autoplay, tap bool, check func(bool, string)) {
	ctx, cancel := newB(autoplay)
	defer cancel()
	how := "desktop click"
	if tap {
		how = "phone tap"
	}
	if autoplay {
		how += ", autoplay flag"
	} else {
		how += ", no autoplay flag"
	}
	c := &console{who: "audio"}
	listen(ctx, c)
	front(ctx)
	if _, err := chromedp.Call(ctx, page.AddScriptToEvaluateOnNewDocument,
		page.AddScriptToEvaluateOnNewDocumentParams{Source: audioHook}); err != nil {
		check(false, "audio ("+how+"): add the hook: "+err.Error())
		return
	}
	view := chromedp.EmulateViewport(1280, 720)
	if tap {
		view = chromedp.EmulateViewport(780, 360, chromedp.EmulateScale(2), chromedp.EmulateMobile, chromedp.EmulateTouch)
	}
	if err := chromedp.Do(ctx, view, chromedp.Navigate(url+"/?audio-debug=1"+extra)); err != nil {
		check(false, "audio ("+how+"): navigate: "+err.Error())
		return
	}
	ready := c.wait(regexp.MustCompile(`AUDIODEBUG ready .*`), 90*time.Second)
	if ready == nil {
		check(false, "audio ("+how+"): the page never printed AUDIODEBUG ready (an export without the debug aid?)")
		return
	}
	fmt.Println("  " + ready[0])
	time.Sleep(2 * time.Second) // the title screen settles
	read := func() []ctxState {
		s, err := chromedp.Run(ctx, chromedp.Evaluate[string](audioState))
		if err != nil {
			return nil
		}
		var out []ctxState
		json.Unmarshal([]byte(s), &out)
		return out
	}
	before := read()
	chromedp.Run(ctx, chromedp.Evaluate[any]("window.__wcPeak = 0"))
	// An empty spot: the top centre of the title page (the wordmark).
	x, y := 640.0, 40.0
	if tap {
		x, y = 390, 30
	}
	var err error
	if tap {
		_, err = chromedp.Call(ctx, input.DispatchTouchEvent, input.DispatchTouchEventParams{
			Type: input.DispatchTouchEventTypeTouchStart, TouchPoints: []*input.TouchPoint{{X: x, Y: y}}})
		if err == nil {
			time.Sleep(60 * time.Millisecond)
			_, err = chromedp.Call(ctx, input.DispatchTouchEvent, input.DispatchTouchEventParams{
				Type: input.DispatchTouchEventTypeTouchEnd, TouchPoints: []*input.TouchPoint{}})
		}
	} else {
		err = chromedp.Do(ctx, chromedp.MouseClickXY(x, y))
	}
	if err != nil {
		check(false, "audio ("+how+"): input: "+err.Error())
		return
	}
	time.Sleep(1 * time.Second)
	after := read()
	time.Sleep(500 * time.Millisecond)
	later := read()
	re := regexp.MustCompile(`AUDIODEBUG play clip=horn_start bus=(\S+) playing=(\w+) pos0=([\d.-]+) pos200=([\d.-]+) pos1400=([\d.-]+) playing200=(\w+) sample=(\w+)`)
	m := c.wait(re, 20*time.Second)
	if shots != "" && !autoplay {
		if png, err := chromedp.Run(ctx, chromedp.CaptureScreenshot()); err == nil {
			p := filepath.Join(shots, "web_audio_debug_"+map[bool]string{true: "phone", false: "desktop"}[tap]+".png")
			os.WriteFile(p, png, 0o644)
			fmt.Println("  screenshot", p)
		}
	}
	for _, l := range c.all {
		if strings.Contains(l, "AUDIODEBUG") && !strings.Contains(l, "AUDIODEBUG ready") {
			fmt.Println("  " + strings.TrimSpace(l))
		}
	}
	st := func(s []ctxState) string {
		if len(s) == 0 {
			return "none"
		}
		return s[0].State
	}
	peak := -1.0
	if len(later) > 0 {
		peak = later[0].Peak
	}
	peak0 := -1.0
	if len(before) > 0 {
		peak0 = before[0].Peak
	}
	fmt.Printf("  audio (%s): contexts %d, state before the input %s (peak %.3f), after %s, clock %.2f -> %.2f s, peak at the speakers %.3f\n",
		how, len(after), st(before), peak0, st(after), timeOf(after), timeOf(later), peak)
	check(len(after) == 1 && st(after) == "running" && timeOf(later) > timeOf(after),
		fmt.Sprintf("audio (%s): the page's AudioContext is running after the first input and its clock advances (%s, %.2f -> %.2f s)",
			how, st(after), timeOf(after), timeOf(later)))
	ok := false
	if m != nil {
		p0, _ := strconv.ParseFloat(m[4], 64)
		p1, _ := strconv.ParseFloat(m[5], 64)
		ok = m[2] == "true" && m[6] == "true" && m[7] == "true" && p1 > p0
	}
	check(peak > 0.01, fmt.Sprintf("audio (%s): sound reaches the speakers (peak %.3f of full scale)", how, peak))
	check(ok, fmt.Sprintf("audio (%s): the test clip plays on bus %s (Sample playback %s) with an advancing position (playing %s, at 200 ms %s; %s -> %s -> %s s)",
		how, idx(m, 1), idx(m, 7), idx(m, 2), idx(m, 6), idx(m, 3), idx(m, 4), idx(m, 5)))
	for _, l := range c.all {
		low := strings.ToLower(l)
		if strings.Contains(l, "EXCEPTION") || strings.Contains(l, "SCRIPT ERROR") ||
			(strings.Contains(low, "audio") && (strings.Contains(low, "error") || strings.Contains(low, "warn"))) {
			check(false, "audio ("+how+") console: "+strings.TrimSpace(l))
		}
	}
}

func timeOf(s []ctxState) float64 {
	if len(s) == 0 {
		return -1
	}
	return s[0].Time
}

// checkAudioLoop (-audio-loop): the ambient bed must loop without a gap.
// It opens the page (?audio-debug=1, so a click unlocks sound and the map
// bed, bed_map, a 48 s loop, starts), records the peak at the speakers every
// 20 ms for 54 s of the AudioContext's clock, and slides a 150 ms window over
// 3-52 s after the click (the seam is at 48 s, the player hand-over starts at
// 46 s). Passes when no window's peak falls under a quarter of the median
// window peak, i.e. no gap anywhere (also covers a loop that wraps too early).
// Prints the lowest ratio for 44-52 s too.
func checkAudioLoop(newB func(autoplay bool) (context.Context, context.CancelFunc), front func(context.Context),
	url, extra string, check func(bool, string)) {
	ctx, cancel := newB(false)
	defer cancel()
	c := &console{who: "loop"}
	listen(ctx, c)
	front(ctx)
	if _, err := chromedp.Call(ctx, page.AddScriptToEvaluateOnNewDocument,
		page.AddScriptToEvaluateOnNewDocumentParams{Source: audioHook}); err != nil {
		check(false, "audio loop: add the hook: "+err.Error())
		return
	}
	if err := chromedp.Do(ctx, chromedp.EmulateViewport(1280, 720), chromedp.Navigate(url+"/?audio-debug=1"+extra)); err != nil {
		check(false, "audio loop: navigate: "+err.Error())
		return
	}
	if c.wait(regexp.MustCompile(`AUDIODEBUG ready .*`), 90*time.Second) == nil {
		check(false, "audio loop: the page never printed AUDIODEBUG ready")
		return
	}
	time.Sleep(2 * time.Second)
	chromedp.Run(ctx, chromedp.Evaluate[any]("window.__wcSeries = []; window.__wcRec = true"))
	if err := chromedp.Do(ctx, chromedp.MouseClickXY(640, 40)); err != nil {
		check(false, "audio loop: input: "+err.Error())
		return
	}
	cur := func() float64 {
		s, err := chromedp.Run(ctx, chromedp.Evaluate[string](audioState))
		var out []ctxState
		if err == nil {
			json.Unmarshal([]byte(s), &out)
		}
		return timeOf(out)
	}
	t0 := cur()
	for cur()-t0 < 54 {
		time.Sleep(500 * time.Millisecond)
	}
	raw, err := chromedp.Run(ctx, chromedp.Evaluate[string]("JSON.stringify(window.__wcSeries)"))
	if err != nil {
		check(false, "audio loop: read the series: "+err.Error())
		return
	}
	var ser [][2]float64
	json.Unmarshal([]byte(raw), &ser)
	// Peak of every 150 ms window (step 50 ms) at time rel (s after the click).
	win := func(rel float64) float64 {
		m := 0.0
		for _, e := range ser {
			if e[0]-t0 >= rel && e[0]-t0 < rel+0.15 && e[1] > m {
				m = e[1]
			}
		}
		return m
	}
	// The typical level: the median of the 150 ms window peaks (step 50 ms)
	// from 3 s to 52 s. A gull or a swell crest would make a running maximum
	// a poor yardstick: the quietest trough of a gap-free bed sits at 0.18-0.2
	// of it, so the check uses the median, where a trough is above 0.5.
	var peaks []float64
	for rel := 3.0; rel < 52; rel += 0.05 {
		peaks = append(peaks, win(rel))
	}
	sorted := append([]float64(nil), peaks...)
	sort.Float64s(sorted)
	med := sorted[len(sorted)/2]
	minSeam, minAll, atSeam, atAll := 9.0, 9.0, 0.0, 0.0
	for i, w := range peaks {
		rel := 3.0 + 0.05*float64(i)
		r := w / med
		if rel >= 44 && rel < 52 && r < minSeam {
			minSeam, atSeam = r, rel
		}
		if r < minAll {
			minAll, atAll = r, rel
		}
	}
	run := sorted[len(sorted)-1]
	fmt.Printf("  audio loop: %d samples over %.1f s, median 150 ms peak %.3f (loudest %.3f); lowest 150 ms window / median: 44-52 s %.2f (at %.2f s), 3-52 s %.2f (at %.2f s)\n",
		len(ser), cur()-t0, med, run, minSeam, atSeam, minAll, atAll)
	// A loop that wraps early (the bed cut off every few seconds and started
	// again, no silence) repeats its own signal: the 100 ms-bin peak series
	// correlates with itself at the wrap period. A 48 s bed has no repeat
	// inside 52 s, so the correlation at lags of 5-30 s must stay low.
	nb := int((52.0 - 3.0) / 0.1)
	bins := make([]float64, nb)
	for i := range bins {
		bins[i] = win(3.0 + 0.1*float64(i))
	}
	mean := 0.0
	for _, v := range bins {
		mean += v / float64(nb)
	}
	var v0 float64
	for _, v := range bins {
		v0 += (v - mean) * (v - mean)
	}
	bestC, bestLag := -1.0, 0.0
	for lag := 50; lag <= 300; lag++ {
		var cc, va, vb float64
		for i := 0; i+lag < nb; i++ {
			a, b := bins[i]-mean, bins[i+lag]-mean
			cc += a * b
			va += a * a
			vb += b * b
		}
		if va > 0 && vb > 0 && cc/math.Sqrt(va*vb) > bestC {
			bestC, bestLag = cc/math.Sqrt(va*vb), float64(lag)*0.1
		}
	}
	fmt.Printf("  audio loop: highest self-correlation of the peak series at lags 5-30 s: %.2f (at %.1f s)\n", bestC, bestLag)
	check(bestC < 0.8, fmt.Sprintf("audio loop: the bed does not repeat early (self-correlation %.2f at %.1f s, needs under 0.8)", bestC, bestLag))
	check(len(ser) > 1500 && med > 0.005 && minAll >= 0.25,
		fmt.Sprintf("audio loop: no gap in 3-52 s of the bed, seam at 48 s included: lowest 150 ms window %.2f of the median (needs 0.25 or more)", minAll))
}
