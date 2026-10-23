#!/usr/bin/env python3
"""Turn result sets into compact tables.

  table.py AFTER                 one set          (AFTER: a results.jsonl, a run dir, 'plan' or 'plan@hash')
  table.py BEFORE AFTER          before -> after, a cell flagged '*' when its change exceeds the combined 95 % interval
  options: --json (a few hundred tokens for the deciding agent; default is Markdown), --seeds N (first N seeds of
  each cell), --pins PATH (campaign_sim pins, default pins.json)

Probes (from the result lines): town_balance (attacker wins % per town x walls, +-95 % Wilson half-width,
pooled rows, minutes to decide, gate-down), open_town, sea, campaign_sim (hashes against pins).
"""
import argparse, collections, json, math, os, sys

import balance_lib as L


def select(rows, plan=None, seeds=None):
    out = []
    for r in rows:
        if plan:
            s0 = int(plan.get("seed0", 0))
            n = int(seeds or plan.get("seeds", 16))
            if r["probe"] in ("town_balance", "open_town") and not (s0 <= r["seed"] < s0 + n):
                continue
            if r["probe"] == "sea" and r["seed"] > n:
                continue
        elif seeds and r["probe"] in ("town_balance", "open_town") and r["seed"] >= seeds + min(
                x["seed"] for x in rows if x["probe"] == r["probe"]):
            continue
        elif seeds and r["probe"] == "sea" and r["seed"] > seeds:
            continue
        out.append(r)
    return out


def probe_of(rows):
    return rows[0]["probe"] if rows else None


def f1(x, d=1):
    return "-" if x is None else ("%.*f" % (d, x))


# ---------------------------------------------------------------- town_balance
def tb_cells(rows):
    by = collections.OrderedDict()
    for r in rows:
        by.setdefault((r["town"], r["walls"]), []).append(r)
    return by


def tb_stat(rs):
    n = len(rs)
    k = sum(1 for r in rs if r["winner"] == 0)
    _, lo, hi, hw = L.wilson(k, n)
    gates = [r["gate_tick"] for r in rs if r["gate_tick"] >= 0]
    return {"n": n, "pct": 100 * k / n if n else 0, "hw": hw, "draw": 100 * sum(1 for r in rs if r["winner"] not in (0, 1)) / n if n else 0,
            "min": L.median([r["ticks"] / 600 for r in rs]), "gate": 100 * len(gates) / n if n else 0,
            "gate_min": L.median([g / 600 for g in gates]), "ka": L.mean(r["killed_att"] for r in rs), "kd": L.mean(r["killed_def"] for r in rs)}


def tb_model(rows):
    cells = tb_cells(rows)
    towns = list(collections.OrderedDict.fromkeys(t for t, w in cells))
    walls = sorted(set(w for t, w in cells))
    m = {"towns": towns, "walls": walls, "cell": {}, "pool": {}, "town_pool": {}}
    for (t, w), rs in cells.items():
        m["cell"][(t, w)] = tb_stat(rs)
    for w in walls:
        m["pool"][w] = tb_stat([r for r in rows if r["walls"] == w])
    for t in towns:
        m["town_pool"][t] = tb_stat([r for r in rows if r["town"] == t])
    m["all"] = tb_stat(rows)
    return m


def cell_md(s):
    return "-" if not s else "%.0f ±%.0f" % (s["pct"], s["hw"])


def diff_md(a, b):
    if not a or not b:
        return "-"
    d = b["pct"] - a["pct"]
    flag = "*" if abs(d) > math.hypot(a["hw"], b["hw"]) else ""
    return "%.0f → %.0f (%+.0f%s)" % (a["pct"], b["pct"], d, flag)


