#!/usr/bin/env python3
"""Run a balance plan with N Godot processes in parallel; results are cached by a hash of sim/ and campaign/.

  measure.py plans/west_named.json [--jobs N] [--seeds N] [--force] [--dry]

Results: tools/balance/out/<plan>/<code-hash>/results.jsonl (one JSON line a battle / seed / sea battle),
plus logs/ (each job's console output) and done.txt (finished jobs). Only files under out/<plan>/<code-hash>
are written. Jobs already done under the same code hash are not repeated (a plan with fewer seeds, or
more, reuses them); when nothing is left to run it prints "cached" and returns. Only processes started here
are ever signalled.
"""
import argparse, concurrent.futures as cf, hashlib, json, os, shutil, subprocess, sys, threading, time

import balance_lib as L

GODOT = os.environ.get("GODOT", "godot")
LOCK = threading.Lock()
CHILDREN = set()


def chunks(seed0, seeds, size):
    s = seed0
    while s < seed0 + seeds:
        n = min(size, seed0 + seeds - s)
        yield s, n
        s += n


def make_jobs(plan):
    """-> list of (job id, script, args, meta) ; meta is merged into every result line of the job."""
    probe = plan["probe"]
    extra = list(plan.get("args", []))
    jobs = []
    seeds = int(plan.get("seeds", 16))
    seed0 = int(plan.get("seed0", 0))
    size = int(plan.get("chunk", 4))
    if probe == "town_balance":
        pack = plan.get("pack", "rome")
        for t in plan["towns"]:
            key, _, level = str(t).partition(":")
            for w in plan["walls"]:
                for s0, n in chunks(seed0, seeds, size):
                    spec = "--town=%s:%s%s" % (pack, key, (":" + level) if level else "")
                    jid = "tb|%s|%s|w%d|s%d+%d|%s" % (pack, t, w, s0, n, " ".join(extra))
                    jobs.append((jid, "town_balance", [spec, "--walls=%d" % w, "--seeds=%d" % n, "--seed0=%d" % s0] + extra,
                                 {"pack": pack, "town": key, "level": int(level) if level else 0}))
    elif probe == "open_town":
        for t in plan["towns"]:
            for w in plan.get("walls", [0]):
                for sk in plan.get("skills", [1]):
                    for s0, n in chunks(seed0, seeds, size):
                        jid = "ot|%s|w%d|k%d|s%d+%d|%s" % (t, w, sk, s0, n, " ".join(extra))
                        jobs.append((jid, "open_town_probe", ["--town=%s" % t, "--walls=%d" % w, "--skill=%d" % sk,
                                                              "--seeds=%d" % n, "--seed0=%d" % s0] + extra, {}))
    elif probe == "sea":
        for mode in plan.get("modes", ["ai", "hold"]):
            for lay in plan.get("layouts", ["ns", "we", "gauge0", "gauge1", "camp"]):
                jid = "sea|%s|%s|n%d|%s" % (mode, lay, seeds, " ".join(extra))
                jobs.append((jid, "sea_probe", ["--seeds=%d" % seeds, "--layouts=%s" % lay, "--modes=%s" % mode] + extra, {}))
    elif probe == "campaign_sim":
        turns = int(plan.get("turns", 60))
        for pack in plan.get("packs", ["rome", "west"]):
            jid = "cs|%s|n%d|t%d|%s" % (pack, seeds, turns, " ".join(extra))
            jobs.append((jid, "campaign_sim", ["--pack=%s" % pack, "--seeds=%d" % seeds, "--turns=%d" % turns] + extra, {}))
    else:
        sys.exit("unknown probe: %s" % probe)
    return jobs


