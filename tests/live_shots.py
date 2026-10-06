#!/usr/bin/env python3
"""Phone-size screenshots of the live co-op UI (milestone 5), against a test
server, with the other player as a headless peer (tests/live_shot_peer.gd):

    python3 tests/live_shots.py [--port 8073] [--out docs/screenshots]

  live_phone_battles_join.png   Carthage's battle list: Rome is in the lobby -> Join battle
  live_phone_lobby.png          Rome's lobby, waiting for Carthage (Start now / Leave)
  live_phone_vote.png           Carthage in battle: the co-op strip, Rome's pause request (Accept / No)
  live_phone_gift.png           Carthage's units selected: Gift to Rome
  live_phone_takeover.png       Rome's connection dropped: Continue without Rome / Wait

Needs a display (windowed Godot at 1560x720, --ui-dpr=2: a 780x360 CSS phone).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import json

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8073)
    ap.add_argument("--out", default=os.path.join(REPO, "docs", "screenshots"))
    args = ap.parse_args()
    binary = os.path.join(REPO, "build", "server-test", "scserver")
    subprocess.run([os.path.join(REPO, "tools", "build_server.sh")], check=True, env=dict(os.environ, SC_BUILD_OUT=binary))
    tmp = tempfile.mkdtemp(prefix="sc_shots_")
    base = "http://127.0.0.1:%d" % args.port
    srv = subprocess.Popen([binary, "-addr", "127.0.0.1:%d" % args.port, "-data", os.path.join(tmp, "data"),
                            "-web", os.path.join(REPO, "build", "web"), "-log-dir", os.path.join(tmp, "logs"),
                            "-test-mode", "-compress=false"], stdout=open(os.path.join(tmp, "server.log"), "w"),
                           stderr=subprocess.STDOUT)
    procs = []

    def peer(*extra):
        p = subprocess.Popen(["godot", "--headless", "--path", REPO, "--script", "res://tests/live_shot_peer.gd", "--",
                              "--server=" + base, "--dir=" + tmp] + list(extra),
                             stdout=open(os.path.join(tmp, "peer.log"), "a"), stderr=subprocess.STDOUT)
        procs.append(p)
        return p

    def window(role, shot, frames, *extra):
        cmd = ["godot", "--path", REPO, "--resolution", "1560x720", "--", "--server=" + base,
               "--accounts=" + os.path.join(tmp, "acc_%s.json" % role), "--open-online=" + cid,
               "--ui-dpr=2", "--ui-touch=1", "--shot=" + os.path.join(args.out, shot), "--shot-frames=%d" % frames] + list(extra)
        r = subprocess.run(cmd, stdout=open(os.path.join(tmp, "window.log"), "a"), stderr=subprocess.STDOUT, timeout=180)
        ok = os.path.exists(os.path.join(args.out, shot))
        print(("  wrote " if ok else "  FAILED ") + shot)
        return ok

    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(base + "/healthz", timeout=2)
                break
            except Exception:
                time.sleep(0.1)
        subprocess.run(["godot", "--headless", "--path", REPO, "--script", "res://tests/live_shot_peer.gd", "--",
                        "--server=" + base, "--dir=" + tmp, "--role=setup"], check=True, stdout=subprocess.DEVNULL)
        cid = open(os.path.join(tmp, "cid.txt")).read().strip()
        print("campaign", cid)
        ok = True
        # 1. The battle list with a live lobby (Rome waits in battle 1).
        a = peer("--role=A", "--bid=1", "--create", "--hold=40")
        time.sleep(3)
        ok &= window("B", "live_phone_battles_join.png", 240)
        a.kill()
        # 2. Rome's own lobby for battle 2, Carthage not there.
        ok &= window("A", "live_phone_lobby.png", 300, "--live-open=2")
        # 3. Carthage joins battle 3; Rome starts and asks for a pause.
        a = peer("--role=A", "--bid=3", "--create", "--start-when-ally", "--pause-at=30", "--hold=60")
        time.sleep(3)
        ok &= window("B", "live_phone_vote.png", 780, "--live-join=3")
        a.kill()
        # 4. Battle 4: Carthage's units selected, the gift button.
        a = peer("--role=A", "--bid=4", "--create", "--start-when-ally", "--hold=60")
        time.sleep(3)
        ok &= window("B", "live_phone_gift.png", 720, "--live-join=4", "--coop-select=mine")
        a.kill()
        # 5. Battle 5: Rome drops at frame 30; Carthage is offered Continue.
        a = peer("--role=A", "--bid=5", "--create", "--start-when-ally", "--drop-at=30", "--hold=60")
        time.sleep(3)
        ok &= window("B", "live_phone_takeover.png", 1150, "--live-join=5", "--coop-grace=3")
        a.kill()
        # 6. The real game (headless) as the host of battle 1 with Carthage
        # joined: starts, withdraws its army, goes back to the campaign when
        # the battle is over; the campaign screen uploads the result.
        time.sleep(9)  # the earlier rooms close
        acc = json.load(open(os.path.join(tmp, "acc_A.json")))
        tok = acc["campaigns"][cid]["token"]
        g = subprocess.Popen(["godot", "--headless", "--path", REPO, "--", "--server=" + base,
                              "--accounts=" + os.path.join(tmp, "acc_A.json"), "--open-online=" + cid, "--live-open=1",
                              "--coop-start-alone", "--coop-test-withdraw-at=400", "--coop-auto-exit", "--coop-frame-ms=10"],
                             stdout=open(os.path.join(tmp, "game.log"), "w"), stderr=subprocess.STDOUT)
        procs.append(g)
        time.sleep(6)
        peer("--role=B", "--bid=1", "--hold=120", "--withdraw-at=400")
        resolved = False
        for _ in range(240):
            time.sleep(0.5)
            s = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/api/c/" + cid, headers={"Authorization": "Bearer " + tok})).read())
            if 1 not in [x["id"] for x in s["battles"]]:
                resolved = True
                break
        h = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/api/c/%s/history/%d?state=0" % (cid, s["version"]),
                                                                     headers={"Authorization": "Bearer " + tok})).read())
        inp = h.get("inputs") or {}
        flow_ok = resolved and inp.get("battle_id") == 1 and inp.get("outcome", {}).get("live") == 1 and h.get("by") == 0
        print(("  ok   " if flow_ok else "  FAIL ") + "the game as host fought battle 1 live (Carthage joined), withdrew, and its campaign screen uploaded the result: version %d, by %s, winner %s" % (
            s["version"], h.get("by"), inp.get("outcome", {}).get("winner")))
        ok &= flow_ok
        g.kill()
    finally:
        for p in procs:
            if p.poll() is None:
                p.kill()
        srv.terminate()
        srv.wait(timeout=10)
    print("logs in", tmp)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