def tb_markdown(ma, mb=None, la="after", lb=None):
    one = mb is None
    m = ma if one else mb
    towns = m["towns"] if one else list(collections.OrderedDict.fromkeys(ma["towns"] + mb["towns"]))
    walls = m["walls"] if one else sorted(set(ma["walls"]) | set(mb["walls"]))
    out = []
    n = m["all"]["n"]
    out.append("Attacker wins %% (±95 %% interval), %s, %d battles%s" % (la if one else "%s → %s" % (la, lb), n,
                                                                    "" if one else "; * = change beyond the interval"))
    out.append("")
    out.append("| Town | " + " | ".join("Walls %d" % w for w in walls) + " | All |")
    out.append("|---|" + "---|" * (len(walls) + 1))
    for t in towns:
        cells = []
        for w in walls:
            if one:
                cells.append(cell_md(ma["cell"].get((t, w))))
            else:
                cells.append(diff_md(ma["cell"].get((t, w)), mb["cell"].get((t, w))))
        allc = cell_md(ma["town_pool"].get(t)) if one else diff_md(ma["town_pool"].get(t), mb["town_pool"].get(t))
        out.append("| %s | %s | %s |" % (t, " | ".join(cells), allc))
    cells = [cell_md(ma["pool"].get(w)) if one else diff_md(ma["pool"].get(w), mb["pool"].get(w)) for w in walls]
    allc = cell_md(ma["all"]) if one else diff_md(ma["all"], mb["all"])
    out.append("| **Pooled** | %s | %s |" % (" | ".join("**%s**" % c for c in cells), allc))
    out.append("")
    out.append("Median minutes to decide / gate down (share of battles, median minute)")
    out.append("")
    out.append("| Town | " + " | ".join("Walls %d" % w for w in walls) + " |")
    out.append("|---|" + "---|" * len(walls))

    def tg(s):
        if not s:
            return "-"
        return "%s / %.0f %% @%s" % (f1(s["min"]), s["gate"], f1(s["gate_min"])) if s["gate"] else "%s / -" % f1(s["min"])
    for t in towns:
        if one:
            cs = [tg(ma["cell"].get((t, w))) for w in walls]
        else:
            cs = []
            for w in walls:
                a, b = ma["cell"].get((t, w)), mb["cell"].get((t, w))
                cs.append("-" if not a or not b else "%s → %s (gate %.0f → %.0f %%)" % (f1(a["min"]), f1(b["min"]), a["gate"], b["gate"]))
        out.append("| %s | %s |" % (t, " | ".join(cs)))
    return "\n".join(out)


def tb_json(ma, mb=None, la="after", lb=None):
    def pack(s):
        return [round(s["pct"], 1), round(s["hw"], 1), s["n"], None if s["min"] is None else round(s["min"], 1), round(s["gate"])]
    one = mb is None
    m = ma if one else mb
    j = {"probe": "town_balance", "fields": "[att win %, +-95 %, n, median min, gate-down %]", "n": m["all"]["n"]}
    if one:
        j["label"] = la
        j["pooled"] = {str(w): pack(s) for w, s in ma["pool"].items()}
        j["all"] = pack(ma["all"])
        j["cells"] = {t: {str(w): pack(ma["cell"][(t, w)]) for w in ma["walls"] if (t, w) in ma["cell"]} for t in ma["towns"]}
    else:
        j["before"], j["after"] = la, lb
        j["pooled"] = {str(w): {"before": pack(ma["pool"][w]), "after": pack(mb["pool"][w])} for w in mb["walls"]
                       if w in ma["pool"]}
        j["all"] = {"before": pack(ma["all"]), "after": pack(mb["all"])}
        flagged = []
        for key, b in mb["cell"].items():
            a = ma["cell"].get(key)
            if not a:
                continue
            d = b["pct"] - a["pct"]
            if abs(d) > math.hypot(a["hw"], b["hw"]):
                flagged.append({"town": key[0], "walls": key[1], "before": round(a["pct"]), "after": round(b["pct"]),
                                "delta": round(d), "interval": round(math.hypot(a["hw"], b["hw"]))})
        j["flagged_beyond_interval"] = flagged
        j["cells_after"] = {t: {str(w): round(mb["cell"][(t, w)]["pct"]) for w in mb["walls"] if (t, w) in mb["cell"]} for t in mb["towns"]}
    return j