def run_job(job, rundir, timeout):
    jid, script, args, meta = job
    tag = hashlib.sha1(jid.encode()).hexdigest()[:10]
    tmp = os.path.join(rundir, "tmp", tag + ".jsonl")
    log = os.path.join(rundir, "logs", tag + ".log")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    os.makedirs(os.path.dirname(log), exist_ok=True)
    cmd = [GODOT, "--headless", "--script", "res://tests/%s.gd" % script, "--", "--json=" + tmp] + args
    t0 = time.time()
    with open(log, "w") as lf:
        lf.write(" ".join(cmd) + "\n")
        lf.flush()
        p = subprocess.Popen(cmd, cwd=L.ROOT, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        with LOCK:
            CHILDREN.add(p)
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.terminate()
            rc = -1
        finally:
            with LOCK:
                CHILDREN.discard(p)
    rows = L.read_jsonl(tmp)
    for r in rows:
        r.update(meta)
    ok = rc == 0 and len(rows) > 0
    return jid, rows, ok, time.time() - t0, log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("plan")
    ap.add_argument("--jobs", type=int, default=None, help="parallel Godot processes (default: plan, else cores - 2)")
    ap.add_argument("--seeds", type=int, default=None, help="override the plan's seed count")
    ap.add_argument("--force", action="store_true", help="re-measure even if cached")
    ap.add_argument("--dry", action="store_true", help="list the jobs, run nothing")
    ap.add_argument("--timeout", type=int, default=3600, help="seconds per job")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    plan = L.load_plan(a.plan)
    if a.seeds:
        plan["seeds"] = a.seeds
    par = a.jobs or int(plan.get("parallelism") or 0) or max(1, (os.cpu_count() or 4) - 2)
    h = L.code_hash()
    rundir = os.path.join(L.OUT, plan["name"], h)
    resf = os.path.join(rundir, "results.jsonl")
    donef = os.path.join(rundir, "done.txt")
    if a.force and os.path.isdir(rundir):
        shutil.rmtree(rundir)
    os.makedirs(rundir, exist_ok=True)
    done = set(open(donef).read().split("\n")) if os.path.exists(donef) else set()
    jobs = make_jobs(plan)
    todo = [j for j in jobs if j[0] not in done]
    t0 = time.time()
    print("plan %s  code %s  %d jobs, %d to run, %d parallel" % (plan["name"], h, len(jobs), len(todo), par), flush=True)
    if a.dry:
        for j in todo:
            print("  ", j[1], " ".join(j[2]))
        return 0
    failed = 0
    if todo:
        ex = cf.ThreadPoolExecutor(max_workers=par)
        futs = [ex.submit(run_job, j, rundir, a.timeout) for j in todo]
        n = 0
        try:
            for f in cf.as_completed(futs):
                jid, rows, ok, dt, log = f.result()
                n += 1
                if ok:
                    with open(resf, "a") as rf:
                        for r in rows:
                            rf.write(json.dumps(r, sort_keys=True) + "\n")
                    with open(donef, "a") as df:
                        df.write(jid + "\n")
                else:
                    failed += 1
                if not a.quiet:
                    print("[%d/%d] %s %s (%d rows, %.0fs)%s" % (n, len(todo), "ok" if ok else "FAILED", jid.split("|")[0:5], len(rows), dt,
                                                           "" if ok else "  log: " + log), flush=True)
        except KeyboardInterrupt:
            for f in futs:
                f.cancel()
            with LOCK:
                for p in list(CHILDREN):
                    p.terminate()
            print("interrupted; finished jobs are kept")
            return 130
        ex.shutdown()
        shutil.rmtree(os.path.join(rundir, "tmp"), ignore_errors=True)
    # Results of this plan: only the lines of its own jobs (the file may hold a wider earlier plan).
    import table
    rows = L.read_jsonl(resf)
    status = "cached" if not todo else "measured"
    print("%s %s code %s: %s%s  (%.0fs)" % (status, plan["name"], h, table.one_line(rows, plan), "  FAILED JOBS %d" % failed if failed else "",
                                           time.time() - t0))
    print("results: %s" % os.path.relpath(resf, L.ROOT))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
