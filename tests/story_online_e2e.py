#!/usr/bin/env python3
"""End-to-end test of the online story campaign "The Brethren's Due" with two
captains: the Go server, a fake Discord webhook and two headless Godot clients
(tests/story_online_client.gd). Every story choice is a crew vote through the
server (kind "story", compare-and-swap); the first one is cast by both captains
at the same moment and they disagree.

    python3 tests/story_online_e2e.py [--port 8074] [--turns 6] [--keep]

The server binary is built into a scratch directory (never build/). Checks:
both clients end on the server's version and hash; every vote is a "story"
version whose inputs name the voting seat; B re-ran every step locally with no
mismatch; the split vote was settled in the state (log keeps both votes and
the winner); a vote waits for the other captain (a notification to them); the
server refuses an answer that changes nothing; the turns resolved after the
votes; the Discord messages.
"""
import argparse, http.server, json, os, shutil, subprocess, sys, tempfile, threading, time, urllib.request, urllib.error

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HOOK_MSGS, FAILS = [], []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)


class Hook(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        HOOK_MSGS.append(json.loads(self.rfile.read(n) or b"{}"))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *a):
        pass


def api(base, method, path, token=None, body=None):
    req = urllib.request.Request(base + path, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"_status": e.code, **json.loads(e.read() or b"{}")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8074)
    ap.add_argument("--turns", type=int, default=6)
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="sc_story_e2e_")
    print("temp dir", tmp)
    binary = os.path.join(tmp, "scserver")
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True, env=dict(os.environ, SC_BUILD_OUT=binary))
    hook = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Hook)
    threading.Thread(target=hook.serve_forever, daemon=True).start()
    hook_url = "http://127.0.0.1:%d/api/webhooks/1/test" % hook.server_address[1]
    base = "http://127.0.0.1:%d" % args.port
    os.makedirs(os.path.join(tmp, "web"), exist_ok=True)
    srv_log = open(os.path.join(tmp, "server.log"), "w")
    srv = subprocess.Popen([binary, "-addr", "127.0.0.1:%d" % args.port, "-data", os.path.join(tmp, "data"),
                            "-web", os.path.join(tmp, "web"), "-log-dir", os.path.join(tmp, "logs"), "-test-mode", "-compress=false"],
                           stdout=srv_log, stderr=srv_log)
    try:
        for _ in range(100):
            try:
                if api(base, "GET", "/healthz")["ok"]:
                    break
            except Exception:
                time.sleep(0.1)
        procs = {}
        for role in ["A", "B"]:
            log = open(os.path.join(tmp, "client_%s.log" % role), "w")
            procs[role] = subprocess.Popen(
                ["godot", "--headless", "--path", REPO, "--script", "res://tests/story_online_client.gd", "--",
                 "--server=" + base, "--role=" + role, "--dir=" + tmp, "--hook=" + hook_url, "--turns=%d" % args.turns],
                stdout=log, stderr=subprocess.STDOUT)
            if role == "A":
                time.sleep(1.0)
        t0 = time.time()
        codes = {}
        for role, p in procs.items():
            try:
                codes[role] = p.wait(timeout=900 - (time.time() - t0))
            except subprocess.TimeoutExpired:
                p.kill()
                codes[role] = "timeout"
        print("clients finished in %.0f s: %s" % (time.time() - t0, codes))
        for _ in range(240):
            n = api(base, "GET", "/healthz")["notify"]
            if n["pending"] == 0 and n["queued"] <= n["sent"] + n["failed"] + n["dropped"]:
                break
            time.sleep(0.5)
        res = {}
        for role in ["A", "B"]:
            path = os.path.join(tmp, "result_%s.json" % role)
            res[role] = json.load(open(path)) if os.path.exists(path) else {}
        check(codes == {"A": 0, "B": 0}, "both clients exit cleanly (%s)" % codes)
        for role in ["A", "B"]:
            check(res[role].get("ok") is True, "client %s reports no errors %s" % (role, res[role].get("errors")))
        acc = json.load(open(os.path.join(tmp, "acc_B.json")))
        cid = res["B"].get("id") or res["A"].get("id")
        tok = acc["campaigns"][cid]["token"]
        summ = api(base, "GET", "/api/c/" + cid, tok)
        print("server: version %d, turn %d, phase %s" % (summ["version"], summ["turn"], summ["phase"]))
        for role in ["A", "B"]:
            fin = res[role].get("final", {})
            check(fin.get("hash") == summ["hash"] and fin.get("local_hash") == summ["hash"] and fin.get("version") == summ["version"],
                  "client %s ends on the server's state (v%s)" % (role, fin.get("version")))
        check(summ["turn"] >= args.turns or summ["phase"] == "over", "played %d turns" % summ["turn"])
        hist = api(base, "GET", "/api/c/%s/history" % cid, tok)["versions"]
        check(all(v["version"] == i + 1 and v["parent"] == i for i, v in enumerate(hist)), "history complete: %d versions" % len(hist))
        kinds = {}
        for v in hist:
            kinds[v["kind"]] = kinds.get(v["kind"], 0) + 1
        print("  versions by kind:", kinds)
        check(kinds.get("story", 0) >= 4, "at least two crew votes went through the server (%d story versions)" % kinds.get("story", 0))
        check(kinds.get("turn", 0) >= 1, "turns resolved after the votes (%d)" % kinds.get("turn", 0))
        chain = res["B"].get("chain", {})
        check(chain.get("bad") == 0 and chain.get("checked", 0) == kinds.get("turn", 0) + kinds.get("battle", 0) + kinds.get("story", 0),
              "B re-ran all %s steps (turns, battles, votes) with %s mismatches" % (chain.get("checked"), chain.get("bad")))
        seats = {}
        for v in hist:
            if v["kind"] == "story":
                d = api(base, "GET", "/api/c/%s/history/%d?state=0" % (cid, v["version"]), tok)
                inp = d["inputs"]
                check(inp["f"] == v["by"], "version %d: the vote is by the seat that uploaded it (f %s)" % (v["version"], inp["f"]))
                seats[inp["f"]] = seats.get(inp["f"], 0) + 1
        check(len(seats) == 2, "both captains voted through the server %s" % seats)
        vl = res["A"].get("final", {}).get("vote_log", [])
        check(len(vl) >= 2 and all(len(e["v"]) == 2 for e in vl), "the log keeps both captains' votes (%d settled votes)" % len(vl))
        first = vl[0] if vl else {}
        check(first.get("w", -1) >= 0 and len({v[1] for v in first.get("v", [])}) == 2, "the first vote was split and Mercy's rule settled it (winner %s)" % first.get("w"))
        check(res["A"]["final"].get("pending", 1) == 0 or summ["turn"] >= args.turns, "no vote left open at the end")
        check(res["A"].get("waited", 0) + res["B"].get("waited", 0) >= 1, "a captain waited for the other's vote")
        votes = res["A"]["votes"] + res["B"]["votes"]
        check(len(votes) >= 4, "%d votes cast" % len(votes))
        check(res["A"]["votes"] and res["B"]["votes"] and sum(r.get("conflicts", 0) for r in res.values()) >= 1,
              "the simultaneous first vote hit the compare-and-swap once and was re-applied (%d conflicts)" % sum(r.get("conflicts", 0) for r in res.values()))
        # The server refuses a story answer that changes nothing.
        cur = api(base, "GET", "/api/c/%s/state" % cid, tok)
        r = api(base, "POST", "/api/c/%s/state" % cid, tok, {"base_version": cur["version"], "kind": "story", "story_pid": 1, "story_k": 0,
                                                            "hash": cur["hash"], "state_gz": "", "rules": "x", "build": "x"})
        check(r.get("_status") == 400, "a story answer with no state is refused (%s)" % r.get("error"))
        msgs = [m["content"] for m in HOOK_MSGS]
        print("  webhook got %d messages" % len(msgs))
        check(any("The crew is voting" in m and "<@222222222222222222>" in m or "The crew is voting" in m and "<@111111111111111111>" in m for m in msgs),
              "a message tells the other captain the crew is voting (@mention)")
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=10)
        except subprocess.TimeoutExpired:
            srv.kill()
        hook.shutdown()
    print("RESULT:", "PASS" if not FAILS else "FAIL (%d)" % len(FAILS))
    if FAILS or args.keep:
        print("logs kept in", tmp)
    else:
        shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(0 if not FAILS else 1)


if __name__ == "__main__":
    main()
