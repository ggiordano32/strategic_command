#!/usr/bin/env python3
"""Rewrite tools/sprites/spec.json in its compact house style (one part,
bone, palette or action per line), so scripted edits keep diffs small."""
import json, os, sys

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spec.json")


def one(v):
    return json.dumps(v, separators=(", ", ": "))


def block(d, ind, depth_one):
    """A dict over several lines; values at depth >= depth_one on one line."""
    pad = " " * ind
    out = []
    for k, v in d.items():
        key = json.dumps(k) + ": "
        if depth_one <= 1 or not isinstance(v, (dict, list)) or k.startswith("_"):
            out.append(pad + key + one(v))
        elif isinstance(v, list):
            items = [pad + "  " + one(x) for x in v]
            out.append(pad + key + "[\n" + ",\n".join(items) + "\n" + pad + "]")
        else:
            out.append(pad + key + "{\n" + block(v, ind + 2, depth_one - 1) + "\n" + pad + "}")
    return ",\n".join(out)


def main():
    s = json.load(open(P))
    depth = {"actions": 2, "materials": 2, "palettes": 2, "rigs": 4, "bodies": 3, "units": 4, "atlas": 1}
    lines = []
    for k, v in s.items():
        key = "  " + json.dumps(k) + ": "
        d = depth.get(k, 1)
        if d <= 1 or not isinstance(v, dict):
            lines.append(key + one(v))
        else:
            lines.append(key + "{\n" + block(v, 4, d - 1) + "\n  }")
    open(P, "w").write("{\n" + ",\n".join(lines) + "\n}\n")


if __name__ == "__main__":
    main()