# ---------------------------------------------------------------- open_town
def ot_stat(rs):
    n = len(rs)
    k = sum(1 for r in rs if r["win"])
    doors = [r["door"] / 600 for r in rs if r["door"] >= 0]
    dn = sum(r["dist_n"] for r in rs)
    return {"n": n, "pct": 100 * k / n if n else 0, "hw": L.wilson(k, n)[3], "l3a": L.mean(r["l3a"] for r in rs), "l3d": L.mean(r["l3d"] for r in rs),
            "dist": sum(r["dist"] for r in rs) / dn if dn else None, "inr": L.mean(r["inr"] for r in rs), "band": L.mean(r["band"] for r in rs),
            "door": L.mean(doors), "door_n": len(doors), "spw": L.mean(r["spw"] for r in rs), "end": L.mean(r["t"] / 600 for r in rs),
            "kia": L.mean(r["kia"] for r in rs), "kid": L.mean(r["kid"] for r in rs)}


def ot_groups(rows):
    by = collections.OrderedDict()
    for r in rows:
        by.setdefault("%s w%d sk%d" % (r["town"], r["walls"], r["skill"]), []).append(r)
    return collections.OrderedDict((k, ot_stat(v)) for k, v in by.items())


OT_COLS = [("pct", "att win %", "%.0f"), ("l3a", "L3 att", "%.0f"), ("l3d", "L3 def", "%.0f"), ("dist", "dist m", "%.0f"),
           ("inr", "inR s", "%.0f"), ("band", "band s", "%.0f"), ("door", "door min", "%.1f"), ("spw", "spw s", "%.0f"),
           ("end", "end min", "%.1f"), ("kia", "killed att", "%.0f"), ("kid", "killed def", "%.0f")]


def ot_markdown(ga, gb=None, la="after", lb=None):
    out = ["Open-town probe, per town / walls / skill (means over seeds; win % ±95 %)", ""]
    out.append("| Group | n | " + " | ".join(c[1] for c in OT_COLS) + " |")
    out.append("|---|---|" + "---|" * len(OT_COLS))

    def fmt(s, k, f):
        v = s[k]
        if v is None:
            return "-"
        return (f % v) + ((" ±%.0f" % s["hw"]) if k == "pct" else "")
    for g in (ga if gb is None else gb):
        a = ga.get(g)
        b = gb.get(g) if gb is not None else None
        if gb is None:
            out.append("| %s | %d | %s |" % (g, a["n"], " | ".join(fmt(a, k, f) for k, _, f in OT_COLS)))
        elif a:
            cs = []
            for k, _, f in OT_COLS:
                if a[k] is None or b[k] is None:
                    cs.append("-")
                else:
                    flag = "*" if k == "pct" and abs(b[k] - a[k]) > math.hypot(a["hw"], b["hw"]) else ""
                    cs.append((f + " → " + f) % (a[k], b[k]) + flag)
            out.append("| %s | %d → %d | %s |" % (g, a["n"], b["n"], " | ".join(cs)))
    return "\n".join(out)


def ot_json(ga, gb=None, la="after", lb=None):
    def pack(s):
        return {k: (None if s[k] is None else round(s[k], 1)) for k, _, _ in OT_COLS} | {"n": s["n"], "pm": round(s["hw"])}
    if gb is None:
        return {"probe": "open_town", "groups": {g: pack(s) for g, s in ga.items()}}
    return {"probe": "open_town", "before": la, "after": lb, "groups": {g: {"before": pack(ga[g]), "after": pack(s)} for g, s in gb.items() if g in ga}}


# ---------------------------------------------------------------- sea
def sea_stat(rs):
    n = len(rs)
    w0 = sum(1 for r in rs if r["winner"] == 0)
    w1 = sum(1 for r in rs if r["winner"] == 1)
    dts = [r["dt"] / 600 if r["dt"] >= 0 else 15 for r in rs]
    lost = [sum(int(r["sides"][s]["sunk"]) + int(r["sides"][s]["taken"]) for r in rs) for s in (0, 1)]
    ge = [sum(r["gr"][s] for r in rs) for s in (0, 1)]
    return {"n": n, "w0": w0, "w1": w1, "pct0": 100 * w0 / n if n else 0, "hw": L.wilson(w0, n)[3], "draw": n - w0 - w1, "min": L.median(dts),
            "board": sum(r["boardings"] for r in rs), "lost0": lost[0], "lost1": lost[1], "gr0": ge[0], "gr1": ge[1],
            "fires": sum(r["fire"][0] for r in rs), "burnt": sum(r["burnt"][0] + r["burnt"][1] for r in rs)}


