#!/usr/bin/env python3
"""End-to-end test of online co-op: the Go server, a fake Discord webhook,
and two headless Godot clients (tests/online_client.gd) playing one campaign.

    python3 tests/online_e2e.py [--port 8071] [--turns 9] [--keep]

Builds the server (tools/build_server.sh, into build/server-test/), starts it in test mode on a temp
data dir, starts a fake webhook, runs client A (Rome, creates) and client B
(Carthage, joins), then checks:
  - both clients end on the server's version and state hash;
  - the version history is complete (1..N, each the child of the one before),
    and B re-ran every step locally with no mismatch;
  - no orders were lost: each turn's stored submissions are exactly what the
    clients submitted (the offline turn has only B's, and is marked forced);
  - the resolve race had one winner and the loser computed the same hash;
  - the device switch carried the half plan over and submitted from device 2;
  - both simulated upload failures recovered and no outcome was left behind;
  - the fake Discord webhook got the expected messages, in order, no dupes.
Exit code 0 on success.
"""
import argparse
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HOOK_MSGS = []
FAILS = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)


class Hook(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n) or b"{}")
        HOOK_MSGS.append(body)
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
    with urllib.request.urlopen(req, data, timeout=30) as r:
        return json.loads(r.read())


def canon(v):
    return json.dumps(v, sort_keys=True, separators=(",", ":"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8071)
    ap.add_argument("--turns", type=int, default=10)
    ap.add_argument("--keep", action="store_true", help="keep the temp dir")
    args = ap.parse_args()

    # A scratch binary: never replace the one a running server uses.
    binary = os.path.join(REPO, "build", "server-test", "scserver")
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True,
                   env=dict(os.environ, SC_BUILD_OUT=binary))
    tmp = tempfile.mkdtemp(prefix="sc_e2e_")
    print("temp dir", tmp)
    hook = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Hook)
    threading.Thread(target=hook.serve_forever, daemon=True).start()
    hook_url = "http://127.0.0.1:%d/api/webhooks/1/test" % hook.server_address[1]
    base = "http://127.0.0.1:%d" % args.port
    srv_log = open(os.path.join(tmp, "server.log"), "w")
    srv = subprocess.Popen([binary, "-addr", "127.0.0.1:%d" % args.port,
                            "-data", os.path.join(tmp, "data"), "-web", os.path.join(REPO, "build", "web"),
                            "-log-dir", os.path.join(tmp, "logs"), "-test-mode", "-compress=false"],
                           stdout=srv_log, stderr=srv_log)
    try:
        for _ in range(100):
            try:
                if api(base, "GET", "/healthz")["ok"]:
                    break
            except Exception:
                time.sleep(0.1)
        clients = {}
        logs = {}
        for role in ["A", "B"]:
            logs[role] = open(os.path.join(tmp, "client_%s.log" % role), "w")
            clients[role] = subprocess.Popen(
                ["godot", "--headless", "--path", REPO, "--script", "res://tests/online_client.gd", "--",
                 "--server=" + base, "--role=" + role, "--dir=" + tmp, "--hook=" + hook_url,
                 "--turns=%d" % args.turns],
                stdout=logs[role], stderr=subprocess.STDOUT)
            if role == "A":
                time.sleep(1.0)
        t0 = time.time()
        codes = {}
        for role, p in clients.items():
            try:
                codes[role] = p.wait(timeout=1500 - (time.time() - t0))
            except subprocess.TimeoutExpired:
                p.kill()
                codes[role] = "timeout"
        print("clients finished in %.0f s: %s" % (time.time() - t0, codes))
        # Let the notifier drain (it spaces a campaign's posts 1.5 s apart).
        for _ in range(240):
            n = api(base, "GET", "/healthz")["notify"]
            if n["pending"] == 0 and n["queued"] <= n["sent"] + n["failed"] + n["dropped"]:
                break
            time.sleep(0.5)
        print("  notifier:", n)
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
        print("server: version %d, turn %d, phase %s, hash %s" % (summ["version"], summ["turn"], summ["phase"], summ["hash"]))
        for role in ["A", "B"]:
            fin = res[role].get("final", {})
            check(fin.get("hash") == summ["hash"] and fin.get("local_hash") == summ["hash"] and fin.get("version") == summ["version"],
                  "client %s ends on the server's state (v%s %s)" % (role, fin.get("version"), fin.get("hash")))
            check(fin.get("outbox") == 0, "client %s has no battle result left unsent" % role)
        check(summ["turn"] >= args.turns or summ["phase"] == "over", "played %d turns" % summ["turn"])
        hist = api(base, "GET", "/api/c/%s/history" % cid, tok)["versions"]
        contiguous = all(v["version"] == i + 1 and v["parent"] == i for i, v in enumerate(hist))
        check(contiguous and hist[-1]["version"] == summ["version"], "history complete: %d versions, each the child of the last" % len(hist))
        kinds = {}
        for v in hist:
            kinds[v["kind"]] = kinds.get(v["kind"], 0) + 1
        print("  versions by kind:", kinds, " stored bytes:", sum(v["stored_size"] for v in hist))
        chain = res["B"].get("chain", {})
        check(chain.get("checked", 0) == kinds.get("turn", 0) + kinds.get("battle", 0) and chain.get("bad") == 0,
              "B re-ran all %s steps locally with %s mismatches" % (chain.get("checked"), chain.get("bad")))
        check(res["A"].get("verify_bad", 1) == 0 and res["B"].get("verify_bad", 1) == 0, "no determinism mismatch on either client")
        # Orders: per turn, the server's inputs are what the clients sent.
        lost = []
        forced_turns = []
        turn_versions = [v for v in hist if v["kind"] == "turn"]
        for v in turn_versions:
            d = api(base, "GET", "/api/c/%s/history/%d?state=0" % (cid, v["version"]), tok)
            inp = d["inputs"]
            t = inp["turn"]
            got = {s["f"]: s["orders"] for s in inp["submissions"]}
            if inp.get("forced"):
                forced_turns.append(t)
            for role, f in [("A", 0), ("B", 1)]:
                sent = res[role].get("submissions", {}).get(str(t))
                if sent is None:
                    if f in got:
                        lost.append("turn %d: %s has a submission the client did not record" % (t, role))
                    continue
                if canon(got.get(f)) != canon(sent):
                    lost.append("turn %d: %s's orders differ (%d sent, %s stored)" % (t, role, len(sent), len(got.get(f) or [])))
        check(not lost, "no orders lost or changed in %d resolved turns %s" % (len(turn_versions), lost[:3]))
        check(forced_turns == [5], "the offline turn (5) was forced, and only it: %s" % forced_turns)
        check(res["B"].get("forced") == "ok", "B forced the turn after the deadline (%s)" % res["B"].get("forced"))
        ra, rb = res["A"].get("race", {}), res["B"].get("race", {})
        outcomes = sorted([ra.get("result"), rb.get("result")])
        check(outcomes in (["already", "won"], ["lost", "won"]), "resolve race: one winner (%s)" % outcomes)
        check(ra.get("computed") and ra.get("computed") == rb.get("computed"), "both racers computed the same state (%s, %s)" % (ra.get("computed"), rb.get("computed")))
        ds = res["A"].get("device_switch", {})
        check(ds.get("half_plan_found") and ds.get("submitted") and ds.get("same_as_first_device"),
              "device switch: half plan carried over, completed and submitted from device 2 %s" % ds)
        ups = res["A"].get("upload_failures", []) + res["B"].get("upload_failures", [])
        check(len(ups) == 2 and all(u["recovered"] and u["first"] == "network" for u in ups) and
              all(u.get("kept_in_outbox", True) for u in ups),
              "battle results kept in the outbox through network failures (and a page close) and delivered %s" % ups)
        battles = res["A"].get("battles", []) + res["B"].get("battles", [])
        check(len(battles) >= 3, "%d battles auto-resolved by the clients (A %d, B %d; %d by command)" % (
            len(battles), len(res["A"].get("battles", [])), len(res["B"].get("battles", [])), sum(1 for b in battles if b["command"])))
        check(any(b["command"] for b in res["B"].get("battles", [])), "Carthage took command of Rome's army in a battle %s" % (
            [b["id"] for b in res["B"].get("battles", []) if b["command"]]))
        # Discord.
        msgs = [m["content"] for m in HOOK_MSGS]
        with open(os.path.join(tmp, "webhook.txt"), "w") as f:
            f.write("\n".join(msgs))
        print("  webhook got %d messages" % len(msgs))
        check(any("Carthage joined the campaign" in m for m in msgs) and any("has submitted turn" in m for m in msgs),
              "'joined' and 'has submitted, waiting for' messages")
        want = ["Turn 1 resolved", "deadline in about 2 hours", "deadline passed",
                "Turn 6 resolved after the timeout without Rome", "Turn %d resolved" % args.turns]
        check(any("Carthage took command of your army at" in m and "<@111111111111111111>" in m for m in msgs),
              "'took command of your army' message to Rome")
        i = 0
        for m in msgs:
            if i < len(want) and want[i] in m:
                i += 1
        check(i == len(want), "webhook messages in order (matched %d of %d: next %r)" % (i, len(want), want[i] if i < len(want) else ""))
        # (Taking command of an army twice at the same settlement in different
        # turns is two real events with the same text.)
        once = [m for m in msgs if "took command of your army" not in m]
        check(len(once) == len(set(once)), "no duplicate webhook messages")
        resolved = sum(1 for m in msgs if "resolved" in m and "Turn" in m and "battles are resolved" not in m)
        check(resolved == len(turn_versions), "one 'turn resolved' message per resolved turn (%d, %d)" % (resolved, len(turn_versions)))
        mention_ok = all("allowed_mentions" in m for m in HOOK_MSGS)
        check(mention_ok and any("<@222222222222222222>" in m for m in msgs), "messages @mention the seat that has to act")
        if any(("took command" in m) for m in msgs):
            print("  'took command' message present")
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
