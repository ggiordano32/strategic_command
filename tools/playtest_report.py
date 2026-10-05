#!/usr/bin/env python3
"""Summarise playtest telemetry written by tools/serve_web.py.

    python3 tools/playtest_report.py [FILE_OR_DIR ...]   (default: playtest_logs/)

Prints, per session (one page load): device, build, scenarios played,
performance, benchmark summaries, input counts, environment events and
errors. Then compares state hashes across sessions for runs of the same
scenario + seed with no player orders (these must match on every device
running the same sim code) and flags mismatches.
"""
import collections
import glob
import json
import os
import re
import statistics
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ENV_KINDS = {"resize", "viewport_resize", "orientation", "visibility", "pagehide",
             "focus", "app_focus", "fullscreen", "browser_gesture",
             "webgl_context_lost", "webgl_context_restored"}
ERROR_KINDS = {"js_error", "js_unhandled_rejection"}


def load(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(glob.glob(os.path.join(p, "*.jsonl")))
        else:
            files.append(p)
    recs, bad = [], 0
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    bad += 1
                    continue
                if isinstance(r, dict):
                    # Godot's JSON turns ints into floats (2.0); undo that.
                    for k, v in r.items():
                        if isinstance(v, float) and v.is_integer() and k not in ("dpr", "speed", "zoom"):
                            r[k] = int(v)
                    recs.append(r)
    return files, recs, bad


def short_device(ss):
    ua = ss.get("user_agent", "")
    m = re.search(r"\(([^)]*)\)", ua)
    dev = m.group(1) if m else ss.get("os", "?")
    browser = "?"
    for pat, name in [(r"CriOS/([\d.]+)", "Chrome iOS"), (r"FxiOS/([\d.]+)", "Firefox iOS"),
                      (r"EdgA?/([\d.]+)", "Edge"), (r"SamsungBrowser/([\d.]+)", "Samsung"),
                      (r"Firefox/([\d.]+)", "Firefox"), (r"Chrome/([\d.]+)", "Chrome"),
                      (r"Version/([\d.]+).*Safari", "Safari")]:
        mm = re.search(pat, ua)
        if mm:
            browser = f"{name} {mm.group(1).split('.')[0]}"
            break
    return dev, browser


def fmt(x, nd=1):
    return "-" if x is None else f"{x:.{nd}f}"


def sim_build(build):
    m = re.search(r"sim:(\w+)", build or "")
    return m.group(1) if m else (build or "?")


def main():
    paths = sys.argv[1:] or [os.path.join(REPO, "playtest_logs")]
    files, recs, bad = load(paths)
    if not recs:
        print(f"No records in {', '.join(paths)}")
        return
    sessions = collections.OrderedDict()
    for r in sorted(recs, key=lambda r: (r.get("recv", ""), r.get("seq", 0))):
        sessions.setdefault(str(r.get("session", "?")), []).append(r)
    print(f"{len(recs)} records, {len(sessions)} sessions, from {len(files)} file(s)"
          + (f"; {bad} unreadable lines" if bad else ""))

    runs = []  # (scenario, seed, sim build, session, end/checkpoints)
    for sid, rs in sessions.items():
        rs.sort(key=lambda r: r.get("seq", 0))
        ss = next((r for r in rs if r.get("kind") == "session_start"), {})
        dev, browser = short_device(ss)
        seqs = [r.get("seq") for r in rs if isinstance(r.get("seq"), int)]
        missing = (max(seqs) + 1 - len(set(seqs))) if seqs else 0
        print("\n" + "=" * 78)
        print(f"Session {sid}  first {rs[0].get('recv', '?')}  ip {rs[0].get('ip', '?')}")
        print(f"  device : {dev} | {browser} | touch points {ss.get('max_touch_points', '?')}"
              f" | screen {ss.get('screen_w', '?')}x{ss.get('screen_h', '?')} @{ss.get('dpr', '?')}"
              f" | viewport {ss.get('viewport_w', '?')}x{ss.get('viewport_h', '?')}")
        print(f"  gpu    : {ss.get('gpu', '?')} ({ss.get('gpu_vendor', '?')}, {ss.get('gpu_api', '?')})"
              f" | godot {ss.get('godot', '?')} | build {ss.get('build', '?')}")
        if ss.get("url_query"):
            print(f"  url    : {ss.get('url_query')}")
        if missing:
            print(f"  NOTE: {missing} record(s) missing from the sequence (lost or not flushed)")

        # Split records into scenario runs.
        cur = None
        scen_runs = []
        for r in rs:
            k = r.get("kind")
            if k == "scenario_start":
                cur = {"start": r, "perf": [], "bench": None, "end": None, "snapshot": None,
                       "checkpoints": {}, "input": collections.Counter(),
                       "order_types": collections.Counter()}
                scen_runs.append(cur)
            elif cur is None:
                continue
            elif k == "perf":
                cur["perf"].append(r)
                cur["input"].update(r.get("input") or {})
                cur["order_types"].update(r.get("orders") or {})
            elif k == "scenario_snapshot":
                cur["snapshot"] = r
            elif k == "bench_summary":
                cur["bench"] = r
            elif k == "hash_checkpoint":
                cur["checkpoints"][str(r.get("tick"))] = r.get("hash")
                cur["player_orders"] = r.get("player_orders", 0)
            elif k == "scenario_end":
                cur["end"] = r
                cur["checkpoints"].update(r.get("checkpoint_hashes") or {})
                cur = None
        for run in scen_runs:
            st, end = run["start"], run["end"]
            perf = run["perf"]
            fps = [p["fps_avg"] for p in perf if isinstance(p.get("fps_avg"), (int, float))]
            fmin = [p["fps_min"] for p in perf if isinstance(p.get("fps_min"), (int, float))]
            p95 = [p["frame_ms_p95"] for p in perf if isinstance(p.get("frame_ms_p95"), (int, float))]
            smean = [p["sim_ms_mean"] for p in perf if p.get("ticks")]
            smax = [p["sim_ms_max"] for p in perf if p.get("ticks")]
            active = [p for p in perf if not p.get("paused")]
            print(f"  -- {st.get('scenario')} seed {st.get('seed')}, {st.get('soldiers')} soldiers"
                  f"{' (bench)' if st.get('bench') else ''}")
            if end:
                print(f"     end: {end.get('reason')} at tick {end.get('tick')}, winner {end.get('winner')}"
                      f" (decided {end.get('decided_tick')}), alive {end.get('alive0')}/{end.get('alive1')},"
                      f" {fmt(end.get('wall_s'), 0)} s wall, player orders {end.get('player_orders')},"
                      f" final hash {end.get('final_hash')}")
            elif run["snapshot"]:
                sn = run["snapshot"]
                print(f"     end: (no scenario_end) page hidden/closed at tick {sn.get('tick')},"
                      f" winner {sn.get('winner')}, alive {sn.get('alive0')}/{sn.get('alive1')},"
                      f" {fmt(sn.get('wall_s'), 0)} s wall, player orders {sn.get('player_orders')}")
            else:
                print("     end: (no scenario_end record: tab closed or still running)")
            if perf:
                print(f"     perf ({len(perf)} samples, {len(active)} unpaused): fps median"
                      f" {fmt(statistics.median(fps)) if fps else '-'}, worst window avg"
                      f" {fmt(min(fps)) if fps else '-'}, lowest instant {fmt(min(fmin)) if fmin else '-'};"
                      f" frame p95 median {fmt(statistics.median(p95)) if p95 else '-'} ms,"
                      f" worst {fmt(max(p95)) if p95 else '-'} ms")
                print(f"     sim ms/tick: mean {fmt(statistics.mean(smean), 2) if smean else '-'},"
                      f" worst window mean {fmt(max(smean), 2) if smean else '-'},"
                      f" max {fmt(max(smax), 2) if smax else '-'}")
            b = run["bench"]
            if b:
                print(f"     BENCH: sim mean {fmt(b.get('sim_ms_mean'), 2)} p95 {fmt(b.get('sim_ms_p95'), 2)}"
                      f" max {fmt(b.get('sim_ms_max'), 2)} ms; {b.get('frames')} frames,"
                      f" avg {fmt(b.get('fps_avg'))} fps, 1% slowest {fmt(b.get('frame_ms_p99'))} ms,"
                      f" max {fmt(b.get('frame_ms_max'))} ms")
            if run["input"]:
                print("     input: " + ", ".join(f"{k} {v}" for k, v in sorted(run["input"].items())))
            if run["order_types"]:
                print("     orders: " + ", ".join(f"{k} {v}" for k, v in sorted(run["order_types"].items())))
            if run["checkpoints"]:
                print("     hashes: " + " ".join(f"{t}:{h}" for t, h in
                                                 sorted(run["checkpoints"].items(), key=lambda kv: int(kv[0]))))
            orders = end.get("player_orders") if end else run.get("player_orders", 0)
            runs.append({"scenario": st.get("scenario"), "seed": st.get("seed"),
                         "sim": sim_build(ss.get("build")), "session": sid,
                         "device": f"{dev} | {browser}", "orders": orders or 0,
                         "checkpoints": dict(run["checkpoints"]),
                         "final": (end or {}).get("final_hash") if (end or {}).get("reason") == "bench_complete" else None,
                         "final_tick": (end or {}).get("tick")})

        env = collections.Counter(r.get("kind") for r in rs if r.get("kind") in ENV_KINDS)
        if env:
            detail = []
            for r in rs:
                if r.get("kind") == "visibility":
                    detail.append(r.get("state"))
            print("  env events: " + ", ".join(f"{k} {v}" for k, v in sorted(env.items()))
                  + (f"  (visibility: {' '.join(detail[:12])})" if detail else ""))
        errs = [r for r in rs if r.get("kind") in ERROR_KINDS]
        if errs:
            print(f"  ERRORS ({len(errs)}):")
            for e in errs[:8]:
                print(f"     {e.get('kind')}: {e.get('message')} {e.get('source', '')}:{e.get('line', '')}")

    # Cross-session determinism check.
    print("\n" + "=" * 78)
    print("Determinism: runs with the same scenario + seed + sim code and no player orders")
    groups = collections.defaultdict(list)
    for r in runs:
        if r["orders"] == 0 and r["checkpoints"]:
            groups[(r["scenario"], r["seed"], r["sim"])].append(r)
    if not groups:
        print("  (no comparable runs)")
    any_bad = False
    for (scen, seed, simb), rs in sorted(groups.items(), key=lambda kv: str(kv[0])):
        ticks = sorted({int(t) for r in rs for t in r["checkpoints"]})
        mismatched = []
        for t in ticks:
            vals = {r["checkpoints"].get(str(t)) for r in rs if str(t) in r["checkpoints"]}
            if len(vals) > 1:
                mismatched.append(t)
        finals = {r["final"] for r in rs if r["final"]}
        if len(finals) > 1:
            mismatched.append("final")
        status = "MISMATCH" if mismatched else "ok"
        any_bad |= bool(mismatched)
        print(f"  {scen} seed {seed} sim:{simb}: {len(rs)} run(s) on "
              f"{len({r['device'] for r in rs})} device(s), checkpoints {ticks} -> {status}")
        if mismatched:
            first = mismatched[0]
            print(f"     first mismatch at {first}:")
            for r in rs:
                h = r["checkpoints"].get(str(first)) if first != "final" else r["final"]
                print(f"       {h}  {r['device']}  (session {r['session']})")
    if any_bad:
        print("  ** DETERMINISM MISMATCH: see above **")


if __name__ == "__main__":
    main()