def sea_groups(rows):
    by = collections.OrderedDict()
    for r in rows:
        by.setdefault("%s/%s" % (r["mode"], r["layout"]), []).append(r)
    g = collections.OrderedDict((k, sea_stat(v)) for k, v in by.items())
    g["all"] = sea_stat(rows)
    return g


SEA_COLS = [("pct0", "side 0 win %", "%.0f"), ("w0", "wins s0", "%d"), ("w1", "wins s1", "%d"), ("draw", "draws", "%d"), ("min", "median min", "%.1f"),
            ("board", "boardings", "%d"), ("lost0", "lost s0", "%d"), ("lost1", "lost s1", "%d"), ("gr0", "grounded s0", "%d"), ("gr1", "grounded s1", "%d"),
            ("fires", "fires", "%d")]


def sea_markdown(ga, gb=None, la="after", lb=None):
    out = ["Sea probe per mode / layout (side 0 win % ±95 %)", ""]
    out.append("| Group | n | " + " | ".join(c[1] for c in SEA_COLS) + " |")
    out.append("|---|---|" + "---|" * len(SEA_COLS))
    for g in (ga if gb is None else gb):
        a, b = ga.get(g), (gb.get(g) if gb is not None else None)
        if gb is None:
            out.append("| %s | %d | %s |" % (g, a["n"], " | ".join(
                ("%s" % (f % a[k]) + (" ±%.0f" % a["hw"] if k == "pct0" else "")) if a[k] is not None else "-" for k, _, f in SEA_COLS)))
        elif a:
            cs = []
            for k, _, f in SEA_COLS:
                flag = "*" if k == "pct0" and abs(b[k] - a[k]) > math.hypot(a["hw"], b["hw"]) else ""
                cs.append((f + " → " + f) % (a[k], b[k]) + flag)
            out.append("| %s | %d | %s |" % (g, b["n"], " | ".join(cs)))
    return "\n".join(out)


def sea_json(ga, gb=None, la="after", lb=None):
    keys = [k for k, _, _ in SEA_COLS]
    pack = lambda s: {k: (round(s[k], 1) if isinstance(s[k], float) else s[k]) for k in keys} | {"n": s["n"], "pm": round(s["hw"])}
    if gb is None:
        return {"probe": "sea", "groups": {g: pack(s) for g, s in ga.items()}}
    return {"probe": "sea", "before": la, "after": lb, "groups": {g: {"before": pack(ga[g]), "after": pack(s)} for g, s in gb.items() if g in ga}}


# ---------------------------------------------------------------- campaign_sim
def pins_check(rows, pins_path):
    pins = json.load(open(pins_path)) if os.path.exists(pins_path) else {}
    res = collections.OrderedDict()
    for pack in sorted(set(r["pack"] for r in rows)):
        got = [r["hash"] for r in sorted((r for r in rows if r["pack"] == pack), key=lambda r: r["seed"])]
        want = pins.get(pack, [])
        res[pack] = {"got": got, "want": want, "match": got == want[:len(got)] and len(got) > 0 and bool(want)}
    return res


def cs_markdown(res):
    out = ["Campaign pins (campaign_sim)", "", "| Pack | Seed | Hash | Pin | |", "|---|---|---|---|---|"]
    for pack, v in res.items():
        for i, h in enumerate(v["got"]):
            w = v["want"][i] if i < len(v["want"]) else "-"
            out.append("| %s | %d | %s | %s | %s |" % (pack, 1000 + i * 77, h, w, "ok" if h == w else "DIFFERS"))
    return "\n".join(out)


def cs_json(res):
    return {"probe": "campaign_sim", "packs": {p: {"match": v["match"], "got": v["got"], "differs_at": [i for i, h in enumerate(v["got"])
                                                                                            if i >= len(v["want"]) or h != v["want"][i]]} for p, v in res.items()}}


