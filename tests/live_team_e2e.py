#!/usr/bin/env python3
"""End-to-end test of a live campaign battle with three humans (N-player
campaigns): the Go server and three headless Godot clients
(tests/live_team_client.gd) over real WebSockets.

    python3 tests/live_team_e2e.py [--port 8073] [--frame-ms 20] [--keep]

Builds the server into the temp dir (never the binary a running server
uses), starts it in test mode on a temp data dir, runs A (Rome, creates the
campaign, hosts), B (Carthage, Rome's team-mate) and C (Macedon, the enemy,
another team), then checks:
  - all three joined one room and took part from frame 0 (A and B on one
    side, C on the other; no side under the battle AI);
  - every frame all three ran has the same lockstep hash on all three, and
    the relay saw no mismatch;
  - each commanded its own units only; A's gift reached B (the gift list
    held Carthage, never Macedon) and B commanded the units;
  - the battle ran to its end with the same result on all three, the host
    uploaded it once and every client ends on the server's campaign state.
Exit 0 on PASS.
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
ROLES = ["A", "B", "C"]


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
    ap.add_argument("--port", type=int, default=8073)
    ap.add_argument("--frame-ms", type=int, default=20)
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="sc_live_team_")
    print("temp dir", tmp)
    binary = os.path.join(tmp, "scserver")  # (built here: never a binary a running server uses)
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True, env=dict(os.environ, SC_BUILD_OUT=binary))
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
        procs, logs = {}, {}
        for role in ROLES:
            logs[role] = open(os.path.join(tmp, "client_%s.log" % role), "w")
            procs[role] = subprocess.Popen(
                ["godot", "--headless", "--path", REPO, "--script", "res://tests/live_team_client.gd", "--",
                 "--server=" + base, "--role=" + role, "--dir=" + tmp, "--coop-frame-ms=%d" % args.frame_ms,
                 "--coop-hash-every=1", "--coop-grace=2"],
                stdout=logs[role], stderr=subprocess.STDOUT)
        t0 = time.time()
        codes = {}
        for role, p in procs.items():
            try:
                codes[role] = p.wait(timeout=900 - (time.time() - t0))
            except subprocess.TimeoutExpired:
                p.kill()
                codes[role] = "timeout"
        print("clients finished in %.0f s: %s" % (time.time() - t0, codes))
        res = {}
        hashes = {}
        for role in ROLES:
            path = os.path.join(tmp, "team_%s.json" % role)
            res[role] = json.load(open(path)) if os.path.exists(path) else {}
            hp = os.path.join(tmp, "thashes_%s.json" % role)
            hashes[role] = json.load(open(hp)) if os.path.exists(hp) else {}
        check(all(codes[r] == 0 for r in ROLES), "three clients exit cleanly (%s)" % codes)
        for role in ROLES:
            check(res[role].get("ok") is True, "client %s reports no errors %s" % (role, res[role].get("errors")))
        a, b, c = res["A"], res["B"], res["C"]
        check(sorted(a.get("players", [])) == sorted(a.get("humans", [])) and len(a.get("humans", [])) == 3
              and a.get("players") == b.get("players") == c.get("players"),
              "all three took part from the start (players %s, humans %s)" % (a.get("players"), a.get("humans")))
        check((a.get("my_side"), b.get("my_side"), c.get("my_side")) == (0, 0, 1) and a.get("ai_sides") == [],
              "sides A %s B %s C %s, AI sides %s" % (a.get("my_side"), b.get("my_side"), c.get("my_side"), a.get("ai_sides")))
        common = [f for f in hashes["A"] if f in hashes["B"] and f in hashes["C"]]
        bad = [f for f in common if not (hashes["A"][f] == hashes["B"][f] == hashes["C"][f])]
        check(len(common) > 200 and not bad, "%d frames with all three hashes, %d different%s" % (
            len(common), len(bad), (" first " + str(sorted(bad, key=int)[:3])) if bad else ""))
        for role in ROLES:
            st = res[role].get("stats", {})
            check(st.get("desyncs", -1) == 0 and st.get("hash_checks", 0) > 200,
                  "%s: %s hash checks over the relay, %s desyncs" % (role, st.get("hash_checks"), st.get("desyncs")))
        check(all(res[r].get("own", 0) > 0 and res[r].get("other_at_30", -1) == 0 for r in ROLES),
              "each commands its own units only (own %s, others' %s)" % ([res[r].get("own") for r in ROLES],
                                                                         [res[r].get("other_at_30") for r in ROLES]))
        ga, gb = a.get("gifts", {}), b.get("gifts", {})
        check(len(ga.get("given", [])) == 2 and gb.get("got", 0) == 2,
              "A gave B units %s at frame %s (gift list %s); B commanded %s from frame %s" % (
                  ga.get("given"), ga.get("given_at"), ga.get("mates"), gb.get("got"), gb.get("got_at")))
        check(a.get("ended") and b.get("ended") and c.get("ended") and a.get("result_hash")
              and a.get("result_hash") == b.get("result_hash") == c.get("result_hash"),
              "fought to the end (A frame %s, winner %s), same result on all three (%s %s %s)" % (
                  a.get("frames"), a.get("winner"), a.get("result_hash"), b.get("result_hash"), c.get("result_hash")))
        check(a.get("upload") == "ok" and not b.get("upload") and not c.get("upload"),
              "the host uploaded the result once (%s; B %s, C %s)" % (a.get("upload"), b.get("upload"), c.get("upload")))
        acc = json.load(open(os.path.join(tmp, "tacc_C.json")))
        cid = list(acc["campaigns"].keys())[0]
        summ = api(base, "GET", "/api/c/" + cid, acc["campaigns"][cid]["token"])
        finals = [res[r].get("final", {}) for r in ROLES]
        check(all(f.get("hash") == summ["hash"] == f.get("local_hash") for f in finals) and summ["phase"] != "battles",
              "all three end on the server's campaign state (v%s %s, phase %s)" % (summ["version"], summ["hash"], summ["phase"]))
        check(all(f.get("outbox") == 0 for f in finals), "no result left unsent")
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


if __name__ == "__main__":
    main()
