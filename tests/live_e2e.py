#!/usr/bin/env python3
"""End-to-end test of live co-op battles (milestone 5): the Go server and two
headless Godot clients (tests/live_client.gd) fighting three battles of one
online campaign together over real WebSockets.

    python3 tests/live_e2e.py [--port 8072] [--frame-ms 20] [--keep]

Builds the server into build/server-test/ (never the binary a running server
uses), starts it in test mode on a temp data dir, runs client A (Rome,
creates the campaign, hosts) and B (Carthage, joins), then checks:
  - every battle ran to its end on both clients and both computed the same
    lockstep hash on every frame they both ran (hash every frame, compared
    here from both clients' files, and by the clients over the relay);
  - battle 1 (B joined in the lobby): the gift and the gift back, the pause
    vote (asked, accepted, resumed) and the speed vote (4x) took effect;
  - battle 2 (B joined mid-battle): restored from a snapshot, caught up,
    admitted, then commanded its own army;
  - battle 3 (B's connection dropped): A was offered Continue and took over
    B's units; B came back by snapshot and regained them;
  - battle 4 (Rome's army alone): B, with no army there, asked to join
    (choice "ask"), A saw the request, opened the room, B joined as a guest,
    A gave B two units and B commanded them;
  - each result was uploaded once by the host; both clients end on the
    server's campaign state with nothing left to send and no mismatch.
Then two custom battles (tests/live_custom_client.gd): head-to-head (each
player commands one side) and co-op (both on one side against the AI):
room by setup, join by code, Player 2 edits its army in the lobby, both
ready, a deployment phase (placements, the other's units refused, ready at
different frames), the fight to the end; hashes equal on every frame.
`--only-custom` skips the campaign battles.
Prints waits, round trips, snapshot sizes and catch-up times. Exit 0 on PASS.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FAILS = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)


def api(base, method, path, token=None):
    req = urllib.request.Request(base + path, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8072)
    ap.add_argument("--frame-ms", type=int, default=20, help="lockstep frame length (100 = real time)")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--only-custom", action="store_true")
    args = ap.parse_args()
    binary = os.path.join(REPO, "build", "server-test", "scserver")
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True, env=dict(os.environ, SC_BUILD_OUT=binary))
    tmp = tempfile.mkdtemp(prefix="sc_live_")
    print("temp dir", tmp)
    base = "http://127.0.0.1:%d" % args.port
    srv_log = open(os.path.join(tmp, "server.log"), "w")
    srv = subprocess.Popen([binary, "-addr", "127.0.0.1:%d" % args.port, "-data", os.path.join(tmp, "data"),
                            "-web", os.path.join(REPO, "build", "web"), "-log-dir", os.path.join(tmp, "logs"),
                            "-test-mode", "-compress=false"], stdout=srv_log, stderr=srv_log)
    try:
        for _ in range(100):
            try:
                if api(base, "GET", "/healthz")["ok"]:
                    break
            except Exception:
                time.sleep(0.1)
        for mode in ["h2h", "coop"]:
            custom_battle(tmp, base, mode, args.frame_ms)
        if args.only_custom:
            print("RESULT:", "PASS" if not FAILS else "FAIL (%d)" % len(FAILS))
            sys.exit(0 if not FAILS else 1)
        procs = {}
        logs = {}
        for role in ["A", "B"]:
            logs[role] = open(os.path.join(tmp, "client_%s.log" % role), "w")
            procs[role] = subprocess.Popen(
                ["godot", "--headless", "--path", REPO, "--script", "res://tests/live_client.gd", "--",
                 "--server=" + base, "--role=" + role, "--dir=" + tmp, "--coop-frame-ms=%d" % args.frame_ms,
                 "--coop-hash-every=1", "--coop-grace=2"],
                stdout=logs[role], stderr=subprocess.STDOUT)
        t0 = time.time()
        codes = {}
        for role, p in procs.items():
            try:
                codes[role] = p.wait(timeout=1200 - (time.time() - t0))
            except subprocess.TimeoutExpired:
                p.kill()
                codes[role] = "timeout"
        print("clients finished in %.0f s: %s" % (time.time() - t0, codes))
        res = {}
        for role in ["A", "B"]:
            path = os.path.join(tmp, "live_%s.json" % role)
            res[role] = json.load(open(path)) if os.path.exists(path) else {}
        check(codes == {"A": 0, "B": 0}, "both clients exit cleanly (%s)" % codes)
        for role in ["A", "B"]:
            check(res[role].get("ok") is True, "client %s reports no errors %s" % (role, res[role].get("errors")))
        ba = {b["battle"]: b for b in res["A"].get("battles", [])}
        bb = {b["battle"]: b for b in res["B"].get("battles", [])}
        check(len(ba) == 4 and len(bb) == 4, "four battles fought on both clients")
        for bid in sorted(ba):
            a, b = ba[bid], bb.get(bid, {})
            kind = a["kind"]
            ha = json.load(open(os.path.join(tmp, "hashes_A_%d.json" % bid)))
            hb = json.load(open(os.path.join(tmp, "hashes_B_%d.json" % bid))) if os.path.exists(os.path.join(tmp, "hashes_B_%d.json" % bid)) else {}
            common = [f for f in ha if f in hb]
            bad = [f for f in common if ha[f] != hb[f]]
            check(len(common) > 200 and not bad,
                  "battle %d (%s): %d frames with both hashes, %d different%s" % (bid, kind, len(common), len(bad), (" first " + str(sorted(bad, key=int)[:3])) if bad else ""))
            check(a.get("ended") and b.get("ended"), "battle %d (%s) ran to its end on both (A frame %s tick %s winner %s; B frame %s)" % (
                bid, kind, a.get("frames"), a.get("tick"), a.get("winner"), b.get("frames")))
            check(a.get("result_hash") and a.get("result_hash") == b.get("result_hash"),
                  "battle %d: both computed the same result (%s / %s)" % (bid, a.get("result_hash"), b.get("result_hash")))
            sa, sb = a["stats"], b["stats"]
            check(sa["desyncs"] == 0 and sb["desyncs"] == 0 and sa["hash_checks"] > 100 and sb["hash_checks"] > 100,
                  "battle %d: hash checks over the relay A %d / B %d, desyncs %d / %d" % (bid, sa["hash_checks"], sb["hash_checks"], sa["desyncs"], sb["desyncs"]))
            check(a.get("deploy_end", -1) >= 90 and (kind == "midjoin" or abs(a.get("deploy_end", 0) - b.get("deploy_end", -99)) <= 8),
                  "battle %d: a 10 s deployment phase ended at frame %s (B %s)" % (bid, a.get("deploy_end"), b.get("deploy_end")))
            check(a.get("upload") == "ok" and not b.get("upload"), "battle %d: the host uploaded the result once (%s)" % (bid, a.get("upload")))
            print("    numbers: A rtt %.1f ms delay %s, waits %d (total %.0f ms, max %.0f ms); B rtt %.1f ms, waits %d (total %.0f ms, max %.0f ms); wall %.1f s" % (
                a["rtt_ms"], a["delay"], sa["waits"], sa["wait_ms_total"], sa["wait_ms_max"], b["rtt_ms"], sb["waits"],
                sb["wait_ms_total"], sb["wait_ms_max"], a["wall_s"]))
            if sa["snap_sent"] or sb["snap_restored"]:
                print("    snapshots: A sent %d (last %d bytes); B restored %d (%.1f ms); B catch-ups %d: %d frames in %.0f ms" % (
                    sa["snap_sent"], sa["snap_bytes"], sb["snap_restored"], sb["restore_ms"], sb["catchups"], sb["catchup_frames"], sb["catchup_ms"]))
            if kind == "prestart":
                g, gb = a.get("gifts", {}), b.get("gifts", {})
                check("given" in g and "back_at" in g and "got" in gb and "back" in gb,
                      "battle %d: A gifted unit %s at frame %s, B got it at %s and gave it back at %s, A had it back at %s" % (
                          bid, g.get("given"), g.get("given_at"), gb.get("got_at"), gb.get("back"), g.get("back_at")))
                va, vb = a.get("votes", {}), b.get("votes", {})
                check(va.get("pause_on", -1) > va.get("pause_asked", 0) and va.get("resume_on", -1) > va.get("resume_asked", 0)
                      and va.get("pause_on") == vb.get("pause_on") and va.get("resume_on") == vb.get("resume_on"),
                      "battle %d: pause vote asked at %s, paused at frame %s, resume asked at %s, resumed at %s on both" % (
                          bid, va.get("pause_asked"), va.get("pause_on"), va.get("resume_asked"), va.get("resume_on")))
                check(vb.get("speed_on", -1) > 0 and vb.get("speed_on") == va.get("speed_on"),
                      "battle %d: speed vote (4x) asked at %s, applied at frame %s on both" % (bid, vb.get("speed_asked"), vb.get("speed_on")))
            if kind == "midjoin":
                check(sb["snap_restored"] >= 1 and b.get("admitted_frame") is not None and b.get("commands", 0) > 0,
                      "battle %d: B joined mid-battle from a snapshot, admitted at frame %s commanding %s units" % (
                          bid, b.get("admitted_frame"), b.get("commands")))
            if kind == "guest":
                g, gb = a.get("gifts", {}), b.get("gifts", {})
                check(b.get("asked") is True and a.get("ask_seen") is True,
                      "battle %d: B (no army) asked to join, A saw the request (guests %s)" % (bid, a.get("guests")))
                check("given" in g and g.get("ally_has", 0) > 0 and gb.get("got", 0) > 0 and "ordered" in gb,
                      "battle %d: A gave units %s at frame %s, B commanded %s from frame %s and ordered them at %s" % (
                          bid, g.get("given"), g.get("given_at"), gb.get("got"), gb.get("got_at"), gb.get("ordered")))
            if kind == "drop":
                check(a.get("took_units", 0) > 0, "battle %d: A took over %s of B's units after B dropped" % (bid, a.get("took_units")))
                check(b.get("regained_units", 0) > 0 and sb["snap_restored"] >= 1,
                      "battle %d: B came back by snapshot and regained %s units" % (bid, b.get("regained_units")))
        fa, fb = res["A"].get("final", {}), res["B"].get("final", {})
        acc = json.load(open(os.path.join(tmp, "acc_B.json")))
        cid = list(acc["campaigns"].keys())[0]
        summ = api(base, "GET", "/api/c/" + cid, acc["campaigns"][cid]["token"])
        check(fa.get("hash") == summ["hash"] == fb.get("hash") and fa.get("local_hash") == summ["hash"] == fb.get("local_hash"),
              "both clients end on the server's campaign state (v%s %s)" % (summ["version"], summ["hash"]))
        check(fa.get("outbox") == 0 and fb.get("outbox") == 0, "no result left unsent")
        check(summ["phase"] != "battles" and summ["version"] == 5, "all four battles resolved (version %d, phase %s)" % (summ["version"], summ["phase"]))
        bad_verify = [k for k, v in list(fa.get("verified", {}).items()) + list(fb.get("verified", {}).items()) if v != 1]
        check(not bad_verify, "every version made by the other device re-checked equal %s" % bad_verify)
        with open(os.path.join(tmp, "server.log")) as f:
            desync_lines = [l for l in f if "LIVE DESYNC" in l]
        check(not desync_lines, "the server saw no hash mismatch (%d)" % len(desync_lines))
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=10)
        except subprocess.TimeoutExpired:
            srv.kill()
    print("RESULT:", "PASS" if not FAILS else "FAIL (%d)" % len(FAILS))
    if FAILS or args.keep:
        print("logs kept in", tmp)
    else:
        shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(0 if not FAILS else 1)


def custom_battle(tmp, base, mode, frame_ms):
    print("custom battle:", mode)
    procs, logs = {}, {}
    for role in ["A", "B"]:
        logs[role] = open(os.path.join(tmp, "custom_%s_%s.log" % (mode, role)), "w")
        procs[role] = subprocess.Popen(
            ["godot", "--headless", "--path", REPO, "--script", "res://tests/live_custom_client.gd", "--",
             "--server=" + base, "--role=" + role, "--dir=" + tmp, "--mode=" + mode,
             "--coop-frame-ms=%d" % frame_ms, "--coop-hash-every=1", "--coop-grace=2"],
            stdout=logs[role], stderr=subprocess.STDOUT)
    t0 = time.time()
    codes = {}
    for role, p in procs.items():
        try:
            codes[role] = p.wait(timeout=600 - (time.time() - t0))
        except subprocess.TimeoutExpired:
            p.kill()
            codes[role] = "timeout"
    print("  clients finished in %.0f s: %s" % (time.time() - t0, codes))
    res = {}
    for role in ["A", "B"]:
        path = os.path.join(tmp, "custom_%s_%s.json" % (mode, role))
        res[role] = json.load(open(path)) if os.path.exists(path) else {}
    a, b = res["A"], res["B"]
    check(codes == {"A": 0, "B": 0} and a.get("ok") is True and b.get("ok") is True,
          "%s: both clients ran cleanly (%s; errors %s %s)" % (mode, codes, a.get("errors"), b.get("errors")))
    ha = json.load(open(os.path.join(tmp, "chashes_%s_A.json" % mode))) if os.path.exists(os.path.join(tmp, "chashes_%s_A.json" % mode)) else {}
    hb = json.load(open(os.path.join(tmp, "chashes_%s_B.json" % mode))) if os.path.exists(os.path.join(tmp, "chashes_%s_B.json" % mode)) else {}
    common = [f for f in ha if f in hb]
    bad = [f for f in common if ha[f] != hb[f]]
    check(len(common) > 200 and not bad, "%s: %d frames with both hashes, %d different" % (mode, len(common), len(bad)))
    check(a.get("setup_rev", 0) >= 2 and a.get("setup_rev") == b.get("setup_rev"),
          "%s: Player 2's lobby edit reached the host (setup rev %s / %s)" % (mode, a.get("setup_rev"), b.get("setup_rev")))
    check(a.get("start_frame", -1) > 40 and a.get("start_frame") == b.get("start_frame"),
          "%s: the deployment ended when both were ready (frame %s / %s; A ready at 40, B at 90)" % (mode, a.get("start_frame"), b.get("start_frame")))
    check(a.get("placed", 0) > 0 and b.get("placed", 0) > 0 and a.get("rejected", 0) > 0,
          "%s: units placed (A %s, B %s); orders for the other's units refused (%s)" % (mode, a.get("placed"), b.get("placed"), a.get("rejected")))
    want_sides = (0, 1) if mode == "h2h" else (0, 0)
    check((a.get("my_side"), b.get("my_side")) == want_sides and (a.get("ai_sides") == ([0, 0] if mode == "h2h" else [0, 1])),
          "%s: sides A %s B %s, AI sides %s" % (mode, a.get("my_side"), b.get("my_side"), a.get("ai_sides")))
    check(a.get("end_frame", -1) > 0 and a.get("result_hash") and a.get("result_hash") == b.get("result_hash"),
          "%s: fought to the end (frame %s, winner %s), same result on both (%s / %s)" % (
              mode, a.get("end_frame"), a.get("winner"), a.get("result_hash"), b.get("result_hash")))


if __name__ == "__main__":
    main()
