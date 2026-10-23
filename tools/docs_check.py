#!/usr/bin/env python3
"""Prove a docs move lost nothing.

Takes the old docs/STATUS.md and docs/DESIGN.md from git (HEAD by default, or
the revision given as the first argument), and asserts that in the union of
the new files (docs/STATUS.md, docs/history/**, docs/DESIGN.md,
docs/design/**) every

  * heading line,
  * table row (its first 60 characters),
  * 8-hex-digit token (hashes, commits),
  * non-blank line (as often as it occurred in the old file)

of the old files still appears. Prints the counts; exits 1 on any miss.

Usage: python3 tools/docs_check.py [old-revision]
"""
import collections, glob, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REV = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
OLD = ["docs/STATUS.md", "docs/DESIGN.md"]
HEX = re.compile(r"(?<![0-9A-Za-z])[0-9a-f]{8}(?![0-9A-Za-z])")


def old_text(path):
    return subprocess.check_output(["git", "show", "%s:%s" % (REV, path)], cwd=ROOT).decode("utf-8")


def new_files():
    out = ["docs/STATUS.md", "docs/DESIGN.md"]
    for pat in ("docs/history/**/*.md", "docs/design/**/*.md"):
        out += sorted(os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, pat), recursive=True))
    return out


def headings(text):
    fence, out = False, []
    for line in text.split("\n"):
        if line.startswith("```"):
            fence = not fence
        if not fence and re.match(r"#{1,6} ", line):
            out.append(line.rstrip())
    return out


def main():
    files = new_files()
    union_lines = collections.Counter()
    union_text = []
    for f in files:
        t = open(os.path.join(ROOT, f), encoding="utf-8").read()
        union_text.append(t)
        for l in t.split("\n"):
            if l.strip():
                union_lines[l.rstrip()] += 1
    union = "\n".join(union_text)
    union_heads = set()
    for t in union_text:
        union_heads.update(headings(t))
    print("new files: %d" % len(files))
    for f in files:
        print("  %-34s %5d lines" % (f, open(os.path.join(ROOT, f), encoding="utf-8").read().count("\n")))
    bad = 0
    for path in OLD:
        old = old_text(path)
        lines = [l.rstrip() for l in old.split("\n")]
        heads = headings(old)
        rows = [l[:60] for l in lines if l.startswith("|")]
        hexes = sorted(set(HEX.findall(old)))
        miss_h = [h for h in heads if h not in union_heads]
        miss_r = [r for r in rows if r not in union]
        miss_x = [x for x in hexes if x not in union]
        old_counts = collections.Counter(l for l in lines if l.strip())
        miss_l = [(l, n, union_lines[l]) for l, n in old_counts.items() if union_lines[l] < n]
        print("%s: %d headings, %d table rows, %d hash strings, %d distinct lines (%d non-blank)" % (
            path, len(heads), len(rows), len(hexes), len(old_counts), sum(old_counts.values())))
        for name, miss in (("heading", miss_h), ("table row", miss_r), ("hash string", miss_x)):
            print("  missing %-11s %d" % (name + "s:", len(miss)))
            for m in miss[:10]:
                print("    ", m[:120])
        print("  missing lines:       %d" % len(miss_l))
        for m in miss_l[:10]:
            print("    ", m[0][:100], "old", m[1], "new", m[2])
        bad += len(miss_h) + len(miss_r) + len(miss_x) + len(miss_l)
    print("RESULT:", "FAIL (%d misses)" % bad if bad else "PASS")
    sys.exit(1 if bad else 0)


main()
