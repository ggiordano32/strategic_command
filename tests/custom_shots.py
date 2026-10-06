#!/usr/bin/env python3
"""Phone screenshots of the deployment phase and custom battles (needs a
window): the custom battle setup, a deployment with its zone and
countdown, and the online lobby with two players on opposing sides (a
test server on a scratch port, Player 1 held by tests/custom_shot_peer.gd,
Player 2 the windowed game joining by code).

    python3 tests/custom_shots.py [--port 8081] [--out docs/screenshots]
"""
import argparse
import json
import os
import subprocess
import tempfile
import time
import urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PHONE = ["--resolution", "1560x720"]
UI = ["--ui-dpr=2", "--ui-touch=1"]


def post(base, path, body):
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def shot(out, name, frames, *extra):
    path = os.path.join(out, name)
    if os.path.exists(path):
        os.remove(path)
    subprocess.run(["godot", "--path", REPO] + PHONE + ["--"] + UI + ["--shot=" + path, "--shot-frames=%d" % frames]
                   + list(extra), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
    print(("  wrote " if os.path.exists(path) else "  FAILED ") + path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--out", default=os.path.join(REPO, "docs", "screenshots"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    shot(args.out, "custom_setup_phone.png", 40, "--custom", "--custom-template=battle_2000")
    shot(args.out, "deploy_phone.png", 120, "--custom-solo")
    binary = os.path.join(REPO, "build", "server-test", "scserver")
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True, env=dict(os.environ, SC_BUILD_OUT=binary))
    tmp = tempfile.mkdtemp(prefix="sc_cshot_")
    base = "http://127.0.0.1:%d" % args.port
    srv = subprocess.Popen([binary, "-addr", "127.0.0.1:%d" % args.port, "-data", os.path.join(tmp, "data"),
                            "-web", os.path.join(REPO, "build", "web"), "-log-dir", os.path.join(tmp, "logs"),
                            "-test-mode", "-compress=false"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    peer = None
    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(base + "/healthz", timeout=2)
                break
            except Exception:
                time.sleep(0.1)
        army = [["cav", 60], ["heavy", 100], ["pike", 120], ["heavy", 100], ["spear", 100], ["archer", 80],
                ["javelin", 60], ["cav", 60]]
        setup = {"v": 1, "seed": 77, "deploy": 60, "funds": 2,
                 "map": {"kind": "field", "terrain": 1, "ground": 3, "woods": 15, "mseed": 77, "plan": 0, "level": 1,
                         "walls": 1, "coast": 0, "def": 1},
                 "sides": [{"skill": 1, "style": 1, "armies": [{"ctrl": "p1", "units": army}]},
                           {"skill": 1, "style": 1, "armies": [{"ctrl": "p2", "units": [["phalangites", 120], ["companions", 60],
                                                                                       ["hoplites", 100], ["cretans", 80]]}]}]}
        r = post(base, "/api/custom", {"setup": setup, "rules": "", "build": "dev", "name": "Custom battle"})
        code = r["code"]
        peer = subprocess.Popen(["godot", "--headless", "--path", REPO, "--script", "res://tests/custom_shot_peer.gd", "--",
                                 "--server=" + base, "--code=" + code, "--token=" + r["token"], "--secs=200"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(4)
        shot(args.out, "custom_lobby_h2h_phone.png", 150, "--server=" + base, "--custom-join=" + code)
    finally:
        if peer:
            peer.kill()
        srv.terminate()


if __name__ == "__main__":
    main()