# ---------------------------------------------------------------- one line for measure.py
def one_line(rows, plan=None):
    rows = select(rows, plan)
    p = probe_of(rows)
    if p is None:
        return "no results"
    if p == "town_balance":
        m = tb_model(rows)
        a = m["all"]
        return "%d battles, attacker wins %.0f %% ±%.0f; by walls %s" % (a["n"], a["pct"], a["hw"], ", ".join(
            "%d: %.0f %%" % (w, s["pct"]) for w, s in m["pool"].items()))
    if p == "open_town":
        s = ot_stat(rows)
        return "%d battles, attackers win %.0f %% ±%.0f, L3 att %.0f def %.0f" % (s["n"], s["pct"], s["hw"], s["l3a"], s["l3d"])
    if p == "sea":
        s = sea_stat(rows)
        return "%d battles, side 0 wins %d, side 1 %d, draws %d, median %.1f min" % (s["n"], s["w0"], s["w1"], s["draw"], s["min"])
    if p == "campaign_sim":
        res = pins_check(rows, os.path.join(L.HERE, "pins.json"))
        return "pins " + "; ".join("%s %s (%d seeds)" % (k, "MATCH" if v["match"] else "DIFFER", len(v["got"])) for k, v in res.items())
    return "%d rows" % len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sets", nargs="+", help="AFTER, or BEFORE AFTER")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--seeds", type=int, default=None)
    ap.add_argument("--pins", default=os.path.join(L.HERE, "pins.json"))
    a = ap.parse_args()
    if len(a.sets) > 2:
        sys.exit("one or two result sets")
    sets = [select(L.read_jsonl(L.resolve(s)), None, a.seeds) for s in a.sets]
    for s, rows in zip(a.sets, sets):
        if not rows:
            sys.exit("no results in %s (%s)" % (s, L.resolve(s)))
    p = probe_of(sets[-1])
    labels = [os.path.basename(os.path.dirname(L.resolve(s))) or s for s in a.sets]
    names = [("%s@%s" % (os.path.basename(os.path.dirname(os.path.dirname(L.resolve(s)))), labels[i])) for i, s in enumerate(a.sets)]
    if len(sets) == 2 and p in ("town_balance", "open_town"):
        # Same seeds in both sets (a cell is compared on the seeds both have).
        keyf = (lambda r: (r["town"], r["walls"], r["seed"], r.get("skill"))) if True else None
        ks = [set(keyf(r) for r in s) for s in sets]
        common = ks[0] & ks[1]
        sets = [[r for r in s if keyf(r) in common] for s in sets]
    if p == "town_balance":
        ms = [tb_model(s) for s in sets]
        if len(ms) == 1:
            print(json.dumps(tb_json(ms[0], None, names[0]), separators=(",", ":")) if a.json else tb_markdown(ms[0], None, names[0]))
        else:
            print(json.dumps(tb_json(ms[0], ms[1], names[0], names[1]), separators=(",", ":")) if a.json else tb_markdown(ms[0], ms[1], names[0], names[1]))
    elif p == "open_town":
        gs = [ot_groups(s) for s in sets]
        if a.json:
            print(json.dumps(ot_json(gs[0], None, names[0]) if len(gs) == 1 else ot_json(gs[0], gs[1], names[0], names[1]), separators=(",", ":")))
        else:
            print(ot_markdown(gs[0], None, names[0]) if len(gs) == 1 else ot_markdown(gs[0], gs[1], names[0], names[1]))
    elif p == "sea":
        gs = [sea_groups(s) for s in sets]
        if a.json:
            print(json.dumps(sea_json(gs[0], None, names[0]) if len(gs) == 1 else sea_json(gs[0], gs[1], names[0], names[1]), separators=(",", ":")))
        else:
            print(sea_markdown(gs[0], None, names[0]) if len(gs) == 1 else sea_markdown(gs[0], gs[1], names[0], names[1]))
    elif p == "campaign_sim":
        res = pins_check(sets[-1], a.pins)
        print(json.dumps(cs_json(res), separators=(",", ":")) if a.json else cs_markdown(res))
    else:
        sys.exit("unknown probe %s" % p)


if __name__ == "__main__":
    main()
