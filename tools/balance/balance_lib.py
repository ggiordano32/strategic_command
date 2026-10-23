"""Shared helpers for tools/balance: code hash, plan loading, result loading, statistics."""
import hashlib, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")


def code_hash():
    """Short hash of every file under sim/ and campaign/ (path + bytes, sorted)."""
    h = hashlib.sha1()
    for top in ("sim", "campaign"):
        base = os.path.join(ROOT, top)
        for dp, dn, fn in os.walk(base):
            dn.sort()
            for f in sorted(fn):
                if f.endswith(".uid") or f.endswith(".import"):
                    continue
                p = os.path.join(dp, f)
                h.update(os.path.relpath(p, ROOT).encode() + b"\0")
                with open(p, "rb") as fh:
                    h.update(fh.read())
                h.update(b"\0")
    return h.hexdigest()[:10]


def load_plan(path):
    with open(path) as f:
        plan = json.load(f)
    plan["name"] = os.path.splitext(os.path.basename(path))[0]
    return plan


def read_jsonl(path):
    rows = []
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("{"):
                    rows.append(json.loads(line))
    return rows


def resolve(spec):
    """A results spec -> results.jsonl path. Accepts a file, a run directory, 'plan' (current code) or 'plan@hash'."""
    if os.path.isfile(spec):
        return spec
    if os.path.isdir(spec):
        return os.path.join(spec, "results.jsonl")
    name, _, h = spec.partition("@")
    return os.path.join(OUT, name, h or code_hash(), "results.jsonl")


def wilson(k, n, z=1.96):
    """Wilson 95 % interval of a proportion, in percent: (centre, lo, hi, half-width)."""
    if n == 0:
        return (0.0, 0.0, 0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    hw = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (100 * p, 100 * max(0, c - hw), 100 * min(1, c + hw), 100 * hw)


def median(v):
    v = sorted(v)
    if not v:
        return None
    m = len(v) // 2
    return v[m] if len(v) % 2 else (v[m - 1] + v[m]) / 2


def mean(v):
    v = list(v)
    return sum(v) / len(v) if v else None
