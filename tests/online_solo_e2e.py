#!/usr/bin/env python3
"""A one-human online campaign (the Host card with one human) on a scratch test-mode server, Rome then the
Caribbean: created without a join code, each submitted turn resolves and the next opens.
    python3 tests/online_solo_e2e.py [--port 8074]
"""
import argparse, json, os, subprocess, sys, tempfile, time, urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FAILS = []


def check(c, w):
    print(("  ok   " if c else "  FAIL ") + w)
    if not c:
        FAILS.append(w)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8074)
    ap.add_argument("--turns", type=int, default=3)
    args = ap.parse_args()
    binary = os.path.join(tempfile.mkdtemp(prefix="sc_solo_bin_"), "scserver")
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True, env=dict(os.environ, SC_BUILD_OUT=binary))
    tmp = tempfile.mkdtemp(prefix="sc_solo_")
    base = "http://127.0.0.1:%d" % args.port
    srv = subprocess.Popen([binary, "-addr", "127.0.0.1:%d" % args.port, "-data", os.path.join(tmp, "data"),
                            "-web", os.path.join(REPO, "build", "web"), "-log-dir", os.path.join(tmp, "logs"),
                            "-test-mode", "-compress=false"], stdout=open(os.path.join(tmp, "server.log"), "w"), stderr=subprocess.STDOUT)
    try:
        for _ in range(100):
            try:
                if json.loads(urllib.request.urlopen(base + "/healthz", timeout=2).read())["ok"]:
                    break
            except Exception:
                time.sleep(0.1)
        for pack in ["rome", "west"]:
            p = subprocess.run(["godot", "--headless", "--path", REPO, "--script", "res://tests/online_solo_client.gd", "--",
                                "--server=" + base, "--dir=" + tmp, "--pack=" + pack, "--turns=%d" % args.turns],
                               capture_output=True, text=True, timeout=600)
            res = json.load(open(os.path.join(tmp, "solo_%s.json" % pack))) if os.path.exists(os.path.join(tmp, "solo_%s.json" % pack)) else {}
            print(pack, "->", json.dumps(res))
            check(p.returncode == 0 and res.get("ok") is True, "%s: client ok %s" % (pack, res.get("errors")))
            check(res.get("join_code", "x") == "", "%s: a one-human campaign has no join code" % pack)
            check(res.get("state_pack") == pack, "%s: the state's pack is %s" % (pack, res.get("state_pack")))
            ts = res.get("turns", [])
            check(len(ts) == args.turns and all(t["resolved"] and t["next_turn"] == t["turn"] + 1 for t in ts),
                  "%s: %d submitted turns each resolved and opened the next" % (pack, len(ts)))
            check(res.get("hash") == res.get("local_hash"), "%s: client state matches the server's hash" % pack)
    finally:
        srv.terminate()
        srv.wait(timeout=10)
    print("RESULT:", "PASS" if not FAILS else "FAIL (%d)" % len(FAILS))
    sys.exit(0 if not FAILS else 1)


main()
